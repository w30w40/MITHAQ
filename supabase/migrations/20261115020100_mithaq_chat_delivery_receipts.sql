alter table public.messages add column if not exists delivered_at timestamptz null;
create or replace function public.mithaq_mark_messages_delivered(p_sender_id uuid default null)
returns integer language plpgsql security definer set search_path='' as $function$
declare v_actor uuid := (select auth.uid()); v_affected integer;
begin
 if v_actor is null or not exists(select 1 from public.profiles p where p.id=v_actor and p.account_status='active') then
  raise exception 'active_account_required' using errcode='42501';
 end if;
 update public.messages set delivered_at=now()
 where recipient_id=v_actor and delivered_at is null and (p_sender_id is null or sender_id=p_sender_id);
 get diagnostics v_affected=row_count;
 return v_affected;
end;$function$;
revoke all on function public.mithaq_mark_messages_delivered(uuid) from public,anon;
grant execute on function public.mithaq_mark_messages_delivered(uuid) to authenticated;