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


create or replace function public.mithaq_admin_list_subscriptions()
returns table(
 id uuid, user_id uuid, display_name text, email text, status text,
 plan_code text, country text, amount_sar numeric, currency text,
 starts_at timestamptz, expires_at timestamptz, created_at timestamptz
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
 select s.id,s.user_id,coalesce(p.display_name,'عضو'),u.email::text,
        s.status,s.plan_code,s.country,s.amount_sar,s.currency,
        s.starts_at,s.expires_at,s.created_at
 from public.mithaq_premium_subscriptions s
 join auth.users u on u.id=s.user_id
 left join public.profiles p on p.id=s.user_id
 order by s.created_at desc
 limit 300;
end;
$function$;

create or replace function public.mithaq_manage_premium_subscription(
 p_action text,
 p_user_id uuid,
 p_plan_code text default 'monthly',
 p_country text default null,
 p_amount_sar numeric default null,
 p_currency text default 'SAR',
 p_starts_at timestamptz default now(),
 p_expires_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
 v_id uuid;
 v_currency text := upper(trim(coalesce(p_currency,'SAR')));
begin
 if (select auth.uid()) is null or not public.mithaq_is_admin() then
  raise exception 'not_authorized' using errcode='42501';
 end if;
 if p_user_id is null then
  raise exception 'user_id_required' using errcode='22023';
 end if;
 if p_action='cancel' then
  update public.mithaq_premium_subscriptions
     set status='canceled',updated_at=now()
   where user_id=p_user_id and status in ('active','pending');
  if not found then raise exception 'active_subscription_not_found' using errcode='P0002'; end if;
  return null;
 elsif p_action='activate' then
  if not exists (
   select 1 from public.profiles p
   where p.id=p_user_id and p.account_status='active'
  ) then
   raise exception 'active_member_not_found' using errcode='P0002';
  end if;
  if coalesce(trim(p_plan_code),'')='' or length(trim(p_plan_code))>40 then
   raise exception 'invalid_plan_code' using errcode='22023';
  end if;
  if p_amount_sar is null or p_amount_sar<0 then
   raise exception 'invalid_amount_sar' using errcode='22023';
  end if;
  if v_currency !~ '^[A-Z]{3}$' then
   raise exception 'invalid_currency_code' using errcode='22023';
  end if;
  if p_starts_at is null or p_expires_at is null or p_expires_at<=p_starts_at then
   raise exception 'invalid_subscription_dates' using errcode='22023';
  end if;
  update public.mithaq_premium_subscriptions
     set status='expired',updated_at=now()
   where user_id=p_user_id and status='active';
  insert into public.mithaq_premium_subscriptions(
   user_id,status,plan_code,country,amount_sar,currency,starts_at,expires_at
  ) values (
   p_user_id,'active',trim(p_plan_code),nullif(left(trim(coalesce(p_country,'')),80),''),
   p_amount_sar,v_currency,p_starts_at,p_expires_at
  ) returning id into v_id;
  return v_id;
 else
  raise exception 'invalid_action' using errcode='22023';
 end if;
end;
$function$;

revoke all on function public.mithaq_admin_list_subscriptions() from public, anon;
revoke all on function public.mithaq_manage_premium_subscription(text,uuid,text,text,numeric,text,timestamptz,timestamptz) from public, anon;
grant execute on function public.mithaq_admin_list_subscriptions() to authenticated;
grant execute on function public.mithaq_manage_premium_subscription(text,uuid,text,text,numeric,text,timestamptz,timestamptz) to authenticated;
