-- ============================================================
-- BINGO PROFILE COVER PHOTO - REVIEW ONLY, NOT APPLIED
--
-- Needed only if 20260928_bingo_profile_INSPECT_READ_ONLY.sql (section 8)
-- shows public.profiles has no cover_url / cover_position columns.
--
-- The app (BINGO_MASTER_CURRENT_VERIFIED.html, aaPersistCover) writes the
-- cover with a SEPARATE owner-scoped update after the normal profile save:
--   update profiles set cover_url = <public url or null>,
--                       cover_position = <0..100>
--   where id = auth.uid()
-- If these columns are missing, that update fails with a column error and
-- the owner is told the cover is saved on the device only; the rest of the
-- profile still saves. Nothing else is changed by this file:
--   * no RLS / policy changes (the existing own-row UPDATE policy on
--     profiles already governs these columns - see
--     20260928_bingo_profile_ownership_REVIEW_NOT_APPLIED.sql);
--   * no Storage change: the image goes to the SAME bucket and owner folder
--     the avatar already uses (profile-images/<uid>/cover-<time>.jpg). If
--     section 9 of the inspection shows that bucket's write policy is not
--     scoped to the owner's own folder, report it - do not widen it here.
-- ============================================================
alter table public.profiles
  add column if not exists cover_url text,
  add column if not exists cover_position smallint not null default 35;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_cover_position_range') then
    alter table public.profiles
      add constraint profiles_cover_position_range check (cover_position between 0 and 100);
  end if;
end $$;

comment on column public.profiles.cover_url is 'Public URL of the owner-chosen profile cover (profile-images/<uid>/cover-*.jpg); null = no cover';
comment on column public.profiles.cover_position is 'Vertical focus of the cover image, 0 (top) .. 100 (bottom); used as CSS object-position';
