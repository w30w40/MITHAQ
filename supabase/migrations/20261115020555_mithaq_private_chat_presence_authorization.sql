create or replace function private.mithaq_chat_realtime_topic_allowed()
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
 v_actor uuid := (select auth.uid());
 v_parts text[];
 v_a uuid;
 v_b uuid;
begin
 if v_actor is null then return false; end if;
 v_parts := regexp_match(
  (select realtime.topic()),
  '^mithaq-chat-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$'
 );
 if v_parts is null then return false; end if;
 v_a := v_parts[1]::uuid;
 v_b := v_parts[2]::uuid;
 if v_a = v_b or v_actor not in (v_a,v_b) then return false; end if;
 if not exists(select 1 from public.profiles p where p.id=v_a and p.account_status='active')
    or not exists(select 1 from public.profiles p where p.id=v_b and p.account_status='active') then
  return false;
 end if;
 if exists(select 1 from public.mithaq_chat_blocks b where
   (b.blocker_id=v_a and b.blocked_id=v_b) or (b.blocker_id=v_b and b.blocked_id=v_a)) then
  return false;
 end if;
 return true;
end;
$function$;
revoke all on function private.mithaq_chat_realtime_topic_allowed() from public,anon;
grant execute on function private.mithaq_chat_realtime_topic_allowed() to authenticated;
drop policy if exists mithaq_chat_presence_read_participants on realtime.messages;
create policy mithaq_chat_presence_read_participants on realtime.messages for select to authenticated using(extension='presence' and private.mithaq_chat_realtime_topic_allowed());
drop policy if exists mithaq_chat_presence_write_participants on realtime.messages;
create policy mithaq_chat_presence_write_participants on realtime.messages for insert to authenticated with check(extension='presence' and private.mithaq_chat_realtime_topic_allowed());