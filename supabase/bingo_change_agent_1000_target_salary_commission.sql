-- ============================================================================
-- BINGO — AGENT 1,000-CLIENT TARGET, SALARY, COMMISSION AND NOTIFICATIONS
--
-- Reconciles (does not replace) supabase/bingo_change_agent_salary_and_business_access.sql:
-- the required-clients=2 rule is retired everywhere below in favour of a
-- server-controlled 1,000-client monthly target with a 500-client half-
-- salary tier. bingo_user_roles, territory, bingo_business_agent_access,
-- bingo_agent_client_qualifications, the Agent business-permission RPCs,
-- moderation, Food Menu, Home feed, M-Pesa and the neon button system are
-- all untouched. Run this AFTER bingo_change_agent_salary_and_business_access.sql.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. New columns on the existing salary-cycle table
-- ---------------------------------------------------------------------------
alter table public.bingo_agent_salary_cycles
  add column if not exists target_clients integer not null default 1000,
  add column if not exists progress_percent numeric(7,2) not null default 0,
  add column if not exists salary_tier text not null default 'none',
  add column if not exists eligible_salary numeric(12,2) not null default 0;

alter table public.bingo_agent_salary_cycles drop constraint if exists bingo_agent_salary_target_check;
alter table public.bingo_agent_salary_cycles add constraint bingo_agent_salary_target_check check (target_clients = 1000);

alter table public.bingo_agent_salary_cycles drop constraint if exists bingo_agent_salary_tier_check;
alter table public.bingo_agent_salary_cycles add constraint bingo_agent_salary_tier_check check (salary_tier in ('none','half','full'));

-- The old "always exactly KSh 35,000" check no longer holds now that half
-- salary (KSh 17,500) and no salary (KSh 0) are both legitimate outcomes.
alter table public.bingo_agent_salary_cycles drop constraint if exists bingo_agent_salary_cycles_salary_amount_check;
alter table public.bingo_agent_salary_cycles add constraint bingo_agent_salary_cycles_salary_amount_check check (salary_amount in (0, 17500, 35000));

-- required_clients (the old =2 column) is left in place, unused going
-- forward, rather than dropped — nothing reads it after this migration,
-- and dropping a column is a destructive operation this change does not
-- need to make.

-- ---------------------------------------------------------------------------
-- 2. New tables (verbatim per spec, RLS added)
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_agent_progress_snapshots (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid not null references auth.users(id) on delete cascade,
  salary_cycle_id uuid not null references public.bingo_agent_salary_cycles(id) on delete cascade,
  qualified_clients integer not null default 0,
  target_clients integer not null default 1000,
  progress_percent numeric(7,2) not null default 0,
  expected_percent numeric(7,2) not null default 0,
  pace_status text not null check (pace_status in ('ahead','on_track','behind')),
  salary_tier text not null check (salary_tier in ('none','half','full')),
  captured_at timestamptz not null default now(),
  unique (agent_id, salary_cycle_id, captured_at)
);

create table if not exists public.bingo_agent_commission_ledger (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid not null references auth.users(id) on delete cascade,
  business_id uuid,
  entry_type text not null check (entry_type in ('credit','reserve','release','paid','adjustment')),
  amount numeric(12,2) not null check (amount > 0),
  reference text,
  created_at timestamptz not null default now()
);

create table if not exists public.bingo_agent_withdrawals (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid not null references auth.users(id) on delete cascade,
  amount numeric(12,2) not null check (amount >= 10000),
  status text not null default 'pending' check (status in ('pending','approved','rejected','paid')),
  payment_reference text,
  reviewed_by uuid references auth.users(id),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  paid_at timestamptz
);

create table if not exists public.bingo_scheduled_notification_runs (
  id uuid primary key default gen_random_uuid(),
  run_key text not null unique,
  notification_type text not null,
  period_start timestamptz not null,
  period_end timestamptz not null,
  completed_at timestamptz not null default now()
);

alter table public.bingo_agent_progress_snapshots enable row level security;
alter table public.bingo_agent_commission_ledger enable row level security;
alter table public.bingo_agent_withdrawals enable row level security;
alter table public.bingo_scheduled_notification_runs enable row level security;

-- Do not grant direct browser INSERT/UPDATE/DELETE on any of these — every
-- write happens through a SECURITY DEFINER RPC below.
drop policy if exists "Agents view own snapshots" on public.bingo_agent_progress_snapshots;
create policy "Agents view own snapshots" on public.bingo_agent_progress_snapshots
  for select to authenticated using (agent_id = auth.uid());
drop policy if exists "Super User views all snapshots" on public.bingo_agent_progress_snapshots;
create policy "Super User views all snapshots" on public.bingo_agent_progress_snapshots
  for select to authenticated using (public.bingo_is_super_user());

drop policy if exists "Agents view own commission ledger" on public.bingo_agent_commission_ledger;
create policy "Agents view own commission ledger" on public.bingo_agent_commission_ledger
  for select to authenticated using (agent_id = auth.uid());
drop policy if exists "Super User views all commission ledgers" on public.bingo_agent_commission_ledger;
create policy "Super User views all commission ledgers" on public.bingo_agent_commission_ledger
  for select to authenticated using (public.bingo_is_super_user());

drop policy if exists "Agents view own withdrawals" on public.bingo_agent_withdrawals;
create policy "Agents view own withdrawals" on public.bingo_agent_withdrawals
  for select to authenticated using (agent_id = auth.uid());
drop policy if exists "Super User views all withdrawals" on public.bingo_agent_withdrawals;
create policy "Super User views all withdrawals" on public.bingo_agent_withdrawals
  for select to authenticated using (public.bingo_is_super_user());

drop policy if exists "Super User views scheduled notification runs" on public.bingo_scheduled_notification_runs;
create policy "Super User views scheduled notification runs" on public.bingo_scheduled_notification_runs
  for select to authenticated using (public.bingo_is_super_user());

create index if not exists bingo_agent_commission_ledger_agent_idx on public.bingo_agent_commission_ledger(agent_id, entry_type);
create index if not exists bingo_agent_withdrawals_agent_idx on public.bingo_agent_withdrawals(agent_id, status);

-- ---------------------------------------------------------------------------
-- 3. Shared internal helper — the single place cycle/tier math happens, so
--    the per-user RPC and the bulk scheduled jobs never compute it twice.
-- ---------------------------------------------------------------------------
create or replace function public._bingo_agent_compute_cycle(p_agent_id uuid)
returns public.bingo_agent_salary_cycles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_agent_since timestamptz;
  v_bounds record;
  v_qualified_count integer;
  v_cycle public.bingo_agent_salary_cycles;
  v_owner record;
  v_tier text;
  v_eligible numeric(12,2);
  v_progress numeric(7,2);
begin
  select agent_since into v_agent_since from public.bingo_user_roles where user_id = p_agent_id and role = 'agent';
  if v_agent_since is null then
    raise exception 'This account does not have an active Agent appointment.';
  end if;

  select * into v_bounds from public._bingo_agent_cycle_bounds(v_agent_since, now());

  for v_owner in
    select distinct on (a.owner_id) a.id as access_id, a.owner_id, a.business_type, a.business_id
    from public.bingo_business_agent_access a
    where a.agent_id = p_agent_id
      and a.invitation_status = 'accepted'
      and a.accepted_at is not null
      and a.accepted_at >= v_bounds.cycle_start
      and a.accepted_at < v_bounds.cycle_end
      and a.owner_id <> p_agent_id
      and (
        (a.business_type = 'food_business' and exists (select 1 from public.food_businesses fb where fb.id = a.business_id and fb.status = 'active'))
        or
        (a.business_type in ('property','stay') and exists (select 1 from public.property_listings pl where pl.id = a.business_id and pl.status = 'published'))
      )
    order by a.owner_id, a.accepted_at asc
  loop
    insert into public.bingo_agent_client_qualifications(agent_id, owner_id, business_type, business_id, access_id, salary_cycle_number)
    values (p_agent_id, v_owner.owner_id, v_owner.business_type, v_owner.business_id, v_owner.access_id, v_bounds.cycle_number)
    on conflict (agent_id, owner_id, salary_cycle_number) do nothing;
  end loop;

  select count(*) into v_qualified_count
  from public.bingo_agent_client_qualifications
  where agent_id = p_agent_id and salary_cycle_number = v_bounds.cycle_number and qualification_status = 'qualified';

  v_progress := least(100, v_qualified_count * 100.0 / 1000);
  if v_qualified_count >= 1000 then v_tier := 'full'; v_eligible := 35000;
  elsif v_qualified_count >= 500 then v_tier := 'half'; v_eligible := 17500;
  else v_tier := 'none'; v_eligible := 0;
  end if;

  insert into public.bingo_agent_salary_cycles(agent_id, cycle_number, cycle_start, cycle_end, qualified_clients, target_clients, progress_percent, salary_tier, eligible_salary, salary_amount)
  values (p_agent_id, v_bounds.cycle_number, v_bounds.cycle_start, v_bounds.cycle_end, v_qualified_count, 1000, v_progress, v_tier, v_eligible, v_eligible)
  on conflict (agent_id, cycle_number) do update
    set qualified_clients = excluded.qualified_clients,
        progress_percent = excluded.progress_percent,
        -- Tier/eligible_salary/salary_amount only ever advance — an
        -- already unlocked/approved/paid cycle is never silently reduced
        -- by a later recount (a lower live count can happen if a business
        -- is later suspended; that must not undo an outcome already
        -- reached this cycle).
        salary_tier = case when public.bingo_agent_salary_cycles.salary_status in ('unlocked','approved','paid')
                        then (case when excluded.salary_tier = 'full' or public.bingo_agent_salary_cycles.salary_tier = 'full' then 'full'
                                   when excluded.salary_tier = 'half' or public.bingo_agent_salary_cycles.salary_tier = 'half' then 'half'
                                   else public.bingo_agent_salary_cycles.salary_tier end)
                        else excluded.salary_tier end,
        eligible_salary = case when public.bingo_agent_salary_cycles.salary_status in ('unlocked','approved','paid')
                             then greatest(excluded.eligible_salary, public.bingo_agent_salary_cycles.eligible_salary)
                             else excluded.eligible_salary end,
        salary_amount = case when public.bingo_agent_salary_cycles.salary_status in ('unlocked','approved','paid')
                           then greatest(excluded.salary_amount, public.bingo_agent_salary_cycles.salary_amount)
                           else excluded.salary_amount end,
        updated_at = now()
  returning * into v_cycle;

  if v_cycle.salary_status = 'locked' and v_cycle.salary_tier <> 'none' then
    update public.bingo_agent_salary_cycles
    set salary_status = 'unlocked', unlocked_at = now(), updated_at = now()
    where id = v_cycle.id
    returning * into v_cycle;
  end if;

  return v_cycle;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. bingo_agent_salary_summary — same public signature as before, now
--    delegating to the shared helper with the 1,000/500 target.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_agent_salary_summary()
returns public.bingo_agent_salary_cycles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.';
  end if;
  select role into v_role from public.bingo_user_roles where user_id = auth.uid();
  if v_role is distinct from 'agent' then
    raise exception 'This account does not have an active Agent appointment.';
  end if;
  return public._bingo_agent_compute_cycle(auth.uid());
end;
$$;

revoke all on function public.bingo_agent_salary_summary() from public;
grant execute on function public.bingo_agent_salary_summary() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. bingo_agent_progress_bulletin — the arrival/dashboard bulletin: cycle
--    dates, progress, pace vs. elapsed time, remaining targets, commission
--    balance and next weekly update date. All server-computed.
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
-- 6. Commission summary + withdrawal request + Super User review
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

  return jsonb_build_object('commission_available', v_available, 'pending_withdrawals', v_pending, 'withdrawal_minimum', 10000);
end;
$$;

revoke all on function public.bingo_agent_commission_summary() from public;
grant execute on function public.bingo_agent_commission_summary() to authenticated;

create or replace function public.bingo_agent_request_commission_withdrawal(p_amount numeric)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_available numeric(12,2);
  v_withdrawal_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.'; end if;
  if not exists (select 1 from public.bingo_user_roles where user_id = auth.uid() and role = 'agent' and agent_status = 'active') then
    raise exception 'Your Agent access is not currently active.';
  end if;
  if p_amount is null or p_amount < 10000 then
    raise exception 'A withdrawal request must be at least KSh 10,000.';
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

create or replace function public.bingo_admin_review_agent_withdrawal(p_withdrawal_id uuid, p_action text, p_payment_reference text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.bingo_agent_withdrawals;
  v_ref text;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may review Agent withdrawals.';
  end if;
  if not (p_action = any(array['approve','reject','pay'])) then
    raise exception 'Invalid review action.';
  end if;

  select * into v_row from public.bingo_agent_withdrawals where id = p_withdrawal_id;
  if not found then raise exception 'Withdrawal request not found.'; end if;

  if p_action = 'approve' then
    if v_row.status <> 'pending' then raise exception 'Only a pending withdrawal can be approved.'; end if;
    update public.bingo_agent_withdrawals set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now() where id = p_withdrawal_id;
    insert into public.bingo_role_notifications(user_id, message) values (v_row.agent_id, 'Your commission withdrawal of KSh '||to_char(v_row.amount,'FM999,999,990')||' has been approved and will be paid shortly.');

  elsif p_action = 'reject' then
    if v_row.status <> 'pending' then raise exception 'Only a pending withdrawal can be rejected.'; end if;
    update public.bingo_agent_withdrawals set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now() where id = p_withdrawal_id;
    insert into public.bingo_agent_commission_ledger(agent_id, entry_type, amount, reference)
    values (v_row.agent_id, 'release', v_row.amount, 'withdrawal:'||p_withdrawal_id);
    insert into public.bingo_role_notifications(user_id, message) values (v_row.agent_id, 'Your commission withdrawal request of KSh '||to_char(v_row.amount,'FM999,999,990')||' was not approved. The amount is available in your balance again.');

  elsif p_action = 'pay' then
    if v_row.status <> 'approved' then raise exception 'Only an approved withdrawal can be marked paid.'; end if;
    v_ref := trim(coalesce(p_payment_reference, ''));
    if v_ref = '' then raise exception 'A payment reference is required.'; end if;
    update public.bingo_agent_withdrawals set status = 'paid', paid_at = now(), payment_reference = v_ref where id = p_withdrawal_id;
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
-- 7. bingo_agent_credit_commission — INTENTIONALLY NOT granted to
--    `authenticated`. Commission must only ever be credited after a
--    payment is independently verified server-side; an Agent (or anyone)
--    calling this directly from the browser would be able to fabricate
--    commission. Only the service-role key (an Edge Function's own
--    server-side environment, never the browser) may call it.
--
--    REQUIRED FOLLOW-UP (same pattern as boost-quote in Change 09): the
--    existing mpesa-boost function is not part of this repository and
--    cannot be edited here. Once a boost payment for an Agent-facilitated
--    business is confirmed by its Safaricom callback, mpesa-boost should
--    call this function (using its own service-role client) with the
--    commission amount it already computes today client-side via
--    aaRecordAgentCommissionIfApplicable — moving that calculation
--    server-side of the verified payment is what finally makes the
--    commission ledger authoritative end to end. Until that follow-up
--    lands, the pre-existing local/legacy commission display in the
--    Agent Dashboard's "Commission" tab keeps working exactly as before;
--    this new ledger and its withdrawal flow simply start at zero and
--    fill in only once mpesa-boost is updated to call this function.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_agent_credit_commission(p_agent_id uuid, p_business_id uuid, p_amount numeric, p_reference text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'Commission amount must be positive.';
  end if;
  insert into public.bingo_agent_commission_ledger(agent_id, business_id, entry_type, amount, reference)
  values (p_agent_id, p_business_id, 'credit', p_amount, p_reference);
  insert into public.bingo_role_notifications(user_id, message)
  values (p_agent_id, 'You earned KSh '||to_char(p_amount,'FM999,999,990')||' commission.');
end;
$$;

revoke all on function public.bingo_agent_credit_commission(uuid,uuid,numeric,text) from public;
-- No grant to authenticated — service_role only (the Supabase service-role
-- key already bypasses explicit grants; this simply ensures no ordinary
-- signed-in user, Agent or otherwise, can invoke it directly).

-- ---------------------------------------------------------------------------
-- 8. Scheduled notification generators — idempotent via
--    bingo_scheduled_notification_runs.run_key, so a re-run (or an
--    overlapping cron tick) never sends the same notification twice.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_generate_agent_weekly_notifications()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_agent record;
  v_cycle public.bingo_agent_salary_cycles;
  v_run_key text;
  v_sent integer := 0;
begin
  for v_agent in select user_id from public.bingo_user_roles where role = 'agent' and agent_status = 'active'
  loop
    v_run_key := 'agent_weekly:'||v_agent.user_id||':'||to_char(now(),'IYYY-IW');
    if exists (select 1 from public.bingo_scheduled_notification_runs where run_key = v_run_key) then
      continue;
    end if;

    v_cycle := public._bingo_agent_compute_cycle(v_agent.user_id);

    insert into public.bingo_role_notifications(user_id, message)
    values (
      v_agent.user_id,
      'Weekly progress: '||v_cycle.qualified_clients||' of '||v_cycle.target_clients||' qualified clients ('||
      round(v_cycle.progress_percent,1)||'%). Current salary eligibility: KSh '||to_char(v_cycle.eligible_salary,'FM999,999,990')||'.'
    );

    insert into public.bingo_scheduled_notification_runs(run_key, notification_type, period_start, period_end)
    values (v_run_key, 'agent_weekly', date_trunc('week', now()), date_trunc('week', now()) + interval '1 week');

    -- Immediate milestone notifications (500 / 1,000), each idempotent on
    -- its own run_key so they never duplicate even if this job re-runs.
    if v_cycle.qualified_clients >= 500 then
      declare v_half_key text := 'agent_milestone_half:'||v_agent.user_id||':'||v_cycle.cycle_number;
      begin
        if not exists (select 1 from public.bingo_scheduled_notification_runs where run_key = v_half_key) then
          insert into public.bingo_role_notifications(user_id, message)
          values (v_agent.user_id, 'Milestone reached: 500 qualified clients. Half salary (KSh 17,500) is unlocked for this cycle.');
          insert into public.bingo_scheduled_notification_runs(run_key, notification_type, period_start, period_end)
          values (v_half_key, 'agent_milestone_half', v_cycle.cycle_start, v_cycle.cycle_end);
        end if;
      end;
    end if;
    if v_cycle.qualified_clients >= 1000 then
      declare v_full_key text := 'agent_milestone_full:'||v_agent.user_id||':'||v_cycle.cycle_number;
      begin
        if not exists (select 1 from public.bingo_scheduled_notification_runs where run_key = v_full_key) then
          insert into public.bingo_role_notifications(user_id, message)
          values (v_agent.user_id, 'Milestone reached: 1,000 qualified clients. Full salary (KSh 35,000) is unlocked for this cycle.');
          insert into public.bingo_scheduled_notification_runs(run_key, notification_type, period_start, period_end)
          values (v_full_key, 'agent_milestone_full', v_cycle.cycle_start, v_cycle.cycle_end);
        end if;
      end;
    end if;

    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end;
$$;

revoke all on function public.bingo_generate_agent_weekly_notifications() from public;
-- Intentionally no grant to authenticated: this is a bulk job over every
-- Agent's data and must only be invoked by the scheduler (see Section 9),
-- which runs as the database owner, or manually by a project admin from
-- the SQL Editor — never callable by a signed-in browser session.

create or replace function public.bingo_generate_super_user_daily_agent_report()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run_key text := 'super_daily:'||to_char(current_date,'YYYY-MM-DD');
  v_total integer;
  v_admin record;
begin
  if exists (select 1 from public.bingo_scheduled_notification_runs where run_key = v_run_key) then
    return;
  end if;

  select count(*) into v_total
  from public.bingo_business_agent_access
  where invitation_status = 'accepted' and accepted_at >= current_date - 1 and accepted_at < current_date;

  for v_admin in select user_id from public.bingo_user_roles where role = 'super_user'
  loop
    insert into public.bingo_role_notifications(user_id, message)
    values (v_admin.user_id, 'Daily Agent report: '||v_total||' business(es) came under confirmed Agent management yesterday.');
  end loop;

  insert into public.bingo_scheduled_notification_runs(run_key, notification_type, period_start, period_end)
  values (v_run_key, 'super_daily_agent_report', current_date - 1, current_date);
end;
$$;

revoke all on function public.bingo_generate_super_user_daily_agent_report() from public;

create or replace function public.bingo_generate_super_user_weekly_agent_report()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run_key text := 'super_weekly:'||to_char(now(),'IYYY-IW');
  v_agent record;
  v_cycle public.bingo_agent_salary_cycles;
  v_expected numeric(7,2);
  v_pace text;
  v_available numeric(12,2);
  v_pending numeric(12,2);
  v_lines text := '';
  v_admin record;
begin
  if exists (select 1 from public.bingo_scheduled_notification_runs where run_key = v_run_key) then
    return;
  end if;

  for v_agent in
    select r.user_id, coalesce(p.full_name, trim(coalesce(p.first_name,'')||' '||coalesce(p.last_name,''))) as full_name
    from public.bingo_user_roles r
    left join public.profiles p on p.id = r.user_id
    where r.role = 'agent' and r.agent_status = 'active'
    order by full_name
  loop
    v_cycle := public._bingo_agent_compute_cycle(v_agent.user_id);
    v_expected := least(100, greatest(0, coalesce(
      extract(epoch from (least(now(), v_cycle.cycle_end) - v_cycle.cycle_start)) /
      nullif(extract(epoch from (v_cycle.cycle_end - v_cycle.cycle_start)), 0), 0) * 100));
    v_pace := case when v_cycle.progress_percent >= v_expected + 5 then 'performing well'
                   when v_cycle.progress_percent <= v_expected - 5 then 'behind'
                   else 'on track' end;

    select coalesce(sum(case entry_type when 'credit' then amount when 'adjustment' then amount when 'release' then amount when 'reserve' then -amount else 0 end), 0)
      into v_available from public.bingo_agent_commission_ledger where agent_id = v_agent.user_id;
    select coalesce(sum(amount), 0) into v_pending from public.bingo_agent_withdrawals where agent_id = v_agent.user_id and status = 'pending';

    v_lines := v_lines || coalesce(v_agent.full_name, 'Agent') || ': ' || v_pace || ' — ' ||
      v_cycle.qualified_clients || '/1000 clients (' || round(v_cycle.progress_percent,1) || '%), tier ' ||
      v_cycle.salary_tier || ', commission KSh ' || to_char(v_available,'FM999,999,990') ||
      case when v_pending > 0 then ', pending withdrawal KSh '||to_char(v_pending,'FM999,999,990') else '' end || E'\n';
  end loop;

  if v_lines = '' then
    v_lines := 'No active Agents this week.';
  end if;

  for v_admin in select user_id from public.bingo_user_roles where role = 'super_user'
  loop
    insert into public.bingo_role_notifications(user_id, message)
    values (v_admin.user_id, 'Weekly Agent report ('||to_char(now(),'DD Mon YYYY')||'):'||E'\n'||v_lines);
  end loop;

  insert into public.bingo_scheduled_notification_runs(run_key, notification_type, period_start, period_end)
  values (v_run_key, 'super_weekly_agent_report', date_trunc('week', now()) - interval '1 week', date_trunc('week', now()));
end;
$$;

revoke all on function public.bingo_generate_super_user_weekly_agent_report() from public;

-- ---------------------------------------------------------------------------
-- 9. Scheduling — pg_cron (a secure database scheduler; no browser tab or
--    always-on client required). If pg_cron is not available on your
--    Supabase plan, deploy a small scheduled Edge Function instead that
--    calls these three RPCs via `select public.bingo_generate_...()` on
--    the same cadence from the Supabase Dashboard's Cron Triggers, using
--    the service-role key — either path is equally valid, this file only
--    sets up the pg_cron path since it needs no extra deployment step.
-- ---------------------------------------------------------------------------
create extension if not exists pg_cron with schema extensions;

select cron.unschedule(jobid) from cron.job where jobname = 'bingo-agent-weekly-notifications';
select cron.schedule(
  'bingo-agent-weekly-notifications',
  '0 5 * * 1', -- Monday 05:00 UTC = 08:00 Africa/Nairobi
  $$select public.bingo_generate_agent_weekly_notifications();$$
);

select cron.unschedule(jobid) from cron.job where jobname = 'bingo-super-user-daily-agent-report';
select cron.schedule(
  'bingo-super-user-daily-agent-report',
  '0 6 * * *', -- 06:00 UTC = 09:00 Africa/Nairobi daily
  $$select public.bingo_generate_super_user_daily_agent_report();$$
);

select cron.unschedule(jobid) from cron.job where jobname = 'bingo-super-user-weekly-agent-report';
select cron.schedule(
  'bingo-super-user-weekly-agent-report',
  '0 5 * * 1', -- Monday 05:00 UTC = 08:00 Africa/Nairobi
  $$select public.bingo_generate_super_user_weekly_agent_report();$$
);

-- ---------------------------------------------------------------------------
-- 10. bingo_admin_agent_salary_directory — re-created (its output columns
--     changed, which CREATE OR REPLACE cannot do for a `returns table`
--     function) to surface target_clients/salary_tier/eligible_salary
--     alongside the fields the Super User Dashboard already shows.
-- ---------------------------------------------------------------------------
drop function if exists public.bingo_admin_agent_salary_directory();

create or replace function public.bingo_admin_agent_salary_directory()
returns table (
  user_id uuid, email text, full_name text, territory text, agent_since timestamptz, agent_status text,
  cycle_id uuid, cycle_number integer, cycle_start timestamptz, cycle_end timestamptz,
  qualified_clients integer, target_clients integer, salary_tier text, eligible_salary numeric,
  salary_amount numeric, salary_status text, payment_reference text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_agent record;
  v_cycle public.bingo_agent_salary_cycles;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may view the Agent salary directory.';
  end if;

  for v_agent in
    select r.user_id, u.email, coalesce(p.full_name, trim(coalesce(p.first_name,'') || ' ' || coalesce(p.last_name,''))) as full_name,
           r.territory, r.agent_since, r.agent_status
    from public.bingo_user_roles r
    join auth.users u on u.id = r.user_id
    left join public.profiles p on p.id = r.user_id
    where r.role = 'agent'
    order by r.agent_since desc nulls last
  loop
    cycle_id := null; cycle_number := null; cycle_start := null; cycle_end := null;
    qualified_clients := null; target_clients := null; salary_tier := null; eligible_salary := null;
    salary_amount := null; salary_status := null; payment_reference := null;
    user_id := v_agent.user_id; email := v_agent.email; full_name := v_agent.full_name;
    territory := v_agent.territory; agent_since := v_agent.agent_since; agent_status := v_agent.agent_status;

    if v_agent.agent_since is not null then
      v_cycle := public._bingo_agent_compute_cycle(v_agent.user_id);
      cycle_id := v_cycle.id; cycle_number := v_cycle.cycle_number; cycle_start := v_cycle.cycle_start; cycle_end := v_cycle.cycle_end;
      qualified_clients := v_cycle.qualified_clients; target_clients := v_cycle.target_clients;
      salary_tier := v_cycle.salary_tier; eligible_salary := v_cycle.eligible_salary;
      salary_amount := v_cycle.salary_amount; salary_status := v_cycle.salary_status; payment_reference := v_cycle.payment_reference;
    end if;

    return next;
  end loop;
end;
$$;

revoke all on function public.bingo_admin_agent_salary_directory() from public;
grant execute on function public.bingo_admin_agent_salary_directory() to authenticated;
