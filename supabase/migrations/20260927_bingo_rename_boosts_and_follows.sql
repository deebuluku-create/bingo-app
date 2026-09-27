-- Bingo App Kenya — legacy "Auto Arcade" naming cleanup (2026-09-27).
--
-- Renames auto_arcade_boosts -> bingo_boosts and auto_arcade_follows ->
-- bingo_follows. ALTER TABLE ... RENAME TO preserves the table's rows,
-- indexes, constraints, triggers and RLS policies automatically (Postgres
-- tracks all of these by object id, not by name) — nothing here drops or
-- recreates any of that, and no payment history or follow relationship
-- is touched.
--
-- What this migration does NOT know and does not need to: the exact
-- column list or existing RLS policy definitions of either table. A
-- rename does not require redefining them.
--
-- Compatibility views: the mpesa-boost Edge Function currently deployed
-- to production still writes to "auto_arcade_boosts" by that literal
-- name (see supabase/functions/mpesa-boost/index.ts — the copy in this
-- repo has been updated to bingo_boosts, but that update is NOT live
-- until someone redeploys the function). Renaming the table out from
-- under a function that is still writing to the old name would break
-- every M-Pesa boost payment immediately. So each rename is followed by
-- a same-name compatibility view with `security_invoker = true` (so it
-- enforces the RENAMED table's RLS as the querying role, not the view
-- owner's) — Postgres auto-updates simple single-table views like these
-- through INSERT/UPDATE/DELETE, so both the old Edge Function and the
-- old frontend keep working, unmodified and un-redeployed, for as long
-- as they still reference the old name. Once the Edge Function has been
-- redeployed with the bingo_boosts name (see that file's header) and the
-- Hostinger preview/production HTML has been redeployed with this
-- repository's bingo_follows/bingo_boosts references, both compatibility
-- views can be dropped — see the DROP statements commented out at the
-- bottom of this file.
--
-- auto_arcade_notifications is NOT renamed here: it does not exist in
-- the current schema (confirmed — the frontend has been querying a
-- table that was never created), and no code in this repository ever
-- writes to it either, under any name. There is nothing to preserve, so
-- a fresh table is created instead: bingo_notifications, matching
-- exactly the shape the frontend already queries
-- (aaSyncBoostNotifications in the main app, select
-- id,type,title,message,created_at,read_at). Populating it (e.g. from
-- the mpesa-boost callback, or a trigger on bingo_boosts) is a separate,
-- not-yet-requested feature and is deliberately not added here.

do $$
begin
  if to_regclass('public.auto_arcade_boosts') is not null
     and to_regclass('public.bingo_boosts') is null then
    alter table public.auto_arcade_boosts rename to bingo_boosts;
  end if;
end
$$;

do $$
begin
  if to_regclass('public.auto_arcade_follows') is not null
     and to_regclass('public.bingo_follows') is null then
    alter table public.auto_arcade_follows rename to bingo_follows;
  end if;
end
$$;

-- Compatibility views over the renamed tables, only created if the
-- rename above actually happened (i.e. the real table now exists under
-- its new name) and nothing already occupies the old name.
do $$
begin
  if to_regclass('public.bingo_boosts') is not null
     and to_regclass('public.auto_arcade_boosts') is null then
    execute 'create view public.auto_arcade_boosts with (security_invoker = true) as select * from public.bingo_boosts';
  end if;
end
$$;

do $$
begin
  if to_regclass('public.bingo_follows') is not null
     and to_regclass('public.auto_arcade_follows') is null then
    execute 'create view public.auto_arcade_follows with (security_invoker = true) as select * from public.bingo_follows';
  end if;
end
$$;

-- Fresh Bingo notifications table (auto_arcade_notifications never
-- existed, so there is nothing to migrate — see note above).
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
  on public.bingo_notifications (user_id, created_at desc);

alter table public.bingo_notifications enable row level security;

drop policy if exists "bingo_notifications_owner_select" on public.bingo_notifications;
create policy "bingo_notifications_owner_select"
  on public.bingo_notifications for select
  to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- Cleanup step (run manually, later, once BOTH of the following are
-- true — do not run this as part of applying the migration above):
--   1. supabase/functions/mpesa-boost/index.ts has been redeployed with
--      its bingo_boosts references live in production, and
--   2. the Hostinger preview/production HTML has been redeployed with
--      this repository's bingo_follows/bingo_boosts references live.
-- ---------------------------------------------------------------------
-- drop view if exists public.auto_arcade_boosts;
-- drop view if exists public.auto_arcade_follows;
