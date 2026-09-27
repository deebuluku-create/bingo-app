-- READ-ONLY. Run against the live project. Requested per the
-- 2026-09-27 correction: the previous design (5503b15,
-- 20260927_bingo_agent_commission_withdrawals_writer_design.sql) got
-- the table name right but invented column names and enum values for
-- everything else (status vs. the real withdrawal_status; credit/
-- reserve/release vs. the real commission/adjustment/reversal; missing
-- source_type/source_id on the ledger; actor_id/target_id vs. the real
-- administrator_id/target_user_id; wrote to bingo_role_notifications,
-- which doesn't exist live) and its local test passed only because its
-- own reproduction repeated the same wrong assumptions instead of the
-- real shape. No more assumptions this round — every statement below
-- is a SELECT, asks for the complete definition of every object a
-- withdrawal-request/review RPC would touch, and nothing is inferred
-- from a partial answer.

-- 1. bingo_agent_commission_withdrawals — full columns, all
--    constraints, RLS policies, grants, triggers.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name='bingo_agent_commission_withdrawals'
order by ordinal_position;

select conname, contype, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid='public.bingo_agent_commission_withdrawals'::regclass;

select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname='public' and tablename='bingo_agent_commission_withdrawals';

select grantee, privilege_type
from information_schema.role_table_grants
where table_schema='public' and table_name='bingo_agent_commission_withdrawals'
  and grantee in ('anon','authenticated','public');

select tgname, pg_get_triggerdef(oid) as definition
from pg_trigger
where tgrelid='public.bingo_agent_commission_withdrawals'::regclass and not tgisinternal;

-- Actual values currently in use for the status column, if any rows
-- exist — the most direct way to confirm the full enum, not just the
-- one value ("pending") this session has assumed exists.
select withdrawal_status, count(*) from public.bingo_agent_commission_withdrawals
group by withdrawal_status;

-- 2. bingo_agent_commission_ledger — same, full detail. In particular:
--    the exact CHECK defining allowed entry_type values, and whether
--    source_type/source_id are NOT NULL, their types, and any FK they
--    carry (e.g. does source_id reference a specific table depending
--    on source_type, or is it a loose uuid/text).
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name='bingo_agent_commission_ledger'
order by ordinal_position;

select conname, contype, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid='public.bingo_agent_commission_ledger'::regclass;

select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname='public' and tablename='bingo_agent_commission_ledger';

select grantee, privilege_type
from information_schema.role_table_grants
where table_schema='public' and table_name='bingo_agent_commission_ledger'
  and grantee in ('anon','authenticated','public');

select tgname, pg_get_triggerdef(oid) as definition
from pg_trigger
where tgrelid='public.bingo_agent_commission_ledger'::regclass and not tgisinternal;

-- Actual entry_type values in use, and whatever source_type values
-- accompany them — needed to know what source_type/source_id this
-- RPC should write for a withdrawal-related ledger entry specifically
-- (e.g. does an existing 'commission' entry from a boost or sale show
-- what source_type looks like, so a withdrawal-related entry follows
-- the same convention).
select entry_type, source_type, count(*) from public.bingo_agent_commission_ledger
group by entry_type, source_type
order by entry_type, source_type;

-- 3. bingo_role_audit_log — full columns/constraints, to get
--    administrator_id/target_user_id's exact types and every other
--    column this table actually requires.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name='bingo_role_audit_log'
order by ordinal_position;

select conname, contype, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid='public.bingo_role_audit_log'::regclass;

-- 4. Confirm bingo_role_notifications really doesn't exist, and look
--    for whatever DOES notify an Agent/Super User live, if anything,
--    under a different name.
select to_regclass('public.bingo_role_notifications') as bingo_role_notifications_exists;
select table_name from information_schema.tables
where table_schema='public' and table_name ilike '%notif%';

-- 5. bingo_user_roles — full columns, to confirm role/agent_status/
--    territory are still what this session has assumed, given how
--    much else was wrong.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name='bingo_user_roles'
order by ordinal_position;

-- 6. bingo_is_super_user — its actual definition, not assumed.
select pg_get_functiondef(oid) as source
from pg_proc
where pronamespace='public'::regnamespace and proname='bingo_is_super_user';

-- 7. One more pass, in case anything DOES already write these two
--    tables under a name this session hasn't tried yet — searches
--    function bodies for the table names directly rather than by
--    guessed function name.
select proname, pg_get_functiondef(oid) as source
from pg_proc
where pronamespace='public'::regnamespace
  and (prosrc ilike '%bingo_agent_commission_withdrawals%' or prosrc ilike '%bingo_agent_commission_ledger%');
