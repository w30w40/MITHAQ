create or replace function private.mithaq_can_view_profile_background(p_target_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
 select
  (select auth.uid()) is not null
  and exists (
   select 1 from public.profiles actor
   where actor.id=(select auth.uid()) and actor.account_status='active'
  )
  and exists (
   select 1
   from public.profiles target
   left join public.profile_details details on details.id=target.id
   where target.id=p_target_id
     and target.account_status='active'
     and (target.is_published=true
       or coalesce(details.details->>'public_listing_consent','false')='true')
  )
  and not exists (
   select 1 from private.member_relations r
   where r.is_active and r.action in ('ignore','block')
     and (
      (r.actor_id=(select auth.uid()) and r.target_id=p_target_id)
      or (r.actor_id=p_target_id and r.target_id=(select auth.uid()) and r.action='block')
     )
  );
$$;
revoke all on function private.mithaq_can_view_profile_background(uuid) from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.mithaq_can_view_profile_background(uuid) to authenticated;

drop policy if exists mithaq_profile_backgrounds_read_visible on public.mithaq_profile_backgrounds;
create policy mithaq_profile_backgrounds_read_visible on public.mithaq_profile_backgrounds
 for select to authenticated using (
  (select auth.uid())=user_id
  or (is_enabled=true and private.mithaq_can_view_profile_background(user_id))
 );

drop policy if exists mithaq_profile_backgrounds_storage_read on storage.objects;
create policy mithaq_profile_backgrounds_storage_read on storage.objects
 for select to authenticated using (
  bucket_id='mithaq-profile-backgrounds' and (
   (storage.foldername(name))[1]=(select auth.uid())::text
   or exists (
    select 1 from public.mithaq_profile_backgrounds b
    where b.object_path=objects.name and b.is_enabled=true
      and split_part(objects.name,'/',1)=b.user_id::text
      and private.mithaq_can_view_profile_background(b.user_id)
   )
  )
 );