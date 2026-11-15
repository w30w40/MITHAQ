do $migration$
begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='mithaq_chat_message_reactions') then
  alter publication supabase_realtime add table public.mithaq_chat_message_reactions;
 end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='mithaq_chat_message_pins') then
  alter publication supabase_realtime add table public.mithaq_chat_message_pins;
 end if;
end;
$migration$;