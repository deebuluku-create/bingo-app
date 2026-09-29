-- APPLIED - PART A (existing table). Kept for the record, not for re-running.
-- Split out of 372226b at the owner's request so Part A (this table) and
-- Part B (schema-wide default, in the companion PARTB file) could be
-- reviewed, verified and approved independently of each other.
--
-- === Execution record ===
-- Authorized by the owner and executed via their connected Supabase
-- tooling (not from this sandbox, which has no live database access at
-- any point in this project). Reported results:
--   Step 1 (before):  authenticated TRUNCATE = true  (grant confirmed present)
--   Step 2 (REVOKE):  executed successfully
--   Step 3 (after):   authenticated TRUNCATE = false; anon TRUNCATE = false
-- Matches the expected outcome exactly - no unexpected result, nothing to
-- stop and investigate. Do not re-run: the grant this file removes is
-- already gone, so Step 2 would be a safe no-op if repeated, but there is
-- no reason to.
--
-- Scope: removes TRUNCATE on the ONE existing table already confirmed to
-- have it (public.bingo_user_roles), from the ONE role confirmed to hold
-- it (authenticated - anon was checked and does not have this grant on
-- this table, so it is not included here).
--
-- Who can run this: any role with ownership or grant privilege on this
-- table - normally the `postgres` role used by the Supabase SQL editor.
-- No special membership needed for a REVOKE on a specific table (unlike
-- Part B's ALTER DEFAULT PRIVILEGES - see that file for the role
-- requirement there).
--
-- Effect if applied: none on any legitimate feature. Confirmed by full
-- grep of BINGO_MASTER_CURRENT_VERIFIED.html that no client code path
-- ever writes to bingo_user_roles, let alone truncates it - every
-- reference is a .select() scoped to the caller's own row.

-- === STEP 1: verify BEFORE applying ===
-- Expected result: one row (authenticated, TRUNCATE) - confirming the
-- grant this correction removes actually exists right now, exactly as
-- reported. If this returns zero rows already, STOP - the grant is gone
-- some other way and the REVOKE below is unnecessary (harmless to run
-- anyway, but worth knowing why before proceeding).
select grantee, privilege_type
from information_schema.role_table_grants
where table_name = 'bingo_user_roles'
  and grantee = 'authenticated'
  and privilege_type = 'TRUNCATE';

-- === STEP 2: the correction itself (only after Step 1 confirms the row above) ===
revoke truncate on public.bingo_user_roles from authenticated;

-- === STEP 3: verify AFTER applying ===
-- Expected result: zero rows - the grant from Step 1 is gone.
select grantee, privilege_type
from information_schema.role_table_grants
where table_name = 'bingo_user_roles'
  and grantee = 'authenticated'
  and privilege_type = 'TRUNCATE';
