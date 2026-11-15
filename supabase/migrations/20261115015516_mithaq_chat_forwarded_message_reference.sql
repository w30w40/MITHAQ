alter table public.messages
 add column if not exists forwarded_from_message_id uuid null references public.messages(id) on delete set null;
create index if not exists messages_forwarded_from_message_id_idx on public.messages(forwarded_from_message_id) where forwarded_from_message_id is not null;
create or replace function public.mithaq_validate_forward_source()
returns trigger language plpgsql set search_path='' as $function$
declare v_source uuid;
begin
 if new.forwarded_from_message_id is null then return new; end if;
 select m.id into v_source from public.messages m
 where m.id=new.forwarded_from_message_id and m.deleted_for_everyone_at is null;
 if not found then raise exception 'الرسالة المراد توجيهها غير متاحة لك' using errcode='42501'; end if;
 return new;
end;$function$;
drop trigger if exists mithaq_messages_validate_forward_source on public.messages;
create trigger mithaq_messages_validate_forward_source
before insert or update of forwarded_from_message_id on public.messages
for each row execute function public.mithaq_validate_forward_source();