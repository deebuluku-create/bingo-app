-- LOCAL TEST HARNESS ONLY (scratch Postgres 16). Recreates the parts of the
-- live Supabase contract that were reported, so the proposed migration can be
-- exercised under real RLS. Items marked ASSUMED were not reported and are
-- modelled on Supabase defaults / the confirmed columns.
-- SAFETY: refuse to run anywhere that looks like a real Supabase database.
do $$ begin
 if exists (select 1 from pg_namespace where nspname in ('storage','supabase_functions','realtime','vault','graphql'))
    or exists (select 1 from pg_roles where rolname in ('supabase_admin','authenticator')) then
  raise exception 'messenger_local_harness.sql is for a scratch Postgres only - refusing to drop schemas here';
 end if;
end $$;
drop schema if exists public cascade; create schema public;
drop schema if exists auth cascade; create schema auth;
do $$ begin
 if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
 if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
 if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
end $$;
grant usage on schema public to anon, authenticated, service_role;
grant usage on schema auth to anon, authenticated, service_role;
create table auth.users(id uuid primary key);
-- Supabase's auth.uid(): the JWT "sub" claim of the current request
create or replace function auth.uid() returns uuid language sql stable as
$$ select nullif(coalesce(current_setting('request.jwt.claim.sub',true),(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')),'')::uuid $$;
grant execute on function auth.uid() to anon, authenticated;

-- ASSUMED: conversations columns were not reported (id + created_at modelled)
create table public.conversations(id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now());
-- REPORTED: conversation_members(conversation_id, user_id, archived, blocked, joined_at)
create table public.conversation_members(
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 user_id uuid not null references auth.users(id),
 archived boolean not null default false,
 blocked boolean not null default false,
 joined_at timestamptz not null default now(),
 primary key(conversation_id,user_id));            -- ASSUMED key
-- REPORTED: messages(id, conversation_id, sender_id, message, deleted, created_at)
create table public.messages(
 id uuid primary key default gen_random_uuid(),
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 sender_id uuid not null references auth.users(id),
 message text not null,
 deleted boolean not null default false,
 created_at timestamptz not null default now());

-- Supabase default grants on public tables (ASSUMED - includes TRUNCATE)
grant all on public.conversations, public.conversation_members, public.messages to anon, authenticated, service_role;

alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
-- REPORTED: members INSERT only user_id = auth.uid(); SELECT only own row
create policy conversation_members_insert_own on public.conversation_members for insert to authenticated with check (user_id = auth.uid());
create policy cm_select_self on public.conversation_members for select to authenticated using (user_id = auth.uid());
-- ASSUMED: members may update their own row (archived / blocked flags)
create policy cm_update_own on public.conversation_members for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
-- ASSUMED (not reported): conversations/messages readable & writable by members
create policy conv_select_member on public.conversations for select to authenticated
 using (exists(select 1 from public.conversation_members m where m.conversation_id = conversations.id and m.user_id = auth.uid()));
-- ASSUMED name: live allows clients to create empty conversations
create policy conversations_insert_authenticated on public.conversations for insert to authenticated with check (true);
create policy msg_select_member on public.messages for select to authenticated
 using (exists(select 1 from public.conversation_members m where m.conversation_id = messages.conversation_id and m.user_id = auth.uid()));
create policy msg_insert_member on public.messages for insert to authenticated
 with check (sender_id = auth.uid() and exists(select 1 from public.conversation_members m where m.conversation_id = messages.conversation_id and m.user_id = auth.uid()));

-- realtime stand-in: notify on inserts (the bridge re-checks visibility per viewer under RLS)
create or replace function public._rt_notify() returns trigger language plpgsql as
$$ begin perform pg_notify('rt', json_build_object('table',TG_TABLE_NAME,'row',row_to_json(new))::text); return new; end $$;
create trigger _rt_msg after insert on public.messages for each row execute function public._rt_notify();
create trigger _rt_cm after insert on public.conversation_members for each row execute function public._rt_notify();

insert into auth.users values ('aaaaaaaa-1111-4111-8111-111111111111'),('bbbbbbbb-2222-4222-8222-222222222222'),('cccccccc-3333-4333-8333-333333333333');
