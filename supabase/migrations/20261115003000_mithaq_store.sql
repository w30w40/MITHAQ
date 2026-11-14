-- MITHAQ Store: admin-published listings with public read access for signed-in members.
create table if not exists public.mithaq_store_items (
  id uuid primary key default gen_random_uuid(),
  item_number bigint generated always as identity unique,
  title text not null check (char_length(btrim(title)) between 2 and 180),
  description text not null check (char_length(btrim(description)) between 1 and 12000),
  specifications text not null default '',
  price numeric(12,2) check (price is null or price >= 0),
  currency text not null default 'SAR' check (currency ~ '^[A-Z]{3}$'),
  availability_status text not null default 'available' check (availability_status in ('available','unavailable')),
  is_published boolean not null default false,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists mithaq_store_items_published_created_idx
  on public.mithaq_store_items (is_published, created_at desc);
create index if not exists mithaq_store_items_item_number_idx
  on public.mithaq_store_items (item_number desc);

create table if not exists public.mithaq_store_images (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.mithaq_store_items(id) on delete cascade,
  object_path text not null unique,
  sort_order integer not null default 0,
  alt_text text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists mithaq_store_images_item_order_idx
  on public.mithaq_store_images (item_id, sort_order, created_at);

alter table public.mithaq_store_items enable row level security;
alter table public.mithaq_store_images enable row level security;

grant select, insert, update, delete on public.mithaq_store_items to authenticated;
grant select, insert, update, delete on public.mithaq_store_images to authenticated;
grant usage, select on sequence public.mithaq_store_items_item_number_seq to authenticated;

drop policy if exists mithaq_store_items_read_published_or_admin on public.mithaq_store_items;
create policy mithaq_store_items_read_published_or_admin
on public.mithaq_store_items for select to authenticated
using (is_published or (select public.mithaq_is_admin()));

drop policy if exists mithaq_store_items_admin_insert on public.mithaq_store_items;
create policy mithaq_store_items_admin_insert
on public.mithaq_store_items for insert to authenticated
with check ((select public.mithaq_is_admin()) and created_by = (select auth.uid()));

drop policy if exists mithaq_store_items_admin_update on public.mithaq_store_items;
create policy mithaq_store_items_admin_update
on public.mithaq_store_items for update to authenticated
using ((select public.mithaq_is_admin()))
with check ((select public.mithaq_is_admin()));

drop policy if exists mithaq_store_items_admin_delete on public.mithaq_store_items;
create policy mithaq_store_items_admin_delete
on public.mithaq_store_items for delete to authenticated
using ((select public.mithaq_is_admin()));

drop policy if exists mithaq_store_images_read_published_or_admin on public.mithaq_store_images;
create policy mithaq_store_images_read_published_or_admin
on public.mithaq_store_images for select to authenticated
using (
  (select public.mithaq_is_admin())
  or exists (
    select 1 from public.mithaq_store_items i
    where i.id = item_id and i.is_published = true
  )
);

drop policy if exists mithaq_store_images_admin_insert on public.mithaq_store_images;
create policy mithaq_store_images_admin_insert
on public.mithaq_store_images for insert to authenticated
with check (
  (select public.mithaq_is_admin())
  and exists (select 1 from public.mithaq_store_items i where i.id = item_id)
);

drop policy if exists mithaq_store_images_admin_update on public.mithaq_store_images;
create policy mithaq_store_images_admin_update
on public.mithaq_store_images for update to authenticated
using ((select public.mithaq_is_admin()))
with check ((select public.mithaq_is_admin()));

drop policy if exists mithaq_store_images_admin_delete on public.mithaq_store_images;
create policy mithaq_store_images_admin_delete
on public.mithaq_store_images for delete to authenticated
using ((select public.mithaq_is_admin()));

-- Store images are intentionally public for display in listings; write operations remain admin-only.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'mithaq-store',
  'mithaq-store',
  true,
  10485760,
  array['image/jpeg','image/png','image/webp','image/gif']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists mithaq_store_images_storage_admin_insert on storage.objects;
create policy mithaq_store_images_storage_admin_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'mithaq-store'
  and (select public.mithaq_is_admin())
);

drop policy if exists mithaq_store_images_storage_admin_update on storage.objects;
create policy mithaq_store_images_storage_admin_update
on storage.objects for update to authenticated
using (
  bucket_id = 'mithaq-store'
  and (select public.mithaq_is_admin())
)
with check (
  bucket_id = 'mithaq-store'
  and (select public.mithaq_is_admin())
);

drop policy if exists mithaq_store_images_storage_admin_delete on storage.objects;
create policy mithaq_store_images_storage_admin_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'mithaq-store'
  and (select public.mithaq_is_admin())
);

comment on table public.mithaq_store_items is 'Admin-managed public marketplace listings for MITHAQ members.';
comment on table public.mithaq_store_images is 'Images attached to MITHAQ Store listings; paths reference the public mithaq-store bucket.';
