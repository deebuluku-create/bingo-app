-- Backup and rollback procedure for the boosts rename draft
-- (20260927_bingo_boosts_rename_DRAFT_DO_NOT_APPLY.sql). Not applied
-- automatically by anything — run the relevant section yourself, at the
-- point described.

-- =====================================================================
-- STEP A — BACKUP. Run this BEFORE applying the rename draft, even
-- though the table currently has zero rows: it costs nothing, it also
-- captures the exact live column list/types (useful evidence if the
-- live schema differs at all from what this draft assumes), and it
-- means the same procedure is safe to reuse later even if rows exist by
-- the time you actually apply it.
--
-- CORRECTION (post-review, 2026-09-27): the original version of this
-- step created the backup as an ordinary table in the `public` schema.
-- That is wrong for a table holding payment/phone-number data on this
-- project specifically, for two compounding reasons confirmed by
-- testing (see the companion follows migration for the same finding
-- applied there): CREATE TABLE ... AS never copies RLS or policies from
-- the source, so the backup would start with RLS OFF; and the live
-- project grants broad default privileges to anon/authenticated on new
-- public tables, so the moment it existed, any authenticated (and
-- possibly anon) caller could read - and, with RLS off, nothing would
-- stop write access either - a full copy of every boost/payment row
-- ever taken. Per-table REVOKE (as used for bingo_follows) would still
-- leave the table reachable to anyone who discovers its name via schema
-- USAGE on `public`, which everyone already has. The backup is moved
-- into its own schema with schema-level USAGE revoked from
-- anon/authenticated entirely - a stronger control than a table-level
-- REVOKE, since without USAGE on the schema no role can reference
-- anything inside it at all, regardless of any table-level grant.
-- =====================================================================
create schema if not exists bingo_backups;
revoke all on schema bingo_backups from public;
revoke all on schema bingo_backups from anon, authenticated;
-- service_role/postgres (table owner) already have implicit access;
-- this grant is explicit only for clarity, matching the "verify grants
-- separately" principle applied throughout this delivery.
grant usage on schema bingo_backups to service_role;

create table if not exists bingo_backups.bingo_boosts_backup_20260927 as
  table public.auto_arcade_boosts;
revoke all on table bingo_backups.bingo_boosts_backup_20260927 from public;
revoke all on table bingo_backups.bingo_boosts_backup_20260927 from anon, authenticated;
grant select on bingo_backups.bingo_boosts_backup_20260927 to service_role;

-- Confirm the backup matches row-for-row before proceeding.
select
  (select count(*) from public.auto_arcade_boosts) as live_row_count,
  (select count(*) from bingo_backups.bingo_boosts_backup_20260927) as backup_row_count;

-- Confirm anon/authenticated have NO access at all to the backup schema
-- or table. Schema-level USAGE isn't covered by information_schema (it's
-- a Postgres-specific ACL, not part of the SQL standard's
-- information_schema views) - has_schema_privilege() is the correct,
-- tested way to check it; verified locally that it correctly reports
-- false for anon/authenticated and true for service_role/postgres
-- immediately after the REVOKE/GRANT pair above.
-- Expect zero rows from this (no table-level grants to either role):
select * from information_schema.role_table_grants
  where table_schema='bingo_backups' and grantee in ('anon','authenticated');
-- Expect false/false (no schema USAGE for either role):
select rolname, has_schema_privilege(rolname, 'bingo_backups', 'usage') as has_usage
  from pg_roles where rolname in ('anon','authenticated');

-- =====================================================================
-- STEP B — ROLLBACK. Run this ONLY if something goes wrong after
-- applying the rename draft (in particular: if mpesa-boost starts
-- failing after the rename, before it has been redeployed). This
-- reverses the rename+view exactly, with no data loss regardless of
-- whether any rows were written in the meantime, since it operates on
-- whichever object currently holds the real data (bingo_boosts) rather
-- than the backup snapshot.
-- =====================================================================
do $$
begin
  if to_regclass('public.auto_arcade_boosts') is not null
     and (select relkind from pg_class where oid = 'public.auto_arcade_boosts'::regclass) = 'v' then
    drop view public.auto_arcade_boosts;
  end if;
  if to_regclass('public.bingo_boosts') is not null
     and to_regclass('public.auto_arcade_boosts') is null then
    alter table public.bingo_boosts rename to auto_arcade_boosts;
  end if;
end
$$;

-- Verify the rollback: mpesa-boost's own literal table name should be
-- queryable again as a real table (relkind='r'), not a view.
select relname, relkind from pg_class where oid = 'public.auto_arcade_boosts'::regclass;

-- =====================================================================
-- STEP C — CLEANUP (only once mpesa-boost has been redeployed against
-- bingo_boosts AND confirmed stable in production for a reasonable
-- period — do not run this in the same session as STEP A/B).
-- =====================================================================
-- drop view if exists public.auto_arcade_boosts;
-- drop table if exists public.bingo_boosts_backup_20260927;
