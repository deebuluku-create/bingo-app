-- REVIEW_NOT_APPLIED - PART B ONLY (schema-wide default privileges).
-- Split out of 372226b at the owner's request so this can be reviewed,
-- verified and approved independently of Part A (the single-table fix,
-- in the companion PARTA file). Not executed by Claude; requires
-- separate, explicit approval to apply. Treat this as the higher-impact
-- half of the two: it changes what EVERY future table in public receives
-- automatically, not just the one table Part A already covers.
--
-- Scope: pg_default_acl showed TRUNCATE granted to anon/authenticated by
-- default for tables created by BOTH the postgres role and the
-- supabase_admin role. Two ALTER DEFAULT PRIVILEGES statements, one per
-- granting role, are needed to remove both.
--
-- === UPDATED after the Part B preflight (20260929f) was actually run ===
-- Confirmed live: postgres is NOT a member of supabase_admin, and
-- postgres is NOT a superuser. Per the PostgreSQL rule for ALTER DEFAULT
-- PRIVILEGES FOR ROLE <target> (the session must BE <target>, be a MEMBER
-- of it, or be a superuser), the Supabase SQL editor session (which
-- connects as postgres) does not meet that rule for "FOR ROLE
-- supabase_admin". Running it anyway would either fail outright, or -
-- worse - if it somehow succeeded via some other path, would mean running
-- a schema-altering statement as an unauthorized role, which this owner
-- has explicitly said not to do. That statement is REMOVED below, not
-- just commented as risky.
--
-- What that leaves: the postgres-role line only. postgres altering its
-- OWN default privileges needs no special membership - that one is
-- unaffected by this finding and remains ready for approval. It only
-- fixes half of what pg_default_acl originally showed (tables postgres
-- creates going forward, not tables supabase_admin creates going
-- forward) - the supabase_admin half is now a known, documented gap
-- requiring Supabase's own support/tooling, not something this project's
-- own SQL editor session can close.
--
-- Effect if applied: no impact on any legitimate feature (same reasoning
-- as Part A - nothing in the client ever uses TRUNCATE). Only changes
-- what gets auto-granted to TABLES CREATED AFTER this runs; it does not
-- retroactively touch any existing table besides what Part A already
-- targets.

alter default privileges for role postgres in schema public
  revoke truncate on tables from authenticated, anon;

-- Verify afterward (expect the postgres row's acl to no longer list
-- TRUNCATE for anon/authenticated; the supabase_admin row, if any exists
-- below, is expected to be UNCHANGED by this file - that gap is tracked
-- separately, not silently left unaddressed):
select defaclrole::regrole as default_grant_owner, defaclnamespace::regnamespace as schema,
       defaclobjtype, defaclacl
from pg_default_acl
where defaclnamespace = 'public'::regnamespace;

-- === Residual gap - not fixed by this file, tracked for the owner ===
-- The supabase_admin default (TRUNCATE granted to anon/authenticated on
-- every future table supabase_admin creates) remains in place after this
-- file runs. Closing it requires one of:
--   1. Supabase support running the equivalent ALTER DEFAULT PRIVILEGES
--      from a role that does have supabase_admin membership, or
--   2. Confirming with Supabase whether tables in this project are ever
--      actually created by supabase_admin in normal operation (dashboard/
--      SQL-editor-created tables are typically owned by postgres, per
--      what this project's own bingo_user_roles table already showed) -
--      if supabase_admin never creates project tables in practice, this
--      gap may be low-priority even though it remains technically open.
