-- ============================================================
-- BINGO PROFILE OWNERSHIP - LIVE CHECK (changes nothing: ends in ROLLBACK)
--
-- Proves, under the real `authenticated` role and RLS, whether one member
-- (B) can change another member's (A) profile through the same client
-- path the app uses (supabase-js .from('profiles').upsert / .update).
--
-- HOW TO RUN (Supabase SQL editor):
--   1. Replace the two placeholder ids on the marked line with two REAL
--      auth user ids: A = the profile owner, B = a different member.
--   2. Run the whole script. Every write happens inside one transaction
--      that is ROLLED BACK at the end, so no profile is modified.
--   3. Send back every row of output and any error text.
--
-- EXPECTED (secure):
--   step 1  B updates B's own row .............. 1
--   step 2  B updates A's row .................. 0      (RLS hides/blocks it)
--   step 3  B upserts a row with A's id ........ ERROR "new row violates
--           row-level security policy" (or 0 rows)   <- the app's real path
-- ANY OTHER RESULT in step 2 or 3 means B can edit A's profile: apply
-- 20260928_bingo_profile_ownership_REVIEW_NOT_APPLIED.sql after review.
-- ============================================================
begin;

create temp table _bingo_probe(a uuid not null, b uuid not null) on commit drop;
insert into _bingo_probe values
 ('00000000-0000-0000-0000-00000000000A','00000000-0000-0000-0000-00000000000B');  -- <<< A (owner), B (other member)
grant select on _bingo_probe to authenticated;

-- act as member B exactly as a signed-in browser would
select set_config('request.jwt.claims',
  (select json_build_object('sub',b::text,'role','authenticated')::text from _bingo_probe), true);
set local role authenticated;

select 'step 0  running as' as check, auth.uid()::text as result;

with u as (update public.profiles set updated_at = updated_at
           where id = (select b from _bingo_probe) returning 1)
select 'step 1  B updates B''s own row (expect 1)' as check, count(*)::text as result from u;

with u as (update public.profiles set updated_at = updated_at
           where id = (select a from _bingo_probe) returning 1)
select 'step 2  B updates A''s row (expect 0)' as check, count(*)::text as result from u;

-- the app saves with profiles.upsert({id: <user id>, full_name, first_name,
-- last_name, email, phone, updated_at}, {onConflict: 'id'}) - same columns here
insert into public.profiles(id, full_name, first_name, last_name, email, phone, updated_at)
select a, 'rls probe', 'rls', 'probe', '', '', now() from _bingo_probe
on conflict (id) do update set full_name = excluded.full_name, updated_at = excluded.updated_at;
select 'step 3  B upsert with A''s id WAS ACCEPTED - NOT SECURE' as check, 'see above' as result;

rollback;
