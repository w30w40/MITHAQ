alter table public.messages
 add column if not exists location_latitude double precision null,
 add column if not exists location_longitude double precision null,
 add column if not exists location_label text null;
do $constraints$
begin
 if not exists(select 1 from pg_constraint where conname='messages_location_latitude_range') then
  alter table public.messages add constraint messages_location_latitude_range check(location_latitude is null or location_latitude between -90 and 90);
 end if;
 if not exists(select 1 from pg_constraint where conname='messages_location_longitude_range') then
  alter table public.messages add constraint messages_location_longitude_range check(location_longitude is null or location_longitude between -180 and 180);
 end if;
 if not exists(select 1 from pg_constraint where conname='messages_location_pair_required') then
  alter table public.messages add constraint messages_location_pair_required check((location_latitude is null and location_longitude is null) or (location_latitude is not null and location_longitude is not null));
 end if;
 if not exists(select 1 from pg_constraint where conname='messages_location_label_length') then
  alter table public.messages add constraint messages_location_label_length check(location_label is null or char_length(location_label)<=120);
 end if;
end;
$constraints$;