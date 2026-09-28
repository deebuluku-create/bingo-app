-- ============================================================
-- BINGO MESSENGER - message-media Storage bucket
-- STATUS: FOR REVIEW - NOT APPLIED.
--
-- Why: the client (aaMsgSendFile) has always uploaded attachments to a
-- bucket named "message-media" and embedded the result of
-- storage.getPublicUrl() as a plain link in the message body - but no
-- migration in this repo ever created that bucket. The read-only check
-- in 20260928_bingo_messenger_live_contract_INSPECT_READ_ONLY.sql
-- (select id, public from storage.buckets where id='message-media')
-- exists for exactly this reason: to let the owner confirm it live
-- before trusting attachment sends. Until the bucket exists, every
-- attachment upload fails at sb.storage.from('message-media').upload()
-- and the client falls back to its documented "kept on this device
-- only, not sent" behaviour (aaMsgSendFile's catch block) - which is
-- the most likely cause of "attachments not working" reports.
--
-- Modelled directly on the already-applied
-- 20260927_bingo_profile_images_bucket.sql: public bucket (the client
-- uses getPublicUrl, not a signed URL, so recipients can load the image
-- straight from the link embedded in the message), writes restricted to
-- the uploader's own id-prefixed folder - matching the client's actual
-- upload path, `${aaMsgMyId()}/${Date.now()}_${safeName}`.
--
-- Nothing else changes: no existing table, column, policy, or the
-- profile-images bucket, is touched.
-- ============================================================

begin;

do $$ begin
  if exists (select 1 from storage.buckets where id = 'message-media') then
    raise exception 'storage bucket message-media already exists - review before re-applying';
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'message-media', 'message-media', true, 26214400,
  array[
    'image/jpeg','image/png','image/webp','image/gif',
    'video/mp4','video/quicktime',
    'audio/mpeg','audio/mp4','audio/webm','audio/ogg','audio/wav','audio/aac',
    'application/pdf'
  ]
)
on conflict (id) do nothing;

create policy "bingo_message_media_public_read" on storage.objects
  for select to public
  using (bucket_id = 'message-media');

create policy "bingo_message_media_owner_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'message-media' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "bingo_message_media_owner_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'message-media' and (storage.foldername(name))[1] = (select auth.uid())::text);

commit;

-- Verify after applying:
--   select id, public, file_size_limit from storage.buckets where id = 'message-media';
--   select policyname, cmd from pg_policies where schemaname='storage' and tablename='objects' and policyname like 'bingo_message_media_%';
