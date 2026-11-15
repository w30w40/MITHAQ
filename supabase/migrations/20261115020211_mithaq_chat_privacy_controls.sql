create table if not exists public.mithaq_chat_privacy_settings (
 user_id uuid primary key references auth.users(id) on delete cascade,
 show_last_seen boolean not null default true,
 read_receipts boolean not null default true,
 typing_indicators boolean not null default true,
 updated_at timestamptz not null default now()
);
alter table public.mithaq_chat_privacy_settings enable row level security;
drop policy if exists mithaq_chat_privacy_own on public.mithaq_chat_privacy_settings;
create policy mithaq_chat_privacy_own on public.mithaq_chat_privacy_settings
 for all to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
grant select,insert,update,delete on public.mithaq_chat_privacy_settings to authenticated;
revoke all on public.mithaq_chat_privacy_settings from anon;

create or replace function public.mithaq_public_member_profiles_v2(p_user_ids uuid[] default null)
returns table(id uuid,display_name text,country text,region text,marriage_type text,life_text text,last_seen_at timestamptz,created_at timestamptz,details jsonb,member_number bigint)
language plpgsql stable security definer set search_path='' as $function$
begin
 if (select auth.uid()) is null or not exists(select 1 from public.profiles actor where actor.id=(select auth.uid()) and actor.account_status='active') then
  raise exception 'active_account_required' using errcode='42501';
 end if;
 return query
 select
  p.id,p.display_name,p.country,p.region,p.marriage_type,
  case when p.bio_review_status='approved' then coalesce(p.life_text,'') else '' end,
  case when coalesce(privacy.show_last_seen,true) then p.last_seen_at else null end,
  p.created_at,
  ((coalesce(d.details,'{}'::jsonb)-array['email','email_verified','phone','phone_number','phone_verified','mobile','full_name','address','private','monthly_income','financial_status','public_listing_consent','health_public','sub','password','token','secret']::text[])
    - case when coalesce(d.details->>'health_public','false')='true' then array[]::text[] else array['health']::text[] end)
    - case when p.bio_review_status='approved' then array[]::text[] else array['about']::text[] end,
  p.member_number
 from public.profiles p
 left join public.profile_details d on d.id=p.id
 left join public.mithaq_chat_privacy_settings privacy on privacy.user_id=p.id
 where p.id<>(select auth.uid())
  and p.account_status='active'
  and (p.is_published=true or coalesce(d.details->>'public_listing_consent','false')='true')
  and (p_user_ids is null or p.id=any(p_user_ids))
  and not exists(
   select 1 from private.member_relations r
   where r.is_active and r.action in ('ignore','block')
    and ((r.actor_id=(select auth.uid()) and r.target_id=p.id)
      or (r.actor_id=p.id and r.target_id=(select auth.uid()) and r.action='block'))
  )
 order by p.created_at desc;
end;$function$;
revoke all on function public.mithaq_public_member_profiles_v2(uuid[]) from public,anon;
grant execute on function public.mithaq_public_member_profiles_v2(uuid[]) to authenticated;

create or replace function public.mithaq_mark_messages_read(p_sender_id uuid default null)
returns integer language plpgsql security definer set search_path='' as $function$
declare v_actor uuid := (select auth.uid()); affected integer;
begin
 if v_actor is null or not exists(select 1 from public.profiles p where p.id=v_actor and p.account_status='active') then
  raise exception 'active_account_required' using errcode='42501';
 end if;
 if not coalesce((select s.read_receipts from public.mithaq_chat_privacy_settings s where s.user_id=v_actor),true) then
  return 0;
 end if;
 update public.messages set read_at=now()
 where recipient_id=v_actor and read_at is null and (p_sender_id is null or sender_id=p_sender_id);
 get diagnostics affected=row_count;
 return affected;
end;$function$;
revoke all on function public.mithaq_mark_messages_read(uuid) from public,anon;
grant execute on function public.mithaq_mark_messages_read(uuid) to authenticated;