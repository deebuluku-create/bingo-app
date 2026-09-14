-- ============================================================================
-- BINGO — FOOD MENU ITEMS (Packet 02)
--
-- Run this once in the Supabase SQL Editor, after
-- bingo_change_food_video_persistence.sql (food_businesses + the food-media
-- bucket must already exist). One food_menu_items row is one dish/drink
-- under an existing food_businesses row. Menu item media reuses the same
-- food-media Storage bucket and its existing owner-prefixed write/delete,
-- public-read policies — no new bucket or policy is needed for Storage.
-- ============================================================================

create table if not exists public.food_menu_items (
  id                uuid primary key default gen_random_uuid(),
  business_id       uuid not null references public.food_businesses(id) on delete cascade,
  user_id           uuid not null references auth.users(id) on delete cascade,
  name              text not null,
  description       text not null default '',
  price_kes         numeric not null default 0 check (price_kes >= 0),
  preparation_type  text not null default 'ready_made' check (preparation_type in ('ready_made','made_to_order')),
  available         boolean not null default true,
  -- At most one element: {type, storageBucket, storagePath, url, mimeType, sizeBytes, createdAt}
  media             jsonb not null default '[]'::jsonb,
  status            text not null default 'draft' check (status in ('draft','published')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

alter table public.food_menu_items enable row level security;

-- Owner always sees their own items (draft or published), mirroring how
-- My Food Business always shows the owner's own restaurant.
drop policy if exists food_menu_items_select_own on public.food_menu_items;
create policy food_menu_items_select_own on public.food_menu_items
  for select
  using (auth.uid() = user_id);

-- The public sees only published items belonging to a publicly eligible
-- (active, unexpired) restaurant.
drop policy if exists food_menu_items_select_public on public.food_menu_items;
create policy food_menu_items_select_public on public.food_menu_items
  for select
  using (
    status = 'published'
    and exists (
      select 1 from public.food_businesses b
      where b.id = food_menu_items.business_id
        and b.status = 'active'
        and b.subscription_expires_at is not null
        and b.subscription_expires_at > now()
    )
  );

-- An owner may only add items to a restaurant they themselves own.
drop policy if exists food_menu_items_insert_own on public.food_menu_items;
create policy food_menu_items_insert_own on public.food_menu_items
  for insert
  with check (
    auth.uid() = user_id
    and exists (select 1 from public.food_businesses b where b.id = business_id and b.user_id = auth.uid())
  );

drop policy if exists food_menu_items_update_own on public.food_menu_items;
create policy food_menu_items_update_own on public.food_menu_items
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Explicit-deletion-only: only the owner, and only by taking the delete
-- action deliberately in the UI, can remove a menu item's row (Storage
-- object removal is a separate client-side call after this succeeds).
drop policy if exists food_menu_items_delete_own on public.food_menu_items;
create policy food_menu_items_delete_own on public.food_menu_items
  for delete
  using (auth.uid() = user_id);

create index if not exists food_menu_items_business_idx on public.food_menu_items(business_id);
create index if not exists food_menu_items_user_idx on public.food_menu_items(user_id);
