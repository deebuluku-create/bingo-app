-- Bingo paid crowns: Bronze KSh 5, Silver KSh 25, Gold KSh 50.
-- Additive only. Production was applied through Supabase migration bingo_paid_crowns_20261004.
create table if not exists public.bingo_crown_purchases (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references auth.users(id) on delete restrict,
  recipient_id uuid not null references auth.users(id) on delete restrict,
  topic_id uuid references public.bingo_topics(id) on delete set null,
  crown_type text not null check (crown_type in ('bronze','silver','gold')),
  amount integer not null check ((crown_type='bronze' and amount=5) or (crown_type='silver' and amount=25) or (crown_type='gold' and amount=50)),
  phone text not null,
  payment_status text not null default 'pending' check (payment_status in ('pending','stk_sent','paid','failed','cancelled','expired')),
  merchant_request_id text, checkout_request_id text unique, mpesa_receipt text,
  result_code integer, result_description text, raw_callback jsonb,
  created_at timestamptz not null default now(), paid_at timestamptz
);
alter table public.bingo_crown_purchases enable row level security;
drop policy if exists bingo_crown_purchase_read_parties on public.bingo_crown_purchases;
create policy bingo_crown_purchase_read_parties on public.bingo_crown_purchases for select using (auth.uid()=buyer_id or auth.uid()=recipient_id or public.bingo_is_super_user());
create table if not exists public.bingo_crown_awards (
 id uuid primary key default gen_random_uuid(), purchase_id uuid not null unique references public.bingo_crown_purchases(id) on delete restrict,
 giver_id uuid not null references auth.users(id) on delete restrict, recipient_id uuid not null references auth.users(id) on delete restrict,
 topic_id uuid references public.bingo_topics(id) on delete set null, crown_type text not null check(crown_type in('bronze','silver','gold')),
 crown_count integer not null default 1 check(crown_count=1), amount_paid integer not null check(amount_paid in(5,25,50)), awarded_at timestamptz not null default now()
);
alter table public.bingo_crown_awards enable row level security;
drop policy if exists bingo_crown_awards_public_read on public.bingo_crown_awards;
create policy bingo_crown_awards_public_read on public.bingo_crown_awards for select using(true);
create index if not exists bingo_crown_awards_recipient_week_idx on public.bingo_crown_awards(recipient_id,awarded_at desc);
create index if not exists bingo_crown_awards_topic_idx on public.bingo_crown_awards(topic_id,awarded_at desc);
create or replace function public.bingo_weekly_crown_leaderboard(p_limit integer default 20)
returns table(recipient_id uuid,crowns bigint,amount_total bigint) language sql stable security definer set search_path=public as $$
 select recipient_id,count(*)::bigint,sum(amount_paid)::bigint from public.bingo_crown_awards
 where awarded_at >= date_trunc('week',now() at time zone 'Africa/Nairobi') at time zone 'Africa/Nairobi'
 group by recipient_id order by count(*) desc,sum(amount_paid) desc limit greatest(1,least(coalesce(p_limit,20),100))
$$;
grant execute on function public.bingo_weekly_crown_leaderboard(integer) to anon,authenticated;