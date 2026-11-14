alter table public.mithaq_profile_backgrounds
  add column if not exists background_position_x smallint not null default 50
    check (background_position_x between 0 and 100),
  add column if not exists background_position_y smallint not null default 50
    check (background_position_y between 0 and 100),
  add column if not exists background_fit text not null default 'cover'
    check (background_fit in ('cover','contain'));

comment on column public.mithaq_profile_backgrounds.background_position_x is
  'Horizontal focal position percentage for displaying the owner background in a conversation';
comment on column public.mithaq_profile_backgrounds.background_position_y is
  'Vertical focal position percentage for displaying the owner background in a conversation';
comment on column public.mithaq_profile_backgrounds.background_fit is
  'Conversation background image fit mode: cover or contain';
