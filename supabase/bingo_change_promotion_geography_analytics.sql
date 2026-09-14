-- ============================================================================
-- BINGO CHANGE 10 — PROMOTION GEOGRAPHY AND ANALYTICS (Supabase backend)
--
-- Admin-controlled distribution (visibility/ranking/editorial), geo-scoped,
-- time-boxed, labeled — never presented as organic Trending — plus real,
-- deduplicated impression/click analytics. Additive only: reuses
-- bingo_role_audit_log (audit), bingo_moderation_cases (moderation
-- workload) and bingo_boost_activations (boost performance) from earlier
-- packets rather than duplicating them; does not touch bingo_ad_campaigns
-- (Change 07 — creative-based platform ads) or bingo_boost_quotes
-- (Change 09 — owner-paid boosts), which are separate, already-shipped
-- distribution mechanisms this one sits alongside.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. bingo_promotion_rules
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_promotion_rules (
  id             uuid primary key default gen_random_uuid(),
  post_type      text not null,
  post_id        text not null,
  objective      text not null check (objective in ('visibility','ranking','editorial')),
  geography      text not null default 'nationwide',
  ranking_weight numeric(8,2) not null default 100 check (ranking_weight >= 0),
  label          text not null default 'Promoted',
  status         text not null default 'active' check (status in ('active','expired','revoked')),
  starts_at      timestamptz not null default now(),
  expires_at     timestamptz not null,
  created_by     uuid not null references auth.users(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint bingo_promotion_rules_dates check (expires_at > starts_at)
);

alter table public.bingo_promotion_rules enable row level security;

-- Public (including guests) may read only currently-live rules — needed
-- to adjust feed ranking for every viewer, not just the Super User.
drop policy if exists bingo_promotion_rules_select_public on public.bingo_promotion_rules;
create policy bingo_promotion_rules_select_public on public.bingo_promotion_rules
  for select
  using (status = 'active' and starts_at <= now() and expires_at > now());

drop policy if exists bingo_promotion_rules_select_admin on public.bingo_promotion_rules;
create policy bingo_promotion_rules_select_admin on public.bingo_promotion_rules
  for select to authenticated
  using (public.bingo_is_super_user());
-- No insert/update/delete policy: only the RPCs below write here.

create index if not exists bingo_promotion_rules_post_idx on public.bingo_promotion_rules(post_type, post_id, status);
create index if not exists bingo_promotion_rules_live_idx on public.bingo_promotion_rules(status, starts_at, expires_at);

-- ---------------------------------------------------------------------------
-- 2. bingo_admin_create_promotion / revoke / list — Super User only
-- ---------------------------------------------------------------------------
create or replace function public.bingo_admin_create_promotion(
  p_post_type text, p_post_id text, p_objective text, p_geography text,
  p_ranking_weight numeric, p_label text, p_starts_at timestamptz, p_expires_at timestamptz
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may create a promotion.';
  end if;
  if coalesce(p_post_id,'') = '' then raise exception 'A post is required.'; end if;
  if not (p_objective = any(array['visibility','ranking','editorial'])) then
    raise exception 'Invalid promotion objective.';
  end if;
  if p_expires_at is null or p_starts_at is null or p_expires_at <= p_starts_at then
    raise exception 'Expiry must be later than the start date.';
  end if;

  insert into public.bingo_promotion_rules(post_type, post_id, objective, geography, ranking_weight, label, starts_at, expires_at, created_by)
  values (p_post_type, p_post_id, p_objective, coalesce(nullif(p_geography,''),'nationwide'),
          greatest(0, coalesce(p_ranking_weight,100)), coalesce(nullif(p_label,''),'Promoted'), p_starts_at, p_expires_at, auth.uid())
  returning id into v_id;

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), auth.uid(), 'promotion_created', jsonb_build_object(
    'promotion_id', v_id, 'post_type', p_post_type, 'post_id', p_post_id,
    'objective', p_objective, 'geography', p_geography, 'ranking_weight', p_ranking_weight
  ));

  return v_id;
end;
$$;

revoke all on function public.bingo_admin_create_promotion(text,text,text,text,numeric,text,timestamptz,timestamptz) from public;
grant execute on function public.bingo_admin_create_promotion(text,text,text,text,numeric,text,timestamptz,timestamptz) to authenticated;

create or replace function public.bingo_admin_revoke_promotion(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may revoke a promotion.';
  end if;
  update public.bingo_promotion_rules set status = 'revoked', updated_at = now() where id = p_id;
  if not found then raise exception 'Promotion not found.'; end if;

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), auth.uid(), 'promotion_revoked', jsonb_build_object('promotion_id', p_id));
end;
$$;

revoke all on function public.bingo_admin_revoke_promotion(uuid) from public;
grant execute on function public.bingo_admin_revoke_promotion(uuid) to authenticated;

create or replace function public.bingo_admin_list_promotions()
returns setof public.bingo_promotion_rules
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.bingo_promotion_rules
  where public.bingo_is_super_user()
  order by created_at desc
  limit 200;
$$;

revoke all on function public.bingo_admin_list_promotions() from public;
grant execute on function public.bingo_admin_list_promotions() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. bingo_analytics_events — real, deduplicated impressions/clicks.
--    Never readable directly (INSERT-only via the RPC below, SELECT
--    restricted to the Super User's own summary RPC), so nothing client-
--    side can ever read back and re-display a manufactured count.
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_analytics_events (
  id           uuid primary key default gen_random_uuid(),
  event_type   text not null check (event_type in ('impression','click')),
  post_type    text not null,
  post_id      text not null,
  slot_id      text,
  session_key  text not null,
  viewer_id    uuid references auth.users(id),
  event_bucket timestamptz not null,
  created_at   timestamptz not null default now()
);

-- One row per (event, post, session, minute) — a refreshed page or a
-- replayed request inside the same minute is a silent no-op, not a
-- second impression/click.
create unique index if not exists bingo_analytics_dedupe
  on public.bingo_analytics_events(event_type, post_type, post_id, session_key, event_bucket);

create index if not exists bingo_analytics_post_idx on public.bingo_analytics_events(post_type, post_id, event_type);

alter table public.bingo_analytics_events enable row level security;
-- No select/insert/update/delete policy for anyone: every write goes
-- through bingo_record_analytics_event (SECURITY DEFINER), every read
-- through bingo_promotion_analytics_summary (Super User only, below).

create or replace function public.bingo_record_analytics_event(
  p_event_type text, p_post_type text, p_post_id text, p_slot_id text, p_session_key text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (p_event_type = any(array['impression','click'])) then return; end if;
  if coalesce(p_post_id,'') = '' or coalesce(p_session_key,'') = '' then return; end if;

  -- The unique index is the real rate limit: at most one row per
  -- event/post/session per minute, however many times this is called.
  insert into public.bingo_analytics_events(event_type, post_type, post_id, slot_id, session_key, viewer_id, event_bucket)
  values (p_event_type, p_post_type, p_post_id, p_slot_id, p_session_key, auth.uid(), date_trunc('minute', now()))
  on conflict (event_type, post_type, post_id, session_key, event_bucket) do nothing;
end;
$$;

revoke all on function public.bingo_record_analytics_event(text,text,text,text,text) from public;
grant execute on function public.bingo_record_analytics_event(text,text,text,text,text) to authenticated, anon;

-- ---------------------------------------------------------------------------
-- 4. bingo_promotion_analytics_summary — Super User dashboard aggregate:
--    real impressions/clicks/CTR per promoted post, moderation workload
--    (Change 06) and recent Agent/admin actions (existing audit log),
--    boost performance (Change 09's activations) — one call, no new
--    duplicate ledgers.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_promotion_analytics_summary()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_promotions jsonb;
  v_open_cases integer;
  v_recent_boosts integer;
  v_agent_actions integer;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may view analytics.';
  end if;

  select coalesce(jsonb_agg(row), '[]'::jsonb) into v_promotions
  from (
    select
      r.id as promotion_id, r.post_type, r.post_id, r.objective, r.geography, r.label, r.status,
      r.starts_at, r.expires_at,
      coalesce((select count(*) from public.bingo_analytics_events e where e.post_type = r.post_type and e.post_id = r.post_id and e.event_type = 'impression'), 0) as impressions,
      coalesce((select count(*) from public.bingo_analytics_events e where e.post_type = r.post_type and e.post_id = r.post_id and e.event_type = 'click'), 0) as clicks
    from public.bingo_promotion_rules r
    order by r.created_at desc
    limit 100
  ) row;

  select count(*) into v_open_cases from public.bingo_moderation_cases where status = 'open';
  select count(*) into v_recent_boosts from public.bingo_boost_activations where activated_at >= now() - interval '30 days';
  select count(*) into v_agent_actions from public.bingo_role_audit_log
  where (action like 'help_sell_%' or action like 'boost_%' or action like 'invite_agent%')
    and created_at >= now() - interval '30 days';

  return jsonb_build_object(
    'promotions', v_promotions,
    'open_moderation_cases', v_open_cases,
    'boosts_last_30_days', v_recent_boosts,
    'agent_actions_last_30_days', v_agent_actions
  );
end;
$$;

revoke all on function public.bingo_promotion_analytics_summary() from public;
grant execute on function public.bingo_promotion_analytics_summary() to authenticated;
