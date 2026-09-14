-- ============================================================================
-- OPTIONAL — food-media bucket hardening
--
-- The food-media bucket and its owner-prefixed write/delete, public-read
-- policies already exist from bingo_change_food_video_persistence.sql. This
-- just adds a server-enforced size limit and MIME allow-list to that same
-- bucket (defense in depth alongside the client-side checks in Mother HTML).
-- Safe to re-run; it does not touch or duplicate any existing RLS policy.
-- ============================================================================

update storage.buckets
set file_size_limit = 104857600, -- 100 MB
    allowed_mime_types = array['image/jpeg','image/png','image/webp','video/mp4','video/webm','video/quicktime']
where id = 'food-media';
