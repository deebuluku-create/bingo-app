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
-- === Who can actually run each line - read this before applying ===
-- PostgreSQL's rule for ALTER DEFAULT PRIVILEGES FOR ROLE <target>: the
-- session running it must be <target> itself, a member of <target>, or a
-- superuser. This is NOT the same requirement as Part A's plain REVOKE
-- (which just needs ownership/grant privilege on the table).
--
--   - "FOR ROLE postgres": the Supabase SQL editor connects AS postgres,
--     so this line is postgres altering its own default privileges -
--     expected to succeed normally.
--   - "FOR ROLE supabase_admin": supabase_admin is Supabase's own internal
--     control-plane role, not something project owners are normally
--     granted membership in. Whether `postgres` on this specific project
--     has been granted that membership is a live-project fact this
--     sandbox cannot see and this review has not independently confirmed
--     either way. If this statement fails with something like
--     "must be member of role supabase_admin", that is PostgreSQL
--     correctly enforcing this rule, not a bug in the statement - it
--     means fixing the supabase_admin default requires either Supabase
--     support/their own tooling, or running it from whatever role
--     Supabase's own migration system uses. Applying just the postgres
--     line first is still a real, independent improvement even if the
--     supabase_admin line has to wait.
--
-- Effect if applied: no impact on any legitimate feature (same reasoning
-- as Part A - nothing in the client ever uses TRUNCATE). Only changes
-- what gets auto-granted to TABLES CREATED AFTER this runs; it does not
-- retroactively touch any existing table besides what Part A already
-- targets.

alter default privileges for role postgres in schema public
  revoke truncate on tables from authenticated, anon;

alter default privileges for role supabase_admin in schema public
  revoke truncate on tables from authenticated, anon;

-- Verify afterward (expect no TRUNCATE entries for postgres/supabase_admin
-- remaining in this list):
select defaclrole::regrole as default_grant_owner, defaclnamespace::regnamespace as schema,
       defaclobjtype, defaclacl
from pg_default_acl
where defaclnamespace = 'public'::regnamespace;
