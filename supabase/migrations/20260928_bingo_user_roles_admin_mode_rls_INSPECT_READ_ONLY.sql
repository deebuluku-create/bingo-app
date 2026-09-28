-- READ-ONLY inspection script. Runs no writes, grants no access, changes
-- nothing. Paste into the Supabase SQL editor and share the output.
--
-- Why this exists: Categories > Admin Mode (client code, aaToggleAllCatAdminMode
-- / aaIsSuperUser in BINGO_MASTER_CURRENT_VERIFIED.html) is gated client-side
-- by reading state.userRole.role, which itself comes only from
--   select role,territory,agent_since,agent_status from bingo_user_roles
--   where user_id = <the signed-in user's own id>
-- A full grep of the client file confirms there is no .update()/.upsert()/
-- .insert() against bingo_user_roles anywhere in the app - the client never
-- writes to this table, only reads its own row. So the only way a session
-- could see "super_user" is (a) a direct database write by someone with
-- Supabase write access, or (b) a gap in this table's own RLS/policies that
-- lets a signed-in user write their own row. This script checks for (b),
-- which cannot be verified from client code or from this repository (no
-- migration here defines bingo_user_roles - it was created directly in the
-- live project).
--
-- What "safe" looks like in the results below:
--   1) rowsecurity = true  (RLS is actually turned on for this table)
--   2) no INSERT/UPDATE policy whose USING/WITH CHECK clause is unrestricted
--      (e.g. "true", or lets a user set user_id/role to anything) - the only
--      acceptable write policy is one that never lets a user set their own
--      role column at all (role changes should only happen via a
--      service-role/admin path outside PostgREST).
--   3) the SELECT policy scopes rows to auth.uid() = user_id (so one user
--      can't read another user's role row either).

-- 1) Is Row Level Security actually enabled on this table?
select schemaname, tablename, rowsecurity
from pg_tables
where tablename = 'bingo_user_roles';

-- 2) Every policy currently defined on it - read them and confirm no
--    INSERT/UPDATE policy allows a normal user to set their own role.
select policyname, cmd, roles, qual, with_check
from pg_policies
where tablename = 'bingo_user_roles'
order by cmd;

-- 3) Table privileges granted directly (outside RLS) to anon/authenticated -
--    a GRANT here with permissive RLS is the same risk as no RLS at all.
select grantee, privilege_type
from information_schema.role_table_grants
where table_name = 'bingo_user_roles'
  and grantee in ('anon','authenticated')
order by grantee, privilege_type;
