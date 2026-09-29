-- REVIEW_NOT_APPLIED: drafted for the owner's review only. Not executed by
-- Claude, and must not be applied without separate, explicit approval.
--
-- Background: the owner's Supabase inspection (run externally, not from
-- this sandbox) reported that the `authenticated` role holds TRUNCATE on
-- public.bingo_user_roles. TRUNCATE is a table-level privilege in
-- PostgreSQL and is NOT gated by Row Level Security policies at all - RLS
-- only governs SELECT/INSERT/UPDATE/DELETE, so the otherwise-correct RLS
-- setup already verified on this table (own-row SELECT for members,
-- broader SELECT for Super Users, no INSERT/UPDATE/DELETE for members)
-- gives zero protection against a member running TRUNCATE directly. The
-- practical effect of that grant existing is that any signed-in member -
-- not just a Super User - could delete every role assignment in the table
-- in one statement. This does not grant self-escalation to super_user
-- (aaLoadUserRole in the client fails closed to "member" on a missing
-- row), but it is an unauthorized destructive capability with no
-- legitimate use from the anon/authenticated keys, since the app only
-- ever reads this table from the client (see the companion inspection
-- migration, 20260928_bingo_user_roles_admin_mode_rls_INSPECT_READ_ONLY.sql,
-- and the full-file grep behind it - no client code writes to, let alone
-- truncates, bingo_user_roles).
--
-- Before applying: confirm no server-side job, edge function, or admin
-- tool intentionally truncates/reloads this table using the anon or
-- authenticated key (as opposed to the service-role key, which this
-- REVOKE does not touch). If nothing does - which matches everything
-- found in the client code - this is safe to apply with no functional
-- regression, since removing a privilege never used by legitimate code
-- cannot break that code.

revoke truncate on public.bingo_user_roles from authenticated;
revoke truncate on public.bingo_user_roles from anon;

-- Read-only verification query to run AFTER applying, to confirm the
-- grant is actually gone (expect zero rows naming 'TRUNCATE' below):
-- select grantee, privilege_type
-- from information_schema.role_table_grants
-- where table_name = 'bingo_user_roles'
--   and grantee in ('anon','authenticated')
--   and privilege_type = 'TRUNCATE';
