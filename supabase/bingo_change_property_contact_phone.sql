-- Bingo change: add contact_phone to public.property_listings
--
-- The Property posting form now sends the seller's phone number so a
-- Property listing's detail view can show a real Call/WhatsApp number,
-- the same way vehicle listings already do.
--
-- This column was NOT found anywhere in the tracked supabase/*.sql
-- migrations, and this environment has no network access to the live
-- Supabase project to confirm it directly (egress to
-- ktwkfavryihrfwghsbuo.supabase.co is blocked here), so its existence in
-- production is UNCONFIRMED. Run this once against the real database to
-- add it if it is missing; it is a no-op if the column already exists.
--
-- Not applying this migration is safe in the meantime: the app's
-- aaInsertPropertyListing/aaUpdatePropertyListing already detect a
-- "column not found" error from PostgREST for any non-core field (see
-- AA_PROPERTY_CORE_FIELDS in BINGO_MASTER_CURRENT_VERIFIED.html) and
-- silently drop that field and retry, so Property publishing will keep
-- working even without this column — the seller phone number simply
-- won't be saved/shown until this migration is applied.

alter table public.property_listings
  add column if not exists contact_phone text not null default '';
