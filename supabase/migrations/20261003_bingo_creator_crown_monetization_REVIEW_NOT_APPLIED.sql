-- ============================================================================
-- BINGO — PRIVATE CREATOR CROWN MONETIZATION SYSTEM
-- Status: REVIEW ONLY. NOT APPLIED. Do not run against any Supabase project
-- without explicit approval and a live-schema confirmation pass first (this
-- session has no live database connection - no SUPABASE_URL/DATABASE_URL/
-- service key is present in this sandbox, so nothing below has been run or
-- verified against the real project; it is written strictly from reading
-- this repository's own already-applied migrations).
--
-- This is a DISTINCT feature from Bingo's existing business/client-
-- acquisition Agent program (bingo_agent_commission_withdrawals,
-- bingo_agent_commission_ledger, bingo_user_roles.role='agent'). Every
-- table/function here is prefixed bingo_creator_ specifically so it cannot
-- collide with that system's names, routes or state. It is also distinct
-- from the existing profiles.crown_status / profiles.crown_awarded_at
-- "recognised member" badge (see bingo_change_crown_recognition.sql,
-- itself still DRAFT/NOT APPLIED) and from the existing single, untiered
-- "Crown" reaction button on the Home Feed/Wall compact card (aaTopicLove,
-- relabeled Crown in the frontend only - no tiers, no money). Neither of
-- those is touched, renamed, or reused by anything below.
--
-- Reused as-is (confirmed already live/applied via this repo's own
-- bingo_change2_super_user_security.sql, which carries no DRAFT/PAUSED
-- caveat, unlike the Agent-withdrawal files that turned out to target the
-- wrong live table name): public.profiles, auth.users, public.bingo_user_
-- roles, public.bingo_role_audit_log, public.bingo_is_super_user(). No new
-- account, profile or auth system is created. This attaches to the SAME
-- existing authenticated Bingo account.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Monetization status - one row per account. A browser toggle is never
--    authoritative; this row is. Default false: turning this on is an
--    explicit per-account action, never implied by existing data.
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_creator_monetization (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  enabled     boolean not null default false,
  enabled_at  timestamptz,
  disabled_at timestamptz,
  updated_at  timestamptz not null default now()
);

alter table public.bingo_creator_monetization enable row level security;

drop policy if exists bingo_creator_monetization_select on public.bingo_creator_monetization;
create policy bingo_creator_monetization_select on public.bingo_creator_monetization
  for select
  using (auth.uid() = user_id or public.bingo_is_super_user());
-- No insert/update/delete policy for authenticated: only the RPC below
-- (SECURITY DEFINER) may change this row, matching bingo_user_roles'
-- "no direct write policy" convention exactly.

-- ---------------------------------------------------------------------------
-- 2. Crown gift ledger - IMMUTABLE. One row per genuine, uniquely-identified
--    Crown-gift event. This is the sole source of truth for "how many
--    Gold/Silver/Bronze Crowns has this creator genuinely received" - never
--    a mutable counter anywhere else, and never client-writable (matches
--    the "Service-only payment ledger" convention in
--    20261001043833_food_subscription_payments.sql exactly: no client can
--    insert, change, or inspect another creator's rows).
--
--    source_event_id is the idempotency key: it must be the real, unique id
--    of the originating Crown transaction/reaction/payment event (e.g. a
--    Supabase realtime payment-confirmation id). The unique constraint is
--    what makes "a duplicate Crown event does not double-credit" true at
--    the database level, not just in frontend logic - a double click, a
--    page refresh, a realtime replay or a duplicate payment callback that
--    retries the same event id can insert at most once.
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_creator_crown_gifts (
  id               uuid primary key default gen_random_uuid(),
  source_event_id  text not null unique,
  topic_id         uuid,
  giver_id         uuid not null references auth.users(id),
  creator_id       uuid not null references auth.users(id),
  tier             text not null check (tier in ('gold','silver','bronze')),
  creator_amount   numeric(10,2) not null,
  created_at       timestamptz not null default now()
);

alter table public.bingo_creator_crown_gifts enable row level security;
revoke all on public.bingo_creator_crown_gifts from public,anon;
grant select on public.bingo_creator_crown_gifts to authenticated;
grant select,insert on public.bingo_creator_crown_gifts to service_role;

drop policy if exists bingo_creator_crown_gifts_select on public.bingo_creator_crown_gifts;
create policy bingo_creator_crown_gifts_select on public.bingo_creator_crown_gifts
  for select
  using (auth.uid() = creator_id or public.bingo_is_super_user());
-- Read access above is for a future "my recent Crown gifts" list if ever
-- wanted; it changes nothing about who may WRITE (no insert/update/delete
-- policy for authenticated at all - only bingo_creator_award_crown_gift()
-- below, or service_role directly, may write a row). The table-level GRANT
-- SELECT to authenticated is required for this RLS policy to be reachable
-- at all - without it Postgres denies the query before RLS is even
-- evaluated, which is what caught this during local testing (see the
-- other four tables below, which already grant select to authenticated).

create index if not exists bingo_creator_crown_gifts_creator_idx
  on public.bingo_creator_crown_gifts(creator_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 3. Weekly competition cycles - a shared schedule, not per-creator. Monday
--    00:00 to the following Monday 00:00, Africa/Nairobi, matching the
--    Monday-08:00-Nairobi convention already used for the Agent program's
--    "next update" calculation in 20260927_bingo_agent_withdrawal_minimum_50.sql.
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_creator_competition_cycles (
  id          uuid primary key default gen_random_uuid(),
  cycle_start timestamptz not null,
  cycle_end   timestamptz not null,
  status      text not null default 'active' check (status in ('active','settled')),
  created_at  timestamptz not null default now(),
  unique (cycle_start, cycle_end)
);

alter table public.bingo_creator_competition_cycles enable row level security;
revoke all on public.bingo_creator_competition_cycles from public,anon,authenticated;
grant select on public.bingo_creator_competition_cycles to authenticated;
grant select,insert,update on public.bingo_creator_competition_cycles to service_role;

drop policy if exists bingo_creator_cycles_select on public.bingo_creator_competition_cycles;
create policy bingo_creator_cycles_select on public.bingo_creator_competition_cycles
  for select
  using (true);
-- Cycle start/end/status carry no private financial information, so this
-- is readable by any signed-in account (needed for a "resets in" countdown)
-- - it is the per-creator ledger below that is strictly private.

-- Single source of truth for "which week is this", auto-creating this
-- week's row the first time anything asks for it. Idempotent: a concurrent
-- second caller hits the unique(cycle_start,cycle_end) constraint and the
-- ON CONFLICT DO NOTHING simply no-ops instead of erroring or duplicating.
create or replace function public._bingo_creator_current_cycle()
returns public.bingo_creator_competition_cycles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_start timestamptz;
  v_end timestamptz;
  v_cycle public.bingo_creator_competition_cycles;
begin
  v_start := (date_trunc('week', now() at time zone 'Africa/Nairobi')) at time zone 'Africa/Nairobi';
  v_end := v_start + interval '7 days';

  insert into public.bingo_creator_competition_cycles(cycle_start, cycle_end)
  values (v_start, v_end)
  on conflict (cycle_start, cycle_end) do nothing;

  select * into v_cycle from public.bingo_creator_competition_cycles
  where cycle_start = v_start and cycle_end = v_end;

  return v_cycle;
end;
$$;

revoke all on function public._bingo_creator_current_cycle() from public;
grant execute on function public._bingo_creator_current_cycle() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Per-creator, per-cycle pool accumulation + settlement. unique
--    (creator_id, cycle_id) is the idempotency guard for "the 30/70 split
--    happens exactly once per creator per cycle" - re-running the
--    settlement RPC against an already-settled row is a safe no-op because
--    the function checks settled=false before touching it (see below), and
--    a second concurrent call is blocked by the row lock (for update).
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_creator_cycle_ledger (
  id                 uuid primary key default gen_random_uuid(),
  creator_id         uuid not null references auth.users(id),
  cycle_id           uuid not null references public.bingo_creator_competition_cycles(id),
  pool_amount        numeric(10,2) not null default 0,
  settled            boolean not null default false,
  settlement_amount  numeric(10,2),
  settled_at         timestamptz,
  updated_at         timestamptz not null default now(),
  unique (creator_id, cycle_id)
);

alter table public.bingo_creator_cycle_ledger enable row level security;
revoke all on public.bingo_creator_cycle_ledger from public,anon,authenticated;
grant select on public.bingo_creator_cycle_ledger to authenticated;
grant select,insert,update on public.bingo_creator_cycle_ledger to service_role;

drop policy if exists bingo_creator_cycle_ledger_select on public.bingo_creator_cycle_ledger;
create policy bingo_creator_cycle_ledger_select on public.bingo_creator_cycle_ledger
  for select
  using (auth.uid() = creator_id or public.bingo_is_super_user());

-- ---------------------------------------------------------------------------
-- 5. Withdrawable wallet ledger - IMMUTABLE, append-only. Mirrors the
--    credit/reserve/release accounting already proven live for Agent
--    commissions (bingo_agent_commission_ledger), applied here to Crown
--    settlement money instead. Withdrawable balance is ALWAYS computed by
--    summing this table, never read from a separately-stored mutable
--    total - so no code path can desync "the balance" from "the sum of
--    everything that actually happened".
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_creator_wallet_ledger (
  id          uuid primary key default gen_random_uuid(),
  creator_id  uuid not null references auth.users(id),
  entry_type  text not null check (entry_type in ('credit','reserve','release')),
  amount      numeric(10,2) not null check (amount > 0),
  source_type text not null check (source_type in ('cycle_settlement','withdrawal_request')),
  source_id   uuid not null,
  created_at  timestamptz not null default now()
);

alter table public.bingo_creator_wallet_ledger enable row level security;
revoke all on public.bingo_creator_wallet_ledger from public,anon,authenticated;
grant select on public.bingo_creator_wallet_ledger to authenticated;
grant select,insert on public.bingo_creator_wallet_ledger to service_role;

drop policy if exists bingo_creator_wallet_ledger_select on public.bingo_creator_wallet_ledger;
create policy bingo_creator_wallet_ledger_select on public.bingo_creator_wallet_ledger
  for select
  using (auth.uid() = creator_id or public.bingo_is_super_user());

create index if not exists bingo_creator_wallet_ledger_creator_idx
  on public.bingo_creator_wallet_ledger(creator_id);

-- ---------------------------------------------------------------------------
-- 6. Withdrawal requests. Payout is ADMIN-REVIEWED, mirroring the real,
--    already-applied Agent commission withdrawal flow in this exact app
--    (bingo_admin_review_agent_withdrawal) - Bingo has no automated M-Pesa
--    B2C disbursement anywhere in this repository today (only Lipa Na
--    M-Pesa Online / STK Push for taking payment IN, in
--    supabase/functions/mpesa-boost and mpesa-food-subscription - nothing
--    for sending money OUT). This is NOT a simulation: the request is a
--    real, persisted, balance-locking row an administrator must act on; it
--    is simply a manual-review payout step, exactly like the Agent program
--    already in production, not an automatic Daraja B2C API call.
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_creator_withdrawal_requests (
  id                uuid primary key default gen_random_uuid(),
  creator_id        uuid not null references auth.users(id),
  amount            numeric(10,2) not null,
  payout_phone      text not null check (payout_phone ~ '^254[17][0-9]{8}$'),
  withdrawal_status text not null default 'pending' check (withdrawal_status in ('pending','approved','rejected','paid')),
  administrator_id  uuid references auth.users(id),
  payment_reference text,
  requested_at      timestamptz not null default now(),
  reviewed_at       timestamptz
);

alter table public.bingo_creator_withdrawal_requests enable row level security;
revoke all on public.bingo_creator_withdrawal_requests from public,anon,authenticated;
grant select on public.bingo_creator_withdrawal_requests to authenticated;
grant select,insert,update on public.bingo_creator_withdrawal_requests to service_role;

drop policy if exists bingo_creator_withdrawals_select on public.bingo_creator_withdrawal_requests;
create policy bingo_creator_withdrawals_select on public.bingo_creator_withdrawal_requests
  for select
  using (auth.uid() = creator_id or public.bingo_is_super_user());

-- ---------------------------------------------------------------------------
-- 7. Constants - single source of truth, matching the
--    _bingo_agent_withdrawal_minimum() pattern already proven live.
-- ---------------------------------------------------------------------------
create or replace function public._bingo_creator_withdrawal_minimum()
returns numeric language sql immutable set search_path = '' as $$ select 5000::numeric; $$;

create or replace function public._bingo_creator_crown_amount(p_tier text)
returns numeric language sql immutable set search_path = '' as $$
  select case p_tier
    when 'gold' then 200::numeric
    when 'silver' then 80::numeric
    when 'bronze' then 40::numeric
    else null
  end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Toggle monetization for the caller's own account only. Logged to the
--    existing audit trail.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_creator_set_monetization(p_enabled boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Sign in required.'; end if;

  insert into public.bingo_creator_monetization(user_id, enabled, enabled_at, disabled_at, updated_at)
  values (auth.uid(), p_enabled, case when p_enabled then now() end, case when not p_enabled then now() end, now())
  on conflict (user_id) do update set
    enabled = p_enabled,
    enabled_at = case when p_enabled then now() else public.bingo_creator_monetization.enabled_at end,
    disabled_at = case when not p_enabled then now() else public.bingo_creator_monetization.disabled_at end,
    updated_at = now();

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), auth.uid(), 'set_creator_monetization', jsonb_build_object('enabled', p_enabled));

  return p_enabled;
end;
$$;

revoke all on function public.bingo_creator_set_monetization(boolean) from public;
grant execute on function public.bingo_creator_set_monetization(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Award a genuine Crown gift. DELIBERATELY NOT granted to `authenticated`
--    - giver_id/creator_id/tier are fully caller-supplied and there is no
--    server-side proof of payment behind them. Granting this to ordinary
--    users would let anyone credit themselves (or anyone) real money by
--    calling the RPC directly, bypassing whatever real payment/reaction
--    event is supposed to produce source_event_id. It is callable only by
--    service_role - i.e. only from a trusted server context (a future Edge
--    Function that has already verified a real payment/reaction event)
--    -  never directly from the browser. No such Edge Function exists yet
--    in this repository; this RPC is the safe landing point for one, not a
--    claim that one exists.
--
--    If the recipient has not turned monetization on, the gift is still
--    logged (so nothing is silently lost if they enable it later is a
--    product decision NOT made here) but credits nothing to any pool -
--    "Default must NOT manufacture earnings" is enforced by the
--    v_enabled check before any pool credit happens.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_creator_award_crown_gift(
  p_source_event_id text, p_topic_id uuid, p_giver_id uuid, p_creator_id uuid, p_tier text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_amount numeric;
  v_enabled boolean;
  v_cycle public.bingo_creator_competition_cycles;
  v_gift_id uuid;
begin
  if p_source_event_id is null or length(p_source_event_id) = 0 then
    raise exception 'A unique source event id is required.';
  end if;
  v_amount := public._bingo_creator_crown_amount(p_tier);
  if v_amount is null then raise exception 'Unknown Crown tier: %', p_tier; end if;

  -- Idempotent: a retried callback/replay with the same source_event_id
  -- returns the existing row instead of inserting (and crediting) twice.
  select id into v_gift_id from public.bingo_creator_crown_gifts where source_event_id = p_source_event_id;
  if v_gift_id is not null then
    return jsonb_build_object('gift_id', v_gift_id, 'duplicate', true);
  end if;

  insert into public.bingo_creator_crown_gifts(source_event_id, topic_id, giver_id, creator_id, tier, creator_amount)
  values (p_source_event_id, p_topic_id, p_giver_id, p_creator_id, p_tier, v_amount)
  returning id into v_gift_id;

  select enabled into v_enabled from public.bingo_creator_monetization where user_id = p_creator_id;
  if coalesce(v_enabled, false) then
    v_cycle := public._bingo_creator_current_cycle();
    insert into public.bingo_creator_cycle_ledger(creator_id, cycle_id, pool_amount)
    values (p_creator_id, v_cycle.id, v_amount)
    on conflict (creator_id, cycle_id) do update set
      pool_amount = public.bingo_creator_cycle_ledger.pool_amount + v_amount,
      updated_at = now()
    where not public.bingo_creator_cycle_ledger.settled;
  end if;

  return jsonb_build_object('gift_id', v_gift_id, 'duplicate', false, 'credited', coalesce(v_enabled, false));
end;
$$;

revoke all on function public.bingo_creator_award_crown_gift(text, uuid, uuid, uuid, text) from public, authenticated;
grant execute on function public.bingo_creator_award_crown_gift(text, uuid, uuid, uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- 10. Admin/dev-only test crediting - the ONLY way an ordinary creator's
--     pool can move without a real event, and it is unreachable by an
--     ordinary creator: bingo_is_super_user() is checked first, inside the
--     function, not just by hiding a button in the UI. Still writes through
--     the same award function (same idempotency, same ledger), just with a
--     synthetic source_event_id so it is always distinguishable from a real
--     gift in the ledger (prefix 'admin_test:').
-- ---------------------------------------------------------------------------
create or replace function public.bingo_admin_test_award_crown_gift(p_creator_id uuid, p_tier text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only a super user may use the Crown test tools.';
  end if;
  return public.bingo_creator_award_crown_gift(
    'admin_test:' || gen_random_uuid()::text, null, auth.uid(), p_creator_id, p_tier
  );
end;
$$;

revoke all on function public.bingo_admin_test_award_crown_gift(uuid, text) from public;
grant execute on function public.bingo_admin_test_award_crown_gift(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 11. Weekly cycle settlement: 30% reset fee / 70% credited to the
--     withdrawable wallet. Restricted to super_user (manual trigger) for
--     now - no scheduled job is created here (pg_cron is a product/ops
--     decision, not assumed). Idempotent per (creator_id, cycle_id): the
--     `for update` row lock plus the `where not settled` guard means a
--     second call against an already-settled row changes nothing and
--     returns settled_count=0, so re-running this safely (e.g. a retried
--     cron invocation) can never double-settle.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_creator_process_cycle_settlement(p_cycle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_settled_count integer := 0;
  v_deduction numeric;
  v_net numeric;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only a super user may process a cycle settlement.';
  end if;

  for v_row in
    select * from public.bingo_creator_cycle_ledger
    where cycle_id = p_cycle_id and not settled and pool_amount > 0
    for update
  loop
    v_deduction := round(v_row.pool_amount * 0.30, 2);
    v_net := round(v_row.pool_amount - v_deduction, 2);

    insert into public.bingo_creator_wallet_ledger(creator_id, entry_type, amount, source_type, source_id)
    values (v_row.creator_id, 'credit', v_net, 'cycle_settlement', v_row.id);

    update public.bingo_creator_cycle_ledger
    set settled = true, settlement_amount = v_net, settled_at = now(), updated_at = now()
    where id = v_row.id;

    v_settled_count := v_settled_count + 1;
  end loop;

  update public.bingo_creator_competition_cycles set status = 'settled'
  where id = p_cycle_id and not exists (
    select 1 from public.bingo_creator_cycle_ledger
    where cycle_id = p_cycle_id and not settled and pool_amount > 0
  );

  return jsonb_build_object('settled_count', v_settled_count);
end;
$$;

revoke all on function public.bingo_creator_process_cycle_settlement(uuid) from public;
grant execute on function public.bingo_creator_process_cycle_settlement(uuid) to authenticated;

-- Convenience wrapper so the super-user-only dev test panel never needs to
-- know or display an internal cycle id - it only ever settles "this week".
create or replace function public.bingo_admin_test_settle_current_cycle()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cycle public.bingo_creator_competition_cycles;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only a super user may use the Crown test tools.';
  end if;
  v_cycle := public._bingo_creator_current_cycle();
  return public.bingo_creator_process_cycle_settlement(v_cycle.id);
end;
$$;

revoke all on function public.bingo_admin_test_settle_current_cycle() from public;
grant execute on function public.bingo_admin_test_settle_current_cycle() to authenticated;

-- ---------------------------------------------------------------------------
-- 12. Private dashboard - the ONLY read path the frontend should use.
--     Always filters by auth.uid(); the client never supplies a creator id
--     to read with, so Creator A cannot construct a call that reads
--     Creator B's row no matter what parameters they pass (there are none).
-- ---------------------------------------------------------------------------
create or replace function public.bingo_creator_dashboard()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid;
  v_enabled boolean;
  v_cycle public.bingo_creator_competition_cycles;
  v_pool numeric;
  v_settled boolean;
  v_withdrawable numeric;
  v_gold_count integer; v_silver_count integer; v_bronze_count integer;
  v_gold_total numeric; v_silver_total numeric; v_bronze_total numeric;
  v_pending_withdrawal numeric;
begin
  v_me := auth.uid();
  if v_me is null then raise exception 'Sign in required.'; end if;

  select enabled into v_enabled from public.bingo_creator_monetization where user_id = v_me;
  v_enabled := coalesce(v_enabled, false);

  v_cycle := public._bingo_creator_current_cycle();

  select coalesce(pool_amount, 0), coalesce(settled, false) into v_pool, v_settled
  from public.bingo_creator_cycle_ledger where creator_id = v_me and cycle_id = v_cycle.id;
  v_pool := coalesce(v_pool, 0);

  select
    coalesce(sum(case when tier = 'gold' then 1 else 0 end), 0),
    coalesce(sum(case when tier = 'silver' then 1 else 0 end), 0),
    coalesce(sum(case when tier = 'bronze' then 1 else 0 end), 0),
    coalesce(sum(case when tier = 'gold' then creator_amount else 0 end), 0),
    coalesce(sum(case when tier = 'silver' then creator_amount else 0 end), 0),
    coalesce(sum(case when tier = 'bronze' then creator_amount else 0 end), 0)
  into v_gold_count, v_silver_count, v_bronze_count, v_gold_total, v_silver_total, v_bronze_total
  from public.bingo_creator_crown_gifts where creator_id = v_me;

  select coalesce(sum(case entry_type when 'credit' then amount when 'release' then amount when 'reserve' then -amount else 0 end), 0)
  into v_withdrawable
  from public.bingo_creator_wallet_ledger where creator_id = v_me;

  select coalesce(sum(amount), 0) into v_pending_withdrawal
  from public.bingo_creator_withdrawal_requests where creator_id = v_me and withdrawal_status = 'pending';

  return jsonb_build_object(
    'monetization_enabled', v_enabled,
    'withdrawable_balance', v_withdrawable,
    'withdrawal_minimum', public._bingo_creator_withdrawal_minimum(),
    'withdrawal_eligible', v_withdrawable >= public._bingo_creator_withdrawal_minimum(),
    'pending_withdrawal', v_pending_withdrawal,
    'competition_pool', v_pool,
    'competition_pool_settled', v_settled,
    'cycle_start', v_cycle.cycle_start,
    'cycle_end', v_cycle.cycle_end,
    'gold_count', v_gold_count, 'silver_count', v_silver_count, 'bronze_count', v_bronze_count,
    'gold_total', v_gold_total, 'silver_total', v_silver_total, 'bronze_total', v_bronze_total,
    'gold_rate', public._bingo_creator_crown_amount('gold'),
    'silver_rate', public._bingo_creator_crown_amount('silver'),
    'bronze_rate', public._bingo_creator_crown_amount('bronze')
  );
end;
$$;

revoke all on function public.bingo_creator_dashboard() from public;
grant execute on function public.bingo_creator_dashboard() to authenticated;

-- ---------------------------------------------------------------------------
-- 13. Withdrawal request - locks (reserves) the balance immediately so it
--     cannot be requested twice while pending, exactly like
--     bingo_agent_request_commission_withdrawal already does for the
--     Agent program.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_creator_request_withdrawal(p_phone text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid;
  v_enabled boolean;
  v_available numeric;
  v_minimum numeric;
  v_request_id uuid;
begin
  v_me := auth.uid();
  if v_me is null then raise exception 'Sign in required.'; end if;

  select enabled into v_enabled from public.bingo_creator_monetization where user_id = v_me;
  if not coalesce(v_enabled, false) then
    raise exception 'Monetization is not enabled on this account.';
  end if;

  if p_phone is null or p_phone !~ '^254[17][0-9]{8}$' then
    raise exception 'Enter a valid Safaricom M-Pesa number in 254 format.';
  end if;

  v_minimum := public._bingo_creator_withdrawal_minimum();
  select coalesce(sum(case entry_type when 'credit' then amount when 'release' then amount when 'reserve' then -amount else 0 end), 0)
  into v_available
  from public.bingo_creator_wallet_ledger where creator_id = v_me;

  if v_available < v_minimum then
    raise exception 'Your withdrawable balance must reach KSh % before you can withdraw.', to_char(v_minimum, 'FM999,999,990');
  end if;

  insert into public.bingo_creator_withdrawal_requests(creator_id, amount, payout_phone)
  values (v_me, v_available, p_phone)
  returning id into v_request_id;

  insert into public.bingo_creator_wallet_ledger(creator_id, entry_type, amount, source_type, source_id)
  values (v_me, 'reserve', v_available, 'withdrawal_request', v_request_id);

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (v_me, v_me, 'request_creator_withdrawal', jsonb_build_object('withdrawal_id', v_request_id, 'amount', v_available));

  return v_request_id;
end;
$$;

revoke all on function public.bingo_creator_request_withdrawal(text) from public;
grant execute on function public.bingo_creator_request_withdrawal(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 14. Admin review of a withdrawal request. This IS the real production
--     payout step for now - a super user manually sends the M-Pesa payment
--     (outside this system, exactly as the Agent program already does) and
--     records what happened. 'approve' -> 'paid' leaves the reserved amount
--     permanently debited (money has left Bingo). 'reject' releases the
--     reserved amount back to the withdrawable balance.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_admin_review_creator_withdrawal(
  p_withdrawal_id uuid, p_action text, p_payment_reference text default null
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.bingo_creator_withdrawal_requests%rowtype;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only a super user may review a withdrawal.';
  end if;
  if p_action not in ('approve','reject') then raise exception 'Invalid action.'; end if;

  select * into v_row from public.bingo_creator_withdrawal_requests where id = p_withdrawal_id for update;
  if not found then raise exception 'Withdrawal request not found.'; end if;
  if v_row.withdrawal_status <> 'pending' then raise exception 'This request has already been reviewed.'; end if;

  if p_action = 'approve' then
    update public.bingo_creator_withdrawal_requests
    set withdrawal_status = 'paid', administrator_id = auth.uid(), payment_reference = p_payment_reference, reviewed_at = now()
    where id = p_withdrawal_id;
  else
    update public.bingo_creator_withdrawal_requests
    set withdrawal_status = 'rejected', administrator_id = auth.uid(), reviewed_at = now()
    where id = p_withdrawal_id;
    insert into public.bingo_creator_wallet_ledger(creator_id, entry_type, amount, source_type, source_id)
    values (v_row.creator_id, 'release', v_row.amount, 'withdrawal_request', v_row.id);
  end if;

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), v_row.creator_id, 'review_creator_withdrawal', jsonb_build_object('withdrawal_id', p_withdrawal_id, 'decision', p_action, 'payment_reference', p_payment_reference));

  return true;
end;
$$;

revoke all on function public.bingo_admin_review_creator_withdrawal(uuid, text, text) from public;
grant execute on function public.bingo_admin_review_creator_withdrawal(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';

-- ============================================================================
-- NOT INCLUDED (deliberately):
--  - Any real caller of bingo_creator_award_crown_gift(). No frontend UI in
--    this repository collects real payment for a tiered Gold/Silver/Bronze
--    Crown gift today - the existing "Crown" button is a single, untiered,
--    non-monetary reaction (aaTopicLove, relabeled). Building that payment
--    flow (almost certainly another STK Push, like mpesa-boost) is a
--    separate feature and is not assumed or faked here.
--  - Any automated M-Pesa B2C disbursement. bingo_admin_review_creator_
--    withdrawal() records that an administrator paid a creator; it does
--    not call Safaricom. No B2C Edge Function, credentials or Daraja B2C
--    app exist anywhere in this repository.
--  - A scheduled trigger for bingo_creator_process_cycle_settlement(). It
--    is callable, idempotent and super-user-gated, but nothing calls it on
--    a timer; wiring pg_cron (or an external scheduler) is an ops decision
--    left for explicit approval.
-- ============================================================================
