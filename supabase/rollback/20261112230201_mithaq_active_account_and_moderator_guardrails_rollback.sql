-- Emergency rollback to the function definitions immediately before migration
-- 20261112230201_mithaq_active_account_and_moderator_guardrails.
-- This restores the previous authorization behavior and should only be used if
-- the new guards cause a confirmed production compatibility failure.

CREATE OR REPLACE FUNCTION public.mithaq_is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM private.admin_users a
    WHERE a.user_id = (SELECT auth.uid())
  );
$function$;

CREATE OR REPLACE FUNCTION public.mithaq_is_moderator()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM private.moderator_users m
    WHERE m.user_id = (SELECT auth.uid())
  );
$function$;

CREATE OR REPLACE FUNCTION public.mithaq_home_feed()
RETURNS TABLE(id uuid,display_name text,gender text,age text,country text,city text,life_text text,last_seen_at timestamptz,is_online boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
  SELECT p.id,p.display_name,COALESCE(d.details->>'gender',''),COALESCE(d.details->>'age',''),
    p.country,COALESCE(NULLIF(d.details->>'city',''),p.region,''),
    CASE WHEN p.bio_review_status='approved' THEN COALESCE(p.life_text,'') ELSE '' END,
    p.last_seen_at,(p.last_seen_at IS NOT NULL AND p.last_seen_at>=now()-interval '5 minutes')
  FROM public.profiles p LEFT JOIN public.profile_details d ON d.id=p.id
  WHERE p.id<>(SELECT auth.uid()) AND p.account_status='active'
    AND (p.is_published=true OR COALESCE(d.details->>'public_listing_consent','false')='true')
  ORDER BY (p.last_seen_at>=now()-interval '5 minutes') DESC NULLS LAST,p.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mithaq_public_member_profiles_v2(p_user_ids uuid[] DEFAULT NULL::uuid[])
RETURNS TABLE(id uuid,display_name text,country text,region text,marriage_type text,life_text text,last_seen_at timestamptz,created_at timestamptz,details jsonb,member_number bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
  SELECT p.id,p.display_name,p.country,p.region,p.marriage_type,
    CASE WHEN p.bio_review_status='approved' THEN COALESCE(p.life_text,'') ELSE '' END,
    p.last_seen_at,p.created_at,
    (COALESCE(d.details,'{}'::jsonb)
      - ARRAY['email','email_verified','phone','phone_number','phone_verified','mobile','full_name','address','private','health','monthly_income','financial_status','public_listing_consent','sub','password','token','secret']::text[])
      - CASE WHEN p.bio_review_status='approved' THEN ARRAY[]::text[] ELSE ARRAY['about']::text[] END,
    p.member_number
  FROM public.profiles p LEFT JOIN public.profile_details d ON d.id=p.id
  WHERE p.id<>(SELECT auth.uid()) AND p.account_status='active'
    AND (p.is_published=true OR COALESCE(d.details->>'public_listing_consent','false')='true')
    AND (p_user_ids IS NULL OR p.id=ANY(p_user_ids))
    AND NOT EXISTS (
      SELECT 1 FROM private.member_relations r
      WHERE r.is_active AND r.action IN ('ignore','block')
        AND ((r.actor_id=(SELECT auth.uid()) AND r.target_id=p.id)
          OR (r.actor_id=p.id AND r.target_id=(SELECT auth.uid()) AND r.action='block'))
    )
  ORDER BY p.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mithaq_list_interested_by()
RETURNS TABLE(id uuid,display_name text,country text,region text,member_number bigint,interested_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_actor uuid := (SELECT auth.uid());
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  RETURN QUERY
  SELECT p.id,p.display_name,p.country,p.region,p.member_number,r.created_at
  FROM private.member_relations r
  JOIN public.profiles p ON p.id=r.actor_id
  LEFT JOIN public.profile_details d ON d.id=p.id
  WHERE r.target_id=v_actor AND r.action='interest' AND r.is_active=true
    AND p.id<>v_actor AND p.account_status='active'
    AND (p.is_published=true OR COALESCE(d.details->>'public_listing_consent','false')='true')
    AND NOT EXISTS (
      SELECT 1 FROM private.member_relations x
      WHERE x.is_active=true AND x.action IN ('block','ignore')
        AND ((x.actor_id=v_actor AND x.target_id=p.id) OR (x.actor_id=p.id AND x.target_id=v_actor))
    )
  ORDER BY r.created_at DESC LIMIT 100;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mithaq_get_member_actions(p_target_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_actor uuid := (SELECT auth.uid());
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF p_target_id IS NULL OR p_target_id=v_actor THEN RAISE EXCEPTION 'invalid_target'; END IF;
  RETURN jsonb_build_object(
    'interest',EXISTS(SELECT 1 FROM private.member_relations r WHERE r.actor_id=v_actor AND r.target_id=p_target_id AND r.action='interest' AND r.is_active),
    'ignored',EXISTS(SELECT 1 FROM private.member_relations r WHERE r.actor_id=v_actor AND r.target_id=p_target_id AND r.action='ignore' AND r.is_active),
    'blocked',EXISTS(SELECT 1 FROM private.member_relations r WHERE r.actor_id=v_actor AND r.target_id=p_target_id AND r.action='block' AND r.is_active)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.mithaq_mark_messages_read(p_sender_id uuid DEFAULT NULL::uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE affected integer;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  UPDATE public.messages SET read_at=now()
  WHERE recipient_id=(SELECT auth.uid()) AND read_at IS NULL
    AND (p_sender_id IS NULL OR sender_id=p_sender_id);
  GET DIAGNOSTICS affected=ROW_COUNT;
  RETURN affected;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mithaq_moderator_list_members()
RETURNS TABLE(id uuid,display_name text,country text,region text,marriage_type text,life_text text,account_status text,bio_review_status text,created_at timestamptz,last_seen_at timestamptz,details jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  IF (SELECT auth.uid()) IS NULL OR NOT public.mithaq_is_moderator() THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
  SELECT p.id,p.display_name,p.country,p.region,p.marriage_type,p.life_text,
    p.account_status,p.bio_review_status,p.created_at,p.last_seen_at,
    COALESCE(jsonb_strip_nulls(jsonb_build_object('username',d.details->'username','about',d.details->'about')),'{}'::jsonb)
  FROM public.profiles p LEFT JOIN public.profile_details d ON d.id=p.id
  ORDER BY p.created_at DESC LIMIT 500;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mithaq_moderator_review_bio(p_user_id uuid,p_approve boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  IF (SELECT auth.uid()) IS NULL OR NOT public.mithaq_is_moderator() THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE='42501';
  END IF;
  UPDATE public.profiles
  SET bio_review_status=CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
      is_published=p_approve,updated_at=now()
  WHERE id=p_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'profile_not_found' USING ERRCODE='P0002'; END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mithaq_moderator_set_account_status(p_user_id uuid,p_status text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  IF (SELECT auth.uid()) IS NULL OR NOT public.mithaq_is_moderator() THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE='42501';
  END IF;
  IF p_status NOT IN ('active','suspended') THEN RAISE EXCEPTION 'invalid_status' USING ERRCODE='22023'; END IF;
  IF p_user_id=(SELECT auth.uid()) THEN RAISE EXCEPTION 'cannot_change_own_status' USING ERRCODE='22023'; END IF;
  UPDATE public.profiles SET account_status=p_status,updated_at=now() WHERE id=p_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'member_not_found' USING ERRCODE='P0002'; END IF;
  RETURN true;
END;
$function$;
