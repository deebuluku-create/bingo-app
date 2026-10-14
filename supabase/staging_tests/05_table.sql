create table if not exists public.bingo_topics (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users(id) on delete cascade,
  title              text not null default '',
  body               text not null default '',
  category           text not null default 'General',
  media              jsonb not null default '[]'::jsonb,
  moderation_status  text not null default 'visible' check (moderation_status in ('visible','hidden')),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint bingo_topics_has_content check (length(trim(title)) > 0 or length(trim(body)) > 0)
);
alter table public.bingo_topics enable row level security;
grant select on public.bingo_topics to anon;
grant select, insert, update, delete on public.bingo_topics to authenticated, service_role;
