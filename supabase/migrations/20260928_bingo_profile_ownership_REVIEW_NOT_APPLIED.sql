-- ============================================================
-- BINGO PROFILE OWNERSHIP - REVIEW ONLY, NOT APPLIED
--
-- Apply ONLY if supabase/tests/profile_ownership_LIVE_CHECK_ROLLBACK.sql
-- shows that member B can update or upsert member A's profile (step 2
-- returns a row, or step 3 is accepted). If the live check already
-- rejects both, this file is unnecessary.
--
-- What it does: adds RESTRICTIVE policies. A restrictive policy is ANDed
-- with every existing permissive policy, so this can only NARROW access -
-- it never grants anything new and does not touch SELECT (public profile
-- reads keep working exactly as today). Existing policies are not dropped.
--   INSERT : only a row whose id = auth.uid()
--   UPDATE : only the caller's own row, and it must stay their own row
--   DELETE : only the caller's own row
-- Covers the app's real write path: profiles.upsert({id: user.id, ...}),
-- i.e. INSERT ... ON CONFLICT (id) DO UPDATE.
-- service_role (server functions) bypasses RLS and is unaffected.
-- ============================================================
do $$
begin
  if to_regclass('public.profiles') is null then
    raise exception 'public.profiles not found - nothing to secure';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass) then
    -- Enabling RLS here without first confirming the existing SELECT
    -- policies would hide every profile from the app. Stop and review.
    raise exception 'RLS is DISABLED on public.profiles. Review the SELECT policies with 20260928_bingo_profile_INSPECT_READ_ONLY.sql before enabling it; this file will not enable it for you.';
  end if;
end $$;

drop policy if exists bingo_profiles_insert_only_own on public.profiles;
create policy bingo_profiles_insert_only_own on public.profiles
  as restrictive for insert to anon, authenticated
  with check (id = (select auth.uid()));

drop policy if exists bingo_profiles_update_only_own on public.profiles;
create policy bingo_profiles_update_only_own on public.profiles
  as restrictive for update to anon, authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists bingo_profiles_delete_only_own on public.profiles;
create policy bingo_profiles_delete_only_own on public.profiles
  as restrictive for delete to anon, authenticated
  using (id = (select auth.uid()));

-- after applying, re-run the live check: step 2 -> 0, step 3 -> RLS error
