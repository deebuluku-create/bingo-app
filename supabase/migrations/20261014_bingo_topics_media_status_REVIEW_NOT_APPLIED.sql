-- =============================================================================
-- REVIEW — NOT APPLIED. Staging tests only. Do not run against production
-- until explicitly approved. Production database is unchanged by this file.
--
-- Purpose: stop unfinished media posts from appearing publicly as empty or
-- text-only posts.
--
--   * media_status = 'pending' while a post's media uploads are in progress.
--   * media_status = 'ready' once bingo_finalize_topic() has verified every
--     uploaded object. Only 'ready' posts are public.
--   * Existing rows default to 'ready', so existing posts and genuine text-only
--     posts keep publishing and reading exactly as before.
--   * Owners cannot set media_status directly (same pattern as the existing
--     moderation lock). Only the finalize RPC can change it.
--   * Abandoned 'pending' posts (older than 24 hours) can be listed and deleted
--     by the service role, so a cleanup worker can remove their storage first.
--
-- Rollback: see the block at the end of this file (not run automatically).
-- =============================================================================

begin;

-- 1. Column ---------------------------------------------------------------------
alter table public.bingo_topics
  add column if not exists media_status text not null default 'ready'
  check (media_status in ('pending', 'ready'));

-- 2. Lock: only the finalize RPC may change media_status ------------------------
create or replace function public.bingo_topics_lock_media_status()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.media_status is distinct from old.media_status
     and coalesce(current_setting('bingo.finalize_topic', true), '') <> 'on' then
    new.media_status := old.media_status;
  end if;
  return new;
end;
$$;

drop trigger if exists bingo_topics_lock_media_status_trg on public.bingo_topics;
create trigger bingo_topics_lock_media_status_trg
  before update on public.bingo_topics
  for each row
  execute function public.bingo_topics_lock_media_status();

-- 3. Public read: a pending post is visible to its owner and super users only ---
drop policy if exists bingo_topics_select on public.bingo_topics;
create policy bingo_topics_select on public.bingo_topics
  for select
  using (
    (moderation_status = 'visible' and media_status = 'ready')
    or auth.uid() = user_id
    or public.bingo_is_super_user()
  );

-- Storage read (topic_media_read) already depends on bingo_topics visibility
-- through its EXISTS check, so pending media is unreadable by others without
-- changing the storage policy.

-- 4. Finalize RPC ----------------------------------------------------------------
-- SECURITY INVOKER on purpose: it runs with the caller's privileges, so RLS on
-- bingo_topics and storage.objects still applies, and no definer privilege is
-- granted. Every check below is still enforced explicitly.
create or replace function public.bingo_finalize_topic(p_topic_id uuid, p_media jsonb)
returns public.bingo_topics
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_row     public.bingo_topics;
  v_item    jsonb;
  v_type    text;
  v_path    text;
  v_prefix  text;
  v_size    bigint;
  v_clean   jsonb := '[]'::jsonb;
  v_found   int;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Lock the row so two finalize calls cannot interleave.
  select * into v_row from public.bingo_topics where id = p_topic_id for update;
  if not found then
    raise exception 'topic not found' using errcode = 'P0002';
  end if;

  -- Ownership: only the author can finalize their own post.
  if v_row.user_id <> v_uid then
    raise exception 'not the owner of this topic' using errcode = '42501';
  end if;

  -- Idempotent: a retry after success returns the finished row.
  if v_row.media_status = 'ready' then
    return v_row;
  end if;

  -- Abandoned uploads are not finalizable; the cleanup worker removes them.
  if v_row.created_at < now() - interval '24 hours' then
    raise exception 'upload window expired for this post' using errcode = '22023';
  end if;

  if p_media is null or jsonb_typeof(p_media) <> 'array' then
    raise exception 'media must be a JSON array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_media) = 0 or jsonb_array_length(p_media) > 10 then
    raise exception 'media must contain 1 to 10 items' using errcode = '22023';
  end if;

  v_prefix := v_uid::text || '/' || p_topic_id::text || '/';

  for v_item in select value from jsonb_array_elements(p_media) loop
    v_type := v_item->>'type';
    v_path := v_item->>'path';

    if v_type not in ('image', 'video') then
      raise exception 'invalid media type' using errcode = '22023';
    end if;

    -- Path verification: must sit under the caller's folder for this topic,
    -- with no traversal and a sane length.
    if v_path is null
       or length(v_path) > 512
       or left(v_path, length(v_prefix)) <> v_prefix
       or position('..' in v_path) > 0
       or position('\' in v_path) > 0 then
      raise exception 'media path is not inside this topic folder' using errcode = '42501';
    end if;

    -- The object must actually exist in the topic-media bucket with content.
    select count(*), coalesce(max((o.metadata->>'size')::bigint), 0)
      into v_found, v_size
      from storage.objects o
     where o.bucket_id = 'topic-media'
       and o.name = v_path;

    if v_found = 0 then
      raise exception 'uploaded media not found in storage' using errcode = 'P0002';
    end if;
    if v_size <= 0 then
      raise exception 'uploaded media is empty' using errcode = '22023';
    end if;

    -- Store only the fields the app uses; drop anything else the client sent.
    v_clean := v_clean || jsonb_build_array(jsonb_build_object(
      'type', v_type,
      'path', v_path,
      'name', left(coalesce(v_item->>'name', ''), 255)
    ));
  end loop;

  -- Open the lock for this transaction only (set_config(..., true) is local to
  -- the transaction), then write. No other statement can use this flag.
  perform set_config('bingo.finalize_topic', 'on', true);

  update public.bingo_topics
     set media = v_clean,
         media_status = 'ready',
         updated_at = now()
   where id = p_topic_id
   returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.bingo_finalize_topic(uuid, jsonb) from public, anon;
grant execute on function public.bingo_finalize_topic(uuid, jsonb) to authenticated;

-- 5. Cleanup support (service role only; the worker deletes storage first) ------
-- Phase 1: list abandoned pending posts and their storage folders.
create or replace function public.bingo_abandoned_topic_uploads()
returns table (topic_id uuid, user_id uuid, storage_prefix text)
language sql
security invoker
set search_path = ''
as $$
  select t.id, t.user_id, t.user_id::text || '/' || t.id::text || '/'
    from public.bingo_topics t
   where t.media_status = 'pending'
     and t.created_at < now() - interval '24 hours'
   limit 500;
$$;

-- Phase 2: delete a row only if it is still pending and still abandoned.
create or replace function public.bingo_delete_abandoned_topic(p_topic_id uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare n int;
begin
  delete from public.bingo_topics
   where id = p_topic_id
     and media_status = 'pending'
     and created_at < now() - interval '24 hours';
  get diagnostics n = row_count;
  return n > 0;
end;
$$;

revoke all on function public.bingo_abandoned_topic_uploads() from public, anon, authenticated;
revoke all on function public.bingo_delete_abandoned_topic(uuid) from public, anon, authenticated;
grant execute on function public.bingo_abandoned_topic_uploads() to service_role;
grant execute on function public.bingo_delete_abandoned_topic(uuid) to service_role;

commit;

-- =============================================================================
-- ROLLBACK (manual, only if this migration is ever applied and must be undone):
--   drop function if exists public.bingo_delete_abandoned_topic(uuid);
--   drop function if exists public.bingo_abandoned_topic_uploads();
--   drop function if exists public.bingo_finalize_topic(uuid, jsonb);
--   drop trigger if exists bingo_topics_lock_media_status_trg on public.bingo_topics;
--   drop function if exists public.bingo_topics_lock_media_status();
--   -- restore the previous select policy exactly as in
--   -- supabase/bingo_change_public_wall_topics.sql
--   alter table public.bingo_topics drop column if exists media_status;
-- =============================================================================
