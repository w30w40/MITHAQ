-- MITHAQ advanced public search fields and online presence
-- Run this migration in Supabase SQL Editor after deploying the site.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS gender text,
  ADD COLUMN IF NOT EXISTS family_status text,
  ADD COLUMN IF NOT EXISTS age integer,
  ADD COLUMN IF NOT EXISTS children text,
  ADD COLUMN IF NOT EXISTS nationality text,
  ADD COLUMN IF NOT EXISTS education text,
  ADD COLUMN IF NOT EXISTS work_field text,
  ADD COLUMN IF NOT EXISTS work text,
  ADD COLUMN IF NOT EXISTS religiosity text,
  ADD COLUMN IF NOT EXISTS prayer text,
  ADD COLUMN IF NOT EXISTS smoking text,
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz;

CREATE INDEX IF NOT EXISTS profiles_search_filters_idx
ON public.profiles (is_published, gender, family_status, age, education, work_field);

CREATE INDEX IF NOT EXISTS profiles_last_seen_idx
ON public.profiles (last_seen_at);

-- Existing rows remain searchable by their public summary only.
-- New/updated searchable details are written only when the member enables profile publishing.
