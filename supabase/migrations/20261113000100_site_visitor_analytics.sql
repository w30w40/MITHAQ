-- Visitor analytics for MITHAQ. Stores random browser/session identifiers only; no IP address or contact data.
alter table public.mithaq_site_visits enable row level security;

revoke all on table public.mithaq_site_visits from anon, authenticated;

revoke all on function public.mithaq_record_site_visit(uuid, uuid) from public;
grant execute on function public.mithaq_record_site_visit(uuid, uuid) to anon, authenticated;

-- Preserve the original visitor category for each visit. A later signup must not
-- rewrite earlier anonymous visits into registered visits.
create or replace function public.mithaq_record_site_visit(p_visitor_id uuid, p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
begin
  if p_visitor_id is null or p_session_id is null then
    raise exception 'Invalid visit identifiers';
  end if;

  insert into public.mithaq_site_visits (session_id, visitor_id, user_id)
  values (p_session_id, p_visitor_id, v_user_id)
  on conflict (session_id) do update
    set user_id = coalesce(excluded.user_id, public.mithaq_site_visits.user_id);
end;
$function$;

create or replace function public.mithaq_admin_site_analytics()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  result jsonb;
begin
  if not public.mithaq_is_admin() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'total_visits', (select count(*) from public.mithaq_site_visits),
    'unique_visitors', (select count(distinct visitor_id) from public.mithaq_site_visits),
    'guest_visitors', (select count(distinct visitor_id) from public.mithaq_site_visits where user_id is null),
    'registered_visitors', (select count(distinct user_id) from public.mithaq_site_visits where user_id is not null),
    'visits_today', (select count(*) from public.mithaq_site_visits where visited_at >= date_trunc('day', now())),
    'visitors_today', (select count(distinct visitor_id) from public.mithaq_site_visits where visited_at >= date_trunc('day', now())),
    'registered_accounts', (select count(*) from public.profiles),
    'new_accounts_today', (select count(*) from public.profiles where created_at >= date_trunc('day', now()))
  ) into result;

  return result;
end;
$function$;

revoke all on function public.mithaq_admin_site_analytics() from public, anon;
grant execute on function public.mithaq_admin_site_analytics() to authenticated;
