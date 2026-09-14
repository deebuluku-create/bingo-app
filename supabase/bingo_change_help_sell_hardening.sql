-- ============================================================================
-- BINGO — HELP SELL FINAL HARDENING
--
-- Two corrections to bingo_change_help_sell_collaboration.sql, applied
-- additively (CREATE OR REPLACE on the same function signatures — no new
-- tables, no data migration needed). Run AFTER that file.
--
-- 1. bingo_owner_accept_help_seller now takes a listing-scoped
--    pg_advisory_xact_lock BEFORE counting accepted helpers. The previous
--    version's `for update` locks only the request row and whatever
--    accepted rows already exist at that instant — it does not stop two
--    concurrent transactions, each accepting a DIFFERENT pending request
--    for the same listing, from both passing the "< 3" check before
--    either commits its own new accepted row. The advisory lock is keyed
--    on the listing itself (not on any row), so every concurrent
--    acceptance attempt for that listing serializes through one mutex,
--    making "recount, then accept" truly atomic under real concurrency —
--    this is what a four-simultaneous-request test actually exercises.
--
-- 2. Vehicle listings have no authoritative backend table (documented
--    already in Change 09's boost-quote and this feature's own first
--    migration), so a vehicle Help Sell request's owner_id could only
--    ever be taken on the client's word. Acceptance itself still can't be
--    forged (only the true owner_id's own session can accept), but an
--    unverifiable request can still spam a stranger's queue, generate a
--    misleading notification, and leave an audit trail Bingo cannot
--    stand behind. Per the correction's own instruction, Help Sell is
--    disabled for vehicle (and every other backend-unverifiable type —
--    spare/cv/job/profile/post) until a real vehicle-listings table
--    exists; bingo_request_help_sell now rejects those types outright
--    instead of accepting a client-supplied owner_id. Property, Stay and
--    Food Business — the types with a real backend owner column — are
--    unaffected and remain fully available.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. bingo_owner_accept_help_seller — advisory-lock-first
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

  -- Serialize every acceptance attempt for THIS listing through one
  -- transaction-scoped mutex (released automatically at commit/rollback,
  -- no separate unlock needed) before counting or writing anything, so
  -- "count, then accept" can never race across concurrent callers.
  perform pg_advisory_xact_lock(hashtextextended(v_req.listing_type || ':' || v_req.listing_id, 0));

  -- Recount after acquiring the lock — the count taken before it would
  -- not be trustworthy under concurrency. Only 'accepted' rows occupy a
  -- position; rejected/withdrawn/removed/completed never do.
  select count(*) into v_accepted_count
  from public.bingo_help_sell_requests
  where listing_type = v_req.listing_type and listing_id = v_req.listing_id and status = 'accepted';

  if v_accepted_count >= 3 then
    raise exception 'This listing already has three helper-sellers';
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
-- 2. bingo_request_help_sell — reject backend-unverifiable listing types
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

  if not (p_listing_type in ('property','stay','food_business')) then
    raise exception 'Help Sell is not yet available for this listing type — it requires a verified backend owner record.';
  end if;

  v_owner_id := public._bingo_resolve_listing_owner(p_listing_type, p_listing_id);
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

-- bingo_complete_help_sell_listing already routes non-property/stay/
-- food_business types through _bingo_resolve_listing_owner's null result
-- and falls back to auth.uid()=owner check — since no vehicle request can
-- be created anymore, this path is simply unreachable for vehicles going
-- forward and needs no change.
