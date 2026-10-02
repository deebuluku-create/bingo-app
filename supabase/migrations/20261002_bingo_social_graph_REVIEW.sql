-- Bingo social graph review migration.
-- IMPORTANT: apply only after confirming the live profile table/columns.
create table if not exists public.bingo_follows (
 follower_id uuid not null references auth.users(id) on delete cascade,
 following_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(follower_id,following_id),
 constraint bingo_follows_not_self check(follower_id<>following_id)
);
create index if not exists bingo_follows_following_idx on public.bingo_follows(following_id);

create table if not exists public.bingo_friendships (
 id uuid primary key default gen_random_uuid(),
 requester_id uuid not null references auth.users(id) on delete cascade,
 addressee_id uuid not null references auth.users(id) on delete cascade,
 status text not null default 'pending' check(status in ('pending','accepted','declined','blocked')),
 created_at timestamptz not null default now(),
 responded_at timestamptz,
 constraint bingo_friendship_not_self check(requester_id<>addressee_id)
);
create unique index if not exists bingo_friendship_unique_pair
on public.bingo_friendships(least(requester_id,addressee_id),greatest(requester_id,addressee_id));

alter table public.bingo_follows enable row level security;
alter table public.bingo_friendships enable row level security;

-- Functions intentionally omitted until the live profile schema is inspected.
-- This prevents guessing whether Bingo uses profiles/bingo_profiles and prevents a duplicate profile system.
