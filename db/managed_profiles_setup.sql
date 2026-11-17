-- MITHAQ managed virtual member profiles.
-- Review this script before running it in Supabase. It does not create Auth users
-- and does not touch public.profiles, messages, or existing member accounts.

create schema if not exists private;

create table if not exists private.mithaq_managed_profiles (
  id uuid primary key,
  display_name text not null,
  gender text not null check (gender in ('ذكر','أنثى')),
  age integer not null check (age between 18 and 80),
  country text not null default 'السعودية',
  region text not null,
  marriage_type text not null check (marriage_type in ('معلن','مسيار')),
  life_text text not null default '',
  details jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table private.mithaq_managed_profiles enable row level security;
revoke all on private.mithaq_managed_profiles from public, anon, authenticated;

create or replace function public.mithaq_list_managed_profiles()
returns table (
  id uuid, display_name text, country text, region text, marriage_type text,
  life_text text, last_seen_at timestamptz, created_at timestamptz,
  details jsonb, member_number bigint, is_platform_managed boolean,
  management_label text, can_interact boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if (select auth.uid()) is null or not exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.account_status = 'active'
  ) then
    raise exception 'active_account_required' using errcode = '42501';
  end if;

  return query
  select m.id, m.display_name, m.country, m.region, m.marriage_type,
         m.life_text, null::timestamptz, m.created_at, m.details,
         null::bigint, true, 'تحت إدارة ميثاق', false
  from private.mithaq_managed_profiles m
  where m.is_active
  order by m.created_at desc;
end;
$function$;

revoke all on function public.mithaq_list_managed_profiles() from public, anon;
grant execute on function public.mithaq_list_managed_profiles() to authenticated;

-- These management functions are restricted to the primary owner in private.admin_users.
create or replace function public.mithaq_admin_list_managed_profiles()
returns setof private.mithaq_managed_profiles
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if (select auth.uid()) is null or not exists (
    select 1 from private.admin_users a where a.user_id = (select auth.uid())
  ) then
    raise exception 'owner_only' using errcode = '42501';
  end if;
  return query
    select * from private.mithaq_managed_profiles
    order by created_at desc;
end;
$function$;

create or replace function public.mithaq_admin_update_managed_profile(
  p_id uuid,
  p_display_name text,
  p_age integer,
  p_region text,
  p_marriage_type text,
  p_life_text text,
  p_details jsonb,
  p_is_active boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if (select auth.uid()) is null or not exists (
    select 1 from private.admin_users a where a.user_id = (select auth.uid())
  ) then
    raise exception 'owner_only' using errcode = '42501';
  end if;
  if p_age < 18 or p_age > 80 or p_marriage_type not in ('معلن','مسيار') then
    raise exception 'invalid_profile_values' using errcode = '22023';
  end if;
  update private.mithaq_managed_profiles
  set display_name = left(trim(p_display_name), 120),
      age = p_age,
      region = left(trim(p_region), 120),
      marriage_type = p_marriage_type,
      life_text = left(coalesce(p_life_text,''), 1500),
      details = coalesce(p_details,'{}'::jsonb),
      is_active = p_is_active,
      updated_at = now()
  where id = p_id;
  if not found then raise exception 'managed_profile_not_found' using errcode = 'P0002'; end if;
  return true;
end;
$function$;

create or replace function public.mithaq_admin_delete_managed_profile(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if (select auth.uid()) is null or not exists (
    select 1 from private.admin_users a where a.user_id = (select auth.uid())
  ) then
    raise exception 'owner_only' using errcode = '42501';
  end if;
  delete from private.mithaq_managed_profiles where id = p_id;
  if not found then raise exception 'managed_profile_not_found' using errcode = 'P0002'; end if;
  return true;
end;
$function$;

revoke all on function public.mithaq_admin_list_managed_profiles() from public, anon;
revoke all on function public.mithaq_admin_update_managed_profile(uuid,text,integer,text,text,text,jsonb,boolean) from public, anon;
revoke all on function public.mithaq_admin_delete_managed_profile(uuid) from public, anon;
grant execute on function public.mithaq_admin_list_managed_profiles() to authenticated;
grant execute on function public.mithaq_admin_update_managed_profile(uuid,text,integer,text,text,text,jsonb,boolean) to authenticated;
grant execute on function public.mithaq_admin_delete_managed_profile(uuid) to authenticated;

-- Seed 1,000 clearly disclosed, non-interactive managed profiles once.
-- These are not Auth users and cannot receive messages or appear in real-user totals.
insert into private.mithaq_managed_profiles
  (id, display_name, gender, age, country, region, marriage_type, life_text, details, is_active)
select
  ('10000000-0000-4000-8000-' || lpad(g.n::text, 12, '0'))::uuid,
  case when g.n <= 500 then
    (array['عبدالله','محمد','أحمد','خالد','فهد','تركي','سعود','فيصل','ناصر','عمر','ماجد','سلمان','بدر','راشد','سلطان','ياسر','حمد','طلال','زياد','عادل'])[((g.n-1)%20)+1]
  else
    (array['نورة','ريم','سارة','جود','لينا','مها','أمل','هيا','دانة','الجوهرة','غادة','نوف','العنود','ليان','رنا','مريم','شذى','منيرة','عبير','دلال'])[((g.n-501)%20)+1]
  end || ' ' ||
  (array['محمد','أحمد','خالد','عبدالله','سعد','ناصر','فهد','علي','حسن','إبراهيم','سليمان','ماجد','فيصل','راشد','عمر','يوسف','صالح','عبدالرحمن','تركي','حمد'])[((g.n-1)%20)+1] || ' ' ||
  (array['سعد','ناصر','فهد','عبدالله','علي','حسن','إبراهيم','سليمان','ماجد','فيصل','راشد','عمر','يوسف','صالح','عبدالرحمن','تركي','حمد','خالد','محمد','أحمد'])[((g.n*7-1)%20)+1] || ' ' ||
  (array['العتيبي','القحطاني','الشهري','الحربي','المطيري','الدوسري','الغامدي','الزهراني','العنزي','الشمري','التميمي','السبيعي','الرشيدي','المالكي','الثقفي','القرني','الجهني','البلوي','العسيري','السلمي'])[((g.n*11-1)%20)+1],
  case when g.n <= 500 then 'ذكر' else 'أنثى' end,
  21 + ((g.n * 7) % 20),
  'السعودية',
  (array['الرياض','جدة','مكة المكرمة','المدينة المنورة','الدمام','الخبر','الطائف','أبها','تبوك','بريدة','حائل','جازان','نجران'])[((g.n*3-1)%13)+1],
  case when g.n % 4 = 0 then 'مسيار' else 'معلن' end,
  (array[
    'أقدّر الصدق والاحترام والتفاهم، وأؤمن أن الاستقرار يبدأ بحسن التعامل.',
    'أبحث عن حياة يسودها الود والتعاون وتحمل المسؤولية.',
    'أؤمن بالحوار الهادئ والوضوح والاحترام المتبادل.',
    'أهتم بالأسرة والاستقرار وبناء علاقة قائمة على الثقة.',
    'أقدّر الطموح والتوازن والاهتمام بالتفاصيل الجميلة في الحياة.',
    'أرى أن المودة والرحمة والتفاهم أساس نجاح الحياة الأسرية.',
    'أحب البساطة والوضوح وأقدّر الالتزام والاحترام.',
    'أؤمن بأن الشراكة الناجحة تقوم على الصراحة والتعاون.'
  ])[((g.n-1)%8)+1],
  jsonb_build_object(
    'gender', case when g.n <= 500 then 'ذكر' else 'أنثى' end,
    'age', 21 + ((g.n * 7) % 20),
    'city', (array['الرياض','جدة','مكة المكرمة','المدينة المنورة','الدمام','الخبر','الطائف','أبها','تبوك','بريدة','حائل','جازان','نجران'])[((g.n*3-1)%13)+1],
    'education', (array['جامعي','دبلوم','ثانوي','دراسات عليا','تعليم مهني'])[((g.n-1)%5)+1],
    'job', (array['موظف','قطاع خاص','عمل حر','إداري','معلم','مهني','طالبة','موظفة','عمل إداري'])[((g.n-1)%9)+1],
    'marital_status', (array['أعزب','مطلق','أرمل','آنسة','مطلقة','أرملة'])[((g.n-1)%6)+1],
    'children', (array['لا يوجد','لا يوجد','طفل واحد','طفلان'])[((g.n-1)%4)+1],
    'about', (array[
      'أقدّر الصدق والاحترام والتفاهم، وأؤمن أن الاستقرار يبدأ بحسن التعامل.',
      'أبحث عن حياة يسودها الود والتعاون وتحمل المسؤولية.',
      'أؤمن بالحوار الهادئ والوضوح والاحترام المتبادل.',
      'أهتم بالأسرة والاستقرار وبناء علاقة قائمة على الثقة.',
      'أقدّر الطموح والتوازن والاهتمام بالتفاصيل الجميلة في الحياة.',
      'أرى أن المودة والرحمة والتفاهم أساس نجاح الحياة الأسرية.',
      'أحب البساطة والوضوح وأقدّر الالتزام والاحترام.',
      'أؤمن بأن الشراكة الناجحة تقوم على الصراحة والتعاون.'
    ])[((g.n-1)%8)+1],
    'is_platform_managed', true,
    'management_label', 'تحت إدارة ميثاق',
    'disclosure', 'حساب افتراضي بإدارة المنصة',
    'can_interact', false
  ),
  true
from generate_series(1,1000) as g(n)
on conflict (id) do nothing;
