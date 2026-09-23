-- ============================================================================
-- BINGO — FOOD MENU ITEM: category / delivery option / dietary tags
--
-- Status: DRAFT ONLY — NOT APPLIED. NOT approved. Do not run against any
-- Supabase project without explicit approval. This file is additive only:
-- it does not create a new table, does not touch any existing column on
-- public.food_menu_items, and does not modify the food-media Storage
-- bucket or any RLS policy already governing this table.
--
-- Why this exists: the redesigned Menu Item editor (BingoFoodMenuEditor)
-- collects three fields that do not yet exist as columns on
-- public.food_menu_items — category, delivery_option and dietary_tags
-- (the multi-select list that includes "High Protein"). Until this
-- migration is reviewed and applied, the frontend already degrades
-- gracefully: it detects a "column does not exist" error on save
-- (public.bingo_missing_property_column style handling, mirrored in JS as
-- aaMissingPropertyColumn) and retries the same save with just these
-- three fields stripped out, so item name/description/price/media/
-- availability/preparation type keep saving normally today. The moment
-- this migration is applied, no frontend code change is needed — the
-- next save simply starts persisting all three fields.
--
-- What this adds:
--   1. category text — nullable, free text matching one of the editor's
--      AA_FOOD_MENU_ITEM_CATEGORIES options (Main Meals, Snacks, Drinks,
--      Breakfast, Desserts). Not an enum: the editor's category list is
--      UI-side and may grow without another migration.
--   2. delivery_option text — nullable, one of the editor's
--      AA_FOOD_MENU_ITEM_DELIVERY_OPTIONS options (Delivery Only,
--      Pickup Only, Both Pickup & Delivery). Same rationale as above.
--   3. dietary_tags text[] — nullable, zero or more of the editor's
--      AA_FOOD_MENU_ITEM_DIETARY_OPTIONS tags (Halal, Vegetarian, Vegan,
--      Gluten Free, High Protein, Dairy Free, Popular, Traditional,
--      Spicy). Stored as a Postgres text array, matching the existing
--      `media` array column's convention on this same table.
--
-- Both text columns are intentionally NOT enums so the editor's option
-- lists can be extended later without a schema change; validation of
-- allowed values is left to the frontend, matching how this table
-- already treats `preparation_type` labels versus its one real enum
-- constraint below.
-- ============================================================================

alter table public.food_menu_items
  add column if not exists category text,
  add column if not exists delivery_option text,
  add column if not exists dietary_tags text[];

comment on column public.food_menu_items.category is
  'Menu item category shown publicly (e.g. Main Meals, Snacks, Drinks, Breakfast, Desserts). Nullable, free text, validated client-side by the Menu Item editor.';
comment on column public.food_menu_items.delivery_option is
  'Delivery option shown publicly (e.g. Delivery Only, Pickup Only, Both Pickup & Delivery). Nullable, free text, validated client-side by the Menu Item editor.';
comment on column public.food_menu_items.dietary_tags is
  'Zero or more dietary/feature tags shown publicly (e.g. Halal, Vegetarian, Vegan, Gluten Free, High Protein, Dairy Free, Popular, Traditional, Spicy). Nullable text array, validated client-side by the Menu Item editor.';

-- ============================================================================
-- END DRAFT — NOT APPLIED
-- ============================================================================
