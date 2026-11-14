-- MITHAQ Premium membership foundation (payment provider intentionally not connected yet).
create table if not exists public.mithaq_premium_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','active','expired','canceled')),
  plan_code text not null default 'monthly',
  country text,
  amount_sar numeric(10,2),
  currency text not null default 'SAR',
  starts_at timestamptz,
  expires_at timestamptz,
  payment_provider text,
  payment_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists mithaq_premium_subscriptions_user_expiry_idx
  on public.mithaq_premium_subscriptions(user_id, expires_at desc);
alter table public.mithaq_premium_subscriptions enable row level security;
drop policy if exists mithaq_premium_read_own_subscription on public.mithaq_premium_subscriptions;
create policy mithaq_premium_read_own_subscription on public.mithaq_premium_subscriptions
 for select to authenticated using (user_id = (select auth.uid()));
revoke insert, update, delete on public.mithaq_premium_subscriptions from anon, authenticated;
grant select on public.mithaq_premium_subscriptions to authenticated;

create or replace function private.mithaq_is_premium_user(p_user_id uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
 select exists (
   select 1 from public.mithaq_premium_subscriptions s
   where s.user_id = p_user_id and s.status = 'active'
     and s.starts_at is not null and s.starts_at <= now()
     and s.expires_at is not null and s.expires_at > now()
 );
$$;
revoke all on function private.mithaq_is_premium_user(uuid) from public, anon, authenticated;
grant execute on function private.mithaq_is_premium_user(uuid) to authenticated, service_role;

create or replace function public.mithaq_my_membership()
returns table(is_premium boolean, status text, expires_at timestamptz, plan_code text, country text, amount_sar numeric)
language sql stable security definer set search_path = ''
as $$
 select private.mithaq_is_premium_user((select auth.uid())),
        coalesce((select s.status from public.mithaq_premium_subscriptions s where s.user_id=(select auth.uid()) order by s.created_at desc limit 1),'free'),
        (select s.expires_at from public.mithaq_premium_subscriptions s where s.user_id=(select auth.uid()) order by s.created_at desc limit 1),
        coalesce((select s.plan_code from public.mithaq_premium_subscriptions s where s.user_id=(select auth.uid()) order by s.created_at desc limit 1),'monthly'),
        (select s.country from public.mithaq_premium_subscriptions s where s.user_id=(select auth.uid()) order by s.created_at desc limit 1),
        (select s.amount_sar from public.mithaq_premium_subscriptions s where s.user_id=(select auth.uid()) order by s.created_at desc limit 1);
$$;
revoke all on function public.mithaq_my_membership() from public, anon;
grant execute on function public.mithaq_my_membership() to authenticated;

create or replace function public.mithaq_premium_member_ids(p_user_ids uuid[])
returns uuid[] language sql stable security definer set search_path = ''
as $$
 select coalesce(array_agg(x.user_id), '{}'::uuid[])
 from (
   select distinct u.user_id
   from unnest(coalesce(p_user_ids, '{}'::uuid[])) as u(user_id)
   where private.mithaq_is_premium_user(u.user_id)
   limit 500
 ) x;
$$;
revoke all on function public.mithaq_premium_member_ids(uuid[]) from public, anon;
grant execute on function public.mithaq_premium_member_ids(uuid[]) to authenticated;

-- A free account cannot bypass the UI and insert image or voice attachments directly.
drop policy if exists mithaq_active_members_send_direct_messages on public.messages;
create policy mithaq_active_members_send_direct_messages on public.messages
 for insert to authenticated
 with check (
   sender_id = (select auth.uid())
   and recipient_id <> (select auth.uid())
   and exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.account_status='active')
   and exists (select 1 from public.profiles p where p.id=messages.recipient_id and p.account_status='active')
   and not (select private.mithaq_message_pair_blocked(messages.sender_id,messages.recipient_id))
   and (
     (coalesce(messages.attachment_kind,'') <> 'voice'
       and coalesce(messages.attachment_mime,'') not like 'image/%'
       and coalesce(messages.attachment_mime,'') not like 'audio/%')
     or private.mithaq_is_premium_user((select auth.uid()))
   )
 );

-- Storage policy: image/audio uploads in the private chat bucket require an active premium plan.
drop policy if exists mithaq_chat_upload_own_conversation_files on storage.objects;
create policy mithaq_chat_upload_own_conversation_files on storage.objects
 for insert to authenticated
 with check (
   bucket_id = 'mithaq-chat'
   and (storage.foldername(name))[1] = (select auth.uid())::text
   and exists (select 1 from public.profiles p where p.id=((storage.foldername(objects.name))[2])::uuid and p.account_status='active')
   and exists (select 1 from public.profiles me where me.id=(select auth.uid()) and me.account_status='active')
   and (
     coalesce(metadata->>'mimetype','') not like 'image/%'
     and coalesce(metadata->>'mimetype','') not like 'audio/%'
     or private.mithaq_is_premium_user((select auth.uid()))
   )
 );
