-- ============================================================
-- DRAFT MIGRATION — Bingo Crown Recognition (badge columns + score ledger)
-- Status: DRAFT ONLY. NOT APPLIED. Do not run against any Supabase project
-- without explicit approval. Fully additive: adds two columns to the
-- existing `profiles` table and one new table. Does not alter or drop
-- anything.
--
-- Background / reconciliation note:
-- The already-built Crown badge frontend (aaCrownLoad/aaCrownStatusFor in
-- BINGO_MASTER_CURRENT_VERIFIED.html) reads profiles.crown_status and
-- profiles.crown_awarded_at directly, and treats a missing column as
-- "no badge" rather than erroring — so those two columns are the fast,
-- badge-rendering source of truth and must keep existing exactly as
-- named below for the frontend to work without changes.
--
-- bingo_profile_crown_status below is a separate, additive score ledger
-- (not read directly by the badge-rendering code) that holds the
-- continuously-recalculated engagement score a scoring job evaluates
-- over time. A scoring job (not included here — no such job exists yet
-- in this repo) is expected to periodically evaluate scores and, only
-- when a user crosses the award threshold, write profiles.crown_status
-- = 'awarded' and profiles.crown_awarded_at = now() so the badge appears.
-- This migration creates the ledger table only; it does not create that
-- job or define the threshold, which should be decided before this is
-- applied.
-- ============================================================

-- Badge columns on the existing profiles table ----------------------------
alter table public.profiles add column if not exists crown_status text;
alter table public.profiles add column if not exists crown_awarded_at timestamptz;

do $$ begin
  if not exists (
    select 1 from pg_constraint where conname = 'bingo_profiles_crown_status_check'
  ) then
    alter table public.profiles
      add constraint bingo_profiles_crown_status_check
      check (crown_status is null or crown_status in ('none','awarded','revoked'));
  end if;
end $$;

-- Score ledger --------------------------------------------------------------
create table if not exists public.bingo_profile_crown_status (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_crowned boolean not null default false,
  score numeric(10,2) not null default 0.00,
  awarded_at timestamptz,
  last_evaluated_at timestamptz not null default now()
);

alter table public.bingo_profile_crown_status enable row level security;

-- Every user may read their own score row (so a "your progress toward the
-- Crown" UI is possible later); nobody may read another user's row except
-- a super user, matching the access pattern already used for
-- bingo_role_notifications and other role-gated tables in this repo.
drop policy if exists bingo_crown_status_select on public.bingo_profile_crown_status;
create policy bingo_crown_status_select on public.bingo_profile_crown_status
  for select
  using (auth.uid() = user_id or public.bingo_is_super_user());

-- Only a super user (or a security-definer scoring job function, not
-- included here) may write scores — never the client directly, since the
-- whole point of verified scoring is that it cannot be self-reported.
drop policy if exists bingo_crown_status_write on public.bingo_profile_crown_status;
create policy bingo_crown_status_write on public.bingo_profile_crown_status
  for all
  using (public.bingo_is_super_user())
  with check (public.bingo_is_super_user());

-- ============================================================
-- NOT INCLUDED IN THIS DRAFT (deliberately):
--  - The scoring job itself (what counts as a "genuine unique share",
--    exclusion of self-sharing/bot engagement/duplicate accounts/copied
--    content per the Bingo Impact Awards fair-scoring rules) - that is a
--    server-side/Edge Function concern, not a schema concern, and must be
--    designed before this ledger is populated with real numbers.
--  - The award threshold that flips is_crowned / writes
--    profiles.crown_status = 'awarded' - a product decision, not assumed
--    here.
--  - Any change to the separate Bingo Impact Awards (Girl/Boy of the
--    Year, Business Impact Award, KSh 1,000,000 Grand Prize) scoring or
--    payout logic, which is a distinct programme from the Crown badge and
--    is not modeled by this table.
-- ============================================================
