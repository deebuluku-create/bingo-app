-- ============================================================
-- DRAFT MIGRATION — Bingo Wall Smart Reactions (5 fixed reaction types)
-- Status: DRAFT ONLY. NOT APPLIED. Do not run against any Supabase project
-- without explicit approval.
--
-- Background: the approved reference design for Wall posts requires five
-- fixed, independently-toggleable reaction buttons (Umependeza! / Sketi
-- kali! / Nimeipenda! / Classy sana! / Hii ni fashion!) alongside the
-- existing single Love heart. The existing public.bingo_topic_reactions
-- table cannot be reused for this: its reaction_type check constraint
-- only allows ('like','love'), and its unique(topic_id,user_id)
-- constraint allows at most ONE reaction row per user per topic total -
-- adding the five new types there would either be rejected by the check
-- constraint or silently collide with a user's existing Love reaction.
-- This is therefore a new, additive table, not a change to the existing
-- one - it does not touch bingo_topic_reactions, bingo_topics or any
-- other existing table.
--
-- Frontend already tolerates this table not existing yet: aaLoadBingoWall
-- queries it alongside the other wall tables and treats a query error the
-- same as an empty result (see BINGO_MASTER_CURRENT_VERIFIED.html), so
-- not applying this migration is safe in the meantime - the five buttons
-- render with a real, honest 0 and simply cannot be toggled server-side
-- until this is deployed.
-- ============================================================

create table if not exists public.bingo_topic_smart_reactions (
  id            uuid primary key default gen_random_uuid(),
  topic_id      uuid not null references public.bingo_topics(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  reaction_type text not null
    check (reaction_type in ('umependeza','sketikali','nimeipenda','classysana','hiifashion')),
  created_at    timestamptz not null default now(),
  -- One row per (topic,user,reaction_type): a user may hold several of
  -- the five reactions on the same post at once (each button toggles
  -- independently), but never more than one row for the SAME reaction
  -- type on the SAME post - that is the "one-user reaction rule".
  unique (topic_id, user_id, reaction_type)
);

alter table public.bingo_topic_smart_reactions enable row level security;

drop policy if exists bingo_topic_smart_reactions_select on public.bingo_topic_smart_reactions;
create policy bingo_topic_smart_reactions_select on public.bingo_topic_smart_reactions
  for select
  using (
    exists (
      select 1 from public.bingo_topics t
      where t.id = topic_id
        and (t.moderation_status = 'visible' or t.user_id = auth.uid() or public.bingo_is_super_user())
    )
  );

drop policy if exists bingo_topic_smart_reactions_insert on public.bingo_topic_smart_reactions;
create policy bingo_topic_smart_reactions_insert on public.bingo_topic_smart_reactions
  for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.bingo_topics t
      where t.id = topic_id
        and (t.moderation_status = 'visible' or t.user_id = auth.uid() or public.bingo_is_super_user())
    )
  );

drop policy if exists bingo_topic_smart_reactions_delete on public.bingo_topic_smart_reactions;
create policy bingo_topic_smart_reactions_delete on public.bingo_topic_smart_reactions
  for delete
  using (auth.uid() = user_id);

-- No update policy: the frontend only ever inserts (new reaction) or
-- deletes (remove a reaction) - toggling never mutates an existing row's
-- topic_id/user_id/reaction_type, so there is nothing for UPDATE to do
-- and no identity-lock trigger is needed here (unlike bingo_topic_reactions,
-- which supports switching like<->love via UPDATE).

create index if not exists bingo_topic_smart_reactions_topic_idx on public.bingo_topic_smart_reactions(topic_id);
create index if not exists bingo_topic_smart_reactions_user_idx on public.bingo_topic_smart_reactions(user_id);

-- ============================================================
-- NOT INCLUDED IN THIS DRAFT (deliberately):
--  - Any change to bingo_topic_reactions (Love) - untouched.
--  - A moderation/anti-abuse layer beyond the existing per-user unique
--    constraint (rate limiting, bot detection) - out of scope for a
--    schema migration.
-- ============================================================
