-- ============================================================
-- BINGO MESSAGING - remove TRUNCATE from client roles
-- STATUS: FOR REVIEW - NOT APPLIED. Separate from the Messenger RPC file
-- and from any preview HTML deployment.
--
-- Why: RLS policies filter rows for SELECT/INSERT/UPDATE/DELETE but do not
-- apply to TRUNCATE. Supabase's default grants give anon and authenticated
-- ALL privileges on public tables, including TRUNCATE. PostgREST exposes
-- no TRUNCATE verb, so this is defence in depth: any other path that runs
-- SQL as anon/authenticated (a SECURITY INVOKER function with dynamic
-- SQL, a future API, a leaked role session) could empty these tables with
-- no RLS check. Removing the grant closes that.
--
-- Scope: TRUNCATE only, on exactly three tables, from anon, authenticated
-- and PUBLIC. SELECT/INSERT/UPDATE/DELETE grants and all RLS policies are
-- unchanged. service_role and the table owner keep TRUNCATE (server-side
-- maintenance); revoke from service_role too if nothing relies on it.
-- ============================================================

-- ---------- BEFORE (read-only): run and keep the output ----------
select table_name, grantee, string_agg(privilege_type, ', ' order by privilege_type) as privileges
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('conversations', 'conversation_members', 'messages')
group by table_name, grantee
order by table_name, grantee;

select c.relname,
       has_table_privilege('anon',          c.oid, 'TRUNCATE') as anon_truncate,
       has_table_privilege('authenticated', c.oid, 'TRUNCATE') as authenticated_truncate,
       has_table_privilege('service_role',  c.oid, 'TRUNCATE') as service_role_truncate
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname in ('conversations', 'conversation_members', 'messages');

-- ---------- CHANGE ----------
begin;
revoke truncate on table public.conversations, public.conversation_members, public.messages
  from anon, authenticated, public;
commit;

-- ---------- AFTER (read-only): anon_truncate / authenticated_truncate must be false ----------
select c.relname,
       has_table_privilege('anon',          c.oid, 'TRUNCATE') as anon_truncate,
       has_table_privilege('authenticated', c.oid, 'TRUNCATE') as authenticated_truncate,
       has_table_privilege('service_role',  c.oid, 'TRUNCATE') as service_role_truncate
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname in ('conversations', 'conversation_members', 'messages');

-- Note: Supabase's default privileges grant ALL on tables created later in
-- public; this revoke covers these three existing tables only.

-- ---------- Rollback (restores the Supabase default) ----------
-- grant truncate on table public.conversations, public.conversation_members, public.messages to anon, authenticated;
