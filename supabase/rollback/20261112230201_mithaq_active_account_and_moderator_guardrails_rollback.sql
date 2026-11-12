-- Emergency rollback to the function definitions immediately before migration
-- 20261112230201_mithaq_active_account_and_moderator_guardrails.
CREATE OR REPLACE FUNCTION public.mithaq_is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS(SELECT 1 FROM private.admin_users a WHERE a.user_id=(SELECT auth.uid()));
$function$;
CREATE OR REPLACE FUNCTION public.mithaq_is_moderator()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS(SELECT 1 FROM private.moderator_users m WHERE m.user_id=(SELECT auth.uid()));
$function$;
CREATE OR REPLACE FUNCTION public.mithaq_moderator_list_members()
RETURNS TABLE(id uuid,display_name text,country text,region text,marriage_type text,life_text text,account_status text,bio_review_status text,created_at timestamptz,last_seen_at timestamptz,details jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  IF (SELECT auth.uid()) IS NULL OR NOT public.mithaq_is_moderator() THEN RAISE EXCEPTION 'not_authorized' USING ERRCODE='42501'; END IF;
  RETURN QUERY
  SELECT p.id,p.display_name,p.country,p.region,p.marriage_type,p.life_text,p.account_status,p.bio_review_status,p.created_at,p.last_seen_at,
    COALESCE(jsonb_strip_nulls(jsonb_build_object('username',d.details->'username','about',d.details->'about')),'{}'::jsonb)
  FROM public.profiles p LEFT JOIN public.profile_details d ON d.id=p.id
  ORDER BY p.created_at DESC LIMIT 500;
END;
$function$;
-- The remaining functions are restored by re-applying their prior definitions from
-- migration history if a rollback is needed. Do not use this partial rollback alone.
