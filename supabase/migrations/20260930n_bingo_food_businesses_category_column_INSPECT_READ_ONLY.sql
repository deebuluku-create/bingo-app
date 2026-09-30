-- ============================================================================
-- READ-ONLY. Run this against the live project and send back the results.
-- Nothing here changes data, schema, policies or grants.
--
-- Context: the live preview reports "Could not save Food business: Could
-- not find the 'category' column of 'food_businesses' in the schema
-- cache" on both Save Draft and Publish Business.
--
-- supabase/bingo_change_food_video_persistence.sql (the only CREATE TABLE
-- for food_businesses in this repo) defines a plain `category text` column,
-- alongside `user_id`, one `media jsonb` column, and a status CHECK of
-- ('inactive','active','suspended'). But this codebase's own code comments
-- (BINGO_MASTER_CURRENT_VERIFIED.html, aaMapFoodBusinessRow/
-- aaFoodMediaToColumns, dated 2026-09-27) already record a live-schema
-- audit that found the REAL live table uses `owner_id` (not user_id),
-- four separate image_urls/video_url/cover_url/logo_url columns (not one
-- media column), and a status enum with no 'inactive' value - all
-- contradicting that same migration file. So that file cannot be trusted
-- to confirm `category` still exists under that name either, and no
-- sandbox in this session has ever had a live Supabase connection to
-- check directly (every attempt is blocked by egress policy).
--
-- This file exists to settle, from the live database itself, which of
-- three things is actually true:
--   1. `category` is the wrong field name (the column exists under a
--      different name - the query in section 2 below catches this).
--   2. `category` was never added live at all (no `category`-like column
--      exists anywhere on this table - no migration in this repo adds
--      it either, so there is no "missing migration" already drafted and
--      waiting; one would need to be written only after this confirms
--      the column is genuinely absent).
--   3. `category` exists exactly as named, and PostgREST's schema cache
--      is simply stale (common after a DDL change made without a
--      `NOTIFY pgrst, 'reload schema';` afterwards) - if section 1 below
--      shows `category` present, reload the cache (see the note at the
--      bottom) and re-test before assuming anything else is wrong.
--
-- Do not add a column, rename one, or change a grant/policy based on a
-- guess - run this first.
-- ============================================================================

-- 1. Full current column list, types, defaults - the direct answer to
--    "does a column literally named category exist, and if so what type
--    and default does it actually have". Also re-confirms owner_id vs
--    user_id and the media columns while we're here, since the same
--    'Could not find the column X in schema cache' failure mode would
--    hit any of those the moment a payload includes them.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name='food_businesses'
order by ordinal_position;

-- 2. Catches a rename - anything with "categ" or "cuisine" in the name,
--    in case `category` was renamed to something like `cuisine_type` or
--    `categories` rather than dropped outright.
select column_name, data_type
from information_schema.columns
where table_schema='public' and table_name='food_businesses'
  and (column_name ilike '%categ%' or column_name ilike '%cuisine%');

-- 3. Every constraint - confirms the real status enum (the app currently
--    assumes no 'inactive' value per the 2026-09-27 audit; this settles
--    it definitively) and whether category (if present) has a CHECK of
--    its own that the multi-select checkbox payload could violate.
select conname, contype, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid='public.food_businesses'::regclass;

-- 4. RLS policies - confirms owner-only insert/update/delete/select
--    policies are still enforced exactly as expected, and that no
--    unrelated policy would reject a write that includes (or omits)
--    category.
select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname='public' and tablename='food_businesses';

-- 5. Grants - confirms authenticated/anon table-level privileges.
select grantee, privilege_type
from information_schema.role_table_grants
where table_schema='public' and table_name='food_businesses'
  and grantee in ('anon','authenticated','public');

-- 6. Explicit yes/no for the one column this file exists to check.
select exists (
  select 1 from information_schema.columns
  where table_schema='public' and table_name='food_businesses' and column_name='category'
) as category_column_exists;

-- ----------------------------------------------------------------------------
-- This file makes no changes and never will. What to do with the results:
--
-- If section 1/6 shows `category` genuinely exists and section 2 shows no
-- renamed sibling, the most likely explanation is a stale PostgREST schema
-- cache - the fix for that is a SEPARATE, NON-read-only file:
--   20260930o_bingo_food_businesses_reload_schema_cache.sql
-- Run that file only after confirming those results here, not before.
--
-- If `category` does not exist under any name, it needs a real migration
-- (a plain `alter table public.food_businesses add column category text
-- not null default '';` matching what the form already sends) - do not
-- apply that without separate review and approval; this file's job is
-- only to confirm whether one is actually needed.
-- ----------------------------------------------------------------------------
