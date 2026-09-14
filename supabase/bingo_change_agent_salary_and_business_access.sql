-- ============================================================================
-- BINGO CHANGE — AGENT CLIENT TARGET, SALARY AND BUSINESS MANAGEMENT
-- (Supabase backend)
--
-- Additive on top of Change 03 (bingo_user_roles, bingo_role_audit_log,
-- bingo_is_super_user, bingo_admin_grant_agent/revoke_agent). Does not
-- touch bingo_moderation_*, bingo_ad_*, or any Food/Property table beyond
-- one new PERMISSIVE (additive, non-replacing) policy each so an
-- authorized Agent can act on a business they've been granted access to,
-- alongside — never instead of — the owner's existing policies.
--
-- Reconciliation note: the existing bingo_user_roles table already has a
-- `territory` column doing exactly what this spec's `assigned_territory`
-- would duplicate, so that column is intentionally not added — every RPC
-- below reads/writes `territory` instead. Everything else here is new.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Agent appointment metadata on the existing role table
-- ---------------------------------------------------------------------------
alter table public.bingo_user_roles add column if not exists agent_since timestamptz;
alter table public.bingo_user_roles add column if not exists agent_status text not null default 'inactive'
  check (agent_status in ('inactive','active','suspended','revoked'));
-- agent_since/agent_status are set only by bingo_admin_grant_agent /
-- bingo_admin_revoke_agent below (both re-created here, same signature,
-- same existing behaviour plus these two fields) — never accepted from
-- the browser directly.

-- ---------------------------------------------------------------------------
-- 2. Business <-> Agent management access (owner-granted, agent-accepted)
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_business_agent_access (
  id                  uuid primary key default gen_random_uuid(),
  business_type       text not null check (business_type in ('food_business','property','stay')),
  business_id         uuid not null,
  owner_id            uuid not null references auth.users(id) on delete cascade,
  agent_id            uuid not null references auth.users(id) on delete cascade,
  invitation_status   text not null default 'pending' check (invitation_status in ('pending','accepted','rejected','revoked')),
  can_edit_business    boolean not null default false,
  can_manage_listings  boolean not null default false,
  can_manage_media     boolean not null default false,
  can_manage_menu      boolean not null default false,
  can_publish          boolean not null default false,
  can_manage_boost     boolean not null default false,
  can_view_enquiries   boolean not null default false,
  invited_at          timestamptz not null default now(),
  accepted_at         timestamptz,
  rejected_at         timestamptz,
  revoked_at          timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (business_type, business_id, agent_id)
);

create index if not exists bingo_business_agent_access_agent_idx on public.bingo_business_agent_access(agent_id, invitation_status);
create index if not exists bingo_business_agent_access_owner_idx on public.bingo_business_agent_access(owner_id, invitation_status);

alter table public.bingo_business_agent_access enable row level security;

drop policy if exists "Owners view business Agent access" on public.bingo_business_agent_access;
create policy "Owners view business Agent access" on public.bingo_business_agent_access
  for select to authenticated using (owner_id = auth.uid());

drop policy if exists "Agents view assigned business access" on public.bingo_business_agent_access;
create policy "Agents view assigned business access" on public.bingo_business_agent_access
  for select to authenticated using (agent_id = auth.uid());

drop policy if exists "Super User views all business Agent access" on public.bingo_business_agent_access;
create policy "Super User views all business Agent access" on public.bingo_business_agent_access
  for select to authenticated using (public.bingo_is_super_user());
-- No insert/update/delete policy for anyone: only the RPCs below write here.

-- ---------------------------------------------------------------------------
-- 3. Qualified Agent clients (one row per unique owner per salary cycle)
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_agent_client_qualifications (
  id                  uuid primary key default gen_random_uuid(),
  agent_id            uuid not null references auth.users(id) on delete cascade,
  owner_id            uuid not null references auth.users(id) on delete cascade,
  business_type       text not null,
  business_id         uuid not null,
  access_id           uuid not null references public.bingo_business_agent_access(id) on delete cascade,
  salary_cycle_number integer not null check (salary_cycle_number > 0),
  qualified_at        timestamptz not null default now(),
  qualification_status text not null default 'qualified' check (qualification_status in ('qualified','disqualified')),
  qualification_reason text,
  disqualified_at     timestamptz,
  unique (agent_id, owner_id, salary_cycle_number)
);

create index if not exists bingo_agent_qualification_cycle_idx on public.bingo_agent_client_qualifications(agent_id, salary_cycle_number, qualification_status);

alter table public.bingo_agent_client_qualifications enable row level security;

drop policy if exists "Agents view own qualifications" on public.bingo_agent_client_qualifications;
create policy "Agents view own qualifications" on public.bingo_agent_client_qualifications
  for select to authenticated using (agent_id = auth.uid());

drop policy if exists "Super User views all qualifications" on public.bingo_agent_client_qualifications;
create policy "Super User views all qualifications" on public.bingo_agent_client_qualifications
  for select to authenticated using (public.bingo_is_super_user());
-- No insert/update/delete policy: only bingo_agent_salary_summary (SECURITY
-- DEFINER, below) computes and writes these.

-- ---------------------------------------------------------------------------
-- 4. Agent salary cycles
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_agent_salary_cycles (
  id                uuid primary key default gen_random_uuid(),
  agent_id          uuid not null references auth.users(id) on delete cascade,
  cycle_number      integer not null check (cycle_number > 0),
  cycle_start       timestamptz not null,
  cycle_end         timestamptz not null,
  required_clients  integer not null default 2 check (required_clients = 2),
  qualified_clients integer not null default 0 check (qualified_clients >= 0),
  salary_amount     numeric(12,2) not null default 35000 check (salary_amount = 35000),
  salary_status     text not null default 'locked' check (salary_status in ('locked','unlocked','approved','paid')),
  unlocked_at       timestamptz,
  approved_at       timestamptz,
  approved_by       uuid references auth.users(id),
  paid_at           timestamptz,
  payment_reference text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (agent_id, cycle_number)
);

create index if not exists bingo_agent_salary_cycle_idx on public.bingo_agent_salary_cycles(agent_id, cycle_start, cycle_end);

alter table public.bingo_agent_salary_cycles enable row level security;

drop policy if exists "Agents view own salary cycles" on public.bingo_agent_salary_cycles;
create policy "Agents view own salary cycles" on public.bingo_agent_salary_cycles
  for select to authenticated using (agent_id = auth.uid());

drop policy if exists "Super User views all salary cycles" on public.bingo_agent_salary_cycles;
create policy "Super User views all salary cycles" on public.bingo_agent_salary_cycles
  for select to authenticated using (public.bingo_is_super_user());
-- No insert/update/delete policy: only bingo_agent_salary_summary /
-- bingo_admin_approve_agent_salary / bingo_admin_mark_agent_salary_paid
-- (all SECURITY DEFINER, below) ever write here.

-- ---------------------------------------------------------------------------
-- 5. bingo_admin_grant_agent / bingo_admin_revoke_agent — re-created with
--    the exact same signature and existing behaviour from Change 03, plus
--    agent_since/agent_status. agent_since is set only on an appointment
--    that starts a fresh Agent tenure (first grant, or re-grant after a
--    prior revoke) — a territory-only re-run never touches it.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_admin_grant_agent(p_user_id uuid, p_territory text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_had_role text;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may grant Agent role.';
  end if;
  if p_user_id is null then
    raise exception 'A target user is required.';
  end if;
  if p_territory is null or length(trim(p_territory)) = 0 then
    raise exception 'A territory/county is required.';
  end if;

  select role into v_had_role from public.bingo_user_roles where user_id = p_user_id;

  if v_had_role = 'super_user' then
    raise exception 'The Super User role cannot be changed here.';
  end if;

  insert into public.bingo_user_roles (user_id, role, territory, approved_by, approved_at, updated_at, agent_since, agent_status)
  values (p_user_id, 'agent', trim(p_territory), auth.uid(), now(), now(), now(), 'active')
  on conflict (user_id) do update
    set role = 'agent',
        territory = excluded.territory,
        approved_by = excluded.approved_by,
        approved_at = excluded.approved_at,
        updated_at = now(),
        agent_since = case when public.bingo_user_roles.role is distinct from 'agent' then now() else public.bingo_user_roles.agent_since end,
        agent_status = 'active';

  insert into public.bingo_role_audit_log (actor_id, target_id, action, details)
  values (
    auth.uid(), p_user_id,
    case when v_had_role = 'agent' then 'update_agent_territory' else 'grant_agent' end,
    jsonb_build_object('territory', trim(p_territory), 'previous_role', coalesce(v_had_role, 'member'))
  );

  insert into public.bingo_role_notifications (user_id, message)
  values (
    p_user_id,
    'Congratulations — you are now a Bingo Agent for ' || trim(p_territory) ||
    '! Switch to Agent from your Profile to onboard businesses.'
  );
end;
$$;

revoke all on function public.bingo_admin_grant_agent(uuid, text) from public;
grant execute on function public.bingo_admin_grant_agent(uuid, text) to authenticated;

create or replace function public.bingo_admin_revoke_agent(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may revoke Agent role.';
  end if;

  select role into v_role from public.bingo_user_roles where user_id = p_user_id;
  if v_role is distinct from 'agent' then
    raise exception 'That account does not currently hold the Agent role.';
  end if;

  update public.bingo_user_roles
     set role = 'member',
         agent_status = 'revoked',
         updated_at = now()
   where user_id = p_user_id;

  insert into public.bingo_role_audit_log (actor_id, target_id, action, details)
  values (auth.uid(), p_user_id, 'revoke_agent', '{}'::jsonb);
end;
$$;

revoke all on function public.bingo_admin_revoke_agent(uuid) from public;
grant execute on function public.bingo_admin_revoke_agent(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Cycle math — server time only, never trusts browser clocks.
-- ---------------------------------------------------------------------------
create or replace function public._bingo_agent_cycle_bounds(p_agent_since timestamptz, p_at timestamptz default now())
returns table (cycle_number integer, cycle_start timestamptz, cycle_end timestamptz)
language sql
stable
set search_path = ''
as $$
  with elapsed as (
    select greatest(0, (extract(year from age(p_at, p_agent_since))*12 + extract(month from age(p_at, p_agent_since)))::int) as whole_months
  )
  select
    whole_months + 1 as cycle_number,
    p_agent_since + (whole_months || ' months')::interval as cycle_start,
    p_agent_since + ((whole_months + 1) || ' months')::interval as cycle_end
  from elapsed;
$$;

-- ---------------------------------------------------------------------------
-- 7. bingo_agent_salary_summary — the single source of truth for "am I
--    unlocked this cycle". Recomputes qualified clients from the access
--    table + live business status every call (so a business that gets
--    published after acceptance, or later suspended, is reflected without
--    needing a trigger), never regresses a cycle that is already
--    unlocked/approved/paid, and never lets the browser set any of it.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_agent_salary_summary()
returns public.bingo_agent_salary_cycles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_agent_since timestamptz;
  v_role text;
  v_bounds record;
  v_qualified_count integer;
  v_cycle public.bingo_agent_salary_cycles;
  v_owner record;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.';
  end if;

  select role, agent_since into v_role, v_agent_since from public.bingo_user_roles where user_id = auth.uid();
  if v_role is distinct from 'agent' or v_agent_since is null then
    raise exception 'This account does not have an active Agent appointment.';
  end if;

  select * into v_bounds from public._bingo_agent_cycle_bounds(v_agent_since, now());

  -- One qualifying owner per business — published, not deleted/rejected/
  -- suspended, accepted within this cycle, never the Agent themself.
  for v_owner in
    select distinct on (a.owner_id) a.id as access_id, a.owner_id, a.business_type, a.business_id
    from public.bingo_business_agent_access a
    where a.agent_id = auth.uid()
      and a.invitation_status = 'accepted'
      and a.accepted_at is not null
      and a.accepted_at >= v_bounds.cycle_start
      and a.accepted_at < v_bounds.cycle_end
      and a.owner_id <> auth.uid()
      and (
        (a.business_type = 'food_business' and exists (select 1 from public.food_businesses fb where fb.id = a.business_id and fb.status = 'active'))
        or
        (a.business_type in ('property','stay') and exists (select 1 from public.property_listings pl where pl.id = a.business_id and pl.status = 'published'))
      )
    order by a.owner_id, a.accepted_at asc
  loop
    insert into public.bingo_agent_client_qualifications(agent_id, owner_id, business_type, business_id, access_id, salary_cycle_number)
    values (auth.uid(), v_owner.owner_id, v_owner.business_type, v_owner.business_id, v_owner.access_id, v_bounds.cycle_number)
    on conflict (agent_id, owner_id, salary_cycle_number) do nothing;
  end loop;

  select count(*) into v_qualified_count
  from public.bingo_agent_client_qualifications
  where agent_id = auth.uid() and salary_cycle_number = v_bounds.cycle_number and qualification_status = 'qualified';

  insert into public.bingo_agent_salary_cycles(agent_id, cycle_number, cycle_start, cycle_end, qualified_clients)
  values (auth.uid(), v_bounds.cycle_number, v_bounds.cycle_start, v_bounds.cycle_end, v_qualified_count)
  on conflict (agent_id, cycle_number) do update
    set qualified_clients = excluded.qualified_clients,
        updated_at = now()
  returning * into v_cycle;

  if v_cycle.salary_status = 'locked' and v_cycle.qualified_clients >= v_cycle.required_clients then
    update public.bingo_agent_salary_cycles
    set salary_status = 'unlocked', unlocked_at = now(), updated_at = now()
    where id = v_cycle.id
    returning * into v_cycle;
  end if;

  return v_cycle;
end;
$$;

revoke all on function public.bingo_agent_salary_summary() from public;
grant execute on function public.bingo_agent_salary_summary() to authenticated;

-- ---------------------------------------------------------------------------
-- 7b. bingo_find_agent_by_email — any signed-in owner needs to find an
--     Agent to invite, but bingo_admin_find_user_by_email (Change 03) is
--     Super-User-only and returns full account data for anyone. This is
--     narrower: callable by any authenticated user, and only ever returns
--     a result when that email belongs to an active Agent (never leaks
--     whether an arbitrary email has a Bingo account at all).
-- ---------------------------------------------------------------------------
create or replace function public.bingo_find_agent_by_email(p_email text)
returns table (user_id uuid, full_name text, territory text)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in required.';
  end if;
  return query
  select u.id, coalesce(p.full_name, trim(coalesce(p.first_name,'') || ' ' || coalesce(p.last_name,''))), r.territory
  from auth.users u
  join public.bingo_user_roles r on r.user_id = u.id
  left join public.profiles p on p.id = u.id
  where lower(u.email) = lower(p_email)
    and r.role = 'agent'
    and r.agent_status = 'active'
  limit 1;
end;
$$;

revoke all on function public.bingo_find_agent_by_email(text) from public;
grant execute on function public.bingo_find_agent_by_email(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Owner invite / Agent accept-reject / owner revoke
-- ---------------------------------------------------------------------------
create or replace function public.bingo_owner_invite_agent(p_business_type text, p_business_id uuid, p_agent_id uuid, p_permissions jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_access_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.';
  end if;
  if not (p_business_type = any(array['food_business','property','stay'])) then
    raise exception 'Invalid business type.';
  end if;
  if not exists (select 1 from public.bingo_user_roles where user_id = p_agent_id and role = 'agent' and agent_status = 'active') then
    raise exception 'That account does not have an active Agent role.';
  end if;

  if p_business_type = 'food_business' then
    select user_id into v_owner_id from public.food_businesses where id = p_business_id;
  else
    select user_id into v_owner_id from public.property_listings where id = p_business_id;
  end if;
  if v_owner_id is null then
    raise exception 'Business not found.';
  end if;
  if v_owner_id <> auth.uid() then
    raise exception 'Only the business owner may invite an Agent.';
  end if;
  if p_agent_id = auth.uid() then
    raise exception 'You cannot invite yourself.';
  end if;

  insert into public.bingo_business_agent_access(
    business_type, business_id, owner_id, agent_id,
    can_edit_business, can_manage_listings, can_manage_media, can_manage_menu, can_publish, can_manage_boost, can_view_enquiries
  ) values (
    p_business_type, p_business_id, auth.uid(), p_agent_id,
    coalesce((p_permissions->>'edit_business')::boolean,false),
    coalesce((p_permissions->>'manage_listings')::boolean,false),
    coalesce((p_permissions->>'manage_media')::boolean,false),
    coalesce((p_permissions->>'manage_menu')::boolean,false),
    coalesce((p_permissions->>'publish')::boolean,false),
    coalesce((p_permissions->>'manage_boost')::boolean,false),
    coalesce((p_permissions->>'view_enquiries')::boolean,false)
  )
  on conflict (business_type, business_id, agent_id) do update
    set invitation_status = 'pending',
        can_edit_business = excluded.can_edit_business,
        can_manage_listings = excluded.can_manage_listings,
        can_manage_media = excluded.can_manage_media,
        can_manage_menu = excluded.can_manage_menu,
        can_publish = excluded.can_publish,
        can_manage_boost = excluded.can_manage_boost,
        can_view_enquiries = excluded.can_view_enquiries,
        invited_at = now(),
        accepted_at = null, rejected_at = null, revoked_at = null,
        updated_at = now()
  returning id into v_access_id;

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), p_agent_id, 'invite_agent_to_business', jsonb_build_object('business_type',p_business_type,'business_id',p_business_id));

  return v_access_id;
end;
$$;

revoke all on function public.bingo_owner_invite_agent(text,uuid,uuid,jsonb) from public;
grant execute on function public.bingo_owner_invite_agent(text,uuid,uuid,jsonb) to authenticated;

create or replace function public.bingo_agent_accept_business_invitation(p_access_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.bingo_business_agent_access;
begin
  if auth.uid() is null then raise exception 'Sign in required.'; end if;
  select * into v_row from public.bingo_business_agent_access where id = p_access_id;
  if not found then raise exception 'Invitation not found.'; end if;
  if v_row.agent_id <> auth.uid() then raise exception 'This invitation is not addressed to you.'; end if;
  if v_row.invitation_status <> 'pending' then raise exception 'This invitation is no longer pending.'; end if;
  if not exists (select 1 from public.bingo_user_roles where user_id = auth.uid() and role = 'agent' and agent_status = 'active') then
    raise exception 'Your Agent access is not currently active.';
  end if;

  update public.bingo_business_agent_access
  set invitation_status = 'accepted', accepted_at = now(), updated_at = now()
  where id = p_access_id;

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), v_row.owner_id, 'accept_business_invitation', jsonb_build_object('access_id',p_access_id));
end;
$$;

revoke all on function public.bingo_agent_accept_business_invitation(uuid) from public;
grant execute on function public.bingo_agent_accept_business_invitation(uuid) to authenticated;

create or replace function public.bingo_agent_reject_business_invitation(p_access_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.bingo_business_agent_access;
begin
  if auth.uid() is null then raise exception 'Sign in required.'; end if;
  select * into v_row from public.bingo_business_agent_access where id = p_access_id;
  if not found then raise exception 'Invitation not found.'; end if;
  if v_row.agent_id <> auth.uid() then raise exception 'This invitation is not addressed to you.'; end if;
  if v_row.invitation_status <> 'pending' then raise exception 'This invitation is no longer pending.'; end if;

  update public.bingo_business_agent_access
  set invitation_status = 'rejected', rejected_at = now(), updated_at = now()
  where id = p_access_id;

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), v_row.owner_id, 'reject_business_invitation', jsonb_build_object('access_id',p_access_id));
end;
$$;

revoke all on function public.bingo_agent_reject_business_invitation(uuid) from public;
grant execute on function public.bingo_agent_reject_business_invitation(uuid) to authenticated;

create or replace function public.bingo_owner_revoke_agent_access(p_access_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.bingo_business_agent_access;
begin
  if auth.uid() is null then raise exception 'Sign in required.'; end if;
  select * into v_row from public.bingo_business_agent_access where id = p_access_id;
  if not found then raise exception 'Access record not found.'; end if;
  if v_row.owner_id <> auth.uid() then raise exception 'Only the business owner may revoke this Agent.'; end if;

  update public.bingo_business_agent_access
  set invitation_status = 'revoked', revoked_at = now(), updated_at = now()
  where id = p_access_id;

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), v_row.agent_id, 'revoke_business_access', jsonb_build_object('access_id',p_access_id));
end;
$$;

revoke all on function public.bingo_owner_revoke_agent_access(uuid) from public;
grant execute on function public.bingo_owner_revoke_agent_access(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Live permission check — used both by the browser (interface control
--    only) and re-verified by every table policy below (the real gate).
-- ---------------------------------------------------------------------------
create or replace function public.bingo_agent_can_manage_business(p_business_type text, p_business_id uuid, p_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.bingo_business_agent_access a
    join public.bingo_user_roles r on r.user_id = a.agent_id
    where a.agent_id = auth.uid()
      and a.business_type = p_business_type
      and a.business_id = p_business_id
      and a.invitation_status = 'accepted'
      and r.role = 'agent'
      and r.agent_status = 'active'
      and (
        (p_permission = 'edit_business' and a.can_edit_business)
        or (p_permission = 'manage_listings' and a.can_manage_listings)
        or (p_permission = 'manage_media' and a.can_manage_media)
        or (p_permission = 'manage_menu' and a.can_manage_menu)
        or (p_permission = 'publish' and a.can_publish)
        or (p_permission = 'manage_boost' and a.can_manage_boost)
        or (p_permission = 'view_enquiries' and a.can_view_enquiries)
      )
  );
$$;

revoke all on function public.bingo_agent_can_manage_business(text,uuid,text) from public;
grant execute on function public.bingo_agent_can_manage_business(text,uuid,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Additional PERMISSIVE policies — additive alongside the existing
--     owner-only UPDATE policies on food_businesses / food_menu_items /
--     property_listings (Postgres ORs permissive policies for the same
--     command, so the owner's own access is completely unchanged).
-- ---------------------------------------------------------------------------
drop policy if exists food_businesses_agent_update on public.food_businesses;
create policy food_businesses_agent_update on public.food_businesses
  for update
  using (public.bingo_agent_can_manage_business('food_business', id, 'edit_business') or public.bingo_agent_can_manage_business('food_business', id, 'publish'))
  with check (public.bingo_agent_can_manage_business('food_business', id, 'edit_business') or public.bingo_agent_can_manage_business('food_business', id, 'publish'));

drop policy if exists food_menu_items_agent_all on public.food_menu_items;
create policy food_menu_items_agent_all on public.food_menu_items
  for all
  using (public.bingo_agent_can_manage_business('food_business', business_id, 'manage_menu'))
  with check (public.bingo_agent_can_manage_business('food_business', business_id, 'manage_menu'));

drop policy if exists property_listings_agent_update on public.property_listings;
create policy property_listings_agent_update on public.property_listings
  for update
  using (public.bingo_agent_can_manage_business('property', id, 'edit_business') or public.bingo_agent_can_manage_business('stay', id, 'edit_business') or public.bingo_agent_can_manage_business('property', id, 'publish') or public.bingo_agent_can_manage_business('stay', id, 'publish'))
  with check (public.bingo_agent_can_manage_business('property', id, 'edit_business') or public.bingo_agent_can_manage_business('stay', id, 'edit_business') or public.bingo_agent_can_manage_business('property', id, 'publish') or public.bingo_agent_can_manage_business('stay', id, 'publish'));

-- Media uploads: the Storage path convention is user_id/business_id/file,
-- where user_id is always the OWNER's id (never the uploading Agent's), so
-- the existing owner-prefix policies cannot match an Agent upload — these
-- are additive INSERT policies just for that case.
drop policy if exists food_media_agent_write on storage.objects;
create policy food_media_agent_write on storage.objects
  for insert
  with check (
    bucket_id = 'food-media'
    and public.bingo_agent_can_manage_business('food_business', ((storage.foldername(name))[2])::uuid, 'manage_media')
  );

drop policy if exists property_media_agent_write on storage.objects;
create policy property_media_agent_write on storage.objects
  for insert
  with check (
    bucket_id = 'property-media'
    and (
      public.bingo_agent_can_manage_business('property', ((storage.foldername(name))[2])::uuid, 'manage_media')
      or public.bingo_agent_can_manage_business('stay', ((storage.foldername(name))[2])::uuid, 'manage_media')
    )
  );

-- ---------------------------------------------------------------------------
-- 11. Super User payroll actions
-- ---------------------------------------------------------------------------
create or replace function public.bingo_admin_approve_agent_salary(p_cycle_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.bingo_agent_salary_cycles;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may approve Agent salary.';
  end if;
  select * into v_row from public.bingo_agent_salary_cycles where id = p_cycle_id;
  if not found then raise exception 'Salary cycle not found.'; end if;
  if v_row.salary_status <> 'unlocked' then
    raise exception 'Only an unlocked salary cycle can be approved.';
  end if;

  update public.bingo_agent_salary_cycles
  set salary_status = 'approved', approved_at = now(), approved_by = auth.uid(), updated_at = now()
  where id = p_cycle_id;

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), v_row.agent_id, 'approve_agent_salary', jsonb_build_object('cycle_id',p_cycle_id,'cycle_number',v_row.cycle_number));
end;
$$;

revoke all on function public.bingo_admin_approve_agent_salary(uuid) from public;
grant execute on function public.bingo_admin_approve_agent_salary(uuid) to authenticated;

create or replace function public.bingo_admin_mark_agent_salary_paid(p_cycle_id uuid, p_payment_reference text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.bingo_agent_salary_cycles;
  v_ref text;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may record Agent salary payment.';
  end if;
  v_ref := trim(coalesce(p_payment_reference,''));
  if v_ref = '' then
    raise exception 'A payment reference is required.';
  end if;
  select * into v_row from public.bingo_agent_salary_cycles where id = p_cycle_id;
  if not found then raise exception 'Salary cycle not found.'; end if;
  if v_row.salary_status <> 'approved' then
    raise exception 'Only an approved salary cycle can be marked paid.';
  end if;

  update public.bingo_agent_salary_cycles
  set salary_status = 'paid', paid_at = now(), payment_reference = v_ref, updated_at = now()
  where id = p_cycle_id;

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), v_row.agent_id, 'pay_agent_salary', jsonb_build_object('cycle_id',p_cycle_id,'cycle_number',v_row.cycle_number,'payment_reference',v_ref));

  insert into public.bingo_role_notifications(user_id, message)
  values (v_row.agent_id, 'Your Agent salary of KSh 35,000 for this cycle has been paid. Reference: ' || v_ref);
end;
$$;

revoke all on function public.bingo_admin_mark_agent_salary_paid(uuid,text) from public;
grant execute on function public.bingo_admin_mark_agent_salary_paid(uuid,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 12. Super User Agent+salary directory (read-only aggregate for the
--     dashboard: current cycle per active Agent).
-- ---------------------------------------------------------------------------
create or replace function public.bingo_admin_agent_salary_directory()
returns table (
  user_id uuid, email text, full_name text, territory text, agent_since timestamptz, agent_status text,
  cycle_id uuid, cycle_number integer, cycle_start timestamptz, cycle_end timestamptz,
  qualified_clients integer, salary_amount numeric, salary_status text, payment_reference text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_agent record;
  v_bounds record;
  v_cycle public.bingo_agent_salary_cycles;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may view the Agent salary directory.';
  end if;

  for v_agent in
    select r.user_id, u.email, coalesce(p.full_name, trim(coalesce(p.first_name,'') || ' ' || coalesce(p.last_name,''))) as full_name,
           r.territory, r.agent_since, r.agent_status
    from public.bingo_user_roles r
    join auth.users u on u.id = r.user_id
    left join public.profiles p on p.id = r.user_id
    where r.role = 'agent'
    order by r.agent_since desc nulls last
  loop
    cycle_id := null; cycle_number := null; cycle_start := null; cycle_end := null;
    qualified_clients := null; salary_amount := null; salary_status := null; payment_reference := null;
    user_id := v_agent.user_id; email := v_agent.email; full_name := v_agent.full_name;
    territory := v_agent.territory; agent_since := v_agent.agent_since; agent_status := v_agent.agent_status;

    if v_agent.agent_since is not null then
      select * into v_bounds from public._bingo_agent_cycle_bounds(v_agent.agent_since, now());
      select * into v_cycle from public.bingo_agent_salary_cycles
      where agent_id = v_agent.user_id and cycle_number = v_bounds.cycle_number;
      if found then
        cycle_id := v_cycle.id; cycle_number := v_cycle.cycle_number; cycle_start := v_cycle.cycle_start; cycle_end := v_cycle.cycle_end;
        qualified_clients := v_cycle.qualified_clients; salary_amount := v_cycle.salary_amount;
        salary_status := v_cycle.salary_status; payment_reference := v_cycle.payment_reference;
      else
        cycle_number := v_bounds.cycle_number; cycle_start := v_bounds.cycle_start; cycle_end := v_bounds.cycle_end;
        qualified_clients := 0; salary_amount := 35000; salary_status := 'locked';
      end if;
    end if;

    return next;
  end loop;
end;
$$;

revoke all on function public.bingo_admin_agent_salary_directory() from public;
grant execute on function public.bingo_admin_agent_salary_directory() to authenticated;
