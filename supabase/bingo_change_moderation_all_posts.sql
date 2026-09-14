-- ============================================================================
-- BINGO CHANGE 06 — MODERATION AND ALL POSTS ADMIN (Supabase backend)
--
-- A report never automatically punishes anyone: it opens a
-- bingo_moderation_cases row for review. Every state change (dismiss,
-- request edit, hide, restore, delete, escalate) runs through
-- bingo_moderation_action, a SECURITY DEFINER RPC with a locked search_path
-- that re-verifies the caller's role from bingo_user_roles (Change 03) on
-- every call and writes an immutable audit entry. An Agent may act only on
-- a case explicitly assigned to them, and only with the two
-- least-privileged actions (dismiss, request_edit) — hide/restore/delete/
-- escalate are Super User only.
--
-- Additive only. This does not know or need to know the exact existing
-- SELECT policies on food_businesses, food_menu_items or property_listings:
-- the moderation gate below is added as a RESTRICTIVE policy, which
-- Postgres ANDs against whatever PERMISSIVE policies those tables already
-- have, so a hidden row disappears from public view without touching or
-- risking anything already deployed. Run once in the Supabase SQL Editor.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. moderation_status — lets a hidden item disappear from public browsing
--    while the owner and moderators can still see it.
-- ---------------------------------------------------------------------------
alter table public.food_businesses   add column if not exists moderation_status text not null default 'visible' check (moderation_status in ('visible','hidden'));
alter table public.food_menu_items   add column if not exists moderation_status text not null default 'visible' check (moderation_status in ('visible','hidden'));
alter table public.property_listings add column if not exists moderation_status text not null default 'visible' check (moderation_status in ('visible','hidden'));

-- ---------------------------------------------------------------------------
-- 2. bingo_moderation_cases — one row per report / admin case
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_moderation_cases (
  id                 uuid primary key default gen_random_uuid(),
  target_type        text not null check (target_type in ('vehicle','property','stay','food_business','food_menu_item','community_member','solution_message','job','candidate','seller_profile','other')),
  target_id          text not null,
  target_owner_id    uuid,
  reporter_id        uuid not null references auth.users(id),
  reason             text not null,
  details            text not null default '',
  status             text not null default 'open' check (status in ('open','dismissed','edit_requested','hidden','resolved_deleted','escalated')),
  assigned_agent_id  uuid references auth.users(id),
  resolution_reason  text not null default '',
  resolved_by        uuid references auth.users(id),
  resolved_at        timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

alter table public.bingo_moderation_cases enable row level security;

drop policy if exists bingo_moderation_cases_select on public.bingo_moderation_cases;
create policy bingo_moderation_cases_select on public.bingo_moderation_cases
  for select
  using (
    auth.uid() = reporter_id
    or auth.uid() = assigned_agent_id
    or public.bingo_is_super_user()
  );

-- A signed-in member may open a case about someone else's content. The row
-- always starts open, unassigned and unresolved; only the SECURITY DEFINER
-- RPCs below can change those fields afterwards.
drop policy if exists bingo_moderation_cases_insert on public.bingo_moderation_cases;
create policy bingo_moderation_cases_insert on public.bingo_moderation_cases
  for insert
  with check (
    auth.uid() = reporter_id
    and status = 'open'
    and assigned_agent_id is null
    and resolved_by is null
    and resolved_at is null
  );

-- No update/delete policy for anyone, including the Super User — every
-- state change goes through bingo_moderation_action / bingo_moderation_assign
-- so there is always an audit trail.

create index if not exists bingo_moderation_cases_status_idx on public.bingo_moderation_cases(status);
create index if not exists bingo_moderation_cases_assigned_idx on public.bingo_moderation_cases(assigned_agent_id);
create index if not exists bingo_moderation_cases_target_idx on public.bingo_moderation_cases(target_type, target_id);

-- ---------------------------------------------------------------------------
-- 3. bingo_moderation_notifications — same pending-Inbox delivery pattern as
--    bingo_role_notifications (Change 03): a message waits here until the
--    owner's next session delivers it into their existing Bingo Inbox.
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_moderation_notifications (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  case_id     uuid references public.bingo_moderation_cases(id) on delete set null,
  message     text not null,
  delivered   boolean not null default false,
  created_at  timestamptz not null default now()
);

alter table public.bingo_moderation_notifications enable row level security;

drop policy if exists bingo_moderation_notifications_select on public.bingo_moderation_notifications;
create policy bingo_moderation_notifications_select on public.bingo_moderation_notifications
  for select
  using (auth.uid() = user_id);

drop policy if exists bingo_moderation_notifications_update on public.bingo_moderation_notifications;
create policy bingo_moderation_notifications_update on public.bingo_moderation_notifications
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 4. bingo_moderation_audit_log — append-only, Super User read only
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_moderation_audit_log (
  id          bigint generated always as identity primary key,
  actor_id    uuid not null references auth.users(id),
  case_id     uuid references public.bingo_moderation_cases(id) on delete set null,
  target_type text not null default '',
  target_id   text not null default '',
  action      text not null,
  reason      text not null default '',
  created_at  timestamptz not null default now()
);

alter table public.bingo_moderation_audit_log enable row level security;

drop policy if exists bingo_moderation_audit_log_select on public.bingo_moderation_audit_log;
create policy bingo_moderation_audit_log_select on public.bingo_moderation_audit_log
  for select
  using (public.bingo_is_super_user());
-- No insert/update/delete policy: only bingo_moderation_action writes here.

-- ---------------------------------------------------------------------------
-- 5. RESTRICTIVE moderation gate on the three server-backed content tables.
--    RESTRICTIVE policies AND against the OR'd set of existing PERMISSIVE
--    SELECT policies, so this narrows visibility without needing to touch
--    (or even know the exact text of) whatever those already are.
-- ---------------------------------------------------------------------------
drop policy if exists food_businesses_moderation_gate on public.food_businesses;
create policy food_businesses_moderation_gate on public.food_businesses as restrictive
  for select
  using (moderation_status = 'visible' or auth.uid() = user_id or public.bingo_is_super_user());

drop policy if exists food_menu_items_moderation_gate on public.food_menu_items;
create policy food_menu_items_moderation_gate on public.food_menu_items as restrictive
  for select
  using (moderation_status = 'visible' or auth.uid() = user_id or public.bingo_is_super_user());

drop policy if exists property_listings_moderation_gate on public.property_listings;
create policy property_listings_moderation_gate on public.property_listings as restrictive
  for select
  using (moderation_status = 'visible' or auth.uid() = user_id or public.bingo_is_super_user());

-- ---------------------------------------------------------------------------
-- 6. bingo_submit_report — creates a case with the caller verified as
--    reporter_id server-side (defense in depth on top of the RLS check
--    above).
-- ---------------------------------------------------------------------------
create or replace function public.bingo_submit_report(
  p_target_type text,
  p_target_id text,
  p_target_owner_id uuid,
  p_reason text,
  p_details text default ''
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.';
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'A reason is required.';
  end if;

  insert into public.bingo_moderation_cases(target_type,target_id,target_owner_id,reporter_id,reason,details)
  values (p_target_type,p_target_id,p_target_owner_id,auth.uid(),btrim(p_reason),coalesce(p_details,''))
  returning id into v_case_id;

  return v_case_id;
end;
$$;

revoke all on function public.bingo_submit_report(text,text,uuid,text,text) from public;
grant execute on function public.bingo_submit_report(text,text,uuid,text,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. bingo_moderation_assign — Super User only: puts a case into an
--    Agent's queue. The Agent must already hold the 'agent' role.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_moderation_assign(
  p_case_id uuid,
  p_agent_id uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may assign moderation cases.';
  end if;
  if not exists (select 1 from public.bingo_user_roles where user_id = p_agent_id and role = 'agent') then
    raise exception 'Target account is not an approved Agent.';
  end if;

  update public.bingo_moderation_cases
  set assigned_agent_id = p_agent_id, updated_at = now()
  where id = p_case_id;

  if not found then
    raise exception 'Case not found.';
  end if;

  insert into public.bingo_moderation_audit_log (actor_id, case_id, action, reason)
  values (auth.uid(), p_case_id, 'assign', 'Assigned to Agent');
end;
$$;

revoke all on function public.bingo_moderation_assign(uuid,uuid) from public;
grant execute on function public.bingo_moderation_assign(uuid,uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. bingo_moderation_action — dismiss / request_edit / hide / restore /
--    delete / escalate. The single authority for every state change.
--
--    Deliberately out of scope: any account-level punitive action (ban,
--    suspend). 'escalate' only flags the case and notifies the Super User
--    dashboard — a genuine account suspension needs its own explicit,
--    separately reviewed permission and is not implemented by this packet.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_moderation_action(
  p_case_id uuid,
  p_action text,
  p_reason text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case record;
  v_caller_role text;
  v_agent_actions text[] := array['dismiss','request_edit'];
  v_super_actions text[] := array['dismiss','request_edit','hide','restore','delete','escalate'];
  v_new_status text;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.';
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'A reason is required.';
  end if;

  select * into v_case from public.bingo_moderation_cases where id = p_case_id for update;
  if not found then
    raise exception 'Case not found.';
  end if;

  select role into v_caller_role from public.bingo_user_roles where user_id = auth.uid();

  if v_caller_role = 'super_user' then
    if not (p_action = any(v_super_actions)) then
      raise exception 'Unknown moderation action.';
    end if;
  elsif v_caller_role = 'agent' and v_case.assigned_agent_id = auth.uid() then
    if not (p_action = any(v_agent_actions)) then
      raise exception 'This action is reserved for the Super User.';
    end if;
  else
    raise exception 'Not authorized.';
  end if;

  v_new_status := case p_action
    when 'dismiss' then 'dismissed'
    when 'request_edit' then 'edit_requested'
    when 'hide' then 'hidden'
    when 'restore' then 'open'
    when 'delete' then 'resolved_deleted'
    when 'escalate' then 'escalated'
    else v_case.status
  end;

  update public.bingo_moderation_cases
  set status = v_new_status,
      resolution_reason = btrim(p_reason),
      resolved_by = auth.uid(),
      resolved_at = now(),
      updated_at = now()
  where id = p_case_id;

  if p_action in ('hide','restore') then
    if v_case.target_type = 'food_business' then
      update public.food_businesses set moderation_status = (case when p_action='hide' then 'hidden' else 'visible' end) where id = v_case.target_id::uuid;
    elsif v_case.target_type = 'food_menu_item' then
      update public.food_menu_items set moderation_status = (case when p_action='hide' then 'hidden' else 'visible' end) where id = v_case.target_id::uuid;
    elsif v_case.target_type in ('property','stay') then
      update public.property_listings set moderation_status = (case when p_action='hide' then 'hidden' else 'visible' end) where id = v_case.target_id::uuid;
    end if;
  end if;

  if p_action = 'delete' then
    if v_case.target_type = 'food_business' then
      delete from public.food_businesses where id = v_case.target_id::uuid;
    elsif v_case.target_type = 'food_menu_item' then
      delete from public.food_menu_items where id = v_case.target_id::uuid;
    elsif v_case.target_type in ('property','stay') then
      delete from public.property_listings where id = v_case.target_id::uuid;
    end if;
    -- vehicle / community_member / solution_message / job / candidate /
    -- seller_profile / other targets currently live only in each member's
    -- own browser storage — there is no server row here to delete. The
    -- case itself still records the confirmed violation and reason, and
    -- the owner (when known) is still notified below.
  end if;

  insert into public.bingo_moderation_audit_log (actor_id, case_id, target_type, target_id, action, reason)
  values (auth.uid(), p_case_id, v_case.target_type, v_case.target_id, p_action, btrim(p_reason));

  if v_case.target_owner_id is not null and p_action in ('request_edit','hide','delete','escalate') then
    insert into public.bingo_moderation_notifications (user_id, case_id, message)
    values (
      v_case.target_owner_id, p_case_id,
      case p_action
        when 'request_edit' then 'A Bingo moderator has asked you to edit your listing/post. Reason: ' || btrim(p_reason)
        when 'hide' then 'Your listing/post has been temporarily hidden pending review. Reason: ' || btrim(p_reason)
        when 'delete' then 'Your listing/post was removed after a confirmed policy violation. Reason: ' || btrim(p_reason)
        when 'escalate' then 'A moderation case on your account has been escalated for further review.'
        else ''
      end
    );
  end if;
end;
$$;

revoke all on function public.bingo_moderation_action(uuid,text,text) from public;
grant execute on function public.bingo_moderation_action(uuid,text,text) to authenticated;
