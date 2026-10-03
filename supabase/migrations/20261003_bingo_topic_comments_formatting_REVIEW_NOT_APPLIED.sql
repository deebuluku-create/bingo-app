-- REVIEW ONLY - NOT APPLIED. Do not run until a maintainer has reviewed
-- and applied this against the live database. The frontend already
-- degrades gracefully if these columns are absent (see aaTopicComment's
-- column-missing retry loop in BINGO_MASTER_CURRENT_VERIFIED.html), so the
-- app keeps working without this migration - comments simply post without
-- a custom display name or text formatting until it is applied.
--
-- Adds per-comment "custom display name" + text formatting support
-- (font family / bold / italic / underline / color) to bingo_topic_comments,
-- requested for the comment 3-dots (•••) formatting menu.
--
-- custom_name: optional display-name override for that single comment only
--   (does not change the commenter's account/profile name anywhere else).
-- fmt: jsonb {font,bold,italic,underline,color} applied to both the
--   custom_name and the comment body text when rendered.

alter table public.bingo_topic_comments
  add column if not exists custom_name text,
  add column if not exists fmt jsonb;

-- Keep custom_name bounded to the same length the client enforces
-- (maxlength=40 on the input) so a direct API call can't store something
-- the UI was never designed to display.
alter table public.bingo_topic_comments
  add constraint if not exists bingo_topic_comments_custom_name_len
  check (custom_name is null or char_length(custom_name) <= 40);

comment on column public.bingo_topic_comments.custom_name is
  'Optional per-comment display-name override, set by the commenter for that single comment only. Does not affect their account/profile name.';
comment on column public.bingo_topic_comments.fmt is
  'Optional per-comment text style: {"font":"<css font-family>","bold":bool,"italic":bool,"underline":bool,"color":"#hex"}. Applied to both custom_name and the comment body when rendering.';
