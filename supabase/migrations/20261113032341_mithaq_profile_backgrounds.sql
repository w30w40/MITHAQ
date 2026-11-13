insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('mithaq-profile-backgrounds','mithaq-profile-backgrounds',false,8388608,array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update set public=false,file_size_limit=8388608,allowed_mime_types=array['image/jpeg','image/png','image/webp','image/gif'];

create table if not exists public.mithaq_profile_backgrounds (
 user_id uuid primary key references auth.users(id) on delete cascade,
 object_path text not null,
 is_enabled boolean not null default false,
 updated_at timestamptz not null default now(),
 constraint mithaq_profile_backgrounds_owner_path check (split_part(object_path,'/',1)=user_id::text and position('/' in object_path)>0)
);
alter table public.mithaq_profile_backgrounds enable row level security;
revoke all on public.mithaq_profile_backgrounds from anon, public;
grant select,insert,update,delete on public.mithaq_profile_backgrounds to authenticated;
drop policy if exists mithaq_profile_backgrounds_read_visible on public.mithaq_profile_backgrounds;
create policy mithaq_profile_backgrounds_read_visible on public.mithaq_profile_backgrounds
 for select to authenticated using ((select auth.uid())=user_id or is_enabled=true);
drop policy if exists mithaq_profile_backgrounds_insert_own on public.mithaq_profile_backgrounds;
create policy mithaq_profile_backgrounds_insert_own on public.mithaq_profile_backgrounds
 for insert to authenticated with check ((select auth.uid())=user_id and split_part(object_path,'/',1)=user_id::text);
drop policy if exists mithaq_profile_backgrounds_update_own on public.mithaq_profile_backgrounds;
create policy mithaq_profile_backgrounds_update_own on public.mithaq_profile_backgrounds
 for update to authenticated using ((select auth.uid())=user_id)
 with check ((select auth.uid())=user_id and split_part(object_path,'/',1)=user_id::text);
drop policy if exists mithaq_profile_backgrounds_delete_own on public.mithaq_profile_backgrounds;
create policy mithaq_profile_backgrounds_delete_own on public.mithaq_profile_backgrounds
 for delete to authenticated using ((select auth.uid())=user_id);

drop policy if exists mithaq_profile_backgrounds_storage_read on storage.objects;
create policy mithaq_profile_backgrounds_storage_read on storage.objects
 for select to authenticated using (
  bucket_id='mithaq-profile-backgrounds' and (
   (storage.foldername(name))[1]=(select auth.uid())::text
   or exists (
    select 1 from public.mithaq_profile_backgrounds b
    where b.object_path=objects.name and b.is_enabled=true
      and split_part(objects.name,'/',1)=b.user_id::text
   )
  )
 );
drop policy if exists mithaq_profile_backgrounds_storage_insert on storage.objects;
create policy mithaq_profile_backgrounds_storage_insert on storage.objects
 for insert to authenticated with check (
  bucket_id='mithaq-profile-backgrounds'
  and (storage.foldername(name))[1]=(select auth.uid())::text
  and array_length(storage.foldername(name),1)=1
 );
drop policy if exists mithaq_profile_backgrounds_storage_delete on storage.objects;
create policy mithaq_profile_backgrounds_storage_delete on storage.objects
 for delete to authenticated using (
  bucket_id='mithaq-profile-backgrounds'
  and (storage.foldername(name))[1]=(select auth.uid())::text
 );