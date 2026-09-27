-- READ-ONLY. Run this FIRST, against the live project, before applying
-- 20260927_bingo_agent_withdrawal_minimum_50.sql.
--
-- Why: the repo's supabase/bingo_change_agent_1000_target_salary_
-- commission.sql is committed history (279e73e / reconciled in
-- 286b0cd) and every object it names is what the migration below
-- expects to already exist and expects to be replacing — but a
-- committed .sql file only proves what was intended to run, not what
-- is actually deployed. This sandbox has no live Supabase network
-- access, so this step cannot be run or its output verified from
-- here — it has to be run by someone with access to the project (SQL
-- Editor or any Postgres client against it), and the output checked
-- against the "Expect" comment before trusting the migration is safe
-- to apply.
--
-- Nothing here writes anything. Every statement is a SELECT.

-- 1. Do the objects the migration touches exist at all?
-- Expect: 4 rows, all present = true.
select 'table:bingo_agent_withdrawals' as object, to_regclass('public.bingo_agent_withdrawals') is not null as present
union all
select 'function:bingo_agent_request_commission_withdrawal(numeric)', to_regprocedure('public.bingo_agent_request_commission_withdrawal(numeric)') is not null
union all
select 'function:bingo_agent_commission_summary()', to_regprocedure('public.bingo_agent_commission_summary()') is not null
union all
select 'function:bingo_agent_progress_bulletin()', to_regprocedure('public.bingo_agent_progress_bulletin()') is not null;

-- 2. The live CHECK constraint on bingo_agent_withdrawals.amount — name
--    and exact definition. This is what the migration's DO block will
--    find and drop (matched by "amount" appearing in the definition,
--    not by an assumed name) before adding the new one.
-- Expect: one row, definition containing "amount >= 10000" (or
-- whatever the live number currently is — this is the point of
-- checking rather than assuming).
select conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.bingo_agent_withdrawals'::regclass
  and contype = 'c';

-- 3. The three live function bodies, verbatim, so the "10000" literals
--    in the request RPC and the summary RPC can be located directly
--    (search the printed source for "10000" / "10,000"), and so the
--    progress-bulletin function's CURRENT returned field list is known
--    before the migration adds withdrawal_minimum to it.
select proname, pg_get_functiondef(oid) as source
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in (
    'bingo_agent_request_commission_withdrawal',
    'bingo_agent_commission_summary',
    'bingo_agent_progress_bulletin'
  );

-- 4. Sanity check on the ledger/withdrawals row counts before touching
--    anything — not required by the migration, just useful context on
--    how much live data exists under the current constraint.
select
  (select count(*) from public.bingo_agent_withdrawals) as withdrawal_rows,
  (select count(*) from public.bingo_agent_commission_ledger) as ledger_rows;
