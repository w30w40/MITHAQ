create or replace function public.mithaq_chat_edit_message(p_message_id uuid,p_body text)
returns void language plpgsql security definer set search_path='' as $function$
declare v_actor uuid := (select auth.uid());
begin
 if v_actor is null or not exists(select 1 from public.profiles p where p.id=v_actor and p.account_status='active') then
  raise exception 'active_account_required' using errcode='42501';
 end if;
 if p_body is null or char_length(btrim(p_body))<1 or char_length(p_body)>5000 then
  raise exception 'نص الرسالة غير صالح' using errcode='22023';
 end if;
 update public.messages set body=btrim(p_body),edited_at=now()
 where id=p_message_id and sender_id=v_actor and deleted_for_everyone_at is null and created_at>=now()-interval '15 minutes';
 if not found then raise exception 'لا يمكن تعديل الرسالة: انتهت مهلة التعديل أو لا تملك صلاحية تعديلها' using errcode='42501'; end if;
end;$function$;
revoke all on function public.mithaq_chat_edit_message(uuid,text) from public,anon;
grant execute on function public.mithaq_chat_edit_message(uuid,text) to authenticated;