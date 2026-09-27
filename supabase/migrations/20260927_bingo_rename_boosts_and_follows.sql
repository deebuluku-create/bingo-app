-- Bingo App Kenya: SAFE additive stage of legacy-name migration.
-- Applied live as bingo_notifications_additive_safe on 2026-09-27.
-- Do NOT rename auto_arcade_boosts in this stage: the deployed mpesa-boost
-- Edge Function still addresses it, and compatibility-view grants / callback
-- semantics have not been end-to-end tested.
-- Neither auto_arcade_follows nor bingo_follows exists in the live schema.
-- Do NOT invent a follows schema until the current frontend read/write
-- column contract has been extracted and checked.
-- This migration is deliberately idempotent.
create table if not exists public.bingo_notifications (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 type text not null default 'system_notification',
 title text,
 message text not null,
 created_at timestamptz not null default now(),
 read_at timestamptz
);
create index if not exists bingo_notifications_user_id_created_at_idx
 on public.bingo_notifications(user_id,created_at desc);
alter table public.bingo_notifications enable row level security;
drop policy if exists bingo_notifications_owner_select on public.bingo_notifications;
create policy bingo_notifications_owner_select on public.bingo_notifications
 for select to authenticated using (user_id=auth.uid());
grant select on public.bingo_notifications to authenticated;
-- Pending separate reviewed migrations:
-- (1) create bingo_follows with actual frontend-required columns, unique
--     follower/followee constraint, ownership RLS and authenticated grants;
-- (2) update and test mpesa-boost against bingo_boosts, then coordinate
--     table rename with verified compatibility and rollback plan.
-- Do not drop or rename payment objects in this stage.
