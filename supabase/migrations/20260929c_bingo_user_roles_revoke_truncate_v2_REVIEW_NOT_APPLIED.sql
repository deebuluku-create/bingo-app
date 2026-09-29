-- REVIEW_NOT_APPLIED: supersedes d3ccb93's draft now that the live
-- inspection (run externally by the owner, not from this sandbox) has
-- identified the actual root cause. Still not executed by Claude and must
-- not be applied without separate, explicit approval.
--
-- Refined findings from the owner's live inspection:
--   - authenticated has effective TRUNCATE on public.bingo_user_roles.
--   - anon does NOT (d3ccb93's REVOKE ... FROM anon was precautionary and
--     is now confirmed unnecessary for this table - harmless either way,
--     but dropped below since it isn't needed).
--   - Both roles have rolinherit = true, but pg_auth_members returned no
--     rows for them - so the grant is NOT arriving through role
--     membership/inheritance from some other role.
--   - The real source: pg_default_acl on the public schema includes
--     TRUNCATE for anon AND authenticated, for objects created by BOTH
--     the postgres role and the supabase_admin role.
--
-- That last point changes the scope of this fix. bingo_user_roles isn't a
-- one-off misconfiguration - it's just the first table this review
-- happened to check. ANY table created in public by postgres or
-- supabase_admin (which, on Supabase, is most tables - created via the
-- dashboard, the SQL editor, or a migration) picks up this same TRUNCATE
-- grant automatically. Revoking it from this one table (part A below)
-- fixes the table this review was already looking at; without part B,
-- every table created after that fix would still inherit the same
-- unwanted default. Both are REVOKE-only - neither denies a privilege any
-- legitimate client code path uses (confirmed by grep: nothing in
-- BINGO_MASTER_CURRENT_VERIFIED.html issues TRUNCATE, or writes to
-- bingo_user_roles at all).

-- =========================================================================
-- PART A - the existing table (bingo_user_roles)
-- =========================================================================
revoke truncate on public.bingo_user_roles from authenticated;

-- verify afterward (expect zero rows):
-- select grantee, privilege_type from information_schema.role_table_grants
-- where table_name = 'bingo_user_roles' and grantee = 'authenticated'
--   and privilege_type = 'TRUNCATE';

-- =========================================================================
-- PART B - the schema-wide default, for every table created from now on
-- =========================================================================
-- One ALTER DEFAULT PRIVILEGES per granting role, matching what the
-- inspection found (postgres and supabase_admin both hand out TRUNCATE by
-- default on public). This does NOT touch tables that already exist other
-- than through the grants already listed in pg_default_acl - it only
-- changes what gets granted automatically to tables created after this
-- runs. Existing tables besides bingo_user_roles would need the same
-- one-line REVOKE as Part A, per table, if the owner wants those checked
-- too - not included here since this review has only inspected this one
-- table so far.

alter default privileges for role postgres in schema public
  revoke truncate on tables from authenticated, anon;

alter default privileges for role supabase_admin in schema public
  revoke truncate on tables from authenticated, anon;

-- verify afterward (expect the TRUNCATE rows for postgres/supabase_admin
-- to be gone from this list - re-run the exact inspection query from
-- 20260929b):
-- select defaclrole::regrole as default_grant_owner,
--        defaclnamespace::regnamespace as schema, defaclobjtype, defaclacl
-- from pg_default_acl
-- where defaclnamespace = 'public'::regnamespace;
