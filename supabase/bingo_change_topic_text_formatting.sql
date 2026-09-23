-- ============================================================
-- DRAFT MIGRATION — Bingo Wall topic title/body text formatting
-- Status: DRAFT ONLY. NOT APPLIED. Do not run against any Supabase project
-- without explicit approval.
--
-- Background: the topic composer's "Write with Your Style" panel now
-- lets a member format the title and message independently (font family
-- from a curated list, bold/italic, size, an approved colour or a custom
-- hex colour, a neon-glow toggle, alignment). Both are stored as small
-- JSON objects with a handful of enum-like keys - never raw HTML or CSS,
-- and never free text: every value the renderer touches (font, size,
-- colour) comes from a fixed lookup table on the client, and the one
-- free-form value (a custom hex colour from a native <input
-- type="color">) is re-validated against ^#[0-9a-fA-F]{6}$ before it is
-- ever used, both in this migration's CHECK constraint and again in the
-- frontend renderer. There is nothing here a client could use to inject
-- markup, scripts or arbitrary CSS.
--
-- Frontend already tolerates these columns not existing yet:
-- aaPublishBingoTopic() retries the insert with title_format/body_format
-- dropped if the database reports the column missing (the same pattern
-- already used by aaInsertPropertyListing for optional fields), and
-- aaMapBingoTopicRow() reads them back as null when absent, falling back
-- to the existing single-preset style system. Not applying this
-- migration is therefore safe in the meantime - new posts simply publish
-- without the richer per-field formatting persisting.
-- ============================================================

alter table public.bingo_topics add column if not exists title_format jsonb;
alter table public.bingo_topics add column if not exists body_format jsonb;

do $$ begin
  if not exists (
    select 1 from pg_constraint where conname = 'bingo_topics_title_format_shape'
  ) then
    alter table public.bingo_topics
      add constraint bingo_topics_title_format_shape
      check (
        title_format is null
        or (
          jsonb_typeof(title_format) = 'object'
          and length(title_format::text) < 500
          and (title_format->>'customColor' is null or title_format->>'customColor' ~ '^#[0-9a-fA-F]{6}$')
        )
      );
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'bingo_topics_body_format_shape'
  ) then
    alter table public.bingo_topics
      add constraint bingo_topics_body_format_shape
      check (
        body_format is null
        or (
          jsonb_typeof(body_format) = 'object'
          and length(body_format::text) < 500
          and (body_format->>'customColor' is null or body_format->>'customColor' ~ '^#[0-9a-fA-F]{6}$')
        )
      );
  end if;
end $$;

-- ============================================================
-- NOT INCLUDED IN THIS DRAFT (deliberately):
--  - Any change to comments' own per-comment style field, which is a
--    separate, unrelated system (bingo_topic_comments.style / c.style)
--    and is not affected by this migration.
--  - Font-loading/asset changes - the curated font list is loaded
--    client-side from Google Fonts (openly SIL-licensed) with a plain
--    CSS fallback family when unavailable; nothing server-side to add.
-- ============================================================
