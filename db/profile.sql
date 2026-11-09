-- MITHAQ member profile storage
-- Safe, additive migration: does not delete existing accounts or profile rows.

CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text,
  country text,
  region text,
  marriage_type text,
  life_text text,
  is_published boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS display_name text,
  ADD COLUMN IF NOT EXISTS country text,
  ADD COLUMN IF NOT EXISTS region text,
  ADD COLUMN IF NOT EXISTS marriage_type text,
  ADD COLUMN IF NOT EXISTS life_text text,
  ADD COLUMN IF NOT EXISTS is_published boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE TABLE IF NOT EXISTS public.profile_details (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.profile_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- A member can read and edit only their private, full profile details.
DROP POLICY IF EXISTS "members_read_own_profile_details" ON public.profile_details;
CREATE POLICY "members_read_own_profile_details"
ON public.profile_details FOR SELECT TO authenticated
USING (id = auth.uid());

DROP POLICY IF EXISTS "members_insert_own_profile_details" ON public.profile_details;
CREATE POLICY "members_insert_own_profile_details"
ON public.profile_details FOR INSERT TO authenticated
WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "members_update_own_profile_details" ON public.profile_details;
CREATE POLICY "members_update_own_profile_details"
ON public.profile_details FOR UPDATE TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- Public discovery exposes only the deliberately selected summary columns.
DROP POLICY IF EXISTS "members_read_published_profiles_or_own" ON public.profiles;
CREATE POLICY "members_read_published_profiles_or_own"
ON public.profiles FOR SELECT TO authenticated
USING (is_published = true OR id = auth.uid());

DROP POLICY IF EXISTS "members_insert_own_public_profile" ON public.profiles;
CREATE POLICY "members_insert_own_public_profile"
ON public.profiles FOR INSERT TO authenticated
WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "members_update_own_public_profile" ON public.profiles;
CREATE POLICY "members_update_own_public_profile"
ON public.profiles FOR UPDATE TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

GRANT SELECT, INSERT, UPDATE ON public.profile_details TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
REVOKE ALL ON public.profile_details FROM anon;
REVOKE ALL ON public.profiles FROM anon;

-- Keep full registration details in the private table for future signups.
CREATE OR REPLACE FUNCTION public.mithaq_create_private_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $
BEGIN
  INSERT INTO public.profile_details (id, details)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data, '{}'::jsonb))
  ON CONFLICT (id) DO UPDATE
  SET details = COALESCE(EXCLUDED.details, '{}'::jsonb) || COALESCE(public.profile_details.details, '{}'::jsonb),
      updated_at = now();
  RETURN NEW;
END;
$;

DROP TRIGGER IF EXISTS mithaq_auth_user_profile_created ON auth.users;
DROP TRIGGER IF EXISTS mithaq_auth_user_profile_metadata_updated ON auth.users;
CREATE TRIGGER mithaq_auth_user_profile_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.mithaq_create_private_profile();

CREATE TRIGGER mithaq_auth_user_profile_metadata_updated
AFTER UPDATE OF raw_user_meta_data ON auth.users
FOR EACH ROW
WHEN (OLD.raw_user_meta_data IS DISTINCT FROM NEW.raw_user_meta_data)
EXECUTE FUNCTION public.mithaq_create_private_profile();

-- Backfill registration metadata for existing accounts.
-- Existing saved profile fields win; missing fields are filled from Auth metadata.
INSERT INTO public.profile_details AS pd (id, details)
SELECT id, COALESCE(raw_user_meta_data, '{}'::jsonb)
FROM auth.users
ON CONFLICT (id) DO UPDATE
SET details = COALESCE(EXCLUDED.details, '{}'::jsonb) || COALESCE(pd.details, '{}'::jsonb);

-- Create/update the public summary for existing users only when it has no row yet.
-- Full personal details remain in profile_details and are never exposed by discovery.
INSERT INTO public.profiles
  (id, display_name, country, region, marriage_type, life_text, is_published)
SELECT
  u.id,
  COALESCE(NULLIF(u.raw_user_meta_data->>'username', ''), 'عضو ميثاق'),
  NULLIF(u.raw_user_meta_data->>'country', ''),
  NULLIF(u.raw_user_meta_data->>'city', ''),
  NULLIF(u.raw_user_meta_data->>'marriage_type', ''),
  COALESCE(NULLIF(u.raw_user_meta_data->>'about', ''), ''),
  false
FROM auth.users AS u
ON CONFLICT (id) DO UPDATE
SET
  display_name = COALESCE(NULLIF(NULLIF(public.profiles.display_name, ''), 'عضو ميثاق'), EXCLUDED.display_name),
  country = COALESCE(NULLIF(public.profiles.country, ''), EXCLUDED.country),
  region = COALESCE(NULLIF(public.profiles.region, ''), EXCLUDED.region),
  marriage_type = COALESCE(NULLIF(public.profiles.marriage_type, ''), EXCLUDED.marriage_type),
  life_text = COALESCE(NULLIF(public.profiles.life_text, ''), EXCLUDED.life_text);
