-- ============================================================
-- BINGO MESSENGER - Request to Communicate (server-enforced)
-- STATUS: FOR REVIEW - NOT APPLIED.   APPLY FIRST (before the RPC file).
--
-- Rule: a member may start private messaging only after the recipient
-- accepts a Request to Communicate. This file creates the real record
-- and the only functions allowed to change it; the conversation RPC
-- (20260928_bingo_messenger_direct_conversation_rpc_...) and a
-- RESTRICTIVE messages INSERT policy (below) both consult it, so neither
-- a frontend gate nor a client write can bypass it.
--
-- One row per PAIR of members (order-independent), holding who asked
-- whom and the current state:
--   pending   requester asked, recipient has not answered
--   accepted  either member may start / continue private messaging
--   rejected  recipient declined; the requester cannot ask again
--             (the recipient may later send their own request)
--   blocked   blocked_by blocked the other member; no requests, no new
--             conversation, no new messages, until blocked_by unblocks
-- Clients: SELECT their own rows only. No client INSERT/UPDATE/DELETE/
-- TRUNCATE - every change goes through the SECURITY DEFINER functions.
-- The live project has no such table today (verified by the owner).
-- ============================================================

begin;

do $$ begin
  if to_regclass('public.bingo_communication_requests') is not null then
    raise exception 'public.bingo_communication_requests already exists - review before re-applying';
  end if;
end $$;

create table public.bingo_communication_requests (
  id            uuid primary key default gen_random_uuid(),
  requester_id  uuid not null references auth.users(id) on delete cascade,
  recipient_id  uuid not null references auth.users(id) on delete cascade,
  status        text not null default 'pending'
                check (status in ('pending','accepted','rejected','blocked')),
  blocked_by    uuid references auth.users(id) on delete cascade,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  responded_at  timestamptz,
  constraint bingo_comm_req_not_self check (requester_id <> recipient_id),
  constraint bingo_comm_req_blocked_by check (
    (status = 'blocked') = (blocked_by is not null)
    and (blocked_by is null or blocked_by in (requester_id, recipient_id)))
);
-- one row per pair, whichever member asked
create unique index bingo_comm_req_pair_uq on public.bingo_communication_requests
  (least(requester_id, recipient_id), greatest(requester_id, recipient_id));
create index bingo_comm_req_recipient_idx on public.bingo_communication_requests (recipient_id, status);

alter table public.bingo_communication_requests enable row level security;
create policy bingo_comm_req_select_own on public.bingo_communication_requests
  for select to authenticated
  using (auth.uid() in (requester_id, recipient_id));

-- Supabase grants ALL on new public tables to anon/authenticated by
-- default: take everything back, then allow reading own rows only.
revoke all on table public.bingo_communication_requests from anon, authenticated, public;
grant select on table public.bingo_communication_requests to authenticated;

-- ---------- helpers ----------
create or replace function public._bingo_comm_pair_lock(a uuid, b uuid)
returns void language sql volatile set search_path = '' as $$
  select pg_advisory_xact_lock(hashtextextended('bingo_comm:' || least(a,b)::text || ':' || greatest(a,b)::text, 0));
$$;

-- is private messaging allowed between the caller and p_other right now?
create or replace function public.bingo_can_message_member(p_other uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.bingo_communication_requests r
    where r.status = 'accepted'
      and least(r.requester_id, r.recipient_id)    = least(auth.uid(), p_other)
      and greatest(r.requester_id, r.recipient_id) = greatest(auth.uid(), p_other));
$$;

-- may the caller post into this conversation? every OTHER member of it
-- must have an accepted request with the caller (used by the restrictive
-- messages policy; a conversation with no other member is refused)
create or replace function public.bingo_can_post_in_conversation(p_conversation uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null
     and exists (select 1 from public.conversation_members m
                 where m.conversation_id = p_conversation and m.user_id <> auth.uid())
     and not exists (
       select 1 from public.conversation_members m
       where m.conversation_id = p_conversation and m.user_id <> auth.uid()
         and not exists (
           select 1 from public.bingo_communication_requests r
           where r.status = 'accepted'
             and least(r.requester_id, r.recipient_id)    = least(auth.uid(), m.user_id)
             and greatest(r.requester_id, r.recipient_id) = greatest(auth.uid(), m.user_id)));
$$;

-- ---------- 1. send a Request to Communicate ----------
-- returns the resulting status: 'pending' or 'accepted' (a request to
-- someone who already asked you counts as accepting theirs)
create or replace function public.bingo_request_communication(p_recipient uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_me uuid := auth.uid(); r public.bingo_communication_requests%rowtype;
begin
  if v_me is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if p_recipient is null or p_recipient = v_me then raise exception 'invalid recipient' using errcode = '22023'; end if;
  if not exists (select 1 from auth.users u where u.id = p_recipient) then
    raise exception 'recipient not found' using errcode = 'P0002'; end if;
  perform public._bingo_comm_pair_lock(v_me, p_recipient);
  select * into r from public.bingo_communication_requests x
  where least(x.requester_id, x.recipient_id) = least(v_me, p_recipient)
    and greatest(x.requester_id, x.recipient_id) = greatest(v_me, p_recipient);
  if not found then
    insert into public.bingo_communication_requests (requester_id, recipient_id) values (v_me, p_recipient);
    return 'pending';
  end if;
  if r.status = 'blocked' then raise exception 'messaging is blocked between these members' using errcode = '42501'; end if;
  if r.status = 'accepted' then return 'accepted'; end if;
  if r.status = 'pending' then
    if r.requester_id = v_me then return 'pending'; end if;
    update public.bingo_communication_requests
       set status = 'accepted', responded_at = now(), updated_at = now() where id = r.id;
    return 'accepted';
  end if;
  -- rejected
  if r.requester_id = v_me then
    raise exception 'your request was declined' using errcode = '42501';
  end if;
  update public.bingo_communication_requests
     set requester_id = v_me, recipient_id = p_recipient, status = 'pending',
         responded_at = null, updated_at = now(), created_at = now()
   where id = r.id;
  return 'pending';
end $$;

-- ---------- 2. accept or decline a pending request addressed to the caller ----------
create or replace function public.bingo_respond_communication_request(p_requester uuid, p_accept boolean)
returns text language plpgsql security definer set search_path = '' as $$
declare v_me uuid := auth.uid(); v_status text;
begin
  if v_me is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if p_accept is null then raise exception 'p_accept is required' using errcode = '22023'; end if;
  perform public._bingo_comm_pair_lock(v_me, p_requester);
  update public.bingo_communication_requests
     set status = case when p_accept then 'accepted' else 'rejected' end,
         responded_at = now(), updated_at = now()
   where requester_id = p_requester and recipient_id = v_me and status = 'pending'
   returning status into v_status;
  if v_status is null then raise exception 'no pending request from this member' using errcode = 'P0002'; end if;
  return v_status;
end $$;

-- ---------- 3. block / unblock ----------
create or replace function public.bingo_block_member(p_other uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if p_other is null or p_other = v_me then raise exception 'invalid member' using errcode = '22023'; end if;
  if not exists (select 1 from auth.users u where u.id = p_other) then raise exception 'member not found' using errcode = 'P0002'; end if;
  perform public._bingo_comm_pair_lock(v_me, p_other);
  update public.bingo_communication_requests
     set status = 'blocked', blocked_by = v_me, updated_at = now()
   where least(requester_id, recipient_id) = least(v_me, p_other)
     and greatest(requester_id, recipient_id) = greatest(v_me, p_other)
     and status <> 'blocked';                      -- an existing block (by either) stays as it is
  if not found and not exists (
       select 1 from public.bingo_communication_requests
       where least(requester_id, recipient_id) = least(v_me, p_other)
         and greatest(requester_id, recipient_id) = greatest(v_me, p_other)) then
    insert into public.bingo_communication_requests (requester_id, recipient_id, status, blocked_by)
    values (v_me, p_other, 'blocked', v_me);
  end if;
  -- reflect it on the pair's conversation(s) for the UI (enforcement is the request row)
  update public.conversation_members m set blocked = true
   where m.conversation_id in (select a.conversation_id from public.conversation_members a
                               join public.conversation_members b on b.conversation_id = a.conversation_id
                               where a.user_id = v_me and b.user_id = p_other)
     and m.user_id in (v_me, p_other);
  return 'blocked';
end $$;

-- removes the caller's own block; the pair then has no relationship and
-- needs a new Request to Communicate
create or replace function public.bingo_unblock_member(p_other uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  perform public._bingo_comm_pair_lock(v_me, p_other);
  delete from public.bingo_communication_requests
   where least(requester_id, recipient_id) = least(v_me, p_other)
     and greatest(requester_id, recipient_id) = greatest(v_me, p_other)
     and status = 'blocked' and blocked_by = v_me;
  if not found then raise exception 'you have not blocked this member' using errcode = 'P0002'; end if;
  update public.conversation_members m set blocked = false
   where m.conversation_id in (select a.conversation_id from public.conversation_members a
                               join public.conversation_members b on b.conversation_id = a.conversation_id
                               where a.user_id = v_me and b.user_id = p_other)
     and m.user_id in (v_me, p_other);
  return 'none';
end $$;

-- ---------- 4. sending also requires acceptance (RESTRICTIVE: only narrows) ----------
-- AND-ed with the existing permissive messages INSERT policy; does not
-- replace or loosen it.
create policy bingo_messages_insert_requires_accepted_request on public.messages
  as restrictive for insert to authenticated
  with check (public.bingo_can_post_in_conversation(conversation_id));

-- ---------- 5. who may call what ----------
revoke all on function public._bingo_comm_pair_lock(uuid, uuid) from public, anon, authenticated;
revoke all on function public.bingo_can_message_member(uuid) from public, anon;
revoke all on function public.bingo_can_post_in_conversation(uuid) from public, anon;
revoke all on function public.bingo_request_communication(uuid) from public, anon;
revoke all on function public.bingo_respond_communication_request(uuid, boolean) from public, anon;
revoke all on function public.bingo_block_member(uuid) from public, anon;
revoke all on function public.bingo_unblock_member(uuid) from public, anon;
grant execute on function public.bingo_can_message_member(uuid) to authenticated;
grant execute on function public.bingo_can_post_in_conversation(uuid) to authenticated;
grant execute on function public.bingo_request_communication(uuid) to authenticated;
grant execute on function public.bingo_respond_communication_request(uuid, boolean) to authenticated;
grant execute on function public.bingo_block_member(uuid) to authenticated;
grant execute on function public.bingo_unblock_member(uuid) to authenticated;

commit;

-- ---------- Rollback ----------
-- drop policy if exists bingo_messages_insert_requires_accepted_request on public.messages;
-- drop function if exists public.bingo_unblock_member(uuid), public.bingo_block_member(uuid),
--   public.bingo_respond_communication_request(uuid, boolean), public.bingo_request_communication(uuid),
--   public.bingo_can_post_in_conversation(uuid), public.bingo_can_message_member(uuid),
--   public._bingo_comm_pair_lock(uuid, uuid);
-- drop table if exists public.bingo_communication_requests;
