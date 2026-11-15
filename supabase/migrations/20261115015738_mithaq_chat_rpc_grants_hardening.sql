create index if not exists mithaq_chat_message_reactions_user_idx
 on public.mithaq_chat_message_reactions(user_id,message_id);
revoke all on function public.mithaq_chat_clear_local(uuid) from public,anon;
grant execute on function public.mithaq_chat_clear_local(uuid) to authenticated;
revoke all on function public.mithaq_chat_delete_message(uuid,boolean) from public,anon;
grant execute on function public.mithaq_chat_delete_message(uuid,boolean) to authenticated;
revoke all on function public.mithaq_chat_set_block(uuid,boolean) from public,anon;
grant execute on function public.mithaq_chat_set_block(uuid,boolean) to authenticated;
revoke all on function public.mithaq_chat_set_preference(uuid,text,boolean,boolean,boolean) from public,anon;
grant execute on function public.mithaq_chat_set_preference(uuid,text,boolean,boolean,boolean) to authenticated;
revoke all on function public.mithaq_mark_messages_read(uuid) from public,anon;
grant execute on function public.mithaq_mark_messages_read(uuid) to authenticated;
revoke all on function public.mithaq_guard_blocked_chat_message() from public,anon,authenticated;