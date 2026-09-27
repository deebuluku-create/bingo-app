-- OPTIONAL: live confirmation of bingo_follows RLS, to run yourself in the
-- Supabase SQL Editor against ktwkfavryihrfwghsbuo, AFTER applying
-- 20260927_bingo_follows_table.sql and BEFORE relying on the feature in
-- production. This is not something Claude executed against your live
-- project - no live network access exists in that sandbox. It IS the
-- same test Claude ran successfully against a real local Postgres 16
-- instance (genuine RLS enforcement, not a mock) - see the delivery
-- report for that transcript. Running it here as well confirms your
-- actual project's auth.uid()/auth.users/grants behave the same way.
--
-- REWRITTEN THREE TIMES (post-review each time, each fix confirmed by
-- actually re-running it — this history is kept because each version
-- looked safe until it was actually run):
--   (1) The original wrapped each case in its own begin/rollback and
--       relied on the caller sending `rollback;` immediately after an
--       expected error. If the SQL Editor sends a pasted script as one
--       batch and stops at the first error, later statements - the
--       cleanup delete included - would never run.
--   (2) Rewrote every expect-a-failure case as a DO block with its own
--       EXCEPTION handler, so the failure never reaches the client as an
--       error. Building this surfaced a second bug, caught only by
--       running it: PL/pgSQL's role switch is transaction-local, and
--       entering an EXCEPTION handler rolls back to the block's start -
--       silently reverting the role switch - so logging a PASS on the
--       SUCCESS path (nothing auto-reverts there) while still switched
--       to authenticated/anon failed with "permission denied for table
--       bingo_follows_test_results", and that secondary failure rolled
--       back the real insert/delete that had already succeeded in the
--       same block, producing cascading false results. Fixed by
--       explicitly reverting role before every results-table write.
--   (3) That version's step 0 unconditionally DELETED any existing
--       relationship between the two chosen accounts before starting -
--       correctly flagged as unsafe for real accounts. Changed step 0 to
--       RAISE EXCEPTION instead of deleting - which then exposed a THIRD
--       bug, again only by actually running it against a database with a
--       pre-existing relationship already in place: psql (and, by
--       extension, anything else that sends this file as a sequence of
--       independent statements rather than one wrapped transaction)
--       does NOT stop at the first error by default - every DO block
--       after the failed one still ran, and TEST 7's unconditional
--       cleanup delete then destroyed the real pre-existing relationship
--       anyway, exactly what step 0 was trying to prevent. Relying on a
--       client's error-stops-the-batch behavior is not safe to assume at
--       all - different tools (raw psql, psql with ON_ERROR_STOP, the
--       Supabase SQL Editor) may differ, and this script was WRONG about
--       it twice in a row while looking correct on paper both times.
--
-- This version does not rely on that behavior at all. A single guard
-- check runs first and writes its result (true/false) into a temporary
-- table; every single subsequent step - EVERY test AND the cleanup -
-- reads that flag before doing anything and no-ops entirely if it is
-- false. If a relationship already exists between the two accounts in
-- either direction, NOTHING below the guard ever touches the table, full
-- stop, regardless of whatever the client does with the guard's own
-- RAISE NOTICE. Verified by actually running this exact file twice: once
-- against a database with a pre-existing relationship already present
-- (every step correctly reports SKIPPED, the pre-existing row survives
-- untouched, confirmed by a direct row count before and after) and once
-- against a clean database (all 8 tests run and PASS, cleanup succeeds,
-- zero residue) - see the delivery report for both transcripts.
--
-- BEFORE RUNNING: find-and-replace both placeholders below with two REAL,
-- already-existing auth.users ids from your project (e.g. two of your
-- own test accounts) - search-and-replace the literal text
-- USER_A_UUID_HERE and USER_B_UUID_HERE in this file. Do not insert
-- synthetic rows into auth.users on a production project.

create temporary table bingo_follows_test_results (
  step text primary key,
  outcome text,
  detail text
);

create temporary table bingo_follows_test_guard (safe_to_proceed boolean not null);
insert into bingo_follows_test_guard
select not exists (
  select 1 from public.bingo_follows
  where (follower_id = 'USER_A_UUID_HERE' and following_id = 'USER_B_UUID_HERE')
     or (follower_id = 'USER_B_UUID_HERE' and following_id = 'USER_A_UUID_HERE')
);

do $$
begin
  if not (select safe_to_proceed from bingo_follows_test_guard) then
    raise notice 'GUARD FAILED: an existing relationship already exists between these two accounts (in one direction or the other). This script will not touch it - every step below will report SKIPPED and do nothing. Choose two accounts with no existing follow relationship between them, or verify/back up manually first.';
    insert into bingo_follows_test_results values ('GUARD', 'FAIL', 'existing relationship detected - all steps below skipped, nothing was touched');
  else
    insert into bingo_follows_test_results values ('GUARD', 'PASS', 'no existing relationship between these accounts - safe to proceed');
  end if;
end $$;

-- TEST 1: user A follows user B — expect SUCCESS.
do $$
begin
  if not (select safe_to_proceed from bingo_follows_test_guard) then
    insert into bingo_follows_test_results values ('TEST1_A_follows_B', 'SKIP', 'guard failed');
    return;
  end if;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', '{"sub":"USER_A_UUID_HERE","role":"authenticated"}', true);
  insert into public.bingo_follows (follower_id, following_id)
    values ('USER_A_UUID_HERE', 'USER_B_UUID_HERE');
  perform set_config('role', 'postgres', true);
  insert into bingo_follows_test_results values ('TEST1_A_follows_B', 'PASS', 'insert succeeded as expected');
exception when others then
  perform set_config('role', 'postgres', true);
  insert into bingo_follows_test_results values ('TEST1_A_follows_B', 'FAIL', sqlerrm);
end $$;

-- TEST 2: user A tries to impersonate B as the follower — expect the
-- INSERT to be REJECTED by RLS. Caught here, never sent to the client.
do $$
begin
  if not (select safe_to_proceed from bingo_follows_test_guard) then
    insert into bingo_follows_test_results values ('TEST2_impersonation_blocked', 'SKIP', 'guard failed');
    return;
  end if;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', '{"sub":"USER_A_UUID_HERE","role":"authenticated"}', true);
  insert into public.bingo_follows (follower_id, following_id)
    values ('USER_B_UUID_HERE', 'USER_A_UUID_HERE');
  perform set_config('role', 'postgres', true);
  insert into bingo_follows_test_results values ('TEST2_impersonation_blocked', 'FAIL', 'insert should have been rejected but succeeded');
  delete from public.bingo_follows where follower_id='USER_B_UUID_HERE' and following_id='USER_A_UUID_HERE'; -- undo if it somehow succeeded
exception when insufficient_privilege then
  perform set_config('role', 'postgres', true);
  insert into bingo_follows_test_results values ('TEST2_impersonation_blocked', 'PASS', 'rejected as expected: ' || sqlerrm);
when others then
  perform set_config('role', 'postgres', true);
  insert into bingo_follows_test_results values ('TEST2_impersonation_blocked', 'FAIL', 'unexpected error: ' || sqlerrm);
end $$;

-- TEST 3: user B tries to delete A's relationship — expect 0 rows
-- deleted (RLS silently filters the row, no error is raised by DELETE
-- matching nothing, so this checks the row still exists afterward).
do $$
declare
  still_there boolean;
begin
  if not (select safe_to_proceed from bingo_follows_test_guard) then
    insert into bingo_follows_test_results values ('TEST3_cross_user_delete_blocked', 'SKIP', 'guard failed');
    return;
  end if;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', '{"sub":"USER_B_UUID_HERE","role":"authenticated"}', true);
  delete from public.bingo_follows
    where follower_id='USER_A_UUID_HERE' and following_id='USER_B_UUID_HERE';
  perform set_config('role', 'postgres', true);
  select exists(
    select 1 from public.bingo_follows
    where follower_id='USER_A_UUID_HERE' and following_id='USER_B_UUID_HERE'
  ) into still_there;
  if still_there then
    insert into bingo_follows_test_results values ('TEST3_cross_user_delete_blocked', 'PASS', 'relationship survived, as expected');
  else
    insert into bingo_follows_test_results values ('TEST3_cross_user_delete_blocked', 'FAIL', 'relationship was deleted by a non-owner');
  end if;
exception when others then
  perform set_config('role', 'postgres', true);
  insert into bingo_follows_test_results values ('TEST3_cross_user_delete_blocked', 'FAIL', 'unexpected error: ' || sqlerrm);
end $$;

-- TEST 4/5: both the owner and an uninvolved authenticated user (and,
-- per the policy, a logged-out anon session) can SELECT the row — this
-- is what makes follower/following counts and mutual-follow checks work
-- for a profile you are not the owner of.
do $$
declare
  seen int;
begin
  if not (select safe_to_proceed from bingo_follows_test_guard) then
    insert into bingo_follows_test_results values ('TEST4_broad_authenticated_read', 'SKIP', 'guard failed');
    return;
  end if;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', '{"sub":"USER_B_UUID_HERE","role":"authenticated"}', true);
  select count(*) into seen from public.bingo_follows where following_id='USER_B_UUID_HERE';
  perform set_config('role', 'postgres', true);
  if seen = 1 then
    insert into bingo_follows_test_results values ('TEST4_broad_authenticated_read', 'PASS', '1 row visible, as expected');
  else
    insert into bingo_follows_test_results values ('TEST4_broad_authenticated_read', 'FAIL', seen || ' rows visible, expected 1');
  end if;
exception when others then
  perform set_config('role', 'postgres', true);
  insert into bingo_follows_test_results values ('TEST4_broad_authenticated_read', 'FAIL', 'unexpected error: ' || sqlerrm);
end $$;

do $$
declare
  seen int;
begin
  if not (select safe_to_proceed from bingo_follows_test_guard) then
    insert into bingo_follows_test_results values ('TEST5_anon_read', 'SKIP', 'guard failed');
    return;
  end if;
  perform set_config('role', 'anon', true);
  select count(*) into seen from public.bingo_follows where following_id='USER_B_UUID_HERE';
  perform set_config('role', 'postgres', true);
  if seen = 1 then
    insert into bingo_follows_test_results values ('TEST5_anon_read', 'PASS', '1 row visible to logged-out anon, as expected');
  else
    insert into bingo_follows_test_results values ('TEST5_anon_read', 'FAIL', seen || ' rows visible, expected 1');
  end if;
exception when others then
  perform set_config('role', 'postgres', true);
  insert into bingo_follows_test_results values ('TEST5_anon_read', 'FAIL', 'unexpected error: ' || sqlerrm);
end $$;

-- TEST 6: self-follow — expect the INSERT to be REJECTED by the check
-- constraint. Caught here, never sent to the client.
do $$
begin
  if not (select safe_to_proceed from bingo_follows_test_guard) then
    insert into bingo_follows_test_results values ('TEST6_self_follow_blocked', 'SKIP', 'guard failed');
    return;
  end if;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', '{"sub":"USER_A_UUID_HERE","role":"authenticated"}', true);
  insert into public.bingo_follows (follower_id, following_id)
    values ('USER_A_UUID_HERE', 'USER_A_UUID_HERE');
  perform set_config('role', 'postgres', true);
  insert into bingo_follows_test_results values ('TEST6_self_follow_blocked', 'FAIL', 'insert should have been rejected but succeeded');
  delete from public.bingo_follows where follower_id='USER_A_UUID_HERE' and following_id='USER_A_UUID_HERE'; -- undo if it somehow succeeded
exception when check_violation then
  perform set_config('role', 'postgres', true);
  insert into bingo_follows_test_results values ('TEST6_self_follow_blocked', 'PASS', 'rejected as expected: ' || sqlerrm);
when others then
  perform set_config('role', 'postgres', true);
  insert into bingo_follows_test_results values ('TEST6_self_follow_blocked', 'FAIL', 'unexpected error: ' || sqlerrm);
end $$;

-- TEST 7 (cleanup — GUARDED, same as every test above): only ever
-- touches the pair this script itself created in TEST 1. If the guard
-- failed, TEST 1 never ran, there is nothing of this script's to clean
-- up, and this step does nothing at all - it does NOT unconditionally
-- delete the pair the way earlier versions did.
do $$
declare
  remaining int;
begin
  if not (select safe_to_proceed from bingo_follows_test_guard) then
    insert into bingo_follows_test_results values ('TEST7_cleanup', 'SKIP', 'guard failed - nothing was created, nothing to clean up, pre-existing relationship left untouched');
    return;
  end if;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', '{"sub":"USER_A_UUID_HERE","role":"authenticated"}', true);
  delete from public.bingo_follows
    where follower_id='USER_A_UUID_HERE' and following_id='USER_B_UUID_HERE';
  perform set_config('role', 'postgres', true);
  select count(*) into remaining from public.bingo_follows
    where (follower_id='USER_A_UUID_HERE' and following_id='USER_B_UUID_HERE')
       or (follower_id='USER_B_UUID_HERE' and following_id='USER_A_UUID_HERE');
  if remaining = 0 then
    insert into bingo_follows_test_results values ('TEST7_cleanup', 'PASS', 'test pair fully removed');
  else
    insert into bingo_follows_test_results values ('TEST7_cleanup', 'FAIL', remaining || ' row(s) left behind - remove manually');
  end if;
exception when others then
  perform set_config('role', 'postgres', true);
  insert into bingo_follows_test_results values ('TEST7_cleanup', 'FAIL', 'unexpected error during cleanup: ' || sqlerrm);
end $$;

-- TEST 8: anon still cannot write. Caught here, never sent to the client.
do $$
begin
  if not (select safe_to_proceed from bingo_follows_test_guard) then
    insert into bingo_follows_test_results values ('TEST8_anon_write_blocked', 'SKIP', 'guard failed');
    return;
  end if;
  perform set_config('role', 'anon', true);
  insert into public.bingo_follows (follower_id, following_id)
    values ('USER_A_UUID_HERE', 'USER_B_UUID_HERE');
  perform set_config('role', 'postgres', true);
  insert into bingo_follows_test_results values ('TEST8_anon_write_blocked', 'FAIL', 'insert should have been rejected but succeeded');
  delete from public.bingo_follows where follower_id='USER_A_UUID_HERE' and following_id='USER_B_UUID_HERE'; -- undo if it somehow succeeded
exception when insufficient_privilege then
  perform set_config('role', 'postgres', true);
  insert into bingo_follows_test_results values ('TEST8_anon_write_blocked', 'PASS', 'rejected as expected: ' || sqlerrm);
when others then
  perform set_config('role', 'postgres', true);
  insert into bingo_follows_test_results values ('TEST8_anon_write_blocked', 'FAIL', 'unexpected error: ' || sqlerrm);
end $$;

-- Final summary. If GUARD is FAIL, every other row should read SKIP and
-- that is correct/expected - it means real data was protected. If GUARD
-- is PASS, every other row should read PASS.
select * from bingo_follows_test_results order by step;

-- Grants, checked separately from RLS — expect exactly:
--   anon           | SELECT
--   authenticated  | DELETE
--   authenticated  | INSERT
--   authenticated  | SELECT
select grantee, privilege_type from information_schema.role_table_grants
  where table_schema='public' and table_name='bingo_follows'
    and grantee in ('anon','authenticated')
  order by grantee, privilege_type;

-- Final state check: if GUARD passed, expect 0 (this script cleaned up
-- after itself). If GUARD failed, expect 1 (the real pre-existing
-- relationship, left exactly as it was).
select 'final state for this pair' as check, count(*) as row_count
  from public.bingo_follows
  where (follower_id='USER_A_UUID_HERE' and following_id='USER_B_UUID_HERE')
     or (follower_id='USER_B_UUID_HERE' and following_id='USER_A_UUID_HERE');
