-- ============================================================================
-- BINGO — FOOD MENU ITEM: ingredients / delicacy_tags / availability_notes
--
-- Status: APPLIED LIVE on 2026-09-28, as migration
-- 20260927222723_bingo_food_menu_items_delicacy_origin_fields_20260928
-- (same three add-column-if-not-exists statements below, run through the
-- normal Supabase migration workflow). Confirmed afterward: ingredients,
-- delicacy_tags and availability_notes all exist on public.food_menu_items,
-- and no existing column, CHECK constraint, RLS policy or grant on that
-- table changed - this file was and remains additive only, and it did
-- not touch the food-media Storage bucket. It followed exactly the same
-- convention already used (as a still-unapplied draft) by
-- supabase/bingo_change_food_menu_item_fields.sql for category/
-- delivery_option/dietary_tags - that companion file's status is
-- unaffected by this one having been applied.
--
-- This file is kept as the historical record of exactly what was
-- reviewed and run; do not re-run it (add column if not exists makes a
-- second run a no-op regardless, but there is no need to).
--
-- Why this exists: the approved "Combined Integration Review" Food Menu
-- layout (integrated on branch bingo-storage-preview-repair-2026-09-27,
-- replacing BingoFoodMenuEditor's markup for this one screen only)
-- collects three fields that had no live column before this migration:
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
-- Before this migration was applied, the frontend degraded gracefully
-- rather than failing outright: on save it detected a "column does not
-- exist" error (aaMissingPropertyColumn, the same pattern used for
-- category/delivery_option/dietary_tags and for property_listings
-- before that) and retried the same save with just the missing field(s)
-- stripped, so item_name/description/price/preparation_type/
-- is_available/media/status (the real live column names - confirmed
-- after this file was first drafted, when the save/load code was also
-- found to be using the wrong names entirely; see the commit fixing
-- that) kept saving normally and nothing already saved by the previous
-- editor was overwritten or lost. Delicacy/Origin was treated
-- differently even pre-migration: whenever the owner had actually
-- ticked a tag, the frontend refused to save at all rather than
-- silently publishing without it - see aaFoodMenuProtoSave's
-- blockedField handling. That handling is still in the code and is now
-- simply dead weight for this table (the columns exist), which is
-- harmless and intentionally left in place rather than removed.
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
-- END — APPLIED LIVE 2026-09-28 (see status note at top of file)
-- ============================================================================
