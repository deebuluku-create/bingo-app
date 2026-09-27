-- ============================================================================
-- PAUSED — DO NOT APPLY. A full live-schema comparison (2026-09-27)
-- found this design still doesn't match the real objects, beyond the
-- table name it got right:
--   - live withdrawal status column is withdrawal_status; this file
--     adds and writes a second column, status
--   - live ledger entry_type values are commission / adjustment /
--     reversal; this file's RPCs use credit / reserve / release
--   - live ledger requires source_type and source_id; this file's
--     inserts provide neither
--   - live audit log columns are administrator_id / target_user_id;
--     this file inserts actor_id / target_id
--   - bingo_role_notifications does not exist live at all; both RPCs
--     here insert into it unconditionally
--   - this file's ledger section (create table if not exists + drop/
--     create policy) runs its policy statements against the REAL,
--     ALREADY-EXISTING live ledger table (the table itself already
--     existing makes "create table if not exists" a no-op, but the
--     drop-and-recreate-policy statements still execute) — touching
--     live RLS on a table already in production use, on assumptions
--     that turned out wrong elsewhere in this same file
--
-- Its local test passed because the disposable reproduction it was
-- tested against didn't include these objects' real shape either —
-- passing tests prove nothing when the reproduction itself is wrong.
-- See 20260927_bingo_agent_commission_withdrawals_INSPECT_LIVE_THIRD.sql
-- for the full-column/constraint/policy request needed before a
-- correct replacement can be drafted. Left in place, unmodified,
-- as a record of the reasoning (single source-of-truth minimum
-- function, defensive/additive column handling, SECURITY DEFINER-
-- only writes) the eventual correct version should keep.
-- ============================================================================

-- ============================================================================
-- BINGO — Agent commission withdrawal WRITE PATH, designed against the
-- REAL live table (public.bingo_agent_commission_withdrawals), per the
-- 2026-09-27 live inspection:
--
--   - amount numeric ... CHECK (amount >= 10000)   [confirmed live]
--   - payout_phone ... NOT NULL                     [confirmed live]
--   - RLS: agents have SELECT only. No INSERT policy or grant exists.
--   - No live database function references this table or payout_phone.
--   - No trigger on the table.
--
-- Cross-checked against this entire git repository (every branch, via
-- git grep across all refs/remotes) before writing this file:
--   - "bingo_agent_commission_withdrawals" and "payout_phone" do not
--     appear anywhere else in this repo. Nothing else here created it.
--   - supabase/functions/ contains exactly two Edge Functions on every
--     branch (boost-quote, mpesa-boost) — neither touches withdrawals
--     or payout phones in any way.
--   - No other backend/API directory exists in this repo at all.
--   - The frontend currently in BINGO_MASTER_CURRENT_VERIFIED.html (all
--     branches) calls bingo_agent_withdrawals / bingo_agent_request_
--     commission_withdrawal / bingo_admin_review_agent_withdrawal, none
--     of which the live inspection found — it was calling the wrong
--     objects entirely, separately from the minimum-amount question.
--   - An older, unrelated file on the same branches
--     (BINGO_COMPLETE_UPDATED_VERIFIED_2026-09-19.html) has a client-
--     only, localStorage-only withdrawal mock (aaRequestAgentWithdrawal
--     / agentPayoutPhone) that never called Supabase — a plausible
--     naming ancestor for "payout phone" as a concept, not evidence of
--     this table's actual shape or origin.
--
-- Conclusion: no writer exists anywhere this session can find. This
-- file DESIGNS the complete request + review flow from scratch against
-- the confirmed live table, per instruction, rather than continuing to
-- search for a writer that the evidence says is not there.
--
-- ASSUMPTIONS made where the live inspection didn't report a value —
-- READ THIS before applying. Every one of them is written defensively
-- (IF NOT EXISTS / DO-block discovery) so the migration cannot error
-- out or clobber something real if an assumption is wrong; at worst it
-- adds a column that turns out to duplicate an existing one under a
-- different name, which would surface immediately as a visible error
-- on apply, not as silent data loss.
--   1. The table has an id primary key already (essentially universal
--      in this codebase's convention) — not modified either way.
--   2. It does NOT yet have agent_id, status, requested_at, reviewed_by,
--      reviewed_at, paid_at, payment_reference — added via ADD COLUMN
--      IF NOT EXISTS, so if any of these already exist under these
--      exact names, this is a safe no-op for that column; if any exist
--      under a DIFFERENT name, this will add a duplicate that must be
--      caught in review before the RPCs below are trusted (the RPCs
--      only ever reference the exact names added here).
--   3. public.bingo_agent_commission_ledger — the base script created
--      this, and the whole Agent salary/progress-bulletin system this
--      session already shipped reads it. Checked defensively: if it
--      doesn't exist live either, this migration creates it (same
--      shape as the base script), which would also mean the Commission
--      tab, Progress Bulletin and Salary card have been reading from a
--      table that doesn't exist live, well beyond just withdrawals.
--      Confirm this in review — it changes how urgent the rest of the
--      Agent dashboard's server-verified figures are.
--   4. bingo_role_audit_log / bingo_role_notifications / bingo_user_
--      roles / bingo_is_super_user() — assumed to exist as this
--      session's earlier work with them (untouched by this file) was
--      never flagged as broken. Not re-verified here; if wrong, the
--      RPCs below fail loudly on apply/test, not silently.
--
-- WRITE PATH DESIGN: no client INSERT/UPDATE policy is added on
-- purpose, matching this codebase's own stated convention ("Do not
-- grant direct browser INSERT/UPDATE/DELETE on any of these — every
-- write happens through a SECURITY DEFINER RPC below", from the base
-- salary/commission script). The two RPCs below are DEFINER and do not
-- need RLS to permit the write; they gate it themselves. The existing
-- agent-SELECT-only policy live is left completely untouched — this
-- file makes no change to any policy or grant on the table.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Single source of truth for the minimum, as before — just now
--    actually wired to the table that exists.
-- ---------------------------------------------------------------------------
create or replace function public._bingo_agent_withdrawal_minimum()
returns numeric
language sql
immutable
set search_path = ''
as $$
  select 50::numeric;
$$;

-- ---------------------------------------------------------------------------
-- 2. Defensive column additions (see assumption #2 above). Every one is
--    IF NOT EXISTS. Existing columns amount and payout_phone are NOT
--    touched here except the amount CHECK constraint in step 3.
-- ---------------------------------------------------------------------------
alter table public.bingo_agent_commission_withdrawals
  add column if not exists agent_id uuid,
  add column if not exists status text not null default 'pending',
  add column if not exists requested_at timestamptz not null default now(),
  add column if not exists reviewed_by uuid,
  add column if not exists reviewed_at timestamptz,
  add column if not exists paid_at timestamptz,
  add column if not exists payment_reference text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.bingo_agent_commission_withdrawals'::regclass
      and contype = 'f' and conname = 'bingo_agent_commission_withdrawals_agent_id_fkey'
  ) then
    alter table public.bingo_agent_commission_withdrawals
      add constraint bingo_agent_commission_withdrawals_agent_id_fkey
      foreign key (agent_id) references auth.users(id) on delete cascade;
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.bingo_agent_commission_withdrawals'::regclass
      and contype = 'c' and pg_get_constraintdef(oid) ilike '%status%pending%'
  ) then
    alter table public.bingo_agent_commission_withdrawals
      add constraint bingo_agent_commission_withdrawals_status_check
      check (status in ('pending','approved','rejected','paid'));
  end if;
end
$$;

create index if not exists bingo_agent_commission_withdrawals_agent_idx
  on public.bingo_agent_commission_withdrawals(agent_id, status);

-- ---------------------------------------------------------------------------
-- 3. amount CHECK -> the shared minimum function, on the CORRECT table
--    this time. Same name-agnostic discovery as the paused migration,
--    just retargeted.
-- ---------------------------------------------------------------------------
do $$
declare v_conname text;
begin
  for v_conname in
    select conname from pg_constraint
    where conrelid = 'public.bingo_agent_commission_withdrawals'::regclass
      and contype = 'c' and pg_get_constraintdef(oid) ilike '%amount%'
  loop
    execute format('alter table public.bingo_agent_commission_withdrawals drop constraint %I', v_conname);
  end loop;
end
$$;
alter table public.bingo_agent_commission_withdrawals
  add constraint bingo_agent_commission_withdrawals_amount_check
  check (amount >= public._bingo_agent_withdrawal_minimum());

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.bingo_agent_commission_withdrawals'::regclass
      and contype = 'c' and pg_get_constraintdef(oid) ilike '%payout_phone%'
  ) then
    alter table public.bingo_agent_commission_withdrawals
      add constraint bingo_agent_commission_withdrawals_payout_phone_check
      check (length(trim(payout_phone)) >= 9);
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 4. Ledger table, defensively — see assumption #3 above. Verbatim from
--    the base salary/commission script if it needs creating at all.
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_agent_commission_ledger(
  id uuid primary key default gen_random_uuid(),
  agent_id uuid not null references auth.users(id) on delete cascade,
  business_id uuid,
  entry_type text not null check (entry_type in ('credit','reserve','release','paid','adjustment')),
  amount numeric(12,2) not null check (amount > 0),
  reference text,
  created_at timestamptz not null default now()
);
alter table public.bingo_agent_commission_ledger enable row level security;
drop policy if exists "Agents view own commission ledger" on public.bingo_agent_commission_ledger;
create policy "Agents view own commission ledger" on public.bingo_agent_commission_ledger
  for select to authenticated using (agent_id = auth.uid());
drop policy if exists "Super User views all commission ledgers" on public.bingo_agent_commission_ledger;
create policy "Super User views all commission ledgers" on public.bingo_agent_commission_ledger
  for select to authenticated using (public.bingo_is_super_user());
create index if not exists bingo_agent_commission_ledger_agent_idx
  on public.bingo_agent_commission_ledger(agent_id, entry_type);

-- ---------------------------------------------------------------------------
-- 5. Request RPC — the only write path for an Agent. Adds p_payout_phone
--    as a new required parameter versus the paused design (the live
--    table requires it; the current frontend does not collect it yet —
--    see the paired frontend change in the same commit as this file).
-- ---------------------------------------------------------------------------
create or replace function public.bingo_agent_request_commission_withdrawal(p_amount numeric, p_payout_phone text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_available numeric(12,2);
  v_withdrawal_id uuid;
  v_minimum numeric;
  v_phone text;
begin
  if auth.uid() is null then raise exception 'Sign in required.'; end if;
  if not exists (select 1 from public.bingo_user_roles where user_id = auth.uid() and role = 'agent' and agent_status = 'active') then
    raise exception 'Your Agent access is not currently active.';
  end if;

  v_phone := trim(coalesce(p_payout_phone, ''));
  if length(v_phone) < 9 then
    raise exception 'Enter a valid registered M-Pesa payout number.';
  end if;

  v_minimum := public._bingo_agent_withdrawal_minimum();
  if p_amount is null or p_amount < v_minimum then
    raise exception 'A withdrawal request must be at least KSh %.', to_char(v_minimum, 'FM999,999,990');
  end if;

  select coalesce(sum(case entry_type
    when 'credit' then amount when 'adjustment' then amount when 'release' then amount
    when 'reserve' then -amount else 0 end), 0) into v_available
  from public.bingo_agent_commission_ledger where agent_id = auth.uid();

  if p_amount > v_available then
    raise exception 'Requested amount exceeds your available commission balance.';
  end if;

  insert into public.bingo_agent_commission_withdrawals(agent_id, amount, payout_phone, status)
  values (auth.uid(), p_amount, v_phone, 'pending')
  returning id into v_withdrawal_id;

  insert into public.bingo_agent_commission_ledger(agent_id, entry_type, amount, reference)
  values (auth.uid(), 'reserve', p_amount, 'withdrawal:'||v_withdrawal_id);

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), auth.uid(), 'request_commission_withdrawal', jsonb_build_object('withdrawal_id', v_withdrawal_id, 'amount', p_amount, 'payout_phone', v_phone));

  insert into public.bingo_role_notifications(user_id, message)
  values (auth.uid(), 'Your commission withdrawal request for KSh '||to_char(p_amount,'FM999,999,990')||' has been submitted for review.');

  return v_withdrawal_id;
end;
$$;

revoke all on function public.bingo_agent_request_commission_withdrawal(numeric, text) from public;
grant execute on function public.bingo_agent_request_commission_withdrawal(numeric, text) to authenticated;

-- Drop the old 1-argument signature if the paused/never-applied design
-- somehow got partially created live — safe no-op if it was never there.
drop function if exists public.bingo_agent_request_commission_withdrawal(numeric);

-- ---------------------------------------------------------------------------
-- 6. Super User review RPC — same shape the frontend already calls
--    (p_withdrawal_id, p_action, p_payment_reference), retargeted at
--    the real table.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_admin_review_agent_withdrawal(p_withdrawal_id uuid, p_action text, p_payment_reference text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.bingo_agent_commission_withdrawals;
  v_ref text;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may review Agent withdrawals.';
  end if;
  if not (p_action = any(array['approve','reject','pay'])) then
    raise exception 'Invalid review action.';
  end if;

  select * into v_row from public.bingo_agent_commission_withdrawals where id = p_withdrawal_id;
  if not found then raise exception 'Withdrawal request not found.'; end if;

  if p_action = 'approve' then
    if v_row.status <> 'pending' then raise exception 'Only a pending withdrawal can be approved.'; end if;
    update public.bingo_agent_commission_withdrawals set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now() where id = p_withdrawal_id;
    insert into public.bingo_role_notifications(user_id, message) values (v_row.agent_id, 'Your commission withdrawal of KSh '||to_char(v_row.amount,'FM999,999,990')||' has been approved and will be paid shortly.');

  elsif p_action = 'reject' then
    if v_row.status <> 'pending' then raise exception 'Only a pending withdrawal can be rejected.'; end if;
    update public.bingo_agent_commission_withdrawals set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now() where id = p_withdrawal_id;
    insert into public.bingo_agent_commission_ledger(agent_id, entry_type, amount, reference)
    values (v_row.agent_id, 'release', v_row.amount, 'withdrawal:'||p_withdrawal_id);
    insert into public.bingo_role_notifications(user_id, message) values (v_row.agent_id, 'Your commission withdrawal request of KSh '||to_char(v_row.amount,'FM999,999,990')||' was not approved. The amount is available in your balance again.');

  elsif p_action = 'pay' then
    if v_row.status <> 'approved' then raise exception 'Only an approved withdrawal can be marked paid.'; end if;
    v_ref := trim(coalesce(p_payment_reference, ''));
    if v_ref = '' then raise exception 'A payment reference is required.'; end if;
    update public.bingo_agent_commission_withdrawals set status = 'paid', paid_at = now(), payment_reference = v_ref where id = p_withdrawal_id;
    insert into public.bingo_agent_commission_ledger(agent_id, entry_type, amount, reference)
    values (v_row.agent_id, 'paid', v_row.amount, v_ref);
    insert into public.bingo_role_notifications(user_id, message) values (v_row.agent_id, 'Your commission withdrawal of KSh '||to_char(v_row.amount,'FM999,999,990')||' has been paid. Reference: '||v_ref);
  end if;

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), v_row.agent_id, 'review_commission_withdrawal', jsonb_build_object('withdrawal_id', p_withdrawal_id, 'action', p_action, 'payment_reference', p_payment_reference));
end;
$$;

revoke all on function public.bingo_admin_review_agent_withdrawal(uuid,text,text) from public;
grant execute on function public.bingo_admin_review_agent_withdrawal(uuid,text,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. bingo_agent_commission_summary / bingo_agent_progress_bulletin —
--    same additive withdrawal_minimum field as the paused migration,
--    only created here if they don't already exist (defensive — the
--    live inspection said no function references this table or
--    payout_phone, but didn't say these two specific functions, which
--    reference the LEDGER not the withdrawals table, are absent).
--    CREATE OR REPLACE either way, so this is safe regardless.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_agent_commission_summary()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_available numeric(12,2);
  v_pending numeric(12,2);
begin
  if auth.uid() is null then raise exception 'Sign in required.'; end if;

  select coalesce(sum(case entry_type
    when 'credit' then amount when 'adjustment' then amount when 'release' then amount
    when 'reserve' then -amount else 0 end), 0) into v_available
  from public.bingo_agent_commission_ledger where agent_id = auth.uid();

  select coalesce(sum(amount), 0) into v_pending
  from public.bingo_agent_commission_withdrawals where agent_id = auth.uid() and status = 'pending';

  return jsonb_build_object(
    'commission_available', v_available,
    'pending_withdrawals', v_pending,
    'withdrawal_minimum', public._bingo_agent_withdrawal_minimum()
  );
end;
$$;

revoke all on function public.bingo_agent_commission_summary() from public;
grant execute on function public.bingo_agent_commission_summary() to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Verification queries — run after applying, before trusting it live.
-- ---------------------------------------------------------------------------
select column_name, data_type, is_nullable from information_schema.columns
  where table_schema='public' and table_name='bingo_agent_commission_withdrawals' order by ordinal_position;
select pg_get_constraintdef(oid) from pg_constraint
  where conrelid='public.bingo_agent_commission_withdrawals'::regclass and contype in ('c','f');
select public._bingo_agent_withdrawal_minimum();
