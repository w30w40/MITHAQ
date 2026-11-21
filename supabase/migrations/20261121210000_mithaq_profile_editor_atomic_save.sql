-- Fix profile editing permissions and make profile saves atomic.
GRANT USAGE ON SEQUENCE public.mithaq_member_number_seq TO authenticated;

CREATE OR REPLACE FUNCTION public.mithaq_save_own_profile(
  p_details jsonb,
  p_display_name text,
  p_country text,
  p_region text,
  p_marriage_type text,
  p_life_text text
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(COALESCE(p_details, '{}'::jsonb)) <> 'object' THEN
    RAISE EXCEPTION 'profile_details_must_be_object' USING ERRCODE = '22023';
  END IF;
  IF NULLIF(btrim(COALESCE(p_display_name, '')), '') IS NULL THEN
    RAISE EXCEPTION 'display_name_required' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.profile_details (id, details, updated_at)
  VALUES (v_uid, COALESCE(p_details, '{}'::jsonb), now())
  ON CONFLICT (id) DO UPDATE SET details = EXCLUDED.details, updated_at = now();

  INSERT INTO public.profiles
    (id, display_name, country, region, marriage_type, life_text, last_seen_at, updated_at)
  VALUES
    (v_uid, btrim(p_display_name), NULLIF(btrim(COALESCE(p_country, '')), ''),
     NULLIF(btrim(COALESCE(p_region, '')), ''),
     NULLIF(btrim(COALESCE(p_marriage_type, '')), ''),
     COALESCE(p_life_text, ''), now(), now())
  ON CONFLICT (id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    country = EXCLUDED.country,
    region = EXCLUDED.region,
    marriage_type = EXCLUDED.marriage_type,
    life_text = EXCLUDED.life_text,
    last_seen_at = now(),
    updated_at = now();
END;
$function$;

REVOKE ALL ON FUNCTION public.mithaq_save_own_profile(jsonb,text,text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mithaq_save_own_profile(jsonb,text,text,text,text,text) TO authenticated;

-- Keep partner preferences private unless the owner explicitly opts in.
CREATE OR REPLACE FUNCTION public.mithaq_public_member_profiles_v2(p_user_ids uuid[] DEFAULT NULL::uuid[])
RETURNS TABLE(
 id uuid, display_name text, country text, region text, marriage_type text,
 life_text text, last_seen_at timestamptz, created_at timestamptz, details jsonb, member_number bigint
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF (SELECT auth.uid()) IS NULL OR NOT EXISTS (
   SELECT 1 FROM public.profiles actor
   WHERE actor.id = (SELECT auth.uid()) AND actor.account_status = 'active'
 ) THEN
   RAISE EXCEPTION 'active_account_required' USING ERRCODE = '42501';
 END IF;
 RETURN QUERY
 SELECT
   p.id, p.display_name, p.country, p.region, p.marriage_type,
   CASE WHEN p.bio_review_status = 'approved' THEN COALESCE(p.life_text,'') ELSE '' END,
   CASE WHEN COALESCE(privacy.show_last_seen,true) THEN p.last_seen_at ELSE NULL END,
   p.created_at,
   (
     (
       COALESCE(d.details,'{}'::jsonb)
       - ARRAY['email','email_verified','phone','phone_number','phone_verified','mobile','full_name','address','private','monthly_income','financial_status','public_listing_consent','health_public','partner_preferences_public','sub','password','token','secret']::text[]
     )
     - CASE WHEN COALESCE(d.details->>'health_public','false') = 'true'
         THEN ARRAY[]::text[] ELSE ARRAY['health']::text[] END
     - CASE WHEN p.bio_review_status = 'approved'
         THEN ARRAY[]::text[] ELSE ARRAY['about']::text[] END
     - CASE WHEN COALESCE(d.details->>'partner_preferences_public','false') = 'true'
         THEN ARRAY[]::text[] ELSE ARRAY['partner_preferences']::text[] END
   ),
   p.member_number
 FROM public.profiles p
 LEFT JOIN public.profile_details d ON d.id = p.id
 LEFT JOIN public.mithaq_chat_privacy_settings privacy ON privacy.user_id = p.id
 WHERE p.id <> (SELECT auth.uid())
   AND p.account_status = 'active'
   AND (p.is_published = true OR COALESCE(d.details->>'public_listing_consent','false') = 'true')
   AND (p_user_ids IS NULL OR p.id = ANY(p_user_ids))
   AND NOT EXISTS (
     SELECT 1 FROM private.member_relations r
     WHERE r.is_active AND r.action IN ('ignore','block')
       AND (
         (r.actor_id = (SELECT auth.uid()) AND r.target_id = p.id)
         OR (r.actor_id = p.id AND r.target_id = (SELECT auth.uid()) AND r.action = 'block')
       )
   )
 ORDER BY p.created_at DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.mithaq_public_member_profiles_v2(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mithaq_public_member_profiles_v2(uuid[]) TO authenticated;
