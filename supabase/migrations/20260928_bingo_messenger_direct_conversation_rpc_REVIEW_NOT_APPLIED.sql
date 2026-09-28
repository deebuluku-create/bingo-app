-- ============================================================
-- BINGO MESSENGER - server-side direct conversation creation + member lookup
-- STATUS: FOR REVIEW - NOT APPLIED to the live project.
--
-- Why: live RLS on public.conversation_members allows a client to INSERT
-- only its own row (user_id = auth.uid()) and to SELECT only its own row.
-- So a client can neither add the recipient as a member nor see who else
-- is in its conversations. Those two policies are NOT changed here.
-- Instead, two narrowly scoped SECURITY DEFINER functions:
--
--   bingo_get_or_create_direct_conversation(p_other_user uuid) -> uuid
--     caller must be signed in; recipient must be a real, different user;
--     the pair must have an ACCEPTED Request to Communicate
--     (public.bingo_communication_requests - apply that file first);
--     returns the existing two-member conversation of the pair, or creates
--     the conversation + BOTH member rows in one transaction (all or
--     nothing); a per-pair advisory lock stops concurrent duplicates.
--
--   bingo_my_conversation_members() -> setof (conversation_id, user_id,
--     archived, blocked, joined_at)
--     the member rows of conversations the CALLER belongs to - nothing else.
--
-- Nothing else changes: no table, column, policy or client grant is
-- altered. The TRUNCATE grant correction is a SEPARATE file
-- (20260928_bingo_messaging_revoke_truncate_REVIEW_NOT_APPLIED.sql).
--
-- FINDING (not changed here - needs its own decision): the reported
-- conversation_members INSERT policy (user_id = auth.uid()) lets ANY signed-in
-- user insert their own member row into ANY conversation whose id they know,
-- and would then pass a membership-based messages SELECT policy. Once these
-- functions are live, clients no longer need to insert member rows at all,
-- so that client INSERT policy could be dropped (only the functions insert).
-- Reproduced on the local replica: supabase/tests/messenger_rpc_test.sh.
--
-- Tested on a local PostgreSQL 16 replica of the reported contract (see
-- the Messenger commit message for the list) - not yet on live Supabase.
-- ============================================================

begin;

-- ---------- 0. Preflight: stop if the live tables differ from what this relies on ----------
do $$
declare missing text; required text; id_type text;
begin
  if to_regclass('public.bingo_communication_requests') is null then
    raise exception 'Apply 20260928_bingo_messenger_communication_requests first - conversations may only start after an accepted request';
  end if;
  select string_agg(c, ', ') into missing
  from unnest(array['conversation_id','user_id','archived','blocked','joined_at']) c
  where not exists (select 1 from information_schema.columns
                    where table_schema='public' and table_name='conversation_members' and column_name=c);
  if missing is not null then raise exception 'conversation_members is missing: %', missing; end if;

  select data_type into id_type from information_schema.columns
  where table_schema='public' and table_name='conversations' and column_name='id';
  if id_type is distinct from 'uuid' then raise exception 'conversations.id is % (expected uuid)', coalesce(id_type,'missing'); end if;

  -- the function inserts "default values": every other NOT NULL column needs a default
  select string_agg(column_name, ', ') into required from information_schema.columns
  where table_schema='public' and table_name='conversations'
    and is_nullable='NO' and column_default is null and is_identity='NO' and column_name<>'id';
  if required is not null then
    raise exception 'conversations has NOT NULL columns without defaults (%) - extend the INSERT in bingo_get_or_create_direct_conversation first', required;
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='conversations' and column_name='id' and column_default is not null) then
    raise exception 'conversations.id has no default';
  end if;
end $$;

-- ---------- 1. Create or reuse the direct conversation of (caller, recipient) ----------
create or replace function public.bingo_get_or_create_direct_conversation(p_other_user uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me   uuid := auth.uid();
  v_conv uuid;
  v_req  text;
begin
  if v_me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_other_user is null or p_other_user = v_me then
    raise exception 'invalid recipient' using errcode = '22023';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_other_user) then
    raise exception 'recipient not found' using errcode = 'P0002';
  end if;

  -- Bingo rule: private messaging starts only after the recipient accepts
  -- a Request to Communicate
  select r.status into v_req from public.bingo_communication_requests r
  where least(r.requester_id, r.recipient_id) = least(v_me, p_other_user)
    and greatest(r.requester_id, r.recipient_id) = greatest(v_me, p_other_user);
  if v_req is distinct from 'accepted' then
    raise exception '%', case coalesce(v_req, 'none')
      when 'none'     then 'request to communicate required'
      when 'pending'  then 'request to communicate is pending'
      when 'rejected' then 'request to communicate was declined'
      when 'blocked'  then 'messaging is blocked between these members'
      else 'request to communicate not accepted' end
      using errcode = '42501';
  end if;

  -- one creator at a time per pair (order-independent key): A->B and B->A
  -- racing each other end up with the same single conversation
  perform pg_advisory_xact_lock(
    hashtextextended(least(v_me, p_other_user)::text || ':' || greatest(v_me, p_other_user)::text, 0));

  -- reuse: a conversation whose members are exactly these two users
  select m1.conversation_id into v_conv
  from public.conversation_members m1
  join public.conversation_members m2
    on m2.conversation_id = m1.conversation_id and m2.user_id = p_other_user
  where m1.user_id = v_me
    and (select count(*) from public.conversation_members m3
         where m3.conversation_id = m1.conversation_id) = 2
  order by m1.joined_at, m1.conversation_id
  limit 1;

  if v_conv is not null then
    return v_conv;
  end if;

  -- create: conversation + both members, one transaction (any error rolls all back)
  insert into public.conversations default values returning id into v_conv;
  insert into public.conversation_members (conversation_id, user_id)
  values (v_conv, v_me), (v_conv, p_other_user);
  return v_conv;
end;
$$;

-- ---------- 2. Member rows of the caller's own conversations ----------
create or replace function public.bingo_my_conversation_members()
returns table (conversation_id uuid, user_id uuid, archived boolean, blocked boolean, joined_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select m.conversation_id, m.user_id, m.archived, m.blocked, m.joined_at
  from public.conversation_members m
  where m.conversation_id in (
    select mine.conversation_id from public.conversation_members mine
    where mine.user_id = auth.uid()
  );
$$;

-- ---------- 3. Who may call them: signed-in users only ----------
revoke all on function public.bingo_get_or_create_direct_conversation(uuid) from public, anon;
revoke all on function public.bingo_my_conversation_members() from public, anon;
grant execute on function public.bingo_get_or_create_direct_conversation(uuid) to authenticated;
grant execute on function public.bingo_my_conversation_members() to authenticated;

commit;

-- ---------- Verify after applying (read-only) ----------
-- select p.proname, p.prosecdef, p.proconfig, pg_get_function_identity_arguments(p.oid)
-- from pg_proc p join pg_namespace n on n.oid=p.pronamespace
-- where n.nspname='public' and p.proname in ('bingo_get_or_create_direct_conversation','bingo_my_conversation_members');
-- select routine_name, grantee, privilege_type from information_schema.routine_privileges
-- where routine_schema='public' and routine_name like 'bingo_%conversation%';

-- ---------- Rollback ----------
-- drop function if exists public.bingo_get_or_create_direct_conversation(uuid);
-- drop function if exists public.bingo_my_conversation_members();
