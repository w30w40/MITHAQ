-- MITHAQ Admin Foundation
-- Run as the Supabase database owner. The first administrator is intentionally NOT
-- auto-assigned. Add the owner's confirmed Auth user UUID to private.admin_users
-- only after verifying the owner identity.

begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create unique index if not exists admin_users_single_admin on private.admin_users ((true));
revoke all on private.admin_users from public, anon, authenticated;

alter table public.profiles
  add column if not exists account_status text not null default 'active';
alter table public.profiles add column if not exists bio_review_status text not null default 'pending';
alter table public.profiles drop constraint if exists profiles_bio_review_status_check;
alter table public.profiles add constraint profiles_bio_review_status_check check (bio_review_status in ('pending','approved','rejected'));
update public.profiles set bio_review_status='approved' where is_published=true and bio_review_status='pending';
alter table public.profiles drop constraint if exists profiles_account_status_check;
alter table public.profiles
  add constraint profiles_account_status_check check (account_status in ('active','suspended'));

create or replace function public.mithaq_is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from private.admin_users a where a.user_id = (select auth.uid()));
$$;
revoke all on function public.mithaq_is_admin() from public, anon;
grant execute on function public.mithaq_is_admin() to authenticated;

drop policy if exists "View published profiles or own" on public.profiles;
drop policy if exists "members_read_published_profiles_or_own" on public.profiles;
drop policy if exists "mithaq_admin_read_all_profiles" on public.profiles;
create policy "mithaq_profiles_visible_to_members_and_admin"
on public.profiles for select to authenticated
using ((is_published = true and bio_review_status = 'approved' and account_status = 'active')
       or id = (select auth.uid())
       or (select public.mithaq_is_admin()));

-- Clients cannot change account_status directly. They may update only profile fields.
revoke update on table public.profiles from public, anon, authenticated;
grant update (id, display_name, country, region, marriage_type, life_text,
              updated_at, last_seen_at)
on public.profiles to authenticated;

create or replace function public.mithaq_admin_stats()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.mithaq_is_admin() then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'members_total', (select count(*) from public.profiles),
    'members_active', (select count(*) from public.profiles where account_status = 'active'),
    'members_suspended', (select count(*) from public.profiles where account_status = 'suspended'),
    'messages_total', (select count(*) from public.messages)
  );
end;
$$;
revoke all on function public.mithaq_admin_stats() from public, anon;
grant execute on function public.mithaq_admin_stats() to authenticated;

create or replace function public.mithaq_admin_set_account_status(p_user_id uuid, p_status text)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  if not public.mithaq_is_admin() then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
  if p_status not in ('active','suspended') then
    raise exception 'invalid_status' using errcode = '22023';
  end if;
  if p_user_id = (select auth.uid()) and p_status = 'suspended' then
    raise exception 'cannot_suspend_self' using errcode = '22023';
  end if;
  update public.profiles set account_status = p_status, updated_at = now() where id = p_user_id;
  if not found then raise exception 'member_not_found' using errcode = 'P0002'; end if;
  return true;
end;
$$;
revoke all on function public.mithaq_admin_set_account_status(uuid,text) from public, anon;
grant execute on function public.mithaq_admin_set_account_status(uuid,text) to authenticated;

drop policy if exists "members read their own messages" on public.messages;
drop policy if exists "members send direct messages" on public.messages;
create policy "mithaq_active_members_read_own_messages"
on public.messages for select to authenticated
using (
  (sender_id = (select auth.uid()) or recipient_id = (select auth.uid()))
  and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.account_status = 'active')
);
create policy "mithaq_active_members_send_direct_messages"
on public.messages for insert to authenticated
with check (
  sender_id = (select auth.uid()) and recipient_id <> (select auth.uid())
  and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.account_status = 'active')
  and exists (select 1 from public.profiles p where p.id = recipient_id and p.account_status = 'active')
);


revoke update (is_published, bio_review_status) on public.profiles from public, anon, authenticated;

drop function if exists public.mithaq_admin_list_members();
create function public.mithaq_admin_list_members()
returns table (
  id uuid, display_name text, country text, region text, marriage_type text,
  life_text text, account_status text, bio_review_status text,
  created_at timestamptz, email text, last_seen_at timestamptz,
  auth_last_sign_in_at timestamptz, details jsonb
)
language plpgsql security definer set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not exists (
    select 1 from private.admin_users a where a.user_id = (select auth.uid())
  ) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
  return query
  select p.id, p.display_name, p.country, p.region, p.marriage_type,
    p.life_text, p.account_status, p.bio_review_status, p.created_at,
    u.email::text, p.last_seen_at, u.last_sign_in_at,
    coalesce(d.details, '{}'::jsonb)
  from public.profiles p
  join auth.users u on u.id = p.id
  left join public.profile_details d on d.id = p.id
  order by p.created_at desc
  limit 500;
end;
$$;
revoke all on function public.mithaq_admin_list_members() from public, anon;
grant execute on function public.mithaq_admin_list_members() to authenticated;

create or replace function public.mithaq_admin_review_bio(p_user_id uuid,p_approve boolean)
returns void language plpgsql security definer set search_path = public, private, auth
as $
begin
  if not public.mithaq_is_admin() then raise exception 'not_authorized' using errcode='42501'; end if;
  update public.profiles set bio_review_status=case when p_approve then 'approved' else 'rejected' end,
    is_published=p_approve,updated_at=now() where id=p_user_id;
  if not found then raise exception 'profile_not_found' using errcode='P0002'; end if;
end;
$;
revoke all on function public.mithaq_admin_review_bio(uuid,boolean) from public, anon;
grant execute on function public.mithaq_admin_review_bio(uuid,boolean) to authenticated;

create or replace function public.mithaq_sync_public_profile()
returns trigger language plpgsql security definer set search_path = public, pg_temp
as $
declare v_name text;
begin
  v_name := nullif(btrim(coalesce(new.raw_user_meta_data->>'username',new.raw_user_meta_data->>'display_name',new.raw_user_meta_data->>'name','')),'');
  if v_name is not null then
    insert into public.profiles (id,display_name,country,region,marriage_type,life_text,is_published,bio_review_status,updated_at)
    values (new.id,v_name,nullif(btrim(coalesce(new.raw_user_meta_data->>'country','')),''),
      nullif(btrim(coalesce(new.raw_user_meta_data->>'city','')),''),
      nullif(btrim(coalesce(new.raw_user_meta_data->>'marriage_type','')),''),
      coalesce(new.raw_user_meta_data->>'about',''),false,'pending',now())
    on conflict (id) do update set display_name=excluded.display_name,country=excluded.country,
      region=excluded.region,marriage_type=excluded.marriage_type,life_text=excluded.life_text,
      is_published=false,bio_review_status='pending',updated_at=now();
  end if;
  return new;
end;
$;

commit;

-- ONE-TIME ADMIN BOOTSTRAP (intentionally not run automatically):
-- Replace with the verified project-owner email and execute separately.
-- insert into private.admin_users(user_id)
-- select id from auth.users
-- where lower(email) = lower('OWNER_CONFIRMED_EMAIL') and email_confirmed_at is not null
-- on conflict (user_id) do nothing;


-- Approved public member feed: exposes only the limited fields shown on the home page.
create or replace function public.mithaq_home_feed()
returns table (
  id uuid, display_name text, gender text, age text, country text, city text,
  life_text text, last_seen_at timestamptz, is_online boolean
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  return query
  select p.id, p.display_name, coalesce(d.details->>'gender',''),
    coalesce(d.details->>'age',''), p.country,
    coalesce(nullif(d.details->>'city',''),p.region,''),
    coalesce(p.life_text,''), p.last_seen_at,
    (p.last_seen_at is not null and p.last_seen_at >= now()-interval '5 minutes')
  from public.profiles p
  left join public.profile_details d on d.id=p.id
  where p.id <> (select auth.uid())
    and p.account_status='active'
    and p.bio_review_status='approved'
    and p.is_published=true
  order by (p.last_seen_at >= now()-interval '5 minutes') desc nulls last,
    p.created_at desc
  limit 12;
end;
$$;
revoke all on function public.mithaq_home_feed() from public, anon;
grant execute on function public.mithaq_home_feed() to authenticated;

-- Mark only messages addressed to the current user as read; clients cannot update messages directly.
create or replace function public.mithaq_mark_messages_read(p_sender_id uuid default null)
returns integer language plpgsql security definer set search_path = ''
as $$
declare affected integer;
begin
  if (select auth.uid()) is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  update public.messages
  set read_at=now()
  where recipient_id=(select auth.uid())
    and read_at is null
    and (p_sender_id is null or sender_id=p_sender_id);
  get diagnostics affected = row_count;
  return affected;
end;
$$;
revoke all on function public.mithaq_mark_messages_read(uuid) from public, anon;
grant execute on function public.mithaq_mark_messages_read(uuid) to authenticated;
