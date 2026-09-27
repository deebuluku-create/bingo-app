-- READ-ONLY. Run this against the live project. It follows the
-- 2026-09-27 correction that live has public.bingo_agent_commission_
-- withdrawals (amount >= 10000, payout_phone required) rather than
-- public.bingo_agent_withdrawals — neither that table name nor
-- payout_phone appear anywhere in this git repository, on any branch,
-- so whatever created it live is not tracked here. This script asks
-- for everything needed to draft a correct, reconciled migration
-- instead of guessing the rest of the shape from two known facts.
--
-- Nothing here writes anything. Every statement is a SELECT.

-- 1. Full column list, types, defaults, nullability — not just amount
--    and payout_phone.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'bingo_agent_commission_withdrawals'
order by ordinal_position;

-- 2. Every constraint on the table (CHECK, PK, FK, UNIQUE) with its
--    exact definition.
select conname, contype, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.bingo_agent_commission_withdrawals'::regclass;

-- 3. RLS: is it enabled, and what are the policies (who can
--    select/insert/update, and under what condition)?
select relrowsecurity, relforcerowsecurity
from pg_class where oid = 'public.bingo_agent_commission_withdrawals'::regclass;

select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'bingo_agent_commission_withdrawals';

-- 4. Every function in public whose SOURCE mentions this table —
--    this is how to find whatever actually gates a write to it
--    live, whatever it happens to be named (the frontend currently
--    in this repo only calls bingo_agent_request_commission_
--    withdrawal / bingo_admin_review_agent_withdrawal, and this
--    session was told those don't exist live, so something else
--    must be the real write path).
select proname, pg_get_functiondef(oid) as source
from pg_proc
where pronamespace = 'public'::regnamespace
  and prosrc ilike '%bingo_agent_commission_withdrawals%';

-- 5. Same search for payout_phone, in case it's referenced by a
--    function that doesn't otherwise mention the table name directly
--    (e.g. a trigger function, or a function operating on a view).
select proname, pg_get_functiondef(oid) as source
from pg_proc
where pronamespace = 'public'::regnamespace
  and prosrc ilike '%payout_phone%';

-- 6. Any triggers on the table.
select tgname, pg_get_triggerdef(oid) as definition
from pg_trigger
where tgrelid = 'public.bingo_agent_commission_withdrawals'::regclass
  and not tgisinternal;

-- 7. Does the OLD name this session assumed (bingo_agent_withdrawals)
--    also exist live, alongside the new one, or was it fully
--    replaced? And does the underlying ledger table
--    (bingo_agent_commission_ledger) — which both the old RPC and any
--    new one would presumably still read for the balance check —
--    exist live with the shape this session assumed?
select
  to_regclass('public.bingo_agent_withdrawals') as old_table_also_exists,
  to_regclass('public.bingo_agent_commission_ledger') as ledger_table_exists;

select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'bingo_agent_commission_ledger'
order by ordinal_position;

-- 8. What grants exist on the table for anon/authenticated (separate
--    from RLS — this project's other tables have shown broad default
--    grants that RLS alone doesn't fully describe).
select grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and table_name = 'bingo_agent_commission_withdrawals'
  and grantee in ('anon', 'authenticated', 'public');

-- 9. Row count and a sample of existing rows' column names only (no
--    row contents needed) — just confirms the table is live/in use.
select count(*) as existing_rows from public.bingo_agent_commission_withdrawals;
