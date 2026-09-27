-- READ-ONLY. Run this against the live project and send back the results
-- before treating the additive migration in the companion file
-- (20260927_bingo_food_menu_items_delicacy_origin_fields.sql) as safe to
-- apply. Per this session's standing rule (established the hard way on
-- the Agent-withdrawal work): never assume a base .sql file in this repo
-- still matches what is actually live - confirm first.
--
-- Context: the new "Combined Integration Review" Food Menu form
-- (approved layout, integrated on branch bingo-storage-preview-repair-
-- 2026-09-27) collects three fields public.food_menu_items does not yet
-- have as columns per supabase/bingo_change_food_menu_items.sql:
--   - ingredients (free text)
--   - delicacy_tags (multi-select, "Delicacy / Origin", required in the UI)
--   - availability_notes (captures "Pre-order" plus Delivery/Pickup
--     checkboxes that don't map onto the existing 2-value
--     preparation_type CHECK constraint)
-- The frontend already degrades gracefully if these columns are missing
-- (same aaMissingPropertyColumn retry pattern already proven for
-- category/delivery_option/dietary_tags on this same table), so nothing
-- breaks either way - but the migration should not be applied on a guess.

-- 1. Full current column list, types, defaults - confirms whether
--    category/delivery_option/dietary_tags (drafted in
--    bingo_change_food_menu_item_fields.sql, marked NOT APPLIED) or
--    ingredients/delicacy_tags/availability_notes already exist under
--    any name, and confirms the base columns this session is relying on
--    (name, description, price_kes, preparation_type, available, media,
--    status) are still exactly as bingo_change_food_menu_items.sql says.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name='food_menu_items'
order by ordinal_position;

-- 2. Every constraint, in particular the exact CHECK on preparation_type
--    and on status - confirms 'ready_made'/'made_to_order' are still the
--    only two live values (the new form's "Pre-order" radio option is
--    deliberately NOT sent as preparation_type for this reason - it is
--    stored in the new availability_notes array instead).
select conname, contype, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid='public.food_menu_items'::regclass;

-- 3. RLS policies - confirms the owner-only insert/update policies this
--    session is relying on (food_menu_items_insert_own/_update_own) are
--    still in force exactly as bingo_change_food_menu_items.sql defines
--    them, and that no other policy would reject the new columns.
select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname='public' and tablename='food_menu_items';

-- 4. Grants - confirms authenticated/anon table-level privileges match
--    what RLS alone is assumed to be gating.
select grantee, privilege_type
from information_schema.role_table_grants
where table_schema='public' and table_name='food_menu_items'
  and grantee in ('anon','authenticated','public');

-- 5. Any trigger on this table this session is not aware of.
select tgname, pg_get_triggerdef(oid) as definition
from pg_trigger
where tgrelid='public.food_menu_items'::regclass and not tgisinternal;

-- 6. Actual values in use today for preparation_type and status, if any
--    rows exist - the most direct confirmation of the real enum, not
--    just the two values this session has assumed.
select preparation_type, status, count(*) from public.food_menu_items
group by preparation_type, status;

-- 7. Confirm the food_businesses relationship this table's insert policy
--    depends on (food_menu_items_insert_own checks business_id against
--    food_businesses.user_id) - full column list, to make sure
--    user_id/id are still named and typed as this session assumes.
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema='public' and table_name='food_businesses'
order by ordinal_position;
