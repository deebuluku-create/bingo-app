-- ============================================================
-- BINGO MESSENGER - database changes the new Messenger may need
-- STATUS: DRAFT - NOT APPLIED - DO NOT RUN BLINDLY.
--
-- The frontend (BINGO_MASTER_CURRENT_VERIFIED.html, "Live data" block
-- above aaMsgFetchConversationsFromSupabase) now talks ONLY to the live
-- public.messages table, using ONLY these four columns, which the
-- pre-existing seller chat already read/wrote on the live project:
--     id, sender_id, recipient_id, body, created_at
-- It no longer calls the never-applied bingo_conversations /
-- bingo_conversation_participants / bingo_messages draft tables, and it
-- does not yet call the live conversations / conversation_members tables
-- (their columns have never been inspected).
--
-- No schema change is required for one-to-one text messaging IF the live
-- project already has the RLS policies and realtime publication below.
-- Run 20260928_bingo_messenger_INSPECT_LIVE.sql first, plus section 0
-- here, and compare. Apply a section only when the inspection shows it is
-- missing. Each section is independent.
-- ============================================================

-- ---------- 0. READ-ONLY checks for exactly what the frontend relies on ----------
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name='messages'
  and column_name in ('id','sender_id','recipient_id','body','created_at')
order by column_name;                         -- expect all 5 rows

select policyname, cmd, roles, qual, with_check
from pg_policies where schemaname='public' and tablename='messages';

select relrowsecurity from pg_class where oid='public.messages'::regclass;

select pubname from pg_publication_tables
where schemaname='public' and tablename='messages';   -- expect supabase_realtime

select id, public from storage.buckets where id='message-media';   -- expect 1 row

-- ---------- 1. RLS: members read their own messages, send only as themselves ----------
-- Only if section 0 shows no equivalent policies. Enabling RLS on a table
-- that has none would block every existing reader, so the policies are
-- created before RLS is (re)enabled.
-- begin;
-- create policy bingo_messages_select_own on public.messages
--   for select to authenticated
--   using (auth.uid() = sender_id or auth.uid() = recipient_id);
-- create policy bingo_messages_insert_as_self on public.messages
--   for insert to authenticated
--   with check (auth.uid() = sender_id and recipient_id is not null and recipient_id <> sender_id);
-- alter table public.messages enable row level security;
-- commit;

-- ---------- 2. Realtime delivery of new messages ----------
-- Without this, Messenger still works but only refreshes every 20 s.
-- alter publication supabase_realtime add table public.messages;

-- ---------- 3. Photo / file / voice-note sending ----------
-- Messenger uploads to Storage bucket "message-media" at
--   <sender uid>/<timestamp>_<file name>
-- and sends the public URL as the message body. Until this bucket
-- exists, attachments stay on the sender's device marked "Not sent".
-- NOTE: a public bucket means anyone holding a URL can open the file.
-- insert into storage.buckets (id, name, public, file_size_limit)
--   values ('message-media','message-media', true, 26214400)
--   on conflict (id) do nothing;
-- create policy bingo_message_media_upload_own_folder on storage.objects
--   for insert to authenticated
--   with check (bucket_id = 'message-media' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------- NOT covered here (needs the inspection output first) ----------
-- * Group chats (New Group) - need the live conversations /
--   conversation_members columns.
-- * Server-side read state, mute, archive, trash, starred, disappearing
--   messages, polls - no live columns exist; these stay per-device or
--   are shown as unavailable in the UI.
-- * bingo_blocks (Block User) - pre-existing frontend call, table not
--   confirmed live; the block is always enforced on the blocker's device.
