-- DRAFT — DO NOT APPLY YET. Prepared for review only, per explicit
-- instruction not to run this rename, redeploy mpesa-boost, merge to
-- main, or trigger a real M-Pesa payment in this stage.
--
-- Live facts this draft is built from (as reported, not independently
-- verified from this sandbox — no live Supabase access here):
--   - auto_arcade_boosts exists, has RLS enabled, and currently has ZERO
--     ROWS.
--   - Deployed mpesa-boost is version 11 and still inserts/updates/selects
--     against auto_arcade_boosts by that literal name.
--
-- Zero rows means there is no payment history at risk from the RENAME
-- itself — Postgres ALTER TABLE RENAME preserves rows (none exist),
-- indexes, RLS policies and triggers regardless of row count, since all
-- of those are tracked by object id, not by name. The real risk here is
-- entirely operational: an in-flight STK push between "rename applied"
-- and "Edge Function confirmed working against the new arrangement"
-- would hit whatever the compatibility view does NOT correctly cover.
--
-- What has been tested (see delivery report for the full transcript):
--   Built a representative table with the exact column set mpesa-boost's
--   repository copy inserts/updates (listing_id, user_id, seller_id,
--   days, duration_days, price_per_day, total_amount, amount, phone,
--   payment_status, boost_status, status, starts_at, ends_at,
--   created_at), enabled RLS on it, created a role with BYPASSRLS
--   (mirroring Supabase's service_role, which is what mpesa-boost
--   authenticates as), created exactly the view proposed below over it,
--   and ran every one of mpesa-boost's actual operations through the
--   VIEW under that BYPASSRLS role: the initial INSERT ... RETURNING,
--   the payment_status="payment_failed" UPDATE, the boost lookup SELECT
--   by id, the existingBoost eq+eq+gt+order+limit SELECT, and the
--   activation UPDATE (status/starts_at/ends_at). Every one worked
--   identically through the view as through the base table. Also
--   confirmed RLS still applies correctly THROUGH the view for a
--   non-bypassrls (authenticated) role: the boost's own owner can read
--   their row, an unrelated authenticated user cannot.
--
-- What this test does NOT prove, and why the rename is still gated:
--   1. This ran through raw SQL role/JWT-claim simulation, not through
--      an actual PostgREST instance. Supabase's supabase-js
--      `.insert().select().single()` goes through PostgREST, which
--      auto-detects updatable views via the same Postgres rules tested
--      here, but that HTTP-layer path itself was not exercised.
--   2. The real auto_arcade_boosts table's exact live column list,
--      constraints, defaults and any triggers were not inspected (no
--      live access) — this draft assumes the schema implied by
--      mpesa-boost's own insert/update payloads, nothing more or less.
--   3. The live table's actual current RLS policy content was not
--      inspected. A RENAME does not change existing policies, so this is
--      low risk regardless — but confirm with
--      `select * from pg_policies where tablename='auto_arcade_boosts';`
--      before applying, simply to know what you're renaming.
--
-- RECOMMENDED order (see delivery report §Deployment order for the full
-- version including the follows stage):
--   1. Run the two verification queries below RIGHT BEFORE applying,
--      to reconfirm the live facts above still hold (in particular, that
--      the row count is still 0 and no payment is mid-flight):
--        select count(*) from public.auto_arcade_boosts;
--        select * from pg_policies where tablename='auto_arcade_boosts';
--   2. Take the backup snapshot (see companion file
--      20260927_bingo_boosts_backup_and_rollback.sql).
--   3. Apply this rename+view migration.
--   4. Verify with a real write, not just a health check. mpesa-boost's
--      GET health check (per its own source) only reports whether
--      environment variables are configured - it never touches
--      auto_arcade_boosts/bingo_boosts at all, so it proves nothing
--      about whether the deployed function can still write through the
--      view. The only real verification is a POST create_boost call, in
--      the M-Pesa SANDBOX environment only, confirming end to end that
--      the still-deployed (old-name) function writes through the view
--      into bingo_boosts with no error, the status-poll query the
--      frontend uses can read it back, and the sandbox callback
--      activates it correctly.
--   5. Only once step 4 is confirmed: redeploy mpesa-boost from this
--      repository's updated copy (which already references bingo_boosts
--      directly), diffing against the live function first per its own
--      header warning.
--   6. Only once step 5 is confirmed stable: drop the compatibility view
--      (see the rollback file) — it is no longer needed once nothing
--      references the old name.

do $$
begin
  if to_regclass('public.auto_arcade_boosts') is not null
     and to_regclass('public.bingo_boosts') is null then
    alter table public.auto_arcade_boosts rename to bingo_boosts;
  end if;
end
$$;

do $$
begin
  if to_regclass('public.bingo_boosts') is not null
     and to_regclass('public.auto_arcade_boosts') is null then
    execute 'create view public.auto_arcade_boosts with (security_invoker = true) as select * from public.bingo_boosts';
    -- Match whatever grants the live table already carries for the
    -- roles that need it. service_role has BYPASSRLS and typically
    -- already has implicit broad access via Supabase's default schema
    -- grants; the explicit grant below is the same "verify separately
    -- from RLS" principle applied here as for bingo_follows.
    execute 'grant select, insert, update, delete on public.auto_arcade_boosts to service_role';
    execute 'grant select on public.auto_arcade_boosts to authenticated';
  end if;
end
$$;
