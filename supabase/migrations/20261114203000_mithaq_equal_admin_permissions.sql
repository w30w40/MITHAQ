-- Give the existing moderator role the same operational admin capabilities.
-- The primary owner remains in private.admin_users and is never managed by these RPCs.

create or replace function public.mithaq_is_admin()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.account_status = 'active'
      and (
        exists (select 1 from private.admin_users a where a.user_id = p.id)
        or exists (select 1 from private.moderator_users m where m.user_id = p.id)
      )
  );
$function$;

create or replace function public.mithaq_admin_list_members()
returns table(
 id uuid, display_name text, country text, region text, marriage_type text,
 life_text text, account_status text, bio_review_status text,
 created_at timestamptz, email text, last_seen_at timestamptz,
 auth_last_sign_in_at timestamptz, details jsonb
)
language plpgsql
security definer
set search_path to ''
as $function$
begin
 if (select auth.uid()) is null or not public.mithaq_is_admin() then
  raise exception 'not_authorized' using errcode='42501';
 end if;
 return query
 select p.id,p.display_name,p.country,p.region,p.marriage_type,p.life_text,
        p.account_status,p.bio_review_status,p.created_at,u.email::text,
        p.last_seen_at,u.last_sign_in_at,coalesce(d.details,'{}'::jsonb)
 from public.profiles p
 join auth.users u on u.id=p.id
 left join public.profile_details d on d.id=p.id
 order by p.created_at desc
 limit 500;
end;
$function$;

create or replace function public.mithaq_admin_list_moderators()
returns table(id uuid, display_name text, email text, created_at timestamptz)
language plpgsql
security definer
set search_path to ''
as $function$
begin
 if (select auth.uid()) is null or not public.mithaq_is_admin() then
  raise exception 'not_authorized' using errcode='42501';
 end if;
 return query
 select m.user_id, coalesce(p.display_name,'مشرف'), u.email::text, m.created_at
 from private.moderator_users m
 join auth.users u on u.id=m.user_id
 left join public.profiles p on p.id=m.user_id
 order by m.created_at, m.user_id;
end;
$function$;

create or replace function public.mithaq_admin_manageable_members()
returns table(id uuid, display_name text, email text)
language plpgsql
security definer
set search_path to ''
as $function$
begin
 if (select auth.uid()) is null or not public.mithaq_is_admin() then
  raise exception 'not_authorized' using errcode='42501';
 end if;
 return query
 select p.id, coalesce(p.display_name,'عضو'), u.email::text
 from public.profiles p
 join auth.users u on u.id=p.id
 where p.account_status='active'
   and not exists (select 1 from private.admin_users a where a.user_id=p.id)
   and not exists (select 1 from private.moderator_users m where m.user_id=p.id)
 order by p.created_at desc
 limit 500;
end;
$function$;

create or replace function public.mithaq_manage_moderator(p_action text, p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
begin
 if (select auth.uid()) is null or not public.mithaq_is_admin() then
  raise exception 'not_authorized' using errcode='42501';
 end if;
 if p_user_id is null then
  raise exception 'user_id_required' using errcode='22023';
 end if;
 if exists (select 1 from private.admin_users a where a.user_id=p_user_id) then
  raise exception 'owner_role_is_protected' using errcode='42501';
 end if;
 if p_action='add' then
  if not exists (
   select 1 from auth.users u join public.profiles p on p.id=u.id
   where u.id=p_user_id and p.account_status='active'
  ) then
   raise exception 'active_member_not_found' using errcode='P0002';
  end if;
  insert into private.moderator_users(user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;
  return true;
 elsif p_action='remove' then
  if p_user_id=(select auth.uid()) then
   raise exception 'cannot_remove_own_moderator_role' using errcode='42501';
  end if;
  delete from private.moderator_users where user_id=p_user_id;
  if not found then raise exception 'moderator_not_found' using errcode='P0002'; end if;
  return true;
 else
  raise exception 'invalid_action' using errcode='22023';
 end if;
end;
$function$;

revoke all on function public.mithaq_admin_list_moderators() from public, anon;
revoke all on function public.mithaq_admin_manageable_members() from public, anon;
revoke all on function public.mithaq_manage_moderator(text,uuid) from public, anon;
grant execute on function public.mithaq_admin_list_moderators() to authenticated;
grant execute on function public.mithaq_admin_manageable_members() to authenticated;
grant execute on function public.mithaq_manage_moderator(text,uuid) to authenticated;
