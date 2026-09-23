-- ============================================================================
-- BINGO — FOOD ORDERS (Order flow / basket / status progression)
--
-- Status: DRAFT ONLY — NOT APPLIED. NOT approved. Do not run against any
-- Supabase project without explicit approval, per this session's standing
-- rule for every SQL change.
--
-- Why this exists: there was no order/basket concept anywhere in the
-- previous Food backend (food_businesses + food_menu_items only ever
-- covered the listing itself, never a customer placing an order against
-- it). The frontend (aaSubmitFoodOrder / aaUpdateFoodOrderStatus) already
-- degrades gracefully without this table: in testMode, or if this insert
-- fails because the table doesn't exist yet, orders are kept in the same
-- aa_v69-localStorage pattern used elsewhere in this file, so nothing
-- breaks today. Once this migration is applied, no frontend code change
-- is needed — orders simply start persisting for real.
--
-- Nothing here touches food_businesses, food_menu_items, or any other
-- existing table/policy.
-- ============================================================================

create table if not exists public.food_orders (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references public.food_businesses(id) on delete cascade,
  customer_id   uuid not null references auth.users(id) on delete cascade,
  -- Each element: {item_id, name, price_kes, qty} — a point-in-time copy of
  -- the menu item at order time, so a later price/name edit on the menu
  -- item never rewrites the customer's own order history.
  items         jsonb not null default '[]'::jsonb,
  total_kes     numeric not null default 0 check (total_kes >= 0),
  note          text not null default '',
  status        text not null default 'placed'
                  check (status in ('placed','ongoing','finished','dispatched')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

alter table public.food_orders enable row level security;

-- The customer who placed the order can always see it.
drop policy if exists food_orders_select_customer on public.food_orders;
create policy food_orders_select_customer on public.food_orders
  for select
  using (auth.uid() = customer_id);

-- The restaurant's owner can see every order placed against their own
-- business. (Manager/agent access to orders is enforced client-side today
-- via aaCanManageBusinessAction's "manage_orders" permission on top of the
-- existing agent-business-access system — this policy intentionally
-- covers the owner only; extending it to managers needs the same table
-- that already grants agents scoped access to a business, so it can be
-- added as a follow-up without touching this migration's shape.)
drop policy if exists food_orders_select_owner on public.food_orders;
create policy food_orders_select_owner on public.food_orders
  for select
  using (
    exists (
      select 1 from public.food_businesses b
      where b.id = food_orders.business_id
        and b.user_id = auth.uid()
    )
  );

-- Any authenticated member can place an order for themselves.
drop policy if exists food_orders_insert_customer on public.food_orders;
create policy food_orders_insert_customer on public.food_orders
  for insert
  with check (auth.uid() = customer_id);

-- Only the business owner may update an order (status progression).
-- customer_id/items/total_kes/business_id are not meant to change after
-- creation; enforcing that is left to the application layer, matching
-- how food_menu_items.preparation_type labels are already validated
-- client-side rather than via a trigger.
drop policy if exists food_orders_update_owner on public.food_orders;
create policy food_orders_update_owner on public.food_orders
  for update
  using (
    exists (
      select 1 from public.food_businesses b
      where b.id = food_orders.business_id
        and b.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.food_businesses b
      where b.id = food_orders.business_id
        and b.user_id = auth.uid()
    )
  );

create index if not exists food_orders_business_id_idx on public.food_orders(business_id);
create index if not exists food_orders_customer_id_idx on public.food_orders(customer_id);

-- ============================================================================
-- END DRAFT — NOT APPLIED
-- ============================================================================
