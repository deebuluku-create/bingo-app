-- ============================================================================
-- BINGO CHANGE 2 — SUPER USER AND AGENT SECURITY (Supabase backend)
--
-- Run this once in the Supabase SQL Editor for the Bingo project. It creates:
--   1. bingo_user_roles      — one row per auth user: role + territory
--   2. bingo_role_audit_log  — immutable log of every admin role change
--   3. bingo_role_notifications — pending Inbox messages for role changes,
--      delivered to the target user's own Bingo Inbox the next time they load
--   4. bingo_is_super_user() — the single source of truth for "am I super_user"
--   5. Four protected RPCs the Super User Dashboard calls
--
-- No password, secret key, or service-role key is stored here or in Mother
-- HTML. Everything below runs under the normal Supabase Auth session using
-- the browser-safe publishable (anon) key; privilege is enforced entirely
-- server-side by RLS and SECURITY DEFINER functions with a locked search_path.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Role table
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_user_roles (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  role        text not null default 'member' check (role in ('member','agent','super_user')),
  territory   text not null default '',
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  updated_at  timestamptz not null default now()
);

alter table public.bingo_user_roles enable row level security;

-- A member may read only their own role row. The Super User may also read
-- every row (needed for the Agent Directory) — this is a READ policy only;
-- there is no INSERT/UPDATE/DELETE policy for authenticated users at all,
-- so the table can only be changed through the SECURITY DEFINER RPCs below.
drop policy if exists bingo_user_roles_select on public.bingo_user_roles;
create policy bingo_user_roles_select on public.bingo_user_roles
  for select
  using (
    auth.uid() = user_id
    or public.bingo_is_super_user()
  );

-- ---------------------------------------------------------------------------
-- 2. Audit log — append-only
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_role_audit_log (
  id          bigint generated always as identity primary key,
  actor_id    uuid not null references auth.users(id),
  target_id   uuid references auth.users(id),
  action      text not null,
  details     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

alter table public.bingo_role_audit_log enable row level security;

drop policy if exists bingo_role_audit_log_select on public.bingo_role_audit_log;
create policy bingo_role_audit_log_select on public.bingo_role_audit_log
  for select
  using (public.bingo_is_super_user());
-- No insert/update/delete policy: only the SECURITY DEFINER RPCs write here.

-- ---------------------------------------------------------------------------
-- 3. Pending Inbox notifications for role changes (delivered client-side into
--    the existing Bingo Inbox the next time the target user's session loads
--    their role — Bingo's Inbox itself stays exactly as it is today).
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_role_notifications (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  message     text not null,
  delivered   boolean not null default false,
  created_at  timestamptz not null default now()
);

alter table public.bingo_role_notifications enable row level security;

drop policy if exists bingo_role_notifications_select on public.bingo_role_notifications;
create policy bingo_role_notifications_select on public.bingo_role_notifications
  for select
  using (auth.uid() = user_id);

-- A user may mark their own notifications delivered once they've been shown.
drop policy if exists bingo_role_notifications_update on public.bingo_role_notifications;
create policy bingo_role_notifications_update on public.bingo_role_notifications
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 4. bingo_is_super_user() — the single authority check every RPC relies on
-- ---------------------------------------------------------------------------
create or replace function public.bingo_is_super_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.bingo_user_roles r
    where r.user_id = auth.uid()
      and r.role = 'super_user'
  );
$$;

revoke all on function public.bingo_is_super_user() from public;
grant execute on function public.bingo_is_super_user() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. bingo_admin_find_user_by_email — exact, case-insensitive lookup
-- ---------------------------------------------------------------------------
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
    u.email,
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

-- ---------------------------------------------------------------------------
-- 6. bingo_admin_grant_agent — grant or re-grant Agent role + territory
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

  insert into public.bingo_user_roles (user_id, role, territory, approved_by, approved_at, updated_at)
  values (p_user_id, 'agent', trim(p_territory), auth.uid(), now(), now())
  on conflict (user_id) do update
    set role = 'agent',
        territory = excluded.territory,
        approved_by = excluded.approved_by,
        approved_at = excluded.approved_at,
        updated_at = now();

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

-- ---------------------------------------------------------------------------
-- 7. bingo_admin_update_agent_territory — change an existing Agent's territory
-- ---------------------------------------------------------------------------
create or replace function public.bingo_admin_update_agent_territory(p_user_id uuid, p_territory text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may update Agent territory.';
  end if;
  if p_territory is null or length(trim(p_territory)) = 0 then
    raise exception 'A territory/county is required.';
  end if;

  select role into v_role from public.bingo_user_roles where user_id = p_user_id;
  if v_role is distinct from 'agent' then
    raise exception 'That account does not currently hold the Agent role.';
  end if;

  update public.bingo_user_roles
     set territory = trim(p_territory),
         updated_at = now()
   where user_id = p_user_id;

  insert into public.bingo_role_audit_log (actor_id, target_id, action, details)
  values (auth.uid(), p_user_id, 'update_agent_territory', jsonb_build_object('territory', trim(p_territory)));
end;
$$;

revoke all on function public.bingo_admin_update_agent_territory(uuid, text) from public;
grant execute on function public.bingo_admin_update_agent_territory(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. bingo_admin_revoke_agent — Agent back to member (never deletes/bans)
-- ---------------------------------------------------------------------------
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
         updated_at = now()
   where user_id = p_user_id;

  insert into public.bingo_role_audit_log (actor_id, target_id, action, details)
  values (auth.uid(), p_user_id, 'revoke_agent', '{}'::jsonb);
end;
$$;

revoke all on function public.bingo_admin_revoke_agent(uuid) from public;
grant execute on function public.bingo_admin_revoke_agent(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Agent directory read for the Super User Dashboard (list, not a mutation)
-- ---------------------------------------------------------------------------
create or replace function public.bingo_admin_list_agents()
returns table (
  user_id     uuid,
  email       text,
  role        text,
  territory   text,
  approved_at timestamptz,
  full_name   text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may list Agents.';
  end if;

  return query
  select r.user_id, u.email, r.role, r.territory, r.approved_at,
         coalesce(p.full_name, trim(coalesce(p.first_name,'') || ' ' || coalesce(p.last_name,'')))
  from public.bingo_user_roles r
  join auth.users u on u.id = r.user_id
  left join public.profiles p on p.id = r.user_id
  where r.role = 'agent'
  order by r.approved_at desc nulls last;
end;
$$;

revoke all on function public.bingo_admin_list_agents() from public;
grant execute on function public.bingo_admin_list_agents() to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Bootstrap — run ONCE for your real Super User account.
--     Replace the email below with the already-registered Bingo account that
--     should become Super User, then run just this block by itself.
--     Passwords are never involved: this only touches the role table.
-- ---------------------------------------------------------------------------
-- insert into public.bingo_user_roles (user_id, role, territory, approved_at, updated_at)
-- select id, 'super_user', 'HQ', now(), now()
-- from auth.users
-- where lower(email) = lower('owner@example.com')
-- on conflict (user_id) do update set role = 'super_user', updated_at = now();
