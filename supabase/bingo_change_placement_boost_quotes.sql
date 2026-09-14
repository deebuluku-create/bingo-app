-- ============================================================================
-- BINGO CHANGE 09 — PLACEMENT-BASED M-PESA BOOST (Supabase backend)
--
-- Adds the quote ledger the boost-quote Edge Function writes to and the
-- existing mpesa-boost function must read from before ever starting an
-- STK push for a placement-based boost — see the note at the bottom of
-- supabase/functions/boost-quote/index.ts for the exact change that
-- existing function needs (it is not part of this repository, so it
-- cannot be edited here).
--
-- Additive only. Does not touch property_listings, food_businesses,
-- bingo_ad_campaigns, or any existing boost/M-Pesa table.
-- ============================================================================

create table if not exists public.bingo_boost_quotes (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  post_id       text not null,
  post_type     text not null default 'vehicle',
  placement_id  text not null,
  duration_days integer not null,
  geo           text not null default 'all',
  amount_kes    numeric(12,2) not null,
  starts_at     timestamptz not null,
  expires_at    timestamptz not null,
  status        text not null default 'quoted' check (status in ('quoted','paid','expired','cancelled')),
  boost_id      text,
  created_at    timestamptz not null default now()
);

alter table public.bingo_boost_quotes enable row level security;

-- The owner can see their own quotes (used to show the confirmation
-- screen and, defensively, to let the client re-fetch a quote it already
-- has the id for). Nobody can see anyone else's quote or its amount.
drop policy if exists bingo_boost_quotes_select on public.bingo_boost_quotes;
create policy bingo_boost_quotes_select on public.bingo_boost_quotes
  for select
  using (auth.uid() = user_id);

-- No insert/update/delete policy for authenticated users at all: only
-- the boost-quote Edge Function (service-role key, never exposed to the
-- browser) creates a row, and only mpesa-boost (also service-role, once
-- updated per the note in boost-quote/index.ts) may mark one paid.

create index if not exists bingo_boost_quotes_user_idx on public.bingo_boost_quotes(user_id, status);
create index if not exists bingo_boost_quotes_expiry_idx on public.bingo_boost_quotes(status, expires_at);
