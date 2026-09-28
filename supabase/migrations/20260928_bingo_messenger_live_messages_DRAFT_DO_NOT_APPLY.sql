-- ============================================================
-- BINGO MESSENGER - live contract checks (+ optional, UNAPPLIED changes)
-- STATUS: DRAFT - NOT APPLIED - DO NOT RUN SECTIONS 1-3 BLINDLY.
-- Nothing in the frontend depends on sections 1-3 having been applied.
--
-- Contract the frontend now uses (BINGO_MASTER_CURRENT_VERIFIED.html,
-- AA_MSG_DB near aaMsgResolveContract):
--   public.messages             id, conversation_id, sender_id, message, deleted, created_at
--                               (confirmed live 2026-09-28; there is NO recipient_id / body)
--   public.conversations        id
--   public.conversation_members conversation_id + the member-id column
--                               (first of user_id / member_id / profile_id that exists)
-- The frontend verifies those columns at runtime (zero-row selects) and
-- refuses to write if any is missing, so a wrong guess fails visibly.
--
-- Writes the frontend performs, in order, when a member sends the FIRST
-- message to someone (and only then):
--   1. insert into conversations (id) values (<client uuid>)
--        - if id is not a uuid column: insert default values returning id
--   2. insert into conversation_members (conversation_id, <member col>) values (<id>, auth.uid())
--   3. insert into conversation_members (conversation_id, <member col>) values (<id>, <other member>)
--   4. insert into messages (conversation_id, sender_id, message) values (<id>, auth.uid(), <text>)
-- Every later message is step 4 only. Reads:
--   conversation_members where <member col> = auth.uid()
--   conversation_members where conversation_id in (...)      (to name the other member)
--   messages where conversation_id in (...) order by created_at
-- Realtime: INSERT on messages filtered conversation_id=in.(...), and
-- INSERT on conversation_members filtered <member col>=eq.<auth.uid()>.
-- ============================================================

-- ---------- 0. READ-ONLY: run and send back the output ----------
select table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name in ('messages','conversations','conversation_members')
order by table_name, ordinal_position;

select conrelid::regclass as table_name, conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid in ('public.messages'::regclass,'public.conversations'::regclass,'public.conversation_members'::regclass);

select c.relname, c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname in ('messages','conversations','conversation_members');

select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname='public' and tablename in ('messages','conversations','conversation_members')
order by tablename, cmd;

select table_name, grantee, string_agg(privilege_type, ',' order by privilege_type) as privileges
from information_schema.role_table_grants
where table_schema='public' and table_name in ('messages','conversations','conversation_members')
  and grantee in ('anon','authenticated')
group by table_name, grantee;

select tgrelid::regclass as table_name, tgname, pg_get_triggerdef(oid) as definition
from pg_trigger
where tgrelid in ('public.messages'::regclass,'public.conversations'::regclass,'public.conversation_members'::regclass)
  and not tgisinternal;

-- functions that might already create conversations (an RPC would be preferable to 4 client inserts)
select p.proname, pg_get_function_identity_arguments(p.oid) as args, p.prosecdef as security_definer
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and (p.proname ilike '%conversation%' or p.proname ilike '%message%');

select tablename from pg_publication_tables
where pubname='supabase_realtime' and schemaname='public'
  and tablename in ('messages','conversations','conversation_members');

select id, public from storage.buckets where id='message-media';

-- ---------- 1..3: only if section 0 shows they are missing ----------
-- These are sketches for review, written against the confirmed messages
-- columns and assuming the member column is user_id. Do not apply them
-- without checking them against the section 0 output and existing policies.
--
-- 1. Members read and write only their own conversations
-- create policy bingo_msg_members_read on public.conversation_members for select to authenticated
--   using (exists (select 1 from public.conversation_members me
--                  where me.conversation_id = conversation_members.conversation_id and me.user_id = auth.uid()));
--   (a policy that queries its own table recurses - use a SECURITY DEFINER helper instead; review needed)
-- create policy bingo_msg_messages_read on public.messages for select to authenticated
--   using (exists (select 1 from public.conversation_members m
--                  where m.conversation_id = messages.conversation_id and m.user_id = auth.uid()));
-- create policy bingo_msg_messages_send on public.messages for insert to authenticated
--   with check (sender_id = auth.uid() and exists (select 1 from public.conversation_members m
--                  where m.conversation_id = messages.conversation_id and m.user_id = auth.uid()));
--
-- 2. Realtime
-- alter publication supabase_realtime add table public.messages, public.conversation_members;
--
-- 3. Attachments (photo / file / voice note) - frontend uploads to <auth.uid()>/<file> in this bucket
-- insert into storage.buckets (id, name, public) values ('message-media','message-media', true) on conflict (id) do nothing;
