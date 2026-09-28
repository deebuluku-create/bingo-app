-- ============================================================
-- BINGO MESSENGER - consolidated backend verification
-- STATUS: read-only inspection only. Every statement below is a SELECT
-- against system catalogs (information_schema / pg_catalog / pg_policies
-- / storage.buckets) - nothing here creates, alters, or deletes any
-- object, table, row, policy, or bucket. Safe to run as-is against the
-- live project; paste the full output back for review.
--
-- This does NOT assume anything is missing because a filename says
-- REVIEW_NOT_APPLIED - it answers "what does the live project actually
-- have" directly, for the six specific things requested:
--   1. message-media Storage bucket
--   2. message-media Storage policies
--   3. bingo_communication_requests table
--   4. bingo_get_or_create_direct_conversation RPC
--   5. Request-to-Communicate + acceptance/block RPCs
--   6. Relevant RLS policies and realtime publication membership
--
-- Builds on, and does not duplicate, the messages/conversations/
-- conversation_members contract already inspected in
-- 20260928_bingo_messenger_live_contract_INSPECT_READ_ONLY.sql (run that
-- one too if those three tables' own state is also in question again).
-- ============================================================


-- ========== 1. message-media Storage bucket ==========
select id, name, public, file_size_limit, allowed_mime_types, created_at
from storage.buckets
where id = 'message-media';
-- Zero rows = the bucket does not exist yet; every attachment upload
-- fails at sb.storage.from('message-media').upload() client-side.


-- ========== 2. message-media Storage policies ==========
select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'storage' and tablename = 'objects'
  and (qual ilike '%message-media%' or with_check ilike '%message-media%'
       or policyname ilike '%message_media%' or policyname ilike '%message-media%')
order by cmd;
-- Zero rows alongside a bucket that DOES exist = the bucket exists but
-- nothing is allowed to read or write it (uploads/opens will fail on
-- permission, not on a missing bucket - a different failure to fix).

-- For context, every policy currently on storage.objects for ANY
-- bucket (so a message-media rule under a different naming convention
-- isn't missed):
select policyname, cmd, roles,
  left(coalesce(qual,''), 140) as qual_preview,
  left(coalesce(with_check,''), 140) as with_check_preview
from pg_policies
where schemaname = 'storage' and tablename = 'objects'
order by policyname;


-- ========== 3. bingo_communication_requests table ==========
select table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'bingo_communication_requests'
order by ordinal_position;
-- Zero rows = the table does not exist - Request to Communicate has no
-- live backing at all; every request/accept/reject/block call fails.

select c.relname, c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'bingo_communication_requests';

select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'bingo_communication_requests'
order by cmd;

select table_name, grantee, string_agg(privilege_type, ',' order by privilege_type) as privileges
from information_schema.role_table_grants
where table_schema = 'public' and table_name = 'bingo_communication_requests'
  and grantee in ('anon','authenticated')
group by table_name, grantee;


-- ========== 4 & 5. All bingo_* Messenger RPCs ==========
-- One query for every function the client calls or expects:
--   bingo_get_or_create_direct_conversation, bingo_my_conversation_members,
--   bingo_request_communication, bingo_respond_communication_request,
--   bingo_block_member, bingo_unblock_member
select p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments,
  pg_get_function_result(p.oid) as returns,
  p.prosecdef as security_definer,
  l.lanname as language
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join pg_language l on l.oid = p.prolang
where n.nspname = 'public'
  and p.proname in (
    'bingo_get_or_create_direct_conversation',
    'bingo_my_conversation_members',
    'bingo_request_communication',
    'bingo_respond_communication_request',
    'bingo_block_member',
    'bingo_unblock_member'
  )
order by p.proname;
-- Compare the returned rows against this list of 6 names - whichever
-- names are absent from the results do not exist live yet.


-- ========== 6. RLS + realtime publication, all Messenger tables ==========
select c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('messages','conversations','conversation_members','bingo_communication_requests')
order by c.relname;

select tablename
from pg_publication_tables
where pubname = 'supabase_realtime' and schemaname = 'public'
  and tablename in ('messages','conversations','conversation_members','bingo_communication_requests');
-- postgres_changes realtime only fires for a table listed here; the
-- Messenger's 20 s poll (aaMsgEnsurePolling) is its fallback for any
-- table missing from this list.
