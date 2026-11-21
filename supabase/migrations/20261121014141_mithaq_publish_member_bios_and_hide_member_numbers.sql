CREATE OR REPLACE FUNCTION public.mithaq_public_member_profiles_v2(p_user_ids uuid[] DEFAULT NULL::uuid[])
RETURNS TABLE(id uuid,display_name text,country text,region text,marriage_type text,life_text text,last_seen_at timestamptz,created_at timestamptz,details jsonb,member_number bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF (SELECT auth.uid()) IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles actor WHERE actor.id=(SELECT auth.uid()) AND actor.account_status='active') THEN
  RAISE EXCEPTION 'active_account_required' USING ERRCODE='42501';
 END IF;
 RETURN QUERY SELECT p.id,p.display_name,p.country,p.region,p.marriage_type,
  COALESCE(NULLIF(d.details->>'about',''),p.life_text,''),
  CASE WHEN COALESCE(privacy.show_last_seen,true) THEN p.last_seen_at ELSE NULL END,
  p.created_at,
  COALESCE(d.details,'{}'::jsonb)-ARRAY['email','email_verified','phone','phone_number','phone_verified','mobile','full_name','address','private','public_listing_consent','health_public','partner_preferences_public','sub','password','token','secret','terms_version','terms_accepted_at','privacy_policy_accepted','honesty_declaration_accepted','marriage_fee_agreed','marriage_fee_amount_sar','marriage_fee_trigger']::text[],
  p.member_number
 FROM public.profiles p
 LEFT JOIN public.profile_details d ON d.id=p.id
 LEFT JOIN public.mithaq_chat_privacy_settings privacy ON privacy.user_id=p.id
 WHERE p.id<>(SELECT auth.uid()) AND p.account_status='active'
 AND (p.is_published=true OR COALESCE(d.details->>'public_listing_consent','false')='true')
 AND (p_user_ids IS NULL OR p.id=ANY(p_user_ids))
 AND NOT EXISTS(SELECT 1 FROM private.member_relations r WHERE r.is_active AND r.action IN ('ignore','block') AND ((r.actor_id=(SELECT auth.uid()) AND r.target_id=p.id) OR (r.actor_id=p.id AND r.target_id=(SELECT auth.uid()) AND r.action='block')))
 ORDER BY p.created_at DESC;
END;
$function$;
