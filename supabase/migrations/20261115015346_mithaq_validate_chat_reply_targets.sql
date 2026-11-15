create or replace function public.mithaq_validate_chat_reply_target()
returns trigger language plpgsql set search_path='' as $function$
declare v_sender uuid; v_recipient uuid;
begin
 if new.reply_to_message_id is null then return new; end if;
 select m.sender_id,m.recipient_id into v_sender,v_recipient
 from public.messages m where m.id=new.reply_to_message_id;
 if not found then raise exception 'الرسالة الأصلية غير متاحة' using errcode='23503'; end if;
 if least(v_sender,v_recipient) <> least(new.sender_id,new.recipient_id)
    or greatest(v_sender,v_recipient) <> greatest(new.sender_id,new.recipient_id) then
   raise exception 'لا يمكن الرد على رسالة من محادثة أخرى' using errcode='23514';
 end if;
 return new;
end;$function$;
drop trigger if exists mithaq_messages_validate_reply_target on public.messages;
create trigger mithaq_messages_validate_reply_target
before insert or update of reply_to_message_id on public.messages
for each row execute function public.mithaq_validate_chat_reply_target();