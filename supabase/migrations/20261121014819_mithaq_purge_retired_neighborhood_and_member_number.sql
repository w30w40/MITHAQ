-- Purge retired neighborhood and member-number data and remove their live API surface.
UPDATE public.profile_details SET details=COALESCE(details,'{}'::jsonb)-'neighborhood',updated_at=now()
WHERE COALESCE(details,'{}'::jsonb) ? 'neighborhood';
UPDATE private.mithaq_managed_profiles SET details=COALESCE(details,'{}'::jsonb)-'neighborhood',updated_at=now()
WHERE COALESCE(details,'{}'::jsonb) ? 'neighborhood';

CREATE OR REPLACE FUNCTION public.mithaq_strip_retired_neighborhood()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN NEW.details:=COALESCE(NEW.details,'{}'::jsonb)-'neighborhood'; RETURN NEW; END; $$;
DROP TRIGGER IF EXISTS mithaq_strip_retired_neighborhood ON public.profile_details;
CREATE TRIGGER mithaq_strip_retired_neighborhood BEFORE INSERT OR UPDATE OF details ON public.profile_details
FOR EACH ROW EXECUTE FUNCTION public.mithaq_strip_retired_neighborhood();
DROP TRIGGER IF EXISTS mithaq_strip_retired_neighborhood ON private.mithaq_managed_profiles;
CREATE TRIGGER mithaq_strip_retired_neighborhood BEFORE INSERT OR UPDATE OF details ON private.mithaq_managed_profiles
FOR EACH ROW EXECUTE FUNCTION public.mithaq_strip_retired_neighborhood();

DROP FUNCTION IF EXISTS public.mithaq_public_member_profiles_v2(uuid[]);
DROP FUNCTION IF EXISTS public.mithaq_list_interested_by();
DROP FUNCTION IF EXISTS public.mithaq_list_member_relations(text);
DROP FUNCTION IF EXISTS public.mithaq_list_managed_profiles();

CREATE FUNCTION public.mithaq_public_member_profiles_v2(p_user_ids uuid[] DEFAULT NULL::uuid[])
RETURNS TABLE(id uuid,display_name text,country text,region text,marriage_type text,life_text text,last_seen_at timestamptz,created_at timestamptz,details jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF (SELECT auth.uid()) IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles actor WHERE actor.id=(SELECT auth.uid()) AND actor.account_status='active') THEN
  RAISE EXCEPTION 'active_account_required' USING ERRCODE='42501';
 END IF;
 RETURN QUERY SELECT p.id,p.display_name,p.country,p.region,p.marriage_type,
  COALESCE(NULLIF(d.details->>'about',''),p.life_text,''),
  CASE WHEN COALESCE(privacy.show_last_seen,true) THEN p.last_seen_at ELSE NULL END,p.created_at,
  (COALESCE(d.details,'{}'::jsonb)-ARRAY['email','email_verified','phone','phone_number','phone_verified','mobile','full_name','address','private','public_listing_consent','health_public','partner_preferences_public','sub','password','token','secret','terms_version','terms_accepted_at','privacy_policy_accepted','honesty_declaration_accepted','marriage_fee_agreed','marriage_fee_amount_sar','marriage_fee_trigger','neighborhood']::text[])
 FROM public.profiles p LEFT JOIN public.profile_details d ON d.id=p.id
 LEFT JOIN public.mithaq_chat_privacy_settings privacy ON privacy.user_id=p.id
 WHERE p.id<>(SELECT auth.uid()) AND p.account_status='active'
 AND (p.is_published=true OR COALESCE(d.details->>'public_listing_consent','false')='true')
 AND (p_user_ids IS NULL OR p.id=ANY(p_user_ids))
 AND NOT EXISTS(SELECT 1 FROM private.member_relations r WHERE r.is_active AND r.action IN ('ignore','block') AND ((r.actor_id=(SELECT auth.uid()) AND r.target_id=p.id) OR (r.actor_id=p.id AND r.target_id=(SELECT auth.uid()) AND r.action='block')))
 ORDER BY p.created_at DESC;
END; $function$;
REVOKE ALL ON FUNCTION public.mithaq_public_member_profiles_v2(uuid[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.mithaq_public_member_profiles_v2(uuid[]) TO authenticated;

CREATE FUNCTION public.mithaq_list_interested_by()
RETURNS TABLE(id uuid,display_name text,country text,region text,interested_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_actor uuid:=(SELECT auth.uid());
BEGIN
 IF v_actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=v_actor AND p.account_status='active') THEN RAISE EXCEPTION 'active_account_required' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT p.id,p.display_name,p.country,p.region,r.created_at
 FROM private.member_relations r JOIN public.profiles p ON p.id=r.actor_id LEFT JOIN public.profile_details d ON d.id=p.id
 WHERE r.target_id=v_actor AND r.action='interest' AND r.is_active=true AND p.id<>v_actor AND p.account_status='active'
 AND (p.is_published=true OR COALESCE(d.details->>'public_listing_consent','false')='true')
 AND NOT EXISTS(SELECT 1 FROM private.member_relations x WHERE x.is_active=true AND x.action IN ('block','ignore') AND ((x.actor_id=v_actor AND x.target_id=p.id) OR (x.actor_id=p.id AND x.target_id=v_actor)))
 ORDER BY r.created_at DESC LIMIT 100;
END; $function$;
REVOKE ALL ON FUNCTION public.mithaq_list_interested_by() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.mithaq_list_interested_by() TO authenticated;

CREATE FUNCTION public.mithaq_list_member_relations(p_action text)
RETURNS TABLE(id uuid,display_name text,country text,region text,relation_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_actor uuid:=(SELECT auth.uid());
BEGIN
 IF v_actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=v_actor AND p.account_status='active') THEN RAISE EXCEPTION 'active_account_required' USING ERRCODE='42501'; END IF;
 IF p_action NOT IN ('interest','ignore','mutual') THEN RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023'; END IF;
 RETURN QUERY
 SELECT p.id,p.display_name,p.country,p.region,r.created_at FROM private.member_relations r JOIN public.profiles p ON p.id=r.target_id LEFT JOIN public.profile_details d ON d.id=p.id
 WHERE r.actor_id=v_actor AND r.is_active AND r.action='interest' AND p_action IN ('interest','mutual') AND p.id<>v_actor AND p.account_status='active'
 AND (p.is_published OR COALESCE(d.details->>'public_listing_consent','false')='true')
 AND (p_action='interest' OR EXISTS(SELECT 1 FROM private.member_relations back WHERE back.actor_id=p.id AND back.target_id=v_actor AND back.action='interest' AND back.is_active))
 AND NOT EXISTS(SELECT 1 FROM private.member_relations x WHERE x.is_active AND x.action IN ('block','ignore') AND ((x.actor_id=v_actor AND x.target_id=p.id) OR (x.actor_id=p.id AND x.target_id=v_actor)))
 UNION ALL
 SELECT p.id,p.display_name,p.country,p.region,r.created_at FROM private.member_relations r JOIN public.profiles p ON p.id=r.target_id LEFT JOIN public.profile_details d ON d.id=p.id
 WHERE p_action='ignore' AND r.actor_id=v_actor AND r.is_active AND r.action='ignore' AND p.id<>v_actor AND p.account_status='active'
 AND (p.is_published OR COALESCE(d.details->>'public_listing_consent','false')='true')
 ORDER BY 5 DESC LIMIT 200;
END; $function$;
REVOKE ALL ON FUNCTION public.mithaq_list_member_relations(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.mithaq_list_member_relations(text) TO authenticated;

CREATE FUNCTION public.mithaq_list_managed_profiles()
RETURNS TABLE(id uuid,display_name text,country text,region text,marriage_type text,life_text text,last_seen_at timestamptz,created_at timestamptz,details jsonb,is_platform_managed boolean,management_label text,can_interact boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF (SELECT auth.uid()) IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=(SELECT auth.uid()) AND p.account_status='active') THEN RAISE EXCEPTION 'active_account_required' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT m.id,m.display_name,m.country,m.region,m.marriage_type,m.life_text,NULL::timestamptz,m.created_at,COALESCE(m.details,'{}'::jsonb)-'neighborhood',true,'تحت إدارة ميثاق',false
 FROM private.mithaq_managed_profiles m WHERE m.is_active ORDER BY m.created_at DESC;
END; $function$;
REVOKE ALL ON FUNCTION public.mithaq_list_managed_profiles() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.mithaq_list_managed_profiles() TO authenticated;

ALTER TABLE public.profiles ALTER COLUMN member_number DROP DEFAULT;
ALTER TABLE public.profiles DROP COLUMN member_number;
DROP SEQUENCE IF EXISTS public.mithaq_member_number_seq;

CREATE OR REPLACE FUNCTION public.mithaq_admin_ai_read(p_action text DEFAULT 'overview'::text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_action text:=lower(coalesce(nullif(trim(p_action),''),'overview')); v_result jsonb;
BEGIN
 IF (SELECT auth.uid()) IS NULL OR NOT EXISTS(SELECT 1 FROM private.admin_users a JOIN public.profiles p ON p.id=a.user_id WHERE a.user_id=(SELECT auth.uid()) AND p.account_status='active') THEN RAISE EXCEPTION 'primary_admin_required' USING ERRCODE='42501'; END IF;
 IF v_action='overview' THEN
  SELECT jsonb_build_object('members_total',(SELECT count(*) FROM public.profiles),'members_active',(SELECT count(*) FROM public.profiles WHERE account_status='active'),'members_suspended',(SELECT count(*) FROM public.profiles WHERE account_status='suspended'),'members_published',(SELECT count(*) FROM public.profiles WHERE is_published),'messages_total',(SELECT count(*) FROM public.messages),'subscriptions_total',(SELECT count(*) FROM public.mithaq_premium_subscriptions),'subscriptions_active',(SELECT count(*) FROM public.mithaq_premium_subscriptions WHERE status='active'),'reports_new',(SELECT count(*) FROM private.member_reports WHERE status='new'),'managed_profiles_total',(SELECT count(*) FROM private.mithaq_managed_profiles),'managed_profiles_active',(SELECT count(*) FROM private.mithaq_managed_profiles WHERE is_active),'notifications_total',(SELECT count(*) FROM public.mithaq_notifications)) INTO v_result;
 ELSIF v_action='members' THEN
  SELECT coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) INTO v_result FROM (SELECT id,display_name,country,region,marriage_type,account_status,bio_review_status,is_published,created_at,last_seen_at FROM public.profiles ORDER BY created_at DESC LIMIT 50) q;
 ELSIF v_action='subscriptions' THEN
  SELECT coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) INTO v_result FROM (SELECT s.id,s.user_id,p.display_name,s.status,s.plan_code,s.country,s.amount_sar,s.currency,s.starts_at,s.expires_at,s.created_at FROM public.mithaq_premium_subscriptions s LEFT JOIN public.profiles p ON p.id=s.user_id ORDER BY s.created_at DESC LIMIT 50) q;
 ELSIF v_action='managed_profiles' THEN
  SELECT coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) INTO v_result FROM (SELECT id,display_name,gender,age,country,region,marriage_type,is_active,created_at,updated_at FROM private.mithaq_managed_profiles ORDER BY created_at DESC LIMIT 100) q;
 ELSIF v_action='schema' THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object('schema',c.table_schema,'table',c.table_name,'columns',c.column_names) ORDER BY c.table_schema,c.table_name),'[]'::jsonb) INTO v_result
  FROM (SELECT table_schema,table_name,jsonb_agg(jsonb_build_object('name',column_name,'type',data_type) ORDER BY ordinal_position) column_names FROM information_schema.columns WHERE table_schema IN ('public','private') GROUP BY table_schema,table_name) c;
 ELSE RAISE EXCEPTION 'unsupported_admin_read_action' USING ERRCODE='22023'; END IF;
 RETURN v_result;
END; $function$;
