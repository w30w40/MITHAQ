-- Public health information is shown only when the member explicitly opts in.
-- The health_public flag itself is never returned to other members.
CREATE OR REPLACE FUNCTION public.mithaq_public_member_profiles_v2(p_user_ids uuid[] DEFAULT NULL::uuid[])
RETURNS TABLE(
 id uuid, display_name text, country text, region text, marriage_type text,
 life_text text, last_seen_at timestamptz, created_at timestamptz, details jsonb, member_number bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF (SELECT auth.uid()) IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM public.profiles actor
       WHERE actor.id = (SELECT auth.uid())
         AND actor.account_status = 'active'
     ) THEN
    RAISE EXCEPTION 'active_account_required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.display_name,
    p.country,
    p.region,
    p.marriage_type,
    CASE WHEN p.bio_review_status = 'approved' THEN COALESCE(p.life_text,'') ELSE '' END,
    p.last_seen_at,
    p.created_at,
    (
      (COALESCE(d.details,'{}'::jsonb)
        - ARRAY['email','email_verified','phone','phone_number','phone_verified','mobile','full_name','address','private','monthly_income','financial_status','public_listing_consent','health_public','sub','password','token','secret']::text[])
      - CASE
          WHEN COALESCE(d.details->>'health_public','false') = 'true' THEN ARRAY[]::text[]
          ELSE ARRAY['health']::text[]
        END
    ) - CASE WHEN p.bio_review_status = 'approved' THEN ARRAY[]::text[] ELSE ARRAY['about']::text[] END,
    p.member_number
  FROM public.profiles p
  LEFT JOIN public.profile_details d ON d.id = p.id
  WHERE p.id <> (SELECT auth.uid())
    AND p.account_status = 'active'
    AND (
      p.is_published = true
      OR COALESCE(d.details ->> 'public_listing_consent','false') = 'true'
    )
    AND (p_user_ids IS NULL OR p.id = ANY(p_user_ids))
    AND NOT EXISTS (
      SELECT 1
      FROM private.member_relations r
      WHERE r.is_active
        AND r.action IN ('ignore','block')
        AND (
          (r.actor_id = (SELECT auth.uid()) AND r.target_id = p.id)
          OR (r.actor_id = p.id AND r.target_id = (SELECT auth.uid()) AND r.action = 'block')
        )
    )
  ORDER BY p.created_at DESC;
END;
$function$;
REVOKE ALL ON FUNCTION public.mithaq_public_member_profiles_v2(uuid[]) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.mithaq_public_member_profiles_v2(uuid[]) TO authenticated;
