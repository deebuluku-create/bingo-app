-- ============================================================================
-- BINGO — AGENT COMMISSION WITHDRAWAL MINIMUM: 10,000 -> 50 (KES)
--
-- Confirmed business rule: an Agent may request a commission withdrawal
-- once their server-verified available balance is at least KES 50.
--
-- Everything that currently hardcodes 10,000 lives in
-- supabase/bingo_change_agent_1000_target_salary_commission.sql
-- (committed as 279e73e / reconciled in 286b0cd), in four places:
--   1. bingo_agent_withdrawals.amount  CHECK (amount >= 10000)
--   2. bingo_agent_request_commission_withdrawal(p_amount)  — the RPC
--      that actually gates the write, independent of the frontend
--   3. bingo_agent_commission_summary()  — returns 'withdrawal_minimum'
--      in its JSON (confirmed via repo-wide grep: not currently called
--      by the frontend, but a public API surface regardless)
--   4. The frontend's own AA_AGENT_WITHDRAWAL_MINIMUM constant, fixed
--      separately in BINGO_MASTER_CURRENT_VERIFIED.html in this same
--      commit, alongside every display string that quoted "KSh 10,000".
--
-- This migration makes the SERVER the single source of truth for the
-- number (per explicit instruction: "cannot silently drift again") by
-- introducing one trivial constant function, _bingo_agent_withdrawal_
-- minimum(), and pointing the CHECK constraint and both RPCs at it
-- instead of each carrying their own copy of the literal 50. Changing
-- the minimum in the future means editing this one function.
--
-- Entirely additive/idempotent: every statement is CREATE OR REPLACE,
-- or an explicit DROP CONSTRAINT IF EXISTS + ADD CONSTRAINT pair. Safe
-- to run multiple times. Does not touch any other Agent, boost, food
-- or follows object.
--
-- IMPORTANT — apply-order prerequisite: this migration assumes
-- supabase/bingo_change_agent_1000_target_salary_commission.sql has
-- already been applied live (bingo_agent_withdrawals,
-- bingo_agent_commission_ledger, bingo_agent_request_commission_
-- withdrawal, bingo_agent_commission_summary and bingo_agent_progress_
-- bulletin must already exist). Run the read-only inspection queries
-- in 20260927_bingo_agent_withdrawal_minimum_50_INSPECT_LIVE_FIRST.sql
-- against the live project BEFORE this file, to confirm that
-- assumption and to see the exact live constraint/function text this
-- migration is about to replace. If any of those objects are missing
-- live, apply the base salary/commission script first.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Single source of truth for the minimum. Pure, no table access, no
--    side effects — a literal wrapped in a function so every consumer
--    (the CHECK constraint and both RPCs below) reads the same value
--    from one place instead of each hardcoding its own copy.
--    No explicit revoke/grant, matching this file's own convention for
--    internal "_"-prefixed helpers (see _bingo_agent_compute_cycle in
--    the base script) — Postgres' default PUBLIC execute grant is fine
--    here since the function is a constant with no table access and no
--    argument-driven behavior to abuse.
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
-- 2. Table CHECK constraint — defense-in-depth against ANY insert path,
--    not just the RPC below (e.g. a future direct-insert bug, or a
--    service-role script). Postgres allows a non-immutable function in
--    a CHECK in principle, but this one genuinely is IMMUTABLE (a
--    literal constant), so it is both correct and best practice here.
--
--    Drops whichever CHECK constraint currently exists on this column
--    by inspecting pg_constraint rather than assuming its name is the
--    Postgres-default "bingo_agent_withdrawals_amount_check" — that IS
--    what an inline column CHECK on a freshly created table gets named
--    by default (matching how the base script defined it), but this
--    does not assume that has held true live untouched. Confirm the
--    live name/definition first with the inspection query in
--    20260927_bingo_agent_withdrawal_minimum_50_INSPECT_LIVE_FIRST.sql.
-- ---------------------------------------------------------------------------
do $$
declare
  v_conname text;
begin
  for v_conname in
    select conname from pg_constraint
    where conrelid = 'public.bingo_agent_withdrawals'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%amount%'
  loop
    execute format('alter table public.bingo_agent_withdrawals drop constraint %I', v_conname);
  end loop;
end
$$;
alter table public.bingo_agent_withdrawals
  add constraint bingo_agent_withdrawals_amount_check
  check (amount >= public._bingo_agent_withdrawal_minimum());

-- ---------------------------------------------------------------------------
-- 3. The authoritative request-time gate. Message text now also derives
--    from the function, so the wording can never say "10,000" while the
--    check enforces a different number.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_agent_request_commission_withdrawal(p_amount numeric)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_available numeric(12,2);
  v_withdrawal_id uuid;
  v_minimum numeric;
begin
  if auth.uid() is null then raise exception 'Sign in required.'; end if;
  if not exists (select 1 from public.bingo_user_roles where user_id = auth.uid() and role = 'agent' and agent_status = 'active') then
    raise exception 'Your Agent access is not currently active.';
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

  insert into public.bingo_agent_withdrawals(agent_id, amount) values (auth.uid(), p_amount) returning id into v_withdrawal_id;
  insert into public.bingo_agent_commission_ledger(agent_id, entry_type, amount, reference)
  values (auth.uid(), 'reserve', p_amount, 'withdrawal:'||v_withdrawal_id);

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), auth.uid(), 'request_commission_withdrawal', jsonb_build_object('withdrawal_id', v_withdrawal_id, 'amount', p_amount));

  insert into public.bingo_role_notifications(user_id, message)
  values (auth.uid(), 'Your commission withdrawal request for KSh '||to_char(p_amount,'FM999,999,990')||' has been submitted for review.');

  return v_withdrawal_id;
end;
$$;

revoke all on function public.bingo_agent_request_commission_withdrawal(numeric) from public;
grant execute on function public.bingo_agent_request_commission_withdrawal(numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. bingo_agent_commission_summary — currently unused by the frontend
--    (verified via repo-wide grep), but a public API surface with its
--    own EXECUTE grant to authenticated, so its number is corrected too.
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
  from public.bingo_agent_withdrawals where agent_id = auth.uid() and status = 'pending';

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
-- 5. bingo_agent_progress_bulletin — additive field only. This is the RPC
--    the frontend already calls on every dashboard load
--    (aaLoadAgentProgressBulletin), so adding withdrawal_minimum here,
--    rather than introducing a second round trip to
--    bingo_agent_commission_summary, is what lets the UI read the
--    server-confirmed minimum with no extra request. Every previously
--    existing field is untouched — this is a pure addition to the
--    returned jsonb.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_agent_progress_bulletin()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_cycle public.bingo_agent_salary_cycles;
  v_elapsed_fraction numeric;
  v_expected_percent numeric(7,2);
  v_pace text;
  v_commission_available numeric(12,2);
  v_next_update timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.';
  end if;
  select role into v_role from public.bingo_user_roles where user_id = auth.uid();
  if v_role is distinct from 'agent' then
    raise exception 'This account does not have an active Agent appointment.';
  end if;

  v_cycle := public._bingo_agent_compute_cycle(auth.uid());

  v_elapsed_fraction := extract(epoch from (least(now(), v_cycle.cycle_end) - v_cycle.cycle_start))
                        / nullif(extract(epoch from (v_cycle.cycle_end - v_cycle.cycle_start)), 0);
  v_expected_percent := least(100, greatest(0, coalesce(v_elapsed_fraction, 0) * 100));
  v_pace := case
    when v_cycle.progress_percent >= v_expected_percent + 5 then 'ahead'
    when v_cycle.progress_percent <= v_expected_percent - 5 then 'behind'
    else 'on_track'
  end;

  select coalesce(sum(case entry_type
    when 'credit' then amount
    when 'adjustment' then amount
    when 'release' then amount
    when 'reserve' then -amount
    else 0 end), 0) into v_commission_available
  from public.bingo_agent_commission_ledger
  where agent_id = auth.uid();

  -- Next Monday 08:00 Africa/Nairobi (UTC+3, no DST).
  v_next_update := (date_trunc('week', (now() at time zone 'Africa/Nairobi') + interval '1 week')
                     + interval '8 hours') at time zone 'Africa/Nairobi';

  return jsonb_build_object(
    'qualified_clients', v_cycle.qualified_clients,
    'target_clients', v_cycle.target_clients,
    'progress_percent', v_cycle.progress_percent,
    'expected_percent', round(v_expected_percent, 1),
    'pace_status', v_pace,
    'salary_tier', v_cycle.salary_tier,
    'eligible_salary', v_cycle.eligible_salary,
    'salary_status', v_cycle.salary_status,
    'commission_available', v_commission_available,
    'withdrawal_minimum', public._bingo_agent_withdrawal_minimum(),
    'cycle_start', v_cycle.cycle_start,
    'cycle_end', v_cycle.cycle_end,
    'cycle_start_label', to_char(v_cycle.cycle_start, 'DD Mon YYYY'),
    'cycle_end_label', to_char(v_cycle.cycle_end, 'DD Mon YYYY'),
    'next_update_label', to_char(v_next_update, 'DD Mon YYYY'),
    'updated_label', to_char(now(), 'DD Mon YYYY HH24:MI')
  );
end;
$$;

revoke all on function public.bingo_agent_progress_bulletin() from public;
grant execute on function public.bingo_agent_progress_bulletin() to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Verification queries — run after applying, before trusting it live.
-- ---------------------------------------------------------------------------
-- Expect: check (amount >= _bingo_agent_withdrawal_minimum())
select pg_get_constraintdef(oid) from pg_constraint
  where conrelid = 'public.bingo_agent_withdrawals'::regclass and contype = 'c';
-- Expect: 50
select public._bingo_agent_withdrawal_minimum();
