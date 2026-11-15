alter table public.messages
  add column if not exists reply_to_message_id uuid null references public.messages(id) on delete set null,
  add column if not exists edited_at timestamptz null;
alter table public.mithaq_chat_preferences
  add column if not exists archived boolean not null default false,
  add column if not exists pinned boolean not null default false;
create index if not exists messages_reply_to_message_id_idx on public.messages(reply_to_message_id) where reply_to_message_id is not null;
create index if not exists mithaq_chat_preferences_inbox_idx on public.mithaq_chat_preferences(user_id,pinned desc,favorite desc,updated_at desc);
create table if not exists public.mithaq_chat_message_reactions (
 id uuid primary key default gen_random_uuid(),
 message_id uuid not null references public.messages(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 emoji text not null check(char_length(emoji) between 1 and 16),
 created_at timestamptz not null default now(),
 constraint mithaq_chat_message_reactions_unique unique(message_id,user_id,emoji)
);
create index if not exists mithaq_chat_message_reactions_message_idx on public.mithaq_chat_message_reactions(message_id,created_at);
alter table public.mithaq_chat_message_reactions enable row level security;
drop policy if exists mithaq_chat_reactions_read_participant on public.mithaq_chat_message_reactions;
create policy mithaq_chat_reactions_read_participant on public.mithaq_chat_message_reactions for select to authenticated using(exists(select 1 from public.messages m where m.id=message_id and (m.sender_id=(select auth.uid()) or m.recipient_id=(select auth.uid()))));
drop policy if exists mithaq_chat_reactions_insert_own on public.mithaq_chat_message_reactions;
create policy mithaq_chat_reactions_insert_own on public.mithaq_chat_message_reactions for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.messages m where m.id=message_id and m.deleted_for_everyone_at is null and (m.sender_id=(select auth.uid()) or m.recipient_id=(select auth.uid()))));
drop policy if exists mithaq_chat_reactions_delete_own on public.mithaq_chat_message_reactions;
create policy mithaq_chat_reactions_delete_own on public.mithaq_chat_message_reactions for delete to authenticated using(user_id=(select auth.uid()));
grant select,insert,delete on public.mithaq_chat_message_reactions to authenticated;
revoke all on public.mithaq_chat_message_reactions from anon;
create table if not exists public.mithaq_chat_message_pins (
 id uuid primary key default gen_random_uuid(),
 message_id uuid not null references public.messages(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 pinned_at timestamptz not null default now(),
 constraint mithaq_chat_message_pins_unique unique(message_id,user_id)
);
create index if not exists mithaq_chat_message_pins_user_idx on public.mithaq_chat_message_pins(user_id,pinned_at desc);
alter table public.mithaq_chat_message_pins enable row level security;
drop policy if exists mithaq_chat_pins_read_participant on public.mithaq_chat_message_pins;
create policy mithaq_chat_pins_read_participant on public.mithaq_chat_message_pins for select to authenticated using(user_id=(select auth.uid()) and exists(select 1 from public.messages m where m.id=message_id and (m.sender_id=(select auth.uid()) or m.recipient_id=(select auth.uid()))));
drop policy if exists mithaq_chat_pins_insert_own on public.mithaq_chat_message_pins;
create policy mithaq_chat_pins_insert_own on public.mithaq_chat_message_pins for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.messages m where m.id=message_id and (m.sender_id=(select auth.uid()) or m.recipient_id=(select auth.uid()))));
drop policy if exists mithaq_chat_pins_delete_own on public.mithaq_chat_message_pins;
create policy mithaq_chat_pins_delete_own on public.mithaq_chat_message_pins for delete to authenticated using(user_id=(select auth.uid()));
grant select,insert,delete on public.mithaq_chat_message_pins to authenticated;
revoke all on public.mithaq_chat_message_pins from anon;
create or replace function public.mithaq_chat_edit_message(p_message_id uuid,p_body text)
returns void language plpgsql security definer set search_path='' as $function$
declare v_actor uuid := (select auth.uid());
begin
 if v_actor is null then raise exception 'يجب تسجيل الدخول' using errcode='42501'; end if;
 if p_body is null or char_length(btrim(p_body))<1 or char_length(p_body)>5000 then raise exception 'نص الرسالة غير صالح' using errcode='22023'; end if;
 update public.messages set body=btrim(p_body),edited_at=now()
 where id=p_message_id and sender_id=v_actor and deleted_for_everyone_at is null and created_at>=now()-interval '15 minutes';
 if not found then raise exception 'لا يمكن تعديل الرسالة: انتهت مهلة التعديل أو لا تملك صلاحية تعديلها' using errcode='42501'; end if;
end;$function$;
revoke all on function public.mithaq_chat_edit_message(uuid,text) from public,anon;
grant execute on function public.mithaq_chat_edit_message(uuid,text) to authenticated;