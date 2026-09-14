-- ============================================================================
-- BINGO CHANGE — FOOD VIDEO PERSISTENCE (Supabase backend)
--
-- Run this once in the Supabase SQL Editor. It creates the food_businesses
-- table (Food had no real backend before this — every business and its
-- media lived only in localStorage, and recorded videos stored a session-
-- only blob: URL as if it were permanent) and the food-media Storage
-- bucket + policies that back it.
--
-- Nothing here touches property_listings, bingo_user_roles, or any other
-- existing table. Only the browser-safe publishable (anon) key is ever
-- used from Mother HTML; all access control is enforced here by RLS.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. food_businesses
-- ---------------------------------------------------------------------------
create table if not exists public.food_businesses (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users(id) on delete cascade,
  business_name       text not null,
  category            text not null default '',
  county              text not null default '',
  town                text not null default '',
  delivery_area       text not null default '',
  phone               text not null default '',
  whatsapp            text not null default '',
  opening_hours       text not null default '',
  price_range         text not null default '',
  delivery_available  boolean not null default false,
  description         text not null default '',
  -- Each element: {type, storageBucket, storagePath, url, mimeType, sizeBytes, createdAt}
  media               jsonb not null default '[]'::jsonb,
  status              text not null default 'inactive' check (status in ('inactive','active','suspended')),
  subscription_expires_at timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

alter table public.food_businesses enable row level security;

-- "My Food Business always shows the owner's saved restaurant, drafts, and
-- permanent media, even when advertising is inactive."
drop policy if exists food_businesses_select_own on public.food_businesses;
create policy food_businesses_select_own on public.food_businesses
  for select
  using (auth.uid() = user_id);

-- "Browse Food shows only businesses that meet the existing active public
-- subscription requirements." (Postgres OR's this with the policy above,
-- so the owner still also sees their own row through either policy.)
drop policy if exists food_businesses_select_public on public.food_businesses;
create policy food_businesses_select_public on public.food_businesses
  for select
  using (
    status = 'active'
    and subscription_expires_at is not null
    and subscription_expires_at > now()
  );

drop policy if exists food_businesses_insert_own on public.food_businesses;
create policy food_businesses_insert_own on public.food_businesses
  for insert
  with check (auth.uid() = user_id);

drop policy if exists food_businesses_update_own on public.food_businesses;
create policy food_businesses_update_own on public.food_businesses
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- "A Food video may be deleted only when the authenticated owner
-- deliberately presses Remove or Delete and confirms" — this policy is
-- what makes that possible; nothing else can delete the row or, via the
-- Storage policies below, its media objects.
drop policy if exists food_businesses_delete_own on public.food_businesses;
create policy food_businesses_delete_own on public.food_businesses
  for delete
  using (auth.uid() = user_id);

create index if not exists food_businesses_user_id_idx on public.food_businesses(user_id);
create index if not exists food_businesses_public_idx on public.food_businesses(status, subscription_expires_at);

-- ---------------------------------------------------------------------------
-- 2. food-media Storage bucket + policies
--    Path convention matches property-media: user_id/business_id/file-name
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('food-media', 'food-media', true)
on conflict (id) do nothing;

drop policy if exists food_media_public_read on storage.objects;
create policy food_media_public_read on storage.objects
  for select
  using (bucket_id = 'food-media');

drop policy if exists food_media_owner_write on storage.objects;
create policy food_media_owner_write on storage.objects
  for insert
  with check (
    bucket_id = 'food-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Explicit-deletion-only: an owner may delete only objects under their own
-- user_id prefix, and only by taking the delete action deliberately in the UI.
drop policy if exists food_media_owner_delete on storage.objects;
create policy food_media_owner_delete on storage.objects
  for delete
  using (
    bucket_id = 'food-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
