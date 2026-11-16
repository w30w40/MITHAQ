-- Harden the admin bio review SECURITY DEFINER function against mutable search_path.
-- All referenced non-catalog objects are schema-qualified.
CREATE OR REPLACE FUNCTION public.mithaq_admin_review_bio(p_user_id uuid, p_approve boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NOT public.mithaq_is_admin() THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '42501';
  END IF;

  UPDATE public.profiles
  SET bio_review_status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
      is_published = p_approve,
      updated_at = now()
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'profile_not_found' USING ERRCODE = 'P0002';
  END IF;
END;
$function$;
