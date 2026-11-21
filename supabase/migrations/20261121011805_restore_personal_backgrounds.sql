UPDATE public.mithaq_profile_backgrounds
SET is_enabled = true, updated_at = now()
WHERE is_enabled = false
  AND updated_at = '2026-11-21 01:07:12.310382+00'::timestamptz;
