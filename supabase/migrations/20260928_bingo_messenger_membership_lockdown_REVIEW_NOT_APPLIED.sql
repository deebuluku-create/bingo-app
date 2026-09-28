-- ============================================================
-- BINGO MESSENGER - remove client-side membership / conversation creation
-- STATUS: FOR REVIEW - NOT APPLIED.
-- APPLY AFTER 20260928_bingo_messenger_direct_conversation_rpc_REVIEW_NOT_APPLIED.sql
-- (this file aborts if those functions are missing).
--
-- The hole: live policy conversation_members_insert_own lets any signed-in
-- user insert their OWN member row into ANY conversation whose id they
-- know. That row then satisfies the membership-based messages SELECT
-- policy and bingo_my_conversation_members(), exposing the conversation.
--
-- Once bingo_get_or_create_direct_conversation() owns conversation and
-- member creation (SECURITY DEFINER, runs as the table owner, unaffected
-- by the changes below), clients need no INSERT on either table:
--   1. drop policy conversation_members_insert_own
--   2. drop every INSERT-only policy on public.conversations (clients
--      could create empty, member-less conversation rows)
--   3. revoke the INSERT privilege on both tables from anon/authenticated,
--      so no remaining or future permissive policy can re-open it
-- Unchanged: every SELECT / UPDATE / DELETE policy and grant (existing
-- members keep reading their rows and updating their own archived /
-- blocked flags), messages policies and grants, service_role.
-- An ALL-command policy on either table would also allow INSERT; the
-- revoke in step 3 closes that too, and step 0 reports any such policy.
-- ============================================================

-- ---------- BEFORE (read-only): keep this output ----------
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname='public' and tablename in ('conversations','conversation_members')
order by tablename, cmd, policyname;

select table_name, grantee, string_agg(privilege_type, ',' order by privilege_type) as privileges
from information_schema.role_table_grants
where table_schema='public' and table_name in ('conversations','conversation_members')
  and grantee in ('anon','authenticated')
group by table_name, grantee order by table_name, grantee;

-- existing members who may have self-joined: conversations with more than two members
select m.conversation_id, count(*) as members, array_agg(m.user_id order by m.joined_at) as user_ids,
       array_agg(m.joined_at order by m.joined_at) as joined
from public.conversation_members m
group by m.conversation_id having count(*) > 2
order by max(m.joined_at) desc;

begin;

-- ---------- 0. Preflight ----------
do $$
declare p record;
begin
  if to_regprocedure('public.bingo_get_or_create_direct_conversation(uuid)') is null
     or to_regprocedure('public.bingo_my_conversation_members()') is null then
    raise exception 'Apply 20260928_bingo_messenger_direct_conversation_rpc first - clients would lose the only way to start a conversation';
  end if;
  if not (select prosecdef from pg_proc where oid = 'public.bingo_get_or_create_direct_conversation(uuid)'::regprocedure) then
    raise exception 'bingo_get_or_create_direct_conversation must be SECURITY DEFINER';
  end if;
  for p in select tablename, policyname from pg_policies
           where schemaname='public' and tablename in ('conversations','conversation_members') and cmd='ALL' loop
    raise notice 'Review: ALL-command policy %.% also allows INSERT - closed by the INSERT revoke below', p.tablename, p.policyname;
  end loop;
end $$;

-- ---------- 1. member rows: no client INSERT ----------
drop policy if exists conversation_members_insert_own on public.conversation_members;

-- ---------- 2. conversations: no client INSERT ----------
do $$
declare p record;
begin
  for p in select policyname from pg_policies
           where schemaname='public' and tablename='conversations' and cmd='INSERT' loop
    execute format('drop policy %I on public.conversations', p.policyname);
    raise notice 'dropped INSERT policy on conversations: %', p.policyname;
  end loop;
end $$;

-- ---------- 3. privileges ----------
revoke insert on table public.conversation_members, public.conversations from anon, authenticated, public;

commit;

-- ---------- AFTER (read-only) ----------
select tablename, policyname, cmd from pg_policies
where schemaname='public' and tablename in ('conversations','conversation_members')
order by tablename, cmd, policyname;
select c.relname,
       has_table_privilege('authenticated', c.oid, 'INSERT') as auth_insert,   -- expect false
       has_table_privilege('authenticated', c.oid, 'SELECT') as auth_select,   -- unchanged
       has_table_privilege('authenticated', c.oid, 'UPDATE') as auth_update    -- unchanged
from pg_class c where c.oid in ('public.conversations'::regclass,'public.conversation_members'::regclass);

-- ---------- Rollback ----------
-- grant insert on table public.conversation_members, public.conversations to authenticated;
-- create policy conversation_members_insert_own on public.conversation_members
--   for insert to authenticated with check (user_id = auth.uid());
-- (re-create any conversations INSERT policy from the BEFORE output)
