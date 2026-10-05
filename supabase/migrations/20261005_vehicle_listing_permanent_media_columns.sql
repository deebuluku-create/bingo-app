-- Applied to Bingo App Kenya production Supabase on 2026-10-05.
-- Surgical repair: the frontend already uploads vehicle media to the public
-- posts bucket and writes these fields. The live vehicle_listings table was
-- missing them, causing the save fallback to drop the permanent video URL and
-- the publication verifier to reject an otherwise-saved listing.
alter table public.vehicle_listings
  add column if not exists area text,
  add column if not exists media_type text default 'photo',
  add column if not exists video_url text,
  add column if not exists video_path text,
  add column if not exists video_bucket text default 'posts',
  add column if not exists video_mime_type text,
  add column if not exists video_size_bytes bigint default 0,
  add column if not exists upload_status text default 'published',
  add column if not exists image_url text;

comment on column public.vehicle_listings.video_url is
  'Permanent public URL for a vehicle video stored in Supabase Storage.';
comment on column public.vehicle_listings.video_path is
  'Storage object path for the vehicle video.';
comment on column public.vehicle_listings.video_bucket is
  'Storage bucket containing the vehicle video; current frontend uses posts.';
comment on column public.vehicle_listings.media_type is
  'Vehicle listing media mode: video or photo.';
