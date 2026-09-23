-- ============================================================================
-- BINGO — WALL PHASE 2 FEATURES: schema-gap fill (Supabase backend)
--
-- NOT applied. NOT approved. For review only. Fully idempotent — every
-- statement is guarded (if not exists / create or replace / drop ... if
-- exists / a pg_constraint existence check before adding a named
-- constraint) so this file can be re-run any number of times with no
-- error and no data loss.
--
-- Scope: this fills the gaps found by auditing supabase/bingo_change_
-- public_wall_topics.sql, every other tracked supabase/*.sql file, and
-- the live frontend Supabase calls against the Phase 2-6 frontend work
-- (Aa styles, Smart Words, Mushene Corner/Bingo Box, refresh/notifications,
-- universal search, CV/candidate profiles). It does NOT recreate or drop
-- any existing Public Wall table, policy, trigger or function — every
-- change below is additive (new column, new table, new function, or a
-- new trigger on an existing table). It does NOT include any Camera/
-- Photo/Video/Live backend object.
--
-- Reused as-is, unchanged: bingo_is_super_user() (Change 2),
-- bingo_touch_updated_at() and bingo_safe_uuid() (Public Wall migration),
-- bingo_topics / bingo_topic_comments / bingo_topic_reactions /
-- bingo_topic_saves / bingo_topic_reports / topic-media (Public Wall
-- migration), bingo_promotion_rules (Change 10), bingo_moderation_cases
-- target_type list (Change 06 — 'candidate' was already anticipated
-- there; this file does not touch that table or its RPC).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Aa styled text — bingo_topics and bingo_topic_comments
--
--    Gap found: the composer already lets a member choose an Aa style
--    (AA_TOPIC_STYLES in the frontend) and Smart Word presses already
--    intend a style too, but neither bingo_topics nor bingo_topic_comments
--    has anywhere to store it — aaMapBingoTopicRow() currently hardcodes
--    style:'Standard' for every row loaded from Supabase, silently
--    discarding whatever the author actually picked. style_key/colour_key
--    are safe preset TOKENS only (checked against a fixed vocabulary),
--    never free text, matching "never render raw user HTML/CSS/JS".
-- ---------------------------------------------------------------------------
alter table public.bingo_topics
  add column if not exists style_key  text not null default 'Standard',
  add column if not exists colour_key text not null default 'ivory';

alter table public.bingo_topic_comments
  add column if not exists style_key  text not null default 'Standard',
  add column if not exists colour_key text not null default 'ivory';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'bingo_topics_style_key_check') then
    alter table public.bingo_topics
      add constraint bingo_topics_style_key_check
      check (style_key in ('Standard','Bold','Italic','Gold Premium','Colour Block','Neon','Celebration','Kenyan Theme','Handwritten','Minimal'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bingo_topics_colour_key_check') then
    alter table public.bingo_topics
      add constraint bingo_topics_colour_key_check
      check (colour_key in ('ivory','gold','cyan','red','navy'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bingo_topic_comments_style_key_check') then
    alter table public.bingo_topic_comments
      add constraint bingo_topic_comments_style_key_check
      check (style_key in ('Standard','Bold','Italic','Gold Premium','Colour Block','Neon','Celebration','Kenyan Theme','Handwritten','Minimal'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bingo_topic_comments_colour_key_check') then
    alter table public.bingo_topic_comments
      add constraint bingo_topic_comments_colour_key_check
      check (colour_key in ('ivory','gold','cyan','red','navy'));
  end if;
end $$;

-- No policy change needed: the existing bingo_topics_update /
-- bingo_topic_comments_update policies already let the owner change any
-- column (author/moderation locking is enforced by the existing TRIGGERS,
-- not the policies), so these new columns are automatically owner-editable
-- and are NOT subject to the moderation-lock or author-lock triggers,
-- which only ever touch moderation_status / user_id respectively.

-- ---------------------------------------------------------------------------
-- 2. Threaded replies — bingo_topic_comments.parent_comment_id
--
--    Gap found: "comments and replies" is part of the approved scope, but
--    bingo_topic_comments is flat today (no self-reference at all), so a
--    reply cannot be recorded as a reply. Nullable: null = top-level
--    comment, matching every comment created before this migration.
-- ---------------------------------------------------------------------------
alter table public.bingo_topic_comments
  add column if not exists parent_comment_id uuid references public.bingo_topic_comments(id) on delete cascade;

create index if not exists bingo_topic_comments_parent_idx
  on public.bingo_topic_comments(parent_comment_id)
  where parent_comment_id is not null;

-- A reply's parent can never be reassigned after creation, mirroring the
-- existing bingo_lock_identity_columns() philosophy for topic_id/user_id.
-- A NEW function is used (not a change to the shared
-- bingo_lock_identity_columns(), which is also used by
-- bingo_topic_reactions — a table that has no parent_comment_id column,
-- so altering the shared function instead of adding this one would break
-- reactions' own trigger the moment it ran).
create or replace function public.bingo_topic_comments_lock_parent()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.parent_comment_id is distinct from old.parent_comment_id then
    new.parent_comment_id := old.parent_comment_id;
  end if;
  return new;
end;
$$;

drop trigger if exists bingo_topic_comments_lock_parent_trg on public.bingo_topic_comments;
create trigger bingo_topic_comments_lock_parent_trg
  before update on public.bingo_topic_comments
  for each row
  execute function public.bingo_topic_comments_lock_parent();

-- ---------------------------------------------------------------------------
-- 3. bingo_topic_smart_reactions — real server-side duplicate prevention
--
--    Gap found: the frontend Smart Word press currently posts a plain row
--    into bingo_topic_comments and prevents a duplicate press only with an
--    in-memory JS Set (aaSmartWordPressed) that resets on every page
--    reload — reloading the page and pressing the same slot again would
--    silently create a second identical comment. This table gives the
--    duplicate rule a real, permanent, server-enforced home:
--    unique(topic_id, user_id, slot) makes a second press of the SAME
--    slot on the SAME topic by the SAME user fail as a unique violation
--    at the database level, regardless of what any client remembers.
--    No update/delete policy at all: a Smart Word press "locks... for
--    that post" per the approved spec, so it is permanent once made.
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_topic_smart_reactions (
  id          uuid primary key default gen_random_uuid(),
  topic_id    uuid not null references public.bingo_topics(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  slot        smallint not null check (slot between 0 and 4),
  phrase      text not null check (length(trim(phrase)) > 0 and length(phrase) <= 80),
  created_at  timestamptz not null default now(),
  unique (topic_id, user_id, slot)
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
-- No update policy, no delete policy: permanent once pressed, by design.

create index if not exists bingo_topic_smart_reactions_topic_idx on public.bingo_topic_smart_reactions(topic_id);

-- ---------------------------------------------------------------------------
-- 4. bingo_box_ranked() — real server-calculated Bingo Box ranking
--
--    Gap found: the frontend currently ranks Bingo Box entirely
--    client-side (aaBingoBoxEntries()/aaMusheneEngagementScore() in the
--    Mother file), from whatever topics/comments/reactions that specific
--    browser happens to already have loaded. That is not a shared,
--    tamper-resistant ranking, and it has no way to exclude promoted
--    content. SECURITY INVOKER (the default — stated explicitly here for
--    auditability) on purpose: it never needs to see more than the
--    calling user's own RLS-visible rows, which keeps this from ever
--    becoming a privilege-escalation path. Every caller — including an
--    anonymous visitor, matching "signed-out visitors may view" — gets
--    the SAME ranking for the SAME public data, because:
--      - the explicit moderation_status='visible' filter (redundant with
--        RLS, kept for defense-in-depth) means an owner's own hidden
--        topic is excluded from the ranking they see, same as everyone
--        else — Bingo Box must not look different to its own author;
--      - the NOT EXISTS against bingo_promotion_rules excludes any topic
--        with a currently-active promotion row (post_type='bingo_topic'),
--        matching both this migration's requirement 4 and the approved
--        Wall spec's own rule that Mushene posts are never paid-promoted
--        — today no such row will ever exist for a topic, so this check
--        currently never matches anything; it is here so the guarantee
--        holds automatically if that ever changes, without a migration;
--      - a hard "deleted" state does not need handling here: bingo_topics
--        rows are hard-deleted by the existing bingo_topics_delete
--        policy, so a deleted topic simply cannot appear in this query;
--      - there is no separate "failed" processing state for a text/Aa-
--        styled Wall post (that concept belongs to the future Photo/
--        Video/Live system's own processing pipeline, explicitly out of
--        scope here).
-- ---------------------------------------------------------------------------
create or replace function public.bingo_box_ranked(p_limit integer default 30)
returns table (
  topic_id  uuid,
  rank      integer,
  score     numeric,
  loves     bigint,
  comments  bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  with scored as (
    select
      t.id as topic_id,
      coalesce(r.love_count, 0) as loves,
      coalesce(c.comment_count, 0) as comments,
      (coalesce(r.love_count, 0) * 2 + coalesce(c.comment_count, 0) * 3)
        / power(greatest(extract(epoch from (now() - t.created_at)) / 3600.0, 0) + 2, 1.2) as score
    from public.bingo_topics t
    left join (
      select topic_id, count(*) as love_count
      from public.bingo_topic_reactions
      group by topic_id
    ) r on r.topic_id = t.id
    left join (
      select topic_id, count(*) as comment_count
      from public.bingo_topic_comments
      where moderation_status = 'visible'
      group by topic_id
    ) c on c.topic_id = t.id
    where t.moderation_status = 'visible'
      and not exists (
        select 1 from public.bingo_promotion_rules pr
        where pr.post_type = 'bingo_topic'
          and pr.post_id = t.id::text
          and pr.status = 'active'
          and pr.starts_at <= now()
          and pr.expires_at > now()
      )
  )
  select
    topic_id,
    (row_number() over (order by score desc, topic_id))::integer as rank,
    round(score, 6) as score,
    loves,
    comments
  from scored
  order by score desc, topic_id
  limit greatest(0, least(coalesce(p_limit, 30), 30));
$$;

revoke all on function public.bingo_box_ranked(integer) from public;
grant execute on function public.bingo_box_ranked(integer) to anon, authenticated;

-- Frontend note: this returns topic_id + rank/score/loves/comments only —
-- the caller still fetches full topic rows (title, author, media, ...)
-- from bingo_topics for the returned ids, exactly like every other list
-- already does. Wiring aaBingoBoxEntries() to call this RPC instead of
-- computing the ranking client-side is a frontend follow-up, not part of
-- this SQL-only change.

-- ---------------------------------------------------------------------------
-- 5. bingo_topic_notifications — pending-Inbox delivery, same shape as
--    bingo_role_notifications (Change 2) and bingo_moderation_notifications
--    (Change 06): a message waits here until the recipient's own next
--    session delivers it into the existing Bingo Inbox. Never self-
--    notifies (an author commenting/reacting on their own topic creates
--    no row). Populated only by the SECURITY DEFINER trigger below —
--    inserting a notification for a DIFFERENT user than the acting one
--    is exactly why it must be SECURITY DEFINER, unlike bingo_box_ranked.
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_topic_notifications (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  topic_id    uuid references public.bingo_topics(id) on delete set null,
  event_type  text not null check (event_type in ('comment','reaction','smart_reaction')),
  message     text not null,
  delivered   boolean not null default false,
  created_at  timestamptz not null default now()
);

alter table public.bingo_topic_notifications enable row level security;

drop policy if exists bingo_topic_notifications_select on public.bingo_topic_notifications;
create policy bingo_topic_notifications_select on public.bingo_topic_notifications
  for select
  using (auth.uid() = user_id);

drop policy if exists bingo_topic_notifications_update on public.bingo_topic_notifications;
create policy bingo_topic_notifications_update on public.bingo_topic_notifications
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
-- No insert/delete policy for ordinary users: only the trigger function
-- below (SECURITY DEFINER) writes here.

create index if not exists bingo_topic_notifications_user_idx on public.bingo_topic_notifications(user_id, delivered);

create or replace function public.bingo_topic_notify_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
  v_title text;
  v_event text;
  v_message text;
begin
  select user_id, coalesce(nullif(trim(title), ''), 'your Wall post')
    into v_owner, v_title
  from public.bingo_topics
  where id = new.topic_id;

  if v_owner is null or v_owner = new.user_id then
    return new; -- topic missing, or acting on your own post: never self-notify
  end if;

  if tg_table_name = 'bingo_topic_comments' then
    v_event := 'comment';
    v_message := 'Someone commented on "' || v_title || '" on the Bingo Wall.';
  elsif tg_table_name = 'bingo_topic_reactions' then
    v_event := 'reaction';
    v_message := 'Someone loved "' || v_title || '" on the Bingo Wall.';
  elsif tg_table_name = 'bingo_topic_smart_reactions' then
    v_event := 'smart_reaction';
    v_message := 'Someone reacted to "' || v_title || '" on the Bingo Wall.';
  else
    return new;
  end if;

  insert into public.bingo_topic_notifications (user_id, topic_id, event_type, message)
  values (v_owner, new.topic_id, v_event, v_message);

  return new;
end;
$$;

revoke all on function public.bingo_topic_notify_owner() from public;

drop trigger if exists bingo_topic_comments_notify_trg on public.bingo_topic_comments;
create trigger bingo_topic_comments_notify_trg
  after insert on public.bingo_topic_comments
  for each row execute function public.bingo_topic_notify_owner();

drop trigger if exists bingo_topic_reactions_notify_trg on public.bingo_topic_reactions;
create trigger bingo_topic_reactions_notify_trg
  after insert on public.bingo_topic_reactions
  for each row execute function public.bingo_topic_notify_owner();

drop trigger if exists bingo_topic_smart_reactions_notify_trg on public.bingo_topic_smart_reactions;
create trigger bingo_topic_smart_reactions_notify_trg
  after insert on public.bingo_topic_smart_reactions
  for each row execute function public.bingo_topic_notify_owner();

-- ---------------------------------------------------------------------------
-- 6. property_listings.furnished — universal-search / property gap
--
--    Gap found: the universal-search frontend already filters on
--    p.furnished (Furnished/Unfurnished, Property category only — never
--    New/Used, matching the approved contextual-filter rules), but no
--    tracked migration ever added a furnished column to property_listings,
--    and the property post form itself has no field for it either — so
--    today the filter always operates on an undefined value. This adds
--    only the database column; adding the actual Yes/No field to the
--    property post form is frontend-only (listed in section 8 below).
-- ---------------------------------------------------------------------------
alter table public.property_listings
  add column if not exists furnished text not null default '';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'property_listings_furnished_check') then
    alter table public.property_listings
      add constraint property_listings_furnished_check
      check (furnished in ('', 'Furnished', 'Unfurnished'));
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 7. bingo_candidates + candidate-media — CV/candidate profiles
--
--    Gap found: audited every tracked migration and every frontend
--    Supabase call — there is no Supabase table backing CV/candidate
--    profiles at all today. The Jobs/CVs page (state.jobs, aa_candidates)
--    is 100% localStorage with transient blob: URLs that do not survive
--    reload, confirmed earlier this session by direct code inspection.
--    'candidate' was already anticipated as a moderation target_type in
--    bingo_moderation_cases (Change 06), but no table exists for it to
--    point at, and bingo_moderation_action's hide/restore branch does not
--    yet act on any target_type beyond food_business/food_menu_item —
--    that is a pre-existing gap in an already-shipped, unrelated
--    migration file, not something this change touches or extends;
--    wiring candidate moderation into that RPC is a separate, future
--    change if wanted. One row per user, mirroring bingo_user_roles'
--    shape (user_id as primary key) since a member has exactly one CV
--    profile, matching the frontend's own one-profile-per-user model.
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_candidates (
  user_id             uuid primary key references auth.users(id) on delete cascade,
  full_name           text not null default '',
  county              text not null default '',
  experience          text not null default '',
  bio                 text not null default '',
  show_contact        boolean not null default false,
  profile_photo_path  text,
  additional_photos   jsonb not null default '[]'::jsonb,
  cv_document_path    text,
  cv_document_name    text not null default '',
  moderation_status   text not null default 'visible' check (moderation_status in ('visible','hidden')),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

alter table public.bingo_candidates enable row level security;

-- Candidate profiles are meant to be publicly browsable (Jobs/CVs ->
-- Candidates), same visibility shape as bingo_topics: visible to anyone,
-- plus the owner and the Super User can also see their own hidden row.
drop policy if exists bingo_candidates_select on public.bingo_candidates;
create policy bingo_candidates_select on public.bingo_candidates
  for select
  using (
    moderation_status = 'visible'
    or auth.uid() = user_id
    or public.bingo_is_super_user()
  );

drop policy if exists bingo_candidates_insert on public.bingo_candidates;
create policy bingo_candidates_insert on public.bingo_candidates
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists bingo_candidates_update on public.bingo_candidates;
create policy bingo_candidates_update on public.bingo_candidates
  for update
  using (auth.uid() = user_id or public.bingo_is_super_user())
  with check (auth.uid() = user_id or public.bingo_is_super_user());

drop policy if exists bingo_candidates_delete on public.bingo_candidates;
create policy bingo_candidates_delete on public.bingo_candidates
  for delete
  using (auth.uid() = user_id or public.bingo_is_super_user());

-- Same moderation-lock / author-lock pair as bingo_topics, adapted to a
-- user_id-as-primary-key table: only the Super User may change
-- moderation_status; user_id is immutable for EVERYONE, including the
-- Super User (new functions — bingo_topics_lock_moderation()/
-- bingo_topics_lock_author() are not reused here because they are
-- written against bingo_topics' own id/user_id column pair on a
-- different table, and this table's user_id doubles as its primary key).
create or replace function public.bingo_candidates_lock_moderation()
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

drop trigger if exists bingo_candidates_lock_moderation_trg on public.bingo_candidates;
create trigger bingo_candidates_lock_moderation_trg
  before update on public.bingo_candidates
  for each row
  execute function public.bingo_candidates_lock_moderation();

create or replace function public.bingo_candidates_lock_owner()
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

drop trigger if exists bingo_candidates_lock_owner_trg on public.bingo_candidates;
create trigger bingo_candidates_lock_owner_trg
  before update on public.bingo_candidates
  for each row
  execute function public.bingo_candidates_lock_owner();

-- Reuses bingo_touch_updated_at() from the Public Wall migration as-is.
drop trigger if exists bingo_candidates_touch_updated_at_trg on public.bingo_candidates;
create trigger bingo_candidates_touch_updated_at_trg
  before update on public.bingo_candidates
  for each row
  execute function public.bingo_touch_updated_at();

create index if not exists bingo_candidates_moderation_idx on public.bingo_candidates(moderation_status);

-- candidate-media — PRIVATE bucket, path convention {user_id}/{filename}.
-- Simpler than topic-media's {user_id}/{topic_id}/{filename}: there is no
-- second id to cross-check ownership against, because the path's own
-- first segment already IS the natural owner key (one profile per user),
-- so write policies only ever need to compare that segment to auth.uid().
insert into storage.buckets (id, name, public)
values ('candidate-media', 'candidate-media', false)
on conflict (id) do update set public = false;

drop policy if exists candidate_media_read on storage.objects;
create policy candidate_media_read on storage.objects
  for select
  using (
    bucket_id = 'candidate-media'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.bingo_is_super_user()
      or exists (
        select 1 from public.bingo_candidates c
        where c.user_id = public.bingo_safe_uuid((storage.foldername(name))[1])
          and c.moderation_status = 'visible'
      )
    )
  );

drop policy if exists candidate_media_owner_write on storage.objects;
create policy candidate_media_owner_write on storage.objects
  for insert
  with check (
    bucket_id = 'candidate-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists candidate_media_owner_update on storage.objects;
create policy candidate_media_owner_update on storage.objects
  for update
  using (bucket_id = 'candidate-media' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'candidate-media' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists candidate_media_owner_delete on storage.objects;
create policy candidate_media_owner_delete on storage.objects
  for delete
  using (
    bucket_id = 'candidate-media'
    and (
      public.bingo_is_super_user()
      or (storage.foldername(name))[1] = auth.uid()::text
    )
  );

-- ---------------------------------------------------------------------------
-- 8. Confirmed frontend-only — no Supabase object needed for these
--
--    - Exact-post routing (Mushene Corner -> Bingo Box entry -> exact
--      post): already fully supported by bingo_topics.id (a real UUID
--      primary key); aaOpenExactTopic() only needs that id, which every
--      row already has. Nothing to add.
--    - Moderation visibility for every Phase 2-6 feature: already
--      enforced end-to-end by the EXISTING RLS from the Public Wall
--      migration (moderation_status checks on bingo_topics/
--      bingo_topic_comments propagate through every join added here);
--      this migration does not weaken or bypass any of it anywhere,
--      including inside bingo_box_ranked().
--    - The property post form has no Furnished input yet — section 6
--      only adds the column; adding the actual form field is frontend.
--    - Wiring aaBingoBoxEntries() to call bingo_box_ranked() instead of
--      ranking client-side, and wiring the Smart Word press handler to
--      insert into bingo_topic_smart_reactions instead of posting a
--      plain comment, are both frontend follow-ups — this migration only
--      makes the correct server-side objects available to switch to.
--    - Jobs/vacancy LISTINGS themselves (separate from CV/candidate
--      profiles) are also 100% frontend/localStorage today (state.jobs,
--      no Supabase table found in any tracked migration) — noted as an
--      observation from this audit; not part of the requested scope, and
--      not built here.
-- ============================================================================
