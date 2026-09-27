-- ============================================================================
-- BINGO — FOOD MENU ITEM: ingredients / delicacy_tags / availability_notes
--
-- Status: DRAFT ONLY — NOT APPLIED. NOT approved. Do not run against any
-- Supabase project without explicit approval, and not before the
-- companion read-only inspection
-- (20260927_bingo_food_menu_items_INSPECT_LIVE.sql) has been run against
-- the live project and its results confirm the assumptions below still
-- hold. This file is additive only: it does not create a new table, does
-- not touch any existing column, CHECK constraint, RLS policy or grant on
-- public.food_menu_items, and does not modify the food-media Storage
-- bucket. It follows exactly the same convention already used (as a
-- draft, also not yet applied) by
-- supabase/bingo_change_food_menu_item_fields.sql for category/
-- delivery_option/dietary_tags.
--
-- Why this exists: the approved "Combined Integration Review" Food Menu
-- layout (integrated on branch bingo-storage-preview-repair-2026-09-27,
-- replacing BingoFoodMenuEditor's markup for this one screen only)
-- collects three fields that have no live column:
--   1. ingredients text — free text, "Ingredients" field under
--      "1. Food Details".
--   2. delicacy_tags text[] — the "2. Delicacy / Origin" checkbox grid
--      (African/Chinese/Italian/Swahili/Luhya/Kikuyu/Coasterian-Coastal/
--      Mijikenda/Kisii/Luo/Maasai/Oromo-Pokomo/Kamba/Meru/Turkana/Somali/
--      Arab/Ethiopian/Turkish/Indian/Other-International), required by
--      the form before Publish (mirrors the existing dietary_tags
--      text[] column's own convention on this same table).
--   3. availability_notes text[] — captures selections from "3.
--      Preparation & Availability" that do NOT map onto the existing
--      2-value preparation_type CHECK ('ready_made'/'made_to_order'):
--      the form's third "Pre-order" radio option, and its separate
--      Delivery/Pickup checkboxes (distinct from the already-drafted,
--      single-select delivery_option column). "Ready Made"/"Made to
--      Order" continue to write the real preparation_type column
--      exactly as before; "Available" continues to write the real
--      available boolean column exactly as before. Nothing about the
--      table's existing enum or boolean columns changes.
--
-- Until this migration is reviewed and applied, the frontend already
-- degrades gracefully: on save it detects a "column does not exist"
-- error (aaMissingPropertyColumn, the same pattern used for category/
-- delivery_option/dietary_tags and for property_listings before that)
-- and retries the same save with just the missing field(s) stripped, so
-- item_name/description/price/preparation_type/is_available/media/status
-- (the real live column names - confirmed after this file was first
-- drafted, when the save/load code was also found to be using the wrong
-- names entirely; see the commit fixing that) keep saving normally
-- today and nothing already saved by the previous editor is overwritten
-- or lost. ingredients/availability_notes stay visible in the form and
-- are retried on every save even before this migration lands. Delicacy/
-- Origin is treated differently: whenever the owner has actually ticked
-- a tag, the frontend refuses to save at all until this migration is
-- applied, rather than silently publishing without it - see
-- aaFoodMenuProtoSave's blockedField handling.
-- ============================================================================

alter table public.food_menu_items
  add column if not exists ingredients text,
  add column if not exists delicacy_tags text[],
  add column if not exists availability_notes text[];

comment on column public.food_menu_items.ingredients is
  'Free-text ingredients list shown on the Food Details section of the Food Menu form. Nullable, validated client-side only.';
comment on column public.food_menu_items.delicacy_tags is
  'One or more Delicacy / Origin tags ticked on the Food Menu form (e.g. Swahili Delicacies, Luhya Delicacies). Nullable text array; the form requires at least one before Publish, but nothing in the database enforces that.';
comment on column public.food_menu_items.availability_notes is
  'Zero or more notes from the Preparation & Availability section that do not map onto the existing preparation_type/available columns - currently "Pre-order", "Delivery", "Pickup". Nullable text array.';

-- ============================================================================
-- END DRAFT — NOT APPLIED
-- ============================================================================
