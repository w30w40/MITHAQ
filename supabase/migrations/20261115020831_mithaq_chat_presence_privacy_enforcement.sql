create or replace function private.mithaq_chat_typing_allowed()
returns boolean language sql stable security definer set search_path=''
as $function$
 select (select auth.uid()) is not null
  and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.account_status='active')
  and coalesce((select s.typing_indicators from public.mithaq_chat_privacy_settings s where s.user_id=(select auth.uid())),true);
$function$;
revoke all on function private.mithaq_chat_typing_allowed() from public,anon;
grant execute on function private.mithaq_chat_typing_allowed() to authenticated;
drop policy if exists mithaq_chat_presence_write_participants on realtime.messages;
create policy mithaq_chat_presence_write_participants on realtime.messages for insert to authenticated with check(extension='presence' and private.mithaq_chat_realtime_topic_allowed() and private.mithaq_chat_typing_allowed());