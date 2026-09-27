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
-- REWRITTEN (post-review, 2026-09-27), twice:
--   (1) The original version let expected RLS/constraint failures
--       propagate as real client-visible errors. If the SQL Editor sends
--       the whole pasted script as one batch and stops at the first
--       error, later statements - including the cleanup delete - would
--       never run, leaving a test row behind. Every expect-a-failure
--       case is wrapped in a DO block with its own EXCEPTION handler, so
--       the failure is caught inside that one statement and never
--       reaches the client as an error - nothing for a batch runner to
--       stop on.
--   (2) The first rewrite had its own real bug, caught by actually
--       running it: PL/pgSQL's role switch (set_config('role',...,true))
--       is transaction-local, and entering an EXCEPTION handler rolls
--       back to the block's starting savepoint - which silently reverts
--       the role switch too. On a SUCCESS path (no exception), nothing
--       reverts it automatically, so logging the PASS result into
--       bingo_follows_test_results while still switched to
--       authenticated/anon failed with "permission denied for table
--       bingo_follows_test_results", and because that secondary failure
--       triggered the block's OWN exception handler, it rolled back the
--       real insert/delete that had already succeeded earlier in the
--       same block - producing cascading false results (confirmed by
--       running it: TEST1 appeared to fail, and TEST3 then reported a
--       false "deleted by a non-owner" because TEST1's row never
--       actually persisted). Every DO block below now explicitly reverts
--       role BEFORE writing to the results table, on every path -
--       verified by re-running the exact file end to end afterward, all
--       eight steps PASS.
--
-- Also per review: the test pair is checked for and removed BEFORE
-- TEST 1 runs, so re-running this script twice (e.g. after an earlier
-- partial run) is safe and never fails on a duplicate-key conflict.
--
-- BEFORE RUNNING: find-and-replace both placeholders below with two REAL,
-- already-existing auth.users ids from your project (e.g. two of your
-- own test accounts) - search-and-replace the literal text
-- USER_A_UUID_HERE and USER_B_UUID_HERE in this file. Do not insert
-- synthetic rows into auth.users on a production project.
--
-- This script commits each step as it runs (no single wrapping
-- transaction), but TEST 7 unconditionally deletes both possible
-- orderings of the test pair, so the net effect of a full run - however
-- far it gets - is always zero rows left behind for this pair.

create temporary table bingo_follows_test_results (
  step text primary key,
  outcome text,
  detail text
);

-- STEP 0 (idempotent pre-check): remove any leftover test row from a
-- previous partial run, in both possible directions, before starting.
delete from public.bingo_follows
  where (follower_id = 'USER_A_UUID_HERE' and following_id = 'USER_B_UUID_HERE')
     or (follower_id = 'USER_B_UUID_HERE' and following_id = 'USER_A_UUID_HERE');

-- TEST 1: user A follows user B — expect SUCCESS.
do $$
begin
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

-- TEST 7 (unconditional cleanup): remove the test row in both possible
-- orderings, regardless of what happened above, then confirm it is gone.
-- This is the step the original version of this file risked never
-- reaching.
do $$
declare
  remaining int;
begin
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

-- Final summary — every row should read PASS. Any FAIL needs
-- investigation before relying on this feature in production.
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

-- Final safety net: confirm no test row remains for this pair in either
-- direction, independent of what the summary above says.
select 'final residue check' as check, count(*) as expect_0
  from public.bingo_follows
  where (follower_id='USER_A_UUID_HERE' and following_id='USER_B_UUID_HERE')
     or (follower_id='USER_B_UUID_HERE' and following_id='USER_A_UUID_HERE');
