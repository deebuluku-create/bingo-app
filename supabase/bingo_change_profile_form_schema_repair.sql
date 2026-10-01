-- Applied to Bingo App Kenya on 1 October 2026 after live schema inspection.
-- Match the existing profile editor and cover-photo persistence payloads.
-- Existing profile rows and owner-only write policies are unchanged.
alter table public.profiles
  add column if not exists first_name text,
  add column if not exists last_name text,
  add column if not exists account_type text,
  add column if not exists company_name text,
  add column if not exists show_phone boolean not null default true,
  add column if not exists cover_url text,
  add column if not exists cover_position integer not null default 35;
notify pgrst, 'reload schema';
