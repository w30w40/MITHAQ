-- Applied to production as Supabase migration 20261112225851_mithaq_security_hardening_20261113.
-- Remove table-wide TRUNCATE from ordinary signed-in users. The app and Edge Function
-- use row-scoped DELETE/UPSERT operations; no runtime path requires TRUNCATE.
REVOKE TRUNCATE ON TABLE public.mithaq_notifications FROM authenticated;
REVOKE TRUNCATE ON TABLE public.mithaq_push_subscriptions FROM authenticated;

-- Keep the limited moderator's response minimal. The review UI needs only username
-- and submitted bio; health, financial, contact, and other profile details stay private.
CREATE OR REPLACE FUNCTION public.mithaq_moderator_list_members()
RETURNS TABLE(
  id uuid,
  display_name text,
  country text,
  region text,
  marriage_type text,
  life_text text,
  account_status text,
  bio_review_status text,
  created_at timestamp with time zone,
  last_seen_at timestamp with time zone,
  details jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF (SELECT auth.uid()) IS NULL OR NOT public.mithaq_is_moderator() THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.display_name,
    p.country,
    p.region,
    p.marriage_type,
    p.life_text,
    p.account_status,
    p.bio_review_status,
    p.created_at,
    p.last_seen_at,
    COALESCE(
      jsonb_strip_nulls(
        jsonb_build_object(
          'username', d.details -> 'username',
          'about', d.details -> 'about'
        )
      ),
      '{}'::jsonb
    )
  FROM public.profiles p
  LEFT JOIN public.profile_details d ON d.id = p.id
  ORDER BY p.created_at DESC
  LIMIT 500;
END;
$function$;
