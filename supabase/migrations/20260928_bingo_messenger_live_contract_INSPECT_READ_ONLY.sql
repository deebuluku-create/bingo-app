-- ============================================================
-- BINGO MESSENGER - READ-ONLY live contract inspection
-- STATUS: inspection queries only (section 0). The optional sketches that
-- used to follow are withdrawn - they assumed client-side member inserts,
-- which the live RLS does not allow.
--
-- Confirmed live contract (project owner, 2026-09-28):
--   messages             id, conversation_id, sender_id, message, deleted, created_at
--   conversation_members conversation_id, user_id, archived, blocked, joined_at
--                        RLS: INSERT only user_id = auth.uid(); SELECT only own row
-- The Messenger therefore creates conversations and reads co-members only
-- through the server functions proposed in
--   20260928_bingo_messenger_direct_conversation_rpc_REVIEW_NOT_APPLIED.sql
-- and the TRUNCATE correction is separate:
--   20260928_bingo_messaging_revoke_truncate_REVIEW_NOT_APPLIED.sql
-- Client operations the Messenger performs:
--   rpc  bingo_my_conversation_members()
--   rpc  bingo_get_or_create_direct_conversation(p_other_user)   (first message to someone)
--   select conversation_id from conversation_members where user_id = auth.uid()   (fallback)
--   select id,conversation_id,sender_id,message,deleted,created_at from messages where conversation_id in (...)
--   insert into messages (conversation_id, sender_id, message)
--   realtime INSERT on messages (conversation_id=in.(...)) and on conversation_members (user_id=eq.<me>)
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
