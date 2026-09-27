-- Bingo App Kenya — bingo_follows (separate, reviewable migration).
--
-- Neither auto_arcade_follows nor bingo_follows exists in the live schema
-- (confirmed 2026-09-27) even though the frontend has been calling
-- bingo_follows all along - the follow/unfollow feature has been fully
-- non-functional in production. This creates the table fresh; there is no
-- existing data to migrate or preserve.
--
-- Frontend read/write contract extracted directly from
-- BINGO_MASTER_CURRENT_VERIFIED.html (every call site):
--   aaSyncFollowNetwork():
--     select("following_id").in("following_id", wanted)   -- follower COUNTS for a batch of arbitrary profiles (not just the caller)
--     select("follower_id").in("follower_id", wanted)      -- following COUNTS for a batch of arbitrary profiles
--     select("following_id").eq("follower_id", me)          -- who I follow (for local "Following" cache)
--   aaToggleFollowSeller():
--     insert({follower_id: mine, following_id: key})        -- follow
--     delete().eq("follower_id", mine).eq("following_id", key) -- unfollow
--   aaProfileFollowersLiveHTML():
--     select("follower_id").eq("following_id", me).limit(100) -- my own followers list
--   reverseFollowExists() (mutual-follow / "message" gating):
--     select("follower_id").eq("follower_id", sid).eq("following_id", me).maybeSingle() -- does seller `sid` follow me back
--
-- Column contract required by the above: follower_id, following_id only.
-- No frontend code reads/writes any other column, so none is added.
--
-- IMPORTANT design finding from this contract: aaSyncFollowNetwork's two
-- ".in(...)" count queries target ARBITRARY OTHER profiles being viewed,
-- not just the signed-in caller's own id. A naive "only see rows you're
-- a party to" SELECT policy would silently make follower/following
-- counts wrong (undercounted) on every profile except the viewer's own,
-- since it would hide rows between two other unrelated users. Follow
-- graphs are the same kind of public metadata Twitter/Instagram expose
-- (who-follows-whom and the counts), so SELECT is granted broadly; only
-- INSERT/DELETE are restricted to the row's own follower_id. This was
-- verified against a real (local, disposable) Postgres instance running
-- actual Postgres RLS - see the delivery report for the exact test
-- transcript - not just reasoned about.
--
-- Also note: aaFollowStatsHTML/aaFollowTopControlHTML call
-- aaEnsureFollowStats() for ANY viewed profile with no
-- state.isLoggedIn gate, meaning a logged-out visitor's anon-role
-- session performs the same count reads. SELECT is therefore granted to
-- both `authenticated` and `anon` (write stays authenticated-only) so
-- counts actually populate for logged-out visitors too, matching "the
-- reads needed for counts ... must work" - granting only to
-- `authenticated` was tested and confirmed to fail for anon with a hard
-- "permission denied" (not a silent empty result); the frontend already
-- tolerates that failure gracefully (stats just don't populate), but it
-- is a real functional gap this migration closes rather than leaves as a
-- documented limitation.

create table if not exists public.bingo_follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  following_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint bingo_follows_no_self_follow check (follower_id <> following_id)
);

-- The primary key already indexes follower_id as its leading column;
-- following_id needs its own index for the reverse-direction lookups
-- (follower lists, follower counts, mutual-follow checks).
create index if not exists bingo_follows_following_id_idx
  on public.bingo_follows (following_id);

alter table public.bingo_follows enable row level security;

drop policy if exists bingo_follows_read_all on public.bingo_follows;
create policy bingo_follows_read_all
  on public.bingo_follows for select
  to authenticated, anon
  using (true);

drop policy if exists bingo_follows_owner_insert on public.bingo_follows;
create policy bingo_follows_owner_insert
  on public.bingo_follows for insert
  to authenticated
  with check (follower_id = auth.uid());

drop policy if exists bingo_follows_owner_delete on public.bingo_follows;
create policy bingo_follows_owner_delete
  on public.bingo_follows for delete
  to authenticated
  using (follower_id = auth.uid());

-- Grants verified separately from RLS: RLS alone does not grant table
-- access, and a GRANT without a passing policy still blocks every row -
-- both need to be correct together.
--
-- CORRECTION (post-review, 2026-09-27): the live project grants broad
-- default table privileges to anon/authenticated (confirmed by review
-- against the live project, and independently reproduced here in a
-- local Postgres instance with an equivalent
-- `alter default privileges in schema public grant all on tables to
-- anon, authenticated` in place). Under that condition, a brand-new
-- table created by anything OTHER than an explicit REVOKE first
-- inherits SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES and
-- TRIGGER for BOTH roles regardless of which narrower GRANTs a
-- migration goes on to add - reproduced and confirmed locally: the
-- GRANTs below, run without the REVOKE first, left anon and
-- authenticated with all seven privileges each, not the intended
-- three. This matters beyond correctness: TRUNCATE is not governed by
-- row-level security at all, so if it were left in place, any
-- authenticated (and, on this project, even anon) caller could wipe
-- the entire follow graph in one statement with RLS providing no
-- protection whatsoever.
--
-- The fix is to REVOKE ALL from both roles on this specific table
-- first, then GRANT only the intended subset - REVOKE/GRANT are
-- table-level, not schema-level, so this doesn't touch the default
-- privilege setting itself (which is out of scope for a migration on
-- one table) and needs no assumption about what that default is: it is
-- correct whether the live default is broad, narrow, or absent, since
-- it fully overrides whatever the table would otherwise have inherited.
-- Confirmed locally, with the reproduced broad-default condition still
-- in place: after this REVOKE+GRANT pair, `anon` has exactly SELECT and
-- `authenticated` has exactly SELECT/INSERT/DELETE - no UPDATE,
-- TRUNCATE, REFERENCES or TRIGGER for either role. No UPDATE is
-- granted; nothing in the frontend contract above ever updates a follow
-- row.
revoke all on public.bingo_follows from anon, authenticated;
grant select on public.bingo_follows to authenticated, anon;
grant insert, delete on public.bingo_follows to authenticated;

-- Verification query — run this on the LIVE project immediately after
-- applying, and confirm the result is EXACTLY these four rows (no more,
-- no fewer; in particular no UPDATE/TRUNCATE/REFERENCES/TRIGGER for
-- either role):
--   anon           | SELECT
--   authenticated  | DELETE
--   authenticated  | INSERT
--   authenticated  | SELECT
--
--   select grantee, privilege_type from information_schema.role_table_grants
--   where table_schema='public' and table_name='bingo_follows'
--     and grantee in ('anon','authenticated')
--   order by grantee, privilege_type;
