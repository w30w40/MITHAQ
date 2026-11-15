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
 where m.recipient_id=v_actor and m.read_at is null and m.deleted_for_everyone_at is null
   and (cp.last_read_at is null or m.created_at>cp.last_read_at);
 return v_count;
end;$function$;
revoke all on function public.mithaq_unread_message_count() from public,anon;
grant execute on function public.mithaq_unread_message_count() to authenticated;