-- ============================================================================
-- BINGO — HELP SELL: THREE-MEMBER COLLABORATION (Supabase backend)
--
-- New, additive feature. Does not touch property_listings, food_businesses,
-- bingo_user_roles, bingo_business_agent_access, bingo_moderation_cases,
-- boosting or M-Pesa tables. Reuses the existing bingo_role_audit_log
-- (audit) and bingo_role_notifications (Inbox) tables rather than creating
-- parallel ones.
--
-- listing_id is TEXT, not uuid: vehicle listings (Bingo's primary, most
-- reachable listing type) have small integer/timestamp-based ids with no
-- backend table at all, so a uuid column would reject them outright.
-- Property/stay/food_business ids ARE uuids and are cast with ::uuid at
-- every point this file actually queries their real tables.
--
-- Ownership note (same documented limitation as boost-quote and the Agent
-- packets): property_listings and food_businesses have a real backend
-- owner column this file can verify against server-side. Vehicle listings
-- (and spare/CV/job/profile-style listings) have no backend table at all,
-- so p_owner_id for those types is taken from the client at REQUEST time
-- only — it grants nothing by itself. The only real gate is acceptance: a
-- request only ever becomes 'accepted' when auth.uid() matches that
-- stored owner_id, so a forged owner_id can at worst land an unwanted
-- pending request in a stranger's queue for them to reject; it can never
-- grant unauthorized access to anyone.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. bingo_help_sell_requests
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_help_sell_requests (
  id uuid primary key default gen_random_uuid(),
  listing_type text not null,
  listing_id text not null,
  owner_id uuid not null references auth.users(id) on delete cascade,
  helper_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check
    (status in ('pending','accepted','rejected','withdrawn','removed','completed')),
  rules_version text not null,
  rules_accepted_at timestamptz not null,
  requested_at timestamptz not null default now(),
  accepted_at timestamptz,
  rejected_at timestamptz,
  withdrawn_at timestamptz,
  removed_at timestamptz,
  completed_at timestamptz,
  owner_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists bingo_help_sell_one_active_request
  on public.bingo_help_sell_requests(listing_type,listing_id,helper_id)
  where status in ('pending','accepted');

create index if not exists bingo_help_sell_listing_status
  on public.bingo_help_sell_requests(listing_type,listing_id,status);

alter table public.bingo_help_sell_requests enable row level security;

drop policy if exists "Owners view Help Sell requests" on public.bingo_help_sell_requests;
create policy "Owners view Help Sell requests"
on public.bingo_help_sell_requests for select to authenticated
using (owner_id=auth.uid());

drop policy if exists "Helpers view own Help Sell requests" on public.bingo_help_sell_requests;
create policy "Helpers view own Help Sell requests"
on public.bingo_help_sell_requests for select to authenticated
using (helper_id=auth.uid());
-- Do not grant direct client INSERT, UPDATE or DELETE.
-- All mutations must use protected SECURITY DEFINER RPCs.

-- ---------------------------------------------------------------------------
-- 2. Shared internal helper — resolves the real owner for the post types
--    that have a backend table, so ownership is never taken purely on the
--    client's word where it doesn't have to be. Returns null (meaning
--    "unverifiable here") for vehicle/spare/cv/job/profile listings.
-- ---------------------------------------------------------------------------
create or replace function public._bingo_resolve_listing_owner(p_listing_type text, p_listing_id text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_listing_type in ('property','stay') then
    return (select user_id from public.property_listings where id = p_listing_id::uuid);
  elsif p_listing_type = 'food_business' then
    return (select user_id from public.food_businesses where id = p_listing_id::uuid);
  end if;
  return null;
exception when invalid_text_representation then
  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. bingo_request_help_sell
-- ---------------------------------------------------------------------------
create or replace function public.bingo_request_help_sell(
  p_listing_type text,
  p_listing_id text,
  p_owner_id uuid,
  p_rules_version text
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_request_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.'; end if;
  if p_rules_version is null or btrim(p_rules_version) = '' then
    raise exception 'You must accept the Help Sell rules before requesting.';
  end if;

  v_owner_id := coalesce(public._bingo_resolve_listing_owner(p_listing_type, p_listing_id), p_owner_id);
  if v_owner_id is null then
    raise exception 'This listing could not be identified.';
  end if;
  if v_owner_id = auth.uid() then
    raise exception 'You cannot request to help sell your own listing.';
  end if;

  if p_listing_type in ('property','stay') then
    if not exists (select 1 from public.property_listings where id = p_listing_id::uuid and status = 'published') then
      raise exception 'This listing is not currently published.';
    end if;
  elsif p_listing_type = 'food_business' then
    if not exists (select 1 from public.food_businesses where id = p_listing_id::uuid and status = 'active') then
      raise exception 'This business is not currently active.';
    end if;
  end if;

  if exists (
    select 1 from public.bingo_help_sell_requests
    where listing_type = p_listing_type and listing_id = p_listing_id and helper_id = auth.uid()
      and status in ('pending','accepted')
  ) then
    raise exception 'You already have a pending or active Help Sell request for this listing.';
  end if;

  if (select count(*) from public.bingo_help_sell_requests
      where listing_type = p_listing_type and listing_id = p_listing_id and status = 'accepted') >= 3 then
    raise exception 'This listing already has three helper-sellers.';
  end if;

  insert into public.bingo_help_sell_requests(listing_type, listing_id, owner_id, helper_id, rules_version, rules_accepted_at)
  values (p_listing_type, p_listing_id, v_owner_id, auth.uid(), btrim(p_rules_version), now())
  returning id into v_request_id;

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), v_owner_id, 'help_sell_requested', jsonb_build_object('request_id', v_request_id, 'listing_type', p_listing_type, 'listing_id', p_listing_id));

  insert into public.bingo_role_notifications(user_id, message)
  values (v_owner_id, 'A member has requested to help sell one of your listings. Review the request from your listing.');

  return v_request_id;
end;
$$;

revoke all on function public.bingo_request_help_sell(text,text,uuid,text) from public;
grant execute on function public.bingo_request_help_sell(text,text,uuid,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. bingo_owner_accept_help_seller — the atomic acceptance rule
-- ---------------------------------------------------------------------------
create or replace function public.bingo_owner_accept_help_seller(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req public.bingo_help_sell_requests;
  v_accepted_count integer;
begin
  if auth.uid() is null then raise exception 'Sign in required.'; end if;

  select * into v_req from public.bingo_help_sell_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found.'; end if;
  if v_req.owner_id <> auth.uid() then raise exception 'Only the listing owner may accept this request.'; end if;
  if v_req.status <> 'pending' then raise exception 'This request is no longer pending.'; end if;

  -- Lock every active relationship for this exact listing so a
  -- simultaneous acceptance on another request cannot race past the
  -- three-helper limit.
  perform id from public.bingo_help_sell_requests
  where listing_type = v_req.listing_type and listing_id = v_req.listing_id and status = 'accepted'
  for update;

  select count(*) into v_accepted_count
  from public.bingo_help_sell_requests
  where listing_type = v_req.listing_type and listing_id = v_req.listing_id and status = 'accepted';

  if v_accepted_count >= 3 then
    raise exception 'This listing already has three helper-sellers.';
  end if;

  update public.bingo_help_sell_requests
  set status = 'accepted', accepted_at = now(), updated_at = now()
  where id = p_request_id;

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), v_req.helper_id, 'help_sell_accepted', jsonb_build_object('request_id', p_request_id, 'listing_type', v_req.listing_type, 'listing_id', v_req.listing_id));

  insert into public.bingo_role_notifications(user_id, message)
  values (v_req.helper_id, 'You have been accepted as a Help Sell helper for a listing. You can now share it and introduce interested buyers to the owner.');

  if v_accepted_count + 1 >= 3 then
    insert into public.bingo_role_notifications(user_id, message)
    values (v_req.owner_id, 'Your listing now has 3 of 3 Help Sell helpers. Help Sell is full for this listing.');
  end if;
end;
$$;

revoke all on function public.bingo_owner_accept_help_seller(uuid) from public;
grant execute on function public.bingo_owner_accept_help_seller(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. bingo_owner_reject_help_seller
-- ---------------------------------------------------------------------------
create or replace function public.bingo_owner_reject_help_seller(p_request_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req public.bingo_help_sell_requests;
begin
  if auth.uid() is null then raise exception 'Sign in required.'; end if;
  select * into v_req from public.bingo_help_sell_requests where id = p_request_id;
  if not found then raise exception 'Request not found.'; end if;
  if v_req.owner_id <> auth.uid() then raise exception 'Only the listing owner may reject this request.'; end if;
  if v_req.status <> 'pending' then raise exception 'This request is no longer pending.'; end if;

  update public.bingo_help_sell_requests
  set status = 'rejected', rejected_at = now(), owner_note = p_note, updated_at = now()
  where id = p_request_id;

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), v_req.helper_id, 'help_sell_rejected', jsonb_build_object('request_id', p_request_id));

  insert into public.bingo_role_notifications(user_id, message)
  values (v_req.helper_id, 'Your Help Sell request was not accepted for this listing.');
end;
$$;

revoke all on function public.bingo_owner_reject_help_seller(uuid,text) from public;
grant execute on function public.bingo_owner_reject_help_seller(uuid,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. bingo_helper_leave_listing
-- ---------------------------------------------------------------------------
create or replace function public.bingo_helper_leave_listing(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req public.bingo_help_sell_requests;
begin
  if auth.uid() is null then raise exception 'Sign in required.'; end if;
  select * into v_req from public.bingo_help_sell_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found.'; end if;
  if v_req.helper_id <> auth.uid() then raise exception 'Only the helper may leave this listing.'; end if;
  if v_req.status not in ('pending','accepted') then raise exception 'This request is not currently active.'; end if;

  update public.bingo_help_sell_requests
  set status = 'withdrawn', withdrawn_at = now(), updated_at = now()
  where id = p_request_id;

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), v_req.owner_id, 'help_sell_left', jsonb_build_object('request_id', p_request_id, 'was_status', v_req.status));

  insert into public.bingo_role_notifications(user_id, message)
  values (v_req.owner_id, 'A Help Sell helper has left your listing. The position is available again.');
end;
$$;

revoke all on function public.bingo_helper_leave_listing(uuid) from public;
grant execute on function public.bingo_helper_leave_listing(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. bingo_owner_remove_help_seller
-- ---------------------------------------------------------------------------
create or replace function public.bingo_owner_remove_help_seller(p_request_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req public.bingo_help_sell_requests;
begin
  if auth.uid() is null then raise exception 'Sign in required.'; end if;
  select * into v_req from public.bingo_help_sell_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found.'; end if;
  if v_req.owner_id <> auth.uid() then raise exception 'Only the listing owner may remove a helper.'; end if;
  if v_req.status <> 'accepted' then raise exception 'This helper is not currently active.'; end if;

  update public.bingo_help_sell_requests
  set status = 'removed', removed_at = now(), owner_note = p_note, updated_at = now()
  where id = p_request_id;

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), v_req.helper_id, 'help_sell_removed', jsonb_build_object('request_id', p_request_id, 'note', p_note));

  insert into public.bingo_role_notifications(user_id, message)
  values (v_req.helper_id, 'The owner has removed you as a Help Sell helper for their listing.');
end;
$$;

revoke all on function public.bingo_owner_remove_help_seller(uuid,text) from public;
grant execute on function public.bingo_owner_remove_help_seller(uuid,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. bingo_complete_help_sell_listing — called when a listing is marked
--    sold. Closes every active/pending relationship without deleting the
--    audit trail (status only ever moves to 'completed', rows stay).
-- ---------------------------------------------------------------------------
create or replace function public.bingo_complete_help_sell_listing(p_listing_type text, p_listing_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_req record;
begin
  if auth.uid() is null then raise exception 'Sign in required.'; end if;

  v_owner_id := coalesce(public._bingo_resolve_listing_owner(p_listing_type, p_listing_id), auth.uid());
  if v_owner_id <> auth.uid() and not public.bingo_is_super_user() then
    raise exception 'Only the listing owner may close Help Sell for this listing.';
  end if;

  for v_req in
    select * from public.bingo_help_sell_requests
    where listing_type = p_listing_type and listing_id = p_listing_id and status in ('pending','accepted')
    for update
  loop
    update public.bingo_help_sell_requests
    set status = 'completed', completed_at = now(), updated_at = now()
    where id = v_req.id;

    insert into public.bingo_role_notifications(user_id, message)
    values (v_req.helper_id, 'The listing you were helping sell has been marked sold. Thank you for helping.');
  end loop;

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (auth.uid(), auth.uid(), 'help_sell_listing_completed', jsonb_build_object('listing_type', p_listing_type, 'listing_id', p_listing_id));
end;
$$;

revoke all on function public.bingo_complete_help_sell_listing(text,text) from public;
grant execute on function public.bingo_complete_help_sell_listing(text,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. bingo_help_sell_listing_summary — public-safe aggregate read (accepted
--    count only) plus the caller's own status when signed in. Grantable to
--    anon too: a guest must see the blinking "Help Selling Active" dot and
--    the Help Sell button (which then asks them to log in when pressed).
-- ---------------------------------------------------------------------------
create or replace function public.bingo_help_sell_listing_summary(p_listing_type text, p_listing_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_accepted_count integer;
  v_my_status text;
  v_my_request_id uuid;
begin
  select count(*) into v_accepted_count
  from public.bingo_help_sell_requests
  where listing_type = p_listing_type and listing_id = p_listing_id and status = 'accepted';

  if auth.uid() is not null then
    select status, id into v_my_status, v_my_request_id
    from public.bingo_help_sell_requests
    where listing_type = p_listing_type and listing_id = p_listing_id and helper_id = auth.uid()
      and status in ('pending','accepted')
    order by requested_at desc
    limit 1;
  end if;

  return jsonb_build_object(
    'accepted_count', v_accepted_count,
    'my_status', v_my_status,
    'my_request_id', v_my_request_id
  );
end;
$$;

revoke all on function public.bingo_help_sell_listing_summary(text,text) from public;
grant execute on function public.bingo_help_sell_listing_summary(text,text) to authenticated, anon;
