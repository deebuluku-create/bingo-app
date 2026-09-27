-- READ-ONLY. Run against the live project and send back the results
-- before any Messenger backend code is rewired. Per this session's
-- standing rule (Agent withdrawals, then food_menu_items): never assume
-- a table/column name matches what the frontend currently calls -
-- confirm first, every time.
--
-- Context: the current Messenger frontend in
-- BINGO_MASTER_CURRENT_VERIFIED.html was built entirely against a DRAFT
-- schema (supabase/bingo_change_messaging_core.sql - status DRAFT ONLY,
-- NEVER APPLIED) using bingo_conversations / bingo_conversation_
-- participants / bingo_messages. You've confirmed the live project
-- instead has conversations / conversation_members / messages - a
-- different, pre-existing schema this session has never inspected.
-- Every Supabase call in the current Messenger code (conversation
-- fetch/create, message send/retry, realtime subscription) targets the
-- wrong table names, so every one of those calls fails live today; the
-- code catches the failure and falls back to a local-only cache
-- (visibly marked _failed with a Retry button - not silently hidden -
-- but two different browsers/devices can never see each other's
-- messages while this is the case).

-- 1. conversations - full columns, constraints, RLS, grants, triggers.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name='conversations'
order by ordinal_position;

select conname, contype, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid='public.conversations'::regclass;

select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname='public' and tablename='conversations';

select grantee, privilege_type
from information_schema.role_table_grants
where table_schema='public' and table_name='conversations'
  and grantee in ('anon','authenticated','public');

select tgname, pg_get_triggerdef(oid) as definition
from pg_trigger
where tgrelid='public.conversations'::regclass and not tgisinternal;

-- Real values in use for any status/type-like column, if one exists -
-- do not assume 'direct'/'group' is the real enum without checking.
select * from public.conversations limit 3;

-- 2. conversation_members - full detail. In particular: the actual
--    primary key (composite conversation_id+user_id, or its own id?),
--    whether a role/admin column exists, and whether read-state
--    (last_read_message_id or similar) lives here or elsewhere.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name='conversation_members'
order by ordinal_position;

select conname, contype, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid='public.conversation_members'::regclass;

select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname='public' and tablename='conversation_members';

select grantee, privilege_type
from information_schema.role_table_grants
where table_schema='public' and table_name='conversation_members'
  and grantee in ('anon','authenticated','public');

select tgname, pg_get_triggerdef(oid) as definition
from pg_trigger
where tgrelid='public.conversation_members'::regclass and not tgisinternal;

select * from public.conversation_members limit 3;

-- 3. messages - full detail. In particular: the real column for message
--    text (body/content/text?), sender column name, whether reply/
--    forward/edit/unsend columns exist at all, and the real message
--    "type" enum (or whether attachments are a separate table/column).
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name='messages'
order by ordinal_position;

select conname, contype, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid='public.messages'::regclass;

select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname='public' and tablename='messages';

select grantee, privilege_type
from information_schema.role_table_grants
where table_schema='public' and table_name='messages'
  and grantee in ('anon','authenticated','public');

select tgname, pg_get_triggerdef(oid) as definition
from pg_trigger
where tgrelid='public.messages'::regclass and not tgisinternal;

select * from public.messages order by created_at desc nulls last limit 5;

-- 4. Realtime: is the 'messages' table (or conversations/
--    conversation_members) actually added to the supabase_realtime
--    publication? Without this, "realtime" silently never fires
--    regardless of correct table/column names or RLS.
select schemaname, tablename
from pg_publication_tables
where pubname='supabase_realtime'
  and tablename in ('messages','conversations','conversation_members');

-- 5. Attachments/reactions/receipts/calls/blocks - search for any
--    existing table under ANY name related to these, rather than
--    assuming they don't exist or guessing a name.
select table_name from information_schema.tables
where table_schema='public'
  and (table_name ilike '%attachment%' or table_name ilike '%reaction%'
       or table_name ilike '%receipt%' or table_name ilike '%call%'
       or table_name ilike '%block%' or table_name ilike '%message%'
       or table_name ilike '%conversation%');

-- 6. Any existing function/RPC already reading or writing these three
--    tables under a name this session hasn't tried - in case a
--    conversation-creation or send-message RPC already exists and
--    should be called instead of raw table inserts.
select proname, pg_get_functiondef(oid) as source
from pg_proc
where pronamespace='public'::regnamespace
  and (prosrc ilike '%conversation_members%' or prosrc ilike '%from messages%'
       or prosrc ilike '%public.conversations%');
