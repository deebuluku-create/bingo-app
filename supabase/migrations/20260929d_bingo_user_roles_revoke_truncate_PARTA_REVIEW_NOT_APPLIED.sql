-- REVIEW_NOT_APPLIED - PART A ONLY (existing table).
-- Split out of 372226b at the owner's request so Part A (this table) and
-- Part B (schema-wide default, in the companion PARTB file) can be
-- reviewed, verified and approved independently of each other. Not
-- executed by Claude; requires separate, explicit approval to apply.
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

revoke truncate on public.bingo_user_roles from authenticated;

-- Verify afterward (expect zero rows):
select grantee, privilege_type
from information_schema.role_table_grants
where table_name = 'bingo_user_roles'
  and grantee = 'authenticated'
  and privilege_type = 'TRUNCATE';
