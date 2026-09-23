-- ============================================================
-- DRAFT MIGRATION — Public Agent badge, masked email search, and a
-- database-backed commission-rate setting.
-- Status: DRAFT ONLY. NOT APPLIED. Do not run against any Supabase project
-- without explicit approval.
--
-- Background: an earlier read-only audit of this codebase (see session
-- notes) found the Agent/Super User role backend (bingo_user_roles, RLS,
-- and every grant/revoke/territory RPC in bingo_change2_super_user_security.sql
-- and bingo_change_agent_salary_and_business_access.sql) to be genuinely
-- solid — real table, real RLS, real SECURITY DEFINER RPCs, real audit
-- log. The gaps this migration addresses are narrower and specific:
--   1. No visitor can see that a member is a Bingo Agent — the only
--      existing UI for it (aaAgentProfilePanelHTML) is shown solely on
--      the Agent's OWN profile.
--   2. The Super User's email-search result currently returns the
--      member's full email to the browser (bingo_admin_find_user_by_email).
--   3. The Super User's "Commission rate (%)" input only ever wrote a
--      per-browser localStorage default (state.commissionRatePercent) —
--      there was no database column for it at all.
-- Nothing here touches salary/commission/withdrawal amounts themselves,
-- which already live in properly-RLS'd tables added by
-- bingo_change_agent_1000_target_salary_commission.sql.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Public-safe read of Agent identity (badge, territory, agent-since)
-- ------------------------------------------------------------
-- bingo_user_roles only has columns: user_id, role, territory, approved_by,
-- approved_at, updated_at, agent_since, agent_status — none of these are
-- sensitive on their own (commission/salary/withdrawal data live in
-- separate, still-restricted tables untouched by this policy). This
-- additive policy lets ANY authenticated visitor read a row ONLY when it
-- is an active agent — it does not loosen access to member/super_user rows,
-- and it does not touch the existing self-or-super-user policy already in
-- place (both policies are evaluated with OR, per Postgres RLS semantics).
do $$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='bingo_user_roles'
      and policyname='bingo_user_roles_public_agent_read'
  ) then
    create policy bingo_user_roles_public_agent_read on public.bingo_user_roles
      for select
      using (role = 'agent' and agent_status = 'active');
  end if;
end $$;

-- ------------------------------------------------------------
-- 2. Masked email in the Super User's search result
-- ------------------------------------------------------------
-- The exact email is still the required SEARCH INPUT (an exact,
-- case-insensitive match is still performed server-side), but the
-- confirmed member's own email is never sent back to the browser in full
-- — only a masked form, e.g. "j***@example.com". Full email is still
-- shown by definition in the input the Super User themself typed.
create or replace function public.bingo_mask_email(p_email text)
returns text
language sql
immutable
as $$
  select case
    when p_email is null or position('@' in p_email) < 2 then '••••••'
    else left(p_email, 1) || repeat('•', greatest(position('@' in p_email) - 2, 1))
         || substring(p_email from position('@' in p_email))
  end;
$$;

-- Supersedes the version in bingo_change2_super_user_security.sql — same
-- authorization check (only a real super_user may call this at all),
-- same exact-match search, only the returned `email` column changes from
-- the raw value to bingo_mask_email(u.email). No other column changes.
create or replace function public.bingo_admin_find_user_by_email(p_email text)
returns table (
  user_id         uuid,
  email           text,
  created_at      timestamptz,
  role            text,
  territory       text,
  full_name       text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may search accounts.';
  end if;

  return query
  select
    u.id,
    public.bingo_mask_email(u.email),
    u.created_at,
    coalesce(r.role, 'member'),
    coalesce(r.territory, ''),
    coalesce(p.full_name, trim(coalesce(p.first_name,'') || ' ' || coalesce(p.last_name,'')))
  from auth.users u
  left join public.bingo_user_roles r on r.user_id = u.id
  left join public.profiles p on p.id = u.id
  where lower(u.email) = lower(p_email)
  limit 1;
end;
$$;

revoke all on function public.bingo_admin_find_user_by_email(text) from public;
grant execute on function public.bingo_admin_find_user_by_email(text) to authenticated;

-- Note on "no result must not reveal whether an email exists outside the
-- authorized workflow": the function already returns zero rows for both
-- "no such account" and any other non-match, with no distinguishing error
-- text, and it is only reachable at all by a real super_user (checked
-- server-side via bingo_is_super_user(), not trusted from the client) —
-- this was already true before this migration and is unchanged here.

-- ------------------------------------------------------------
-- 3. Database-backed commission rate (replaces the browser-only default)
-- ------------------------------------------------------------
create table if not exists public.bingo_platform_settings (
  key         text primary key,
  value       jsonb not null,
  updated_by  uuid references auth.users(id),
  updated_at  timestamptz not null default now()
);
alter table public.bingo_platform_settings enable row level security;

do $$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='bingo_platform_settings'
      and policyname='bingo_platform_settings_select'
  ) then
    -- Any authenticated member may read the current commission rate (an
    -- Agent needs it to understand their own commission calculations) —
    -- nothing here is written except through the RPC below.
    create policy bingo_platform_settings_select on public.bingo_platform_settings
      for select to authenticated using (true);
  end if;
end $$;

-- Deliberately NOT seeded with a default 40% row here — until a real
-- Super User explicitly sets a rate via the RPC below, the key is simply
-- absent and the frontend must treat that as "no official rate set yet",
-- never silently treating the old browser-only 40% as if it were an
-- approved company-wide value.

create or replace function public.bingo_admin_set_commission_rate(p_rate_percent numeric)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may set the platform commission rate.';
  end if;
  if p_rate_percent is null or p_rate_percent < 0 or p_rate_percent > 100 then
    raise exception 'Commission rate must be between 0 and 100.';
  end if;

  insert into public.bingo_platform_settings (key, value, updated_by, updated_at)
  values ('agent_commission_rate_percent', to_jsonb(p_rate_percent), auth.uid(), now())
  on conflict (key) do update
    set value = to_jsonb(p_rate_percent), updated_by = auth.uid(), updated_at = now();

  insert into public.bingo_role_audit_log (actor_id, target_id, action, details)
  values (auth.uid(), auth.uid(), 'set_commission_rate',
          jsonb_build_object('rate_percent', p_rate_percent));
end;
$$;

revoke all on function public.bingo_admin_set_commission_rate(numeric) from public;
grant execute on function public.bingo_admin_set_commission_rate(numeric) to authenticated;

-- ============================================================
-- NOT INCLUDED IN THIS DRAFT (deliberately):
--  - Any change to bingo_agent_commission_ledger / bingo_agent_withdrawals
--    themselves, or to the RPCs that already read/write them
--    (bingo_agent_progress_bulletin, bingo_agent_commission_summary,
--    bingo_agent_request_commission_withdrawal, bingo_admin_review_agent_
--    withdrawal) — those are already real and RLS-correct; the frontend
--    change in this same patch stops reading the parallel localStorage
--    ledger and reads these existing, unmodified tables/RPCs instead.
--  - Wiring bingo_admin_set_commission_rate's stored rate into the actual
--    commission-crediting math inside the service-role-only
--    bingo_agent_credit_commission RPC — that function was not read in
--    full during this audit, so changing its commission-percent source is
--    left for a follow-up once its current body is confirmed line by line.
--  - Full per-business "who originally registered it" attribution for
--    vehicle listings specifically — the existing codebase already notes
--    (bingo_change_agent_salary_and_business_access.sql context) that
--    vehicle listings have no reliable backend owner_id column yet, which
--    is why Help Sell is deliberately disabled for vehicles; the same gap
--    limits a fully authoritative per-business attribution history to
--    property/stay/food-business records for now. The Super User history
--    view added in this patch's frontend reads the existing, already-real
--    bingo_role_audit_log (grant/revoke/territory-update rows), which is
--    accurate for agent-level history regardless of this gap.
--  - Extending the public Agent badge to every post/listing card site-wide
--    (Wall posts, Marketplace cards, Home Feed cards) — this migration
--    only adds the underlying public-read policy; the frontend change in
--    this same patch renders the badge on the Agent's own profile page
--    only. Extending it to every card render site needs a batched/cached
--    lookup strategy (avoiding one query per card) and is left as a
--    separate follow-up patch.
-- ============================================================
