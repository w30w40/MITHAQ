-- Capture sanitized browser runtime failures for MITHAQ administrators.
-- The event table is intentionally inaccessible through direct Data API table grants.
-- Writes and reads are performed only through tightly scoped SECURITY DEFINER RPCs
-- that validate auth.uid() and, for reads, the primary-admin allowlist.

create table public.mithaq_client_error_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null check (event_type in ('javascript', 'promise_rejection', 'resource')),
  message text not null check (char_length(message) between 1 and 1000),
  source_path text check (source_path is null or (char_length(source_path) <= 300 and source_path ~ '^/[A-Za-z0-9_./-]*$')),
  line_number integer check (line_number is null or line_number between 0 and 1000000),
  column_number integer check (column_number is null or column_number between 0 and 1000000),
  created_at timestamptz not null default now()
);

create index mithaq_client_error_events_created_at_idx
  on public.mithaq_client_error_events (created_at desc);
create index mithaq_client_error_events_user_created_idx
  on public.mithaq_client_error_events (user_id, created_at desc);

alter table public.mithaq_client_error_events enable row level security;
revoke all on table public.mithaq_client_error_events from public, anon, authenticated;

create or replace function public.mithaq_report_client_error(
  p_event_type text,
  p_message text,
  p_source_path text default null,
  p_line_number integer default null,
  p_column_number integer default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_message text := left(btrim(coalesce(p_message, '')), 1000);
  v_source_path text := case
    when p_source_path is not null
      and char_length(p_source_path) <= 300
      and p_source_path ~ '^/[A-Za-z0-9_./-]*$'
    then p_source_path
    else null
  end;
  v_count integer;
  v_id uuid;
begin
  if v_user_id is null then
    raise exception 'authenticated_user_required' using errcode = '42501';
  end if;

  if p_event_type not in ('javascript', 'promise_rejection', 'resource')
     or char_length(v_message) = 0 then
    raise exception 'invalid_client_error_event' using errcode = '22023';
  end if;

  select count(*)::integer
    into v_count
    from public.mithaq_client_error_events e
   where e.user_id = v_user_id
     and e.created_at > now() - interval '1 minute';

  if v_count >= 10 then
    return jsonb_build_object('ok', false, 'rate_limited', true);
  end if;

  insert into public.mithaq_client_error_events
    (user_id, event_type, message, source_path, line_number, column_number)
  values
    (v_user_id, p_event_type, v_message, v_source_path,
     case when p_line_number between 0 and 1000000 then p_line_number else null end,
     case when p_column_number between 0 and 1000000 then p_column_number else null end)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$function$;

revoke all on function public.mithaq_report_client_error(text, text, text, integer, integer) from public, anon;
grant execute on function public.mithaq_report_client_error(text, text, text, integer, integer) to authenticated;

create or replace function public.mithaq_admin_ai_client_errors(p_limit integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_result jsonb;
begin
  if (select auth.uid()) is null
     or not exists (
       select 1
         from private.admin_users a
         join public.profiles p on p.id = a.user_id
        where a.user_id = (select auth.uid())
          and p.account_status = 'active'
     ) then
    raise exception 'primary_admin_required' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc), '[]'::jsonb)
    into v_result
    from (
      select id, event_type, message, source_path, line_number, column_number, created_at
        from public.mithaq_client_error_events
       order by created_at desc
       limit greatest(1, least(coalesce(p_limit, 30), 100))
    ) q;

  return v_result;
end;
$function$;

revoke all on function public.mithaq_admin_ai_client_errors(integer) from public, anon;
grant execute on function public.mithaq_admin_ai_client_errors(integer) to authenticated;
