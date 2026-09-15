-- ============================================================================
-- BINGO — PUBLIC WALL / BINGO TOPICS (Supabase backend)
--
-- NOT applied. NOT approved. For review only.
--
-- Tables (additive; nothing here touches property_listings,
-- food_businesses, food_menu_items, vehicles, or bingo_moderation_cases):
--   1. bingo_topics
--   2. bingo_topic_comments
--   3. bingo_topic_reactions
--   4. bingo_topic_saves
--   5. bingo_topic_reports
--   6. topic-media Storage bucket (PRIVATE) + policies
--
-- Moderation authority is public.bingo_is_super_user() throughout (see
-- bingo_change2_super_user_security.sql). No dedicated "moderator" role
-- is invented.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Shared helpers
-- ---------------------------------------------------------------------------
create or replace function public.bingo_touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Safely parses a Storage path segment as a uuid, returning null instead of
-- raising on a malformed/garbage segment, so a bad object path can never
-- turn a whole SELECT/INSERT/UPDATE/DELETE on storage.objects into an error.
create or replace function public.bingo_safe_uuid(p_text text)
returns uuid
language sql
immutable
as $$
  select case
    when p_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then p_text::uuid
    else null
  end;
$$;

-- Blocks an ordinary UPDATE from ever reassigning which topic or which
-- user a comment/reaction belongs to. Used by bingo_topic_comments and
-- bingo_topic_reactions below (both have topic_id + user_id columns).
-- This runs unconditionally, including for a Super User: there is no
-- legitimate reason to re-parent a comment/reaction via UPDATE, so this
-- is not gated on public.bingo_is_super_user() the way moderation_status
-- locking is — reassignment should be delete-and-recreate, not UPDATE.
create or replace function public.bingo_lock_identity_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.topic_id is distinct from old.topic_id then
    new.topic_id := old.topic_id;
  end if;
  if new.user_id is distinct from old.user_id then
    new.user_id := old.user_id;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. bingo_topics
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_topics (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users(id) on delete cascade,
  title              text not null default '',
  body               text not null default '',
  category           text not null default 'General',
  media              jsonb not null default '[]'::jsonb,
  moderation_status  text not null default 'visible' check (moderation_status in ('visible','hidden')),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint bingo_topics_has_content check (length(trim(title)) > 0 or length(trim(body)) > 0)
);

alter table public.bingo_topics enable row level security;

drop policy if exists bingo_topics_select on public.bingo_topics;
create policy bingo_topics_select on public.bingo_topics
  for select
  using (
    moderation_status = 'visible'
    or auth.uid() = user_id
    or public.bingo_is_super_user()
  );

drop policy if exists bingo_topics_insert on public.bingo_topics;
create policy bingo_topics_insert on public.bingo_topics
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists bingo_topics_update on public.bingo_topics;
create policy bingo_topics_update on public.bingo_topics
  for update
  using (auth.uid() = user_id or public.bingo_is_super_user())
  with check (auth.uid() = user_id or public.bingo_is_super_user());

drop policy if exists bingo_topics_delete on public.bingo_topics;
create policy bingo_topics_delete on public.bingo_topics
  for delete
  using (auth.uid() = user_id or public.bingo_is_super_user());

-- Only public.bingo_is_super_user() may actually change moderation_status.
-- An owner's UPDATE still succeeds for every other column; this silently
-- reverts just that one field otherwise.
create or replace function public.bingo_topics_lock_moderation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.moderation_status is distinct from old.moderation_status
     and not public.bingo_is_super_user() then
    new.moderation_status := old.moderation_status;
  end if;
  return new;
end;
$$;

drop trigger if exists bingo_topics_lock_moderation_trg on public.bingo_topics;
create trigger bingo_topics_lock_moderation_trg
  before update on public.bingo_topics
  for each row
  execute function public.bingo_topics_lock_moderation();

-- user_id (authorship) is immutable for EVERYONE, including a Super
-- User — unlike moderation_status, there is no legitimate reason for
-- authorship itself to ever be reassigned. Moderation may still change
-- moderation_status freely (see the trigger above); this trigger only
-- ever touches user_id.
create or replace function public.bingo_topics_lock_author()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.user_id is distinct from old.user_id then
    new.user_id := old.user_id;
  end if;
  return new;
end;
$$;

drop trigger if exists bingo_topics_lock_author_trg
  on public.bingo_topics;

create trigger bingo_topics_lock_author_trg
  before update on public.bingo_topics
  for each row
  execute function public.bingo_topics_lock_author();

drop trigger if exists bingo_topics_touch_updated_at_trg on public.bingo_topics;
create trigger bingo_topics_touch_updated_at_trg
  before update on public.bingo_topics
  for each row
  execute function public.bingo_touch_updated_at();

create index if not exists bingo_topics_user_idx on public.bingo_topics(user_id);
create index if not exists bingo_topics_public_idx on public.bingo_topics(moderation_status, created_at desc);
create index if not exists bingo_topics_category_idx on public.bingo_topics(category);

-- ---------------------------------------------------------------------------
-- 2. bingo_topic_comments
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_topic_comments (
  id                 uuid primary key default gen_random_uuid(),
  topic_id           uuid not null references public.bingo_topics(id) on delete cascade,
  user_id            uuid not null references auth.users(id) on delete cascade,
  body               text not null check (length(trim(body)) > 0),
  moderation_status  text not null default 'visible' check (moderation_status in ('visible','hidden')),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

alter table public.bingo_topic_comments enable row level security;

drop policy if exists bingo_topic_comments_select on public.bingo_topic_comments;
create policy bingo_topic_comments_select on public.bingo_topic_comments
  for select
  using (
    (
      moderation_status = 'visible'
      and exists (
        select 1 from public.bingo_topics t
        where t.id = bingo_topic_comments.topic_id
          and t.moderation_status = 'visible'
      )
    )
    or auth.uid() = user_id
    or public.bingo_is_super_user()
  );

-- Comment INSERT verifies the parent topic is visible, owned by the
-- commenter, or accessible to a Super User.
drop policy if exists bingo_topic_comments_insert on public.bingo_topic_comments;
create policy bingo_topic_comments_insert on public.bingo_topic_comments
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

-- UPDATE re-validates the (unchangeable, per the identity-lock trigger
-- below) parent topic on every edit, in both USING and WITH CHECK: an
-- edit is only allowed while the topic remains visible, owned by the
-- editor, or a Super User is acting.
drop policy if exists bingo_topic_comments_update on public.bingo_topic_comments;
create policy bingo_topic_comments_update on public.bingo_topic_comments
  for update
  using (
    (auth.uid() = user_id or public.bingo_is_super_user())
    and exists (
      select 1 from public.bingo_topics t
      where t.id = topic_id
        and (t.moderation_status = 'visible' or t.user_id = auth.uid() or public.bingo_is_super_user())
    )
  )
  with check (
    (auth.uid() = user_id or public.bingo_is_super_user())
    and exists (
      select 1 from public.bingo_topics t
      where t.id = topic_id
        and (t.moderation_status = 'visible' or t.user_id = auth.uid() or public.bingo_is_super_user())
    )
  );

drop policy if exists bingo_topic_comments_delete on public.bingo_topic_comments;
create policy bingo_topic_comments_delete on public.bingo_topic_comments
  for delete
  using (auth.uid() = user_id or public.bingo_is_super_user());

-- Only a Super User may change moderation_status.
create or replace function public.bingo_topic_comments_lock_moderation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.moderation_status is distinct from old.moderation_status
     and not public.bingo_is_super_user() then
    new.moderation_status := old.moderation_status;
  end if;
  return new;
end;
$$;

drop trigger if exists bingo_topic_comments_lock_moderation_trg on public.bingo_topic_comments;
create trigger bingo_topic_comments_lock_moderation_trg
  before update on public.bingo_topic_comments
  for each row
  execute function public.bingo_topic_comments_lock_moderation();

-- Nobody may reassign a comment's topic_id or user_id via UPDATE.
drop trigger if exists bingo_topic_comments_lock_identity_trg on public.bingo_topic_comments;
create trigger bingo_topic_comments_lock_identity_trg
  before update on public.bingo_topic_comments
  for each row
  execute function public.bingo_lock_identity_columns();

drop trigger if exists bingo_topic_comments_touch_updated_at_trg on public.bingo_topic_comments;
create trigger bingo_topic_comments_touch_updated_at_trg
  before update on public.bingo_topic_comments
  for each row
  execute function public.bingo_touch_updated_at();

create index if not exists bingo_topic_comments_topic_idx on public.bingo_topic_comments(topic_id, created_at);
create index if not exists bingo_topic_comments_user_idx on public.bingo_topic_comments(user_id);

-- ---------------------------------------------------------------------------
-- 3. bingo_topic_reactions — SELECT/INSERT/UPDATE all tied to the parent
--    topic's visibility, in both USING and WITH CHECK. DELETE (removing
--    your own reaction) is never blocked by a topic later becoming
--    hidden. topic_id/user_id can never be changed via UPDATE (trigger).
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_topic_reactions (
  id            uuid primary key default gen_random_uuid(),
  topic_id      uuid not null references public.bingo_topics(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  reaction_type text not null default 'love' check (reaction_type in ('like','love')),
  created_at    timestamptz not null default now(),
  unique (topic_id, user_id)
);

alter table public.bingo_topic_reactions enable row level security;

drop policy if exists bingo_topic_reactions_select on public.bingo_topic_reactions;
create policy bingo_topic_reactions_select on public.bingo_topic_reactions
  for select
  using (
    exists (
      select 1 from public.bingo_topics t
      where t.id = topic_id
        and (t.moderation_status = 'visible' or t.user_id = auth.uid() or public.bingo_is_super_user())
    )
  );

drop policy if exists bingo_topic_reactions_insert on public.bingo_topic_reactions;
create policy bingo_topic_reactions_insert on public.bingo_topic_reactions
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

-- WITH CHECK re-validates the parent topic, matching USING (needed even
-- though the identity-lock trigger keeps topic_id constant across the
-- update, so both clauses independently enforce the same rule).
drop policy if exists bingo_topic_reactions_update on public.bingo_topic_reactions;
create policy bingo_topic_reactions_update on public.bingo_topic_reactions
  for update
  using (
    auth.uid() = user_id
    and exists (
      select 1 from public.bingo_topics t
      where t.id = topic_id
        and (t.moderation_status = 'visible' or t.user_id = auth.uid() or public.bingo_is_super_user())
    )
  )
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.bingo_topics t
      where t.id = topic_id
        and (t.moderation_status = 'visible' or t.user_id = auth.uid() or public.bingo_is_super_user())
    )
  );

drop policy if exists bingo_topic_reactions_delete on public.bingo_topic_reactions;
create policy bingo_topic_reactions_delete on public.bingo_topic_reactions
  for delete
  using (auth.uid() = user_id);

-- Nobody may reassign a reaction's topic_id or user_id via UPDATE
-- (switching like<->love is the only legitimate UPDATE this table needs).
drop trigger if exists bingo_topic_reactions_lock_identity_trg on public.bingo_topic_reactions;
create trigger bingo_topic_reactions_lock_identity_trg
  before update on public.bingo_topic_reactions
  for each row
  execute function public.bingo_lock_identity_columns();

create index if not exists bingo_topic_reactions_topic_idx on public.bingo_topic_reactions(topic_id);

-- ---------------------------------------------------------------------------
-- 4. bingo_topic_saves — SELECT and INSERT both respect topic visibility;
--    DELETE (unsaving) is always allowed for your own save regardless, so
--    a hidden topic never traps an existing save. A Super User can always
--    see any save for moderation oversight. No UPDATE policy exists for
--    this table at all, so it can never be re-parented via UPDATE.
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_topic_saves (
  id          uuid primary key default gen_random_uuid(),
  topic_id    uuid not null references public.bingo_topics(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (topic_id, user_id)
);

alter table public.bingo_topic_saves enable row level security;

drop policy if exists bingo_topic_saves_select on public.bingo_topic_saves;
create policy bingo_topic_saves_select on public.bingo_topic_saves
  for select
  using (
    public.bingo_is_super_user()
    or (
      auth.uid() = user_id
      and exists (
        select 1 from public.bingo_topics t
        where t.id = topic_id
          and (t.moderation_status = 'visible' or t.user_id = auth.uid())
      )
    )
  );

drop policy if exists bingo_topic_saves_insert on public.bingo_topic_saves;
create policy bingo_topic_saves_insert on public.bingo_topic_saves
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

drop policy if exists bingo_topic_saves_delete on public.bingo_topic_saves;
create policy bingo_topic_saves_delete on public.bingo_topic_saves
  for delete
  using (auth.uid() = user_id);

create index if not exists bingo_topic_saves_user_idx on public.bingo_topic_saves(user_id);

-- ---------------------------------------------------------------------------
-- 5. bingo_topic_reports — private to the reporter and Super Users.
--    unique(topic_id, reporter_id): one active report per reporter per
--    topic. INSERT also verifies the reported topic is itself accessible
--    to the reporter (visible, or theirs, or they are a Super User) — you
--    cannot file a report referencing a topic you cannot see.
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_topic_reports (
  id           uuid primary key default gen_random_uuid(),
  topic_id     uuid not null references public.bingo_topics(id) on delete cascade,
  reporter_id  uuid not null references auth.users(id) on delete cascade,
  reason       text not null default 'Other',
  details      text not null default '',
  created_at   timestamptz not null default now(),
  unique (topic_id, reporter_id)
);

alter table public.bingo_topic_reports enable row level security;

drop policy if exists bingo_topic_reports_select on public.bingo_topic_reports;
create policy bingo_topic_reports_select on public.bingo_topic_reports
  for select
  using (auth.uid() = reporter_id or public.bingo_is_super_user());

drop policy if exists bingo_topic_reports_insert on public.bingo_topic_reports;
create policy bingo_topic_reports_insert on public.bingo_topic_reports
  for insert
  to authenticated
  with check (
    auth.uid() = reporter_id
    and exists (
      select 1 from public.bingo_topics t
      where t.id = topic_id
        and (t.moderation_status = 'visible' or t.user_id = auth.uid() or public.bingo_is_super_user())
    )
  );
-- No update/delete: reports are immutable once filed. The unique
-- constraint means a repeat report attempt fails as a unique violation,
-- which the client should read as "you already reported this."

create index if not exists bingo_topic_reports_topic_idx on public.bingo_topic_reports(topic_id);

-- ---------------------------------------------------------------------------
-- 6. topic-media Storage bucket — PRIVATE. Path convention:
--    {user_id}/{topic_id}/{filename}
--
-- SELECT: the object's own owner-prefix, a Super User, or the topic named
-- by the path's second segment currently being visible.
--
-- INSERT/UPDATE/DELETE: all three require the owner-prefixed path
-- (segment 1 = auth.uid()) AND that segment 2 parses (via
-- public.bingo_safe_uuid(), so a malformed segment evaluates to "no
-- match" instead of raising) as a real bingo_topics row owned by that
-- same auth.uid(). UPDATE covers upsert-mode uploads (overwriting an
-- existing object), which is a Storage UPDATE, not an INSERT. DELETE
-- additionally allows a Super User unconditionally — see the ordering
-- note below for why.
--
-- Frontend upload order (required by the INSERT check above, since it
-- needs the topic row to already exist and already be owned by the
-- caller): 1) INSERT the bingo_topics row first (title/body/category,
-- media: []). 2) Upload the media file(s) to Storage under that real
-- topic id. 3) UPDATE the topic row's media column with the resulting
-- path(s)/url(s). This is the reverse of "upload first, insert the row
-- after" used by property/food listings, and is not optional here.
--
-- Frontend deletion order (required by the DELETE check's ownership
-- join): 1) Delete the topic's media objects from Storage FIRST, while
-- the bingo_topics row — and therefore the ownership check these
-- policies depend on — still exists. 2) Only then delete the bingo_topics
-- row itself. Deleting the topic row first would cascade-delete it out
-- from under its own media before that media can be removed, and since
-- the ownership check joins live to bingo_topics, the orphaned objects
-- would become unremovable by their own uploader afterward (the
-- public.bingo_is_super_user() clause on DELETE exists specifically as a
-- recovery path if this order is ever missed by mistake).
--
-- Corrected note on signed URLs (a false claim in an earlier revision of
-- this file has been removed): a signed URL from
-- supabase.storage.from('topic-media').createSignedUrl(path, ttl), once
-- issued, remains fetchable for its full ttl regardless of any later
-- moderation_status change — Supabase Storage validates that request
-- against the signed token's own signature and expiry, not against this
-- RLS policy again. Hiding a topic therefore does NOT retroactively
-- revoke a signed URL a viewer already has open; it only stops a NEW
-- signed URL from being issued for that media from that point on. To
-- keep the exposure window small, the frontend should request short-
-- lived signed URLs (refreshed as needed) rather than long ones, and/or
-- use an authenticated download (`.download(path)`) instead of a signed
-- URL when immediate revocation on hide genuinely matters, since a fresh
-- `.download()` call IS re-checked against this policy every time.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('topic-media', 'topic-media', false)
on conflict (id) do update set public = false;

drop policy if exists topic_media_public_read on storage.objects;
drop policy if exists topic_media_read on storage.objects;
create policy topic_media_read on storage.objects
  for select
  using (
    bucket_id = 'topic-media'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.bingo_is_super_user()
      or exists (
        select 1 from public.bingo_topics t
        where t.id = public.bingo_safe_uuid((storage.foldername(name))[2])
          and t.moderation_status = 'visible'
      )
    )
  );

drop policy if exists topic_media_owner_write on storage.objects;
create policy topic_media_owner_write on storage.objects
  for insert
  with check (
    bucket_id = 'topic-media'
    and (storage.foldername(name))[1] = auth.uid()::text
    and exists (
      select 1 from public.bingo_topics t
      where t.id = public.bingo_safe_uuid((storage.foldername(name))[2])
        and t.user_id = auth.uid()
    )
  );

drop policy if exists topic_media_owner_update on storage.objects;
create policy topic_media_owner_update on storage.objects
  for update
  using (
    bucket_id = 'topic-media'
    and (storage.foldername(name))[1] = auth.uid()::text
    and exists (
      select 1 from public.bingo_topics t
      where t.id = public.bingo_safe_uuid((storage.foldername(name))[2])
        and t.user_id = auth.uid()
    )
  )
  with check (
    bucket_id = 'topic-media'
    and (storage.foldername(name))[1] = auth.uid()::text
    and exists (
      select 1 from public.bingo_topics t
      where t.id = public.bingo_safe_uuid((storage.foldername(name))[2])
        and t.user_id = auth.uid()
    )
  );

drop policy if exists topic_media_owner_delete on storage.objects;
create policy topic_media_owner_delete on storage.objects
  for delete
  using (
    bucket_id = 'topic-media'
    and (
      public.bingo_is_super_user()
      or (
        (storage.foldername(name))[1] = auth.uid()::text
        and exists (
          select 1 from public.bingo_topics t
          where t.id = public.bingo_safe_uuid((storage.foldername(name))[2])
            and t.user_id = auth.uid()
        )
      )
    )
  );
