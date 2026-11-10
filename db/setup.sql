-- MITHAQ: Supabase schema setup (safe to run more than once)
-- Email/password authentication is provided by Supabase Auth.
-- Public profiles are visible only to signed-in members; private details and messages remain owner/participant-only.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  country text,
  region text,
  marriage_type text,
  life_text text not null default '',
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz
);

alter table public.profiles add column if not exists last_seen_at timestamptz;

create table if not exists public.profile_details (
  id uuid primary key references auth.users(id) on delete cascade,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint messages_no_self_message check (sender_id <> recipient_id)
);

-- No content filter and no maximum message length. Empty/whitespace-only messages are rejected.
alter table public.messages drop constraint if exists messages_body_check;
alter table public.messages
  add constraint messages_body_check check (char_length(btrim(body)) >= 1);

alter table public.profiles enable row level security;
alter table public.profile_details enable row level security;
alter table public.messages enable row level security;

drop policy if exists "View published profiles or own" on public.profiles;
drop policy if exists "Create own profile" on public.profiles;
drop policy if exists "Update own profile" on public.profiles;
drop policy if exists "members_read_published_profiles_or_own" on public.profiles;
drop policy if exists "members_insert_own_public_profile" on public.profiles;
drop policy if exists "members_update_own_public_profile" on public.profiles;
create policy "mithaq_members_read_published_profiles" on public.profiles
  for select to authenticated using (is_published = true or id = auth.uid());
create policy "mithaq_members_insert_own_profile" on public.profiles
  for insert to authenticated with check (id = auth.uid());
create policy "mithaq_members_update_own_profile" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "members_read_own_profile_details" on public.profile_details;
drop policy if exists "members_insert_own_profile_details" on public.profile_details;
drop policy if exists "members_update_own_profile_details" on public.profile_details;
create policy "mithaq_read_own_profile_details" on public.profile_details
  for select to authenticated using (id = auth.uid());
create policy "mithaq_insert_own_profile_details" on public.profile_details
  for insert to authenticated with check (id = auth.uid());
create policy "mithaq_update_own_profile_details" on public.profile_details
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "members read their own messages" on public.messages;
drop policy if exists "members send direct messages" on public.messages;
create policy "mithaq_members_read_direct_messages" on public.messages
  for select to authenticated
  using (sender_id = auth.uid() or recipient_id = auth.uid());
create policy "mithaq_members_send_direct_messages" on public.messages
  for insert to authenticated
  with check (sender_id = auth.uid() and recipient_id <> auth.uid());

grant select, insert, update on public.profiles to authenticated;
grant select, insert, update on public.profile_details to authenticated;
grant select, insert on public.messages to authenticated;

-- Enable live message events for Supabase Realtime.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;

-- Keep signup metadata in the private details table and publish only the public profile fields.
create or replace function public.mithaq_create_private_profile()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profile_details (id, details)
  values (new.id, coalesce(new.raw_user_meta_data, '{}'::jsonb))
  on conflict (id) do update
    set details = coalesce(excluded.details, '{}'::jsonb) || coalesce(public.profile_details.details, '{}'::jsonb),
        updated_at = now();
  return new;
end;
$$;

create or replace function public.mithaq_sync_public_profile()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text;
begin
  v_name := nullif(btrim(coalesce(new.raw_user_meta_data->>'username',
                                  new.raw_user_meta_data->>'display_name',
                                  new.raw_user_meta_data->>'name', '')), '');
  if v_name is not null then
    insert into public.profiles
      (id, display_name, country, region, marriage_type, life_text, is_published, updated_at)
    values
      (new.id, v_name,
       nullif(btrim(coalesce(new.raw_user_meta_data->>'country','')), ''),
       nullif(btrim(coalesce(new.raw_user_meta_data->>'city','')), ''),
       nullif(btrim(coalesce(new.raw_user_meta_data->>'marriage_type','')), ''),
       coalesce(new.raw_user_meta_data->>'about',''), true, now())
    on conflict (id) do update set
      display_name = excluded.display_name,
      country = excluded.country,
      region = excluded.region,
      marriage_type = excluded.marriage_type,
      life_text = excluded.life_text,
      is_published = true,
      updated_at = now();
  end if;
  return new;
end;
$$;

drop trigger if exists mithaq_auth_user_profile_created on auth.users;
create trigger mithaq_auth_user_profile_created
  after insert on auth.users
  for each row execute function public.mithaq_create_private_profile();
drop trigger if exists mithaq_auth_user_profile_metadata_updated on auth.users;
create trigger mithaq_auth_user_profile_metadata_updated
  after update of raw_user_meta_data on auth.users
  for each row execute function public.mithaq_create_private_profile();
drop trigger if exists mithaq_auth_public_profile_created on auth.users;
create trigger mithaq_auth_public_profile_created
  after insert on auth.users
  for each row execute function public.mithaq_sync_public_profile();
drop trigger if exists mithaq_auth_public_profile_metadata_updated on auth.users;
create trigger mithaq_auth_public_profile_metadata_updated
  after update of raw_user_meta_data on auth.users
  for each row execute function public.mithaq_sync_public_profile();

-- Trigger-only functions are not exposed as client RPC endpoints.
revoke all on function public.mithaq_create_private_profile() from public, anon, authenticated;
revoke all on function public.mithaq_sync_public_profile() from public, anon, authenticated;
