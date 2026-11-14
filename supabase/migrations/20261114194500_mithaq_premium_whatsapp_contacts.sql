create table if not exists public.mithaq_premium_contact_numbers (
  id uuid primary key default gen_random_uuid(),
  label text not null default 'واتساب الإدارة',
  phone text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint mithaq_premium_contact_phone_format check (phone ~ '^\+[1-9][0-9]{7,14}$')
);
alter table public.mithaq_premium_contact_numbers enable row level security;
revoke all on public.mithaq_premium_contact_numbers from anon, authenticated;
insert into public.mithaq_premium_contact_numbers(label,phone,is_active)
values ('واتساب الإدارة','+966561894729',true)
on conflict do nothing;

create or replace function public.mithaq_premium_contacts()
returns table(id uuid,label text,phone text,is_active boolean)
language sql security definer set search_path = public
as $$
  select c.id,c.label,c.phone,c.is_active from public.mithaq_premium_contact_numbers c
  where c.is_active = true order by c.created_at, c.id
$$;

create or replace function public.mithaq_manage_premium_contact(
  p_action text, p_id uuid default null, p_label text default null,
  p_phone text default null, p_active boolean default true
)
returns uuid language plpgsql security definer set search_path = public
as $$
declare v_id uuid; v_phone text;
begin
  if not coalesce(public.mithaq_is_admin(), false) then raise exception 'admin_only'; end if;
  if p_action = 'delete' then
    if p_id is null then raise exception 'contact_id_required'; end if;
    delete from public.mithaq_premium_contact_numbers where id = p_id;
    return p_id;
  elsif p_action in ('add','update') then
    v_phone := regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g');
    if v_phone !~ '^\+[1-9][0-9]{7,14}$' then raise exception 'invalid_phone_format_use_international_format'; end if;
    if length(trim(coalesce(p_label,''))) = 0 then raise exception 'contact_label_required'; end if;
    if p_action = 'add' then
      insert into public.mithaq_premium_contact_numbers(label,phone,is_active)
      values (left(trim(p_label),60),v_phone,coalesce(p_active,true)) returning id into v_id;
    else
      if p_id is null then raise exception 'contact_id_required'; end if;
      update public.mithaq_premium_contact_numbers
      set label=left(trim(p_label),60),phone=v_phone,is_active=coalesce(p_active,true),updated_at=now()
      where id=p_id returning id into v_id;
      if v_id is null then raise exception 'contact_not_found'; end if;
    end if;
    return v_id;
  else raise exception 'invalid_action'; end if;
end;
$$;
grant execute on function public.mithaq_premium_contacts() to anon, authenticated;
grant execute on function public.mithaq_manage_premium_contact(text,uuid,text,text,boolean) to authenticated;

create or replace function public.mithaq_premium_contacts_admin()
returns table(id uuid,label text,phone text,is_active boolean)
language plpgsql security definer set search_path = public
as $$
begin
  if not coalesce(public.mithaq_is_admin(), false) then raise exception 'admin_only'; end if;
  return query select c.id,c.label,c.phone,c.is_active
  from public.mithaq_premium_contact_numbers c order by c.created_at, c.id;
end;
$$;
grant execute on function public.mithaq_premium_contacts_admin() to authenticated;