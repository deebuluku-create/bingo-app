-- ============================================================================
-- BINGO PACKET 09 — BOOST PAYMENT SERVER CLOSURE (Supabase backend)
--
-- Closes the gap this packet itself names: bingo-boost-quote already makes
-- the quote (price/placement/dates) server-authoritative, but the
-- deployed mpesa-boost Edge Function that actually takes payment and
-- receives the Safaricom callback is NOT part of this repository, so it
-- could not be inspected or edited directly. This migration adds the
-- pieces a replacement mpesa-boost (see
-- supabase/functions/mpesa-boost/index.ts, written fresh alongside this
-- file) needs to make quote verification, activation and Agent commission
-- atomic and idempotent — reusing bingo_boost_quotes (Change 09) and
-- bingo_agent_commission_ledger (Agent 1,000-client-target packet)
-- rather than inventing parallel ledgers.
--
-- IMPORTANT — table-name honesty: this repository has no visibility into
-- whatever M-Pesa transaction table the currently-deployed mpesa-boost
-- already writes to (if one exists). Rather than guess a name and risk a
-- second, disconnected ledger, this migration defines ONE new, clearly-
-- named raw-callback log (bingo_boost_mpesa_log) purely for receipt-reuse
-- detection and audit. If your deployed function already persists M-Pesa
-- transactions elsewhere, point bingo_activate_boost_from_quote's insert
-- at that table instead — it is the ONLY place in this file that needs
-- adjusting to reuse an existing transaction table.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. bingo_boost_activations — the server's own record that a quote was
--    verified and turned into a live boost. Vehicle listings have no
--    backend row to flip a boosted flag on (documented already in
--    boost-quote/index.ts), so this table — not a listing column — is
--    the authoritative "was this boost actually paid and activated"
--    record the client's boost_status poll reads from.
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_boost_activations (
  id                  uuid primary key default gen_random_uuid(),
  quote_id            uuid not null unique references public.bingo_boost_quotes(id),
  user_id             uuid not null references auth.users(id),
  agent_id            uuid references auth.users(id),
  mpesa_receipt       text,
  commission_credited boolean not null default false,
  activated_at        timestamptz not null default now()
);

alter table public.bingo_boost_activations enable row level security;

drop policy if exists bingo_boost_activations_select on public.bingo_boost_activations;
create policy bingo_boost_activations_select on public.bingo_boost_activations
  for select
  using (auth.uid() = user_id or public.bingo_is_super_user());
-- No insert/update/delete policy: only bingo_activate_boost_from_quote
-- (service-role only, below) ever writes here.

-- ---------------------------------------------------------------------------
-- 2. bingo_boost_mpesa_log — raw Safaricom callback receipts, kept purely
--    for replay/reuse detection and audit. One row per callback actually
--    processed (not per retry Safaricom itself may send for the same
--    transaction — the unique index below is what makes a replay a no-op
--    instead of a duplicate activation).
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_boost_mpesa_log (
  id                    uuid primary key default gen_random_uuid(),
  quote_id              uuid references public.bingo_boost_quotes(id),
  checkout_request_id   text,
  mpesa_receipt_number  text,
  result_code           integer,
  result_desc           text,
  amount                numeric(12,2),
  raw_payload           jsonb not null default '{}'::jsonb,
  received_at           timestamptz not null default now()
);

alter table public.bingo_boost_mpesa_log enable row level security;

drop policy if exists bingo_boost_mpesa_log_select on public.bingo_boost_mpesa_log;
create policy bingo_boost_mpesa_log_select on public.bingo_boost_mpesa_log
  for select
  using (public.bingo_is_super_user());
-- No insert/update/delete policy: only the mpesa-boost Edge Function
-- (service-role) writes here.

-- ---------------------------------------------------------------------------
-- 3. Idempotency constraints (per the packet's own required indexes)
-- ---------------------------------------------------------------------------
create unique index if not exists bingo_boost_quote_paid_once
  on public.bingo_boost_quotes(id)
  where status = 'paid';

create unique index if not exists bingo_mpesa_receipt_once
  on public.bingo_boost_mpesa_log(mpesa_receipt_number)
  where mpesa_receipt_number is not null;

-- Commission-once: one credit per quote, ever. Requires a quote reference
-- on the existing ledger table (Agent 1,000-client-target packet) —
-- added here, additive, nullable so every non-boost ledger entry (still
-- keyed by business_id/reference as before) is unaffected.
alter table public.bingo_agent_commission_ledger add column if not exists boost_quote_id uuid references public.bingo_boost_quotes(id);
create unique index if not exists bingo_agent_boost_commission_once
  on public.bingo_agent_commission_ledger(boost_quote_id)
  where entry_type = 'credit' and boost_quote_id is not null;

alter table public.bingo_boost_quotes add column if not exists checkout_request_id text;
create unique index if not exists bingo_boost_quotes_checkout_idx on public.bingo_boost_quotes(checkout_request_id) where checkout_request_id is not null;

-- ---------------------------------------------------------------------------
-- 4. bingo_activate_boost_from_quote — the single atomic transaction the
--    packet's pseudocode describes. Deliberately NOT granted to
--    `authenticated`: it may only be called by mpesa-boost's own
--    service-role client, strictly after that function has independently
--    verified the Safaricom callback (amount + receipt). Re-verifies
--    ownership/Agent authorization at confirmation time (not just at
--    quote-creation time), so a permission revoked between quote and
--    payment is caught here too, for the post types that have a real
--    backend authorization table (property/stay/food_business). Vehicle
--    quotes keep the same documented limitation as boost-quote itself:
--    no backend row exists to re-check ownership against.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_activate_boost_from_quote(
  p_quote_id uuid,
  p_mpesa_receipt text,
  p_confirmed_amount numeric,
  p_checkout_request_id text default null
) returns public.bingo_boost_activations
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quote public.bingo_boost_quotes;
  v_authorized boolean;
  v_is_agent boolean;
  v_activation public.bingo_boost_activations;
begin
  -- Lock the pending quote so a replayed/concurrent callback cannot
  -- process the same quote twice — this row lock is the transaction's
  -- real mutual-exclusion boundary, the unique indexes above are the
  -- backstop if two callbacks somehow race past it.
  select * into v_quote
  from public.bingo_boost_quotes
  where id = p_quote_id and status = 'quoted' and expires_at > now()
  for update;

  if not found then
    raise exception 'Quote not found, expired, cancelled, or already used.';
  end if;

  if p_confirmed_amount is null or p_confirmed_amount <> v_quote.amount_kes then
    raise exception 'Payment amount does not match the quoted amount. Activation stopped.';
  end if;

  if p_checkout_request_id is not null and v_quote.checkout_request_id is not null
     and p_checkout_request_id <> v_quote.checkout_request_id then
    raise exception 'This callback does not match the STK push started for this quote.';
  end if;

  -- Re-verify authorization at confirmation time, not just at quote time.
  -- For vehicle/spare/cv/job/profile quotes (the else branch) this always
  -- evaluates v_is_agent to false — those post types have no backend
  -- owner row to compare against, and vehicle Agent commission is already
  -- attributed by the pre-existing CLIENT-side aaRecordAgentCommissionIfApplicable
  -- (createdByAgentId, tracked locally, unrelated to who happened to pay
  -- for this specific boost). Crediting here too would double-count it.
  v_is_agent := v_quote.user_id <> (
    case v_quote.post_type
      when 'property' then (select user_id from public.property_listings where id = v_quote.post_id::uuid)
      when 'stay' then (select user_id from public.property_listings where id = v_quote.post_id::uuid)
      when 'food_business' then (select user_id from public.food_businesses where id = v_quote.post_id::uuid)
      else v_quote.user_id
    end
  );

  if v_quote.post_type in ('property','stay','food_business') then
    if v_is_agent then
      v_authorized := public.bingo_agent_can_manage_business(v_quote.post_type, v_quote.post_id::uuid, 'manage_boost');
    else
      v_authorized := true; -- confirmed owner match above
    end if;
    if not v_authorized then
      raise exception 'Boost authorization is no longer valid for this post.';
    end if;
  end if;

  insert into public.bingo_boost_activations(quote_id, user_id, agent_id, mpesa_receipt)
  values (p_quote_id, v_quote.user_id, case when v_is_agent then v_quote.user_id else null end, p_mpesa_receipt)
  returning * into v_activation;

  -- Credit Agent commission exactly once, only when an Agent (not the
  -- owner) paid for the boost. The unique index on boost_quote_id makes
  -- a second attempt (a replayed callback slipping past the row lock) a
  -- silent no-op rather than a duplicate credit.
  if v_is_agent then
    begin
      insert into public.bingo_agent_commission_ledger(agent_id, business_id, entry_type, amount, reference, boost_quote_id)
      values (v_quote.user_id, v_quote.post_id::uuid, 'credit', round(v_quote.amount_kes * 0.10, 2), 'boost:'||p_mpesa_receipt, p_quote_id);
      update public.bingo_boost_activations set commission_credited = true where id = v_activation.id;
      insert into public.bingo_role_notifications(user_id, message)
      values (v_quote.user_id, 'You earned KSh '||to_char(round(v_quote.amount_kes*0.10,2),'FM999,999,990')||' commission from a boost you initiated.');
    exception when unique_violation then
      null; -- already credited for this quote — expected on a replay, not an error
    end;
  end if;

  update public.bingo_boost_quotes set status = 'paid', boost_id = v_activation.id::text where id = p_quote_id;

  insert into public.bingo_role_audit_log(actor_id, target_id, action, details)
  values (v_quote.user_id, v_quote.user_id, 'boost_activated', jsonb_build_object(
    'quote_id', p_quote_id, 'post_type', v_quote.post_type, 'post_id', v_quote.post_id,
    'amount_kes', v_quote.amount_kes, 'mpesa_receipt', p_mpesa_receipt, 'agent_paid', v_is_agent
  ));

  return v_activation;
end;
$$;

revoke all on function public.bingo_activate_boost_from_quote(uuid,text,numeric,text) from public;
-- No grant to authenticated: service_role only, called from
-- mpesa-boost/index.ts after Safaricom's callback is independently
-- verified. An ordinary signed-in user (Agent or otherwise) must never be
-- able to self-activate a boost by calling this directly.

-- ---------------------------------------------------------------------------
-- 5. bingo_boost_activation_status — read-only, callable by the owning
--    user, so the client's boost_status poll can ask "is my quote paid
--    yet" without needing the service-role key.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_boost_activation_status(p_quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quote public.bingo_boost_quotes;
  v_activation public.bingo_boost_activations;
begin
  if auth.uid() is null then raise exception 'Sign in required.'; end if;
  select * into v_quote from public.bingo_boost_quotes where id = p_quote_id;
  if not found or v_quote.user_id <> auth.uid() then
    raise exception 'Quote not found.';
  end if;

  if v_quote.status = 'paid' then
    select * into v_activation from public.bingo_boost_activations where quote_id = p_quote_id;
    return jsonb_build_object('status','paid','mpesa_receipt',v_activation.mpesa_receipt,'expires_at',v_quote.expires_at);
  end if;
  if v_quote.status = 'expired' or (v_quote.status = 'quoted' and v_quote.expires_at <= now()) then
    return jsonb_build_object('status','expired');
  end if;
  if v_quote.status = 'cancelled' then
    return jsonb_build_object('status','cancelled');
  end if;
  return jsonb_build_object('status','pending');
end;
$$;

revoke all on function public.bingo_boost_activation_status(uuid) from public;
grant execute on function public.bingo_boost_activation_status(uuid) to authenticated;
