-- READ-ONLY preflight for Part B (20260929e). Run this FIRST, before even
-- attempting Part B's ALTER DEFAULT PRIVILEGES statements, to know in
-- advance whether the supabase_admin line will succeed or fail on
-- permission grounds - rather than finding out by running a statement
-- that changes (or fails to change) real privileges.
--
-- Recap of the rule Part B's file already documents: ALTER DEFAULT
-- PRIVILEGES FOR ROLE <target> requires the executing session to BE
-- <target>, be a MEMBER of <target>, or be a superuser. The Supabase SQL
-- editor connects as `postgres`, so the only open question is whether
-- `postgres` is a member of `supabase_admin` on this specific project.

-- 1) Direct answer: is postgres a member of supabase_admin (or a
--    superuser, which would also satisfy the rule)?
select
  pg_has_role('postgres', 'supabase_admin', 'MEMBER') as postgres_is_member_of_supabase_admin,
  (select rolsuper from pg_roles where rolname = 'postgres') as postgres_is_superuser;

-- 2) The full membership list either direction, for context (does
--    postgres belong to supabase_admin, or the reverse, or neither):
select
  m.rolname as member_role,
  g.rolname as granted_role
from pg_auth_members am
join pg_roles m on m.oid = am.member
join pg_roles g on g.oid = am.roleid
where m.rolname = 'postgres' or g.rolname = 'postgres'
   or m.rolname = 'supabase_admin' or g.rolname = 'supabase_admin';

-- === How to read the results ===
-- postgres_is_member_of_supabase_admin = true (or postgres_is_superuser =
--   true): Part B's "FOR ROLE supabase_admin" line is expected to succeed.
--   Safe to proceed to Part B after this, pending the owner's separate
--   approval of Part B itself.
-- Both false: that line will fail with a permission/membership error if
--   run as-is. That is PostgreSQL correctly enforcing its own rule, not a
--   mistake in the statement. In that case Part B's "FOR ROLE postgres"
--   line can still be applied on its own (postgres altering its own
--   defaults needs no special membership); the supabase_admin line would
--   need to be run by Supabase's own support/tooling, or from whatever
--   role actually holds that membership on this project, once identified.
