-- ============================================================================
-- NOT READ-ONLY. This changes server state (forces PostgREST to reload its
-- cached schema). Do not run this file until
-- 20260930n_bingo_food_businesses_category_column_INSPECT_READ_ONLY.sql has
-- been run first and its results confirm BOTH of the following:
--   - section 6 (category_column_exists) is true, and
--   - section 2 shows no renamed sibling column that the app should be
--     using instead.
-- If either of those is not true, this file will not fix anything - the
-- problem is a genuinely missing/renamed column, not a stale cache, and
-- needs a real migration decided separately, not this command.
-- ============================================================================

NOTIFY pgrst, 'reload schema';

-- Equivalent from the Supabase dashboard instead of the SQL editor, if
-- preferred: Settings -> API -> "Reload schema".
--
-- After running this, re-test a Save Draft on the live preview before
-- concluding anything else is wrong.
