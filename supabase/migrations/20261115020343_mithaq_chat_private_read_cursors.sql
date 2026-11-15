alter table public.mithaq_chat_preferences add column if not exists last_read_at timestamptz null;
create or replace function public.mithaq_mark_messages_read(p_sender_id uuid default null)
returns integer language plpgsql security definer set search_path='' as $function$
declare v_actor uuid := (select auth.uid()); affected integer; v_receipts boolean;
begin
 if v_actor is null or not exists(select 1 from public.profiles p where p.id=v_actor and p.account_status='active') then
  raise exception 'active_account_required' using errcode='42501';
 end if;
 select coalesce(s.read_receipts,true) into v_receipts
 from public.mithaq_chat_privacy_settings s where s.user_id=v_actor;
 v_receipts:=coalesce(v_receipts,true);
 if not v_receipts then
  insert into public.mithaq_chat_preferences(user_id,peer_id,last_read_at)
  select v_actor,m.sender_id,max(m.created_at)
  from public.messages m
  where m.recipient_id=v_actor and m.read_at is null and (p_sender_id is null or m.sender_id=p_sender_id)
  group by m.sender_id
  on conflict(user_id,peer_id) do update
   set last_read_at=greatest(coalesce(public.mithaq_chat_preferences.last_read_at,'-infinity'::timestamptz),excluded.last_read_at),
       updated_at=now();
  return 0;
 end if;
 update public.messages set read_at=now()
 where recipient_id=v_actor and read_at is null and (p_sender_id is null or sender_id=p_sender_id);
 get diagnostics affected=row_count;
 return affected;
end;$function$;
revoke all on function public.mithaq_mark_messages_read(uuid) from public,anon;
grant execute on function public.mithaq_mark_messages_read(uuid) to authenticated;
create or replace function public.mithaq_unread_message_count()
returns bigint language plpgsql security definer set search_path='' as $function$
declare v_actor uuid := (select auth.uid()); v_count bigint;
begin
 if v_actor is null or not exists(select 1 from public.profiles p where p.id=v_actor and p.account_status='active') then
  raise exception 'active_account_required' using errcode='42501';
 end if;
 select count(*) into v_count
 from public.messages m
 left join public.mithaq_chat_preferences cp on cp.user_id=v_actor and cp.peer_id=m.sender_id
 where m.recipient_id=v_actor and m.read_at is null
   and (cp.last_read_at is null or m.created_at>cp.last_read_at);
 return v_count;
end;$function$;
revoke all on function public.mithaq_unread_message_count() from public,anon;
grant execute on function public.mithaq_unread_message_count() to authenticated;