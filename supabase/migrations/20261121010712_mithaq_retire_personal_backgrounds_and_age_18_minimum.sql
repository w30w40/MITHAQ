ALTER TABLE private.mithaq_managed_profiles
  ADD CONSTRAINT mithaq_managed_profiles_age_min_18
  CHECK (age >= 18);

CREATE OR REPLACE FUNCTION public.mithaq_enforce_member_age_minimum_18()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_age text;
BEGIN
  v_age := NULLIF(BTRIM(NEW.details->>'age'), '');
  IF v_age IS NOT NULL THEN
    IF v_age !~ '^[0-9]{1,3}$' OR v_age::integer < 18 THEN
      RAISE EXCEPTION 'minimum_member_age_is_18' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS mithaq_profile_details_age_min_18 ON public.profile_details;
CREATE TRIGGER mithaq_profile_details_age_min_18
BEFORE INSERT OR UPDATE ON public.profile_details
FOR EACH ROW
EXECUTE FUNCTION public.mithaq_enforce_member_age_minimum_18();

ALTER TABLE public.mithaq_notifications
  DROP CONSTRAINT IF EXISTS mithaq_notifications_notification_type_check;
ALTER TABLE public.mithaq_notifications
  ADD CONSTRAINT mithaq_notifications_notification_type_check
  CHECK (notification_type = ANY (ARRAY['profile_view'::text, 'interest'::text, 'new_registration'::text, 'system_update'::text]));

UPDATE public.mithaq_profile_backgrounds
SET is_enabled = false, updated_at = now()
WHERE is_enabled = true;
