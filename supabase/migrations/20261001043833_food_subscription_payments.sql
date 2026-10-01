-- Service-only payment ledger. No client can insert, change, or inspect callbacks.
create table public.food_subscription_payments (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null,
 owner_id uuid not null,
 phone text not null check (phone ~ '^254[17][0-9]{8}$'),
 amount integer not null default 1000 check (amount=1000),
 days integer not null default 30 check (days=30),
 environment text not null check (environment in ('sandbox','production')),
 status text not null default 'requesting' check (status in ('requesting','pending','unknown','paid','failed')),
 callback_token_hash text not null check (callback_token_hash ~ '^[a-f0-9]{64}$'),
 checkout_request_id text unique,
 merchant_request_id text,
 callback_payload jsonb,
 result_code integer,
 result_description text,
 receipt text unique,
 activated_at timestamptz,
 subscription_expires_at timestamptz,
 created_at timestamptz not null default now(),
 completed_at timestamptz
);
alter table public.food_subscription_payments enable row level security;
revoke all on public.food_subscription_payments from public,anon,authenticated;
grant select,insert,update on public.food_subscription_payments to service_role;
create unique index food_subscription_one_pending on public.food_subscription_payments(business_id,environment) where status in ('requesting','pending','unknown');
create index food_subscription_owner_created on public.food_subscription_payments(owner_id,created_at desc);

-- Called only by the authenticated Edge Function's service client AFTER a
-- server-to-server Safaricom query. Ledger completion and activation are atomic.
create function public.bingo_finish_food_subscription_payment(
 p_payment_id uuid,p_checkout text,p_code integer,p_description text,p_receipt text default null
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare p public.food_subscription_payments%rowtype; f public.food_businesses%rowtype; expires timestamptz;
begin
 select * into p from public.food_subscription_payments where id=p_payment_id for update;
 if not found then raise exception 'Payment not found';end if;
 if p_checkout is null or p_checkout is distinct from p.checkout_request_id then raise exception 'Checkout mismatch';end if;
 if p.status='paid' then
  if p_code=0 and p_receipt is not null and p.receipt is null then update public.food_subscription_payments set receipt=p_receipt where id=p.id;end if;
  return jsonb_build_object('status','paid','activated',p.activated_at is not null,'duplicate',true);
 end if;
 if p.status='failed' then return jsonb_build_object('status','failed','duplicate',true);end if;
 if p_code is null or p_code<0 then raise exception 'Invalid payment result';end if;
 if p_code<>0 then
  update public.food_subscription_payments set status='failed',result_code=p_code,result_description=p_description,completed_at=now() where id=p.id;
  return jsonb_build_object('status','failed','activated',false);
 end if;
 -- Sandbox tests NEVER change production restaurants or create paid exposure.
 if p.environment='production' then
  select * into f from public.food_businesses where id=p.business_id for update;
  if found and f.owner_id=p.owner_id and f.status not in ('hidden','deleted') then
   expires=greatest(now(),coalesce(f.subscription_expires_at,now()))+interval '30 days';
   update public.food_businesses set status='published',subscription_expires_at=expires,updated_at=now() where id=f.id;
  end if;
 end if;
 update public.food_subscription_payments set status='paid',result_code=0,result_description=p_description,receipt=p_receipt,completed_at=now(),activated_at=case when expires is not null then now() else null end,subscription_expires_at=expires where id=p.id;
 return jsonb_build_object('status','paid','activated',expires is not null,'subscription_expires_at',expires);
end $$;
revoke all on function public.bingo_finish_food_subscription_payment(uuid,text,integer,text,text) from public,anon,authenticated;
grant execute on function public.bingo_finish_food_subscription_payment(uuid,text,integer,text,text) to service_role;
notify pgrst,'reload schema';
