-- extracted verbatim from repo
-- ---------------------------------------------------------------------------
create or replace function public.bingo_is_super_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.bingo_user_roles r
    where r.user_id = auth.uid()
      and r.role = 'super_user'
  );
$$;

revoke all on function public.bingo_is_super_user() from public;
grant execute on function public.bingo_is_super_user() to authenticated;

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
