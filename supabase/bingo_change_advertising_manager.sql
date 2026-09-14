-- ============================================================================
-- BINGO CHANGE 07 — ADVERTISING MANAGER (Supabase backend)
--
-- In the pre-Change-07 Mother HTML, aaAdHTML() returned an empty string —
-- there was no real Advertising Manager, only the dormant state.adOpen /
-- aaCloseAd() slot. This adds the protected campaign system behind it.
-- Additive only; does not touch bingo_user_roles, property_listings,
-- food_businesses, bingo_moderation_cases or any other existing table.
--
-- Every mutation (save/publish/pause/resume/extend/duplicate/retire/delete)
-- runs through a SECURITY DEFINER RPC that re-checks bingo_is_super_user()
-- (Change 03) on every call and writes an immutable audit entry — nothing
-- here is reachable by a plain authenticated update/delete.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. bingo_ad_campaigns
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_ad_campaigns (
  id                uuid primary key default gen_random_uuid(),
  name              text not null,
  reference         text not null default '',
  source_type       text not null default 'image' check (source_type in ('image','video','post','html')),
  source_post_type  text not null default '',
  source_post_id    text not null default '',
  media_url         text not null default '',
  creative_html     text not null default '',
  variants          jsonb not null default '{"large":null,"medium":null,"small":null,"micro":null}'::jsonb,
  destination_type  text not null default 'post' check (destination_type in ('post','url','none')),
  destination_post_type text not null default '',
  destination_value text not null default '',
  starts_at         timestamptz,
  expires_at        timestamptz,
  status            text not null default 'draft' check (status in ('draft','scheduled','published','paused','retired')),
  priority          integer not null default 0,
  eligible_pages    text[] not null default '{}',
  created_by        uuid not null references auth.users(id),
  updated_at        timestamptz not null default now(),
  created_at        timestamptz not null default now(),
  constraint bingo_ad_campaigns_dates check (starts_at is null or expires_at is null or expires_at > starts_at)
);

alter table public.bingo_ad_campaigns enable row level security;

-- The Super User dashboard sees every campaign (all statuses). Anyone else
-- (including a signed-out guest) may see only a campaign that is actually
-- live right now — this is the read path the public ad slot uses to serve
-- an ad, so it must work without requiring the Super User role.
drop policy if exists bingo_ad_campaigns_select on public.bingo_ad_campaigns;
create policy bingo_ad_campaigns_select on public.bingo_ad_campaigns
  for select
  using (
    public.bingo_is_super_user()
    or (
      status = 'published'
      and (starts_at is null or starts_at <= now())
      and (expires_at is null or expires_at > now())
    )
  );

-- No insert/update/delete policy for anyone — every change goes through the
-- RPCs below so there is always an audit trail and a role check.

create index if not exists bingo_ad_campaigns_status_idx on public.bingo_ad_campaigns(status);
create index if not exists bingo_ad_campaigns_live_idx on public.bingo_ad_campaigns(status, starts_at, expires_at);

-- ---------------------------------------------------------------------------
-- 2. bingo_ad_audit_log — append-only, Super User read only
-- ---------------------------------------------------------------------------
create table if not exists public.bingo_ad_audit_log (
  id          bigint generated always as identity primary key,
  actor_id    uuid not null references auth.users(id),
  campaign_id uuid references public.bingo_ad_campaigns(id) on delete set null,
  action      text not null,
  details     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

alter table public.bingo_ad_audit_log enable row level security;

drop policy if exists bingo_ad_audit_log_select on public.bingo_ad_audit_log;
create policy bingo_ad_audit_log_select on public.bingo_ad_audit_log
  for select
  using (public.bingo_is_super_user());
-- No insert/update/delete policy: only the RPCs below write here.

-- ---------------------------------------------------------------------------
-- 3. ad-media Storage bucket — Super User writes, public reads (an ad's
--    image/video creative has to be fetchable by every visitor's browser).
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('ad-media', 'ad-media', true)
on conflict (id) do nothing;

drop policy if exists ad_media_public_read on storage.objects;
create policy ad_media_public_read on storage.objects
  for select
  using (bucket_id = 'ad-media');

drop policy if exists ad_media_admin_write on storage.objects;
create policy ad_media_admin_write on storage.objects
  for insert
  with check (bucket_id = 'ad-media' and public.bingo_is_super_user());

drop policy if exists ad_media_admin_delete on storage.objects;
create policy ad_media_admin_delete on storage.objects
  for delete
  using (bucket_id = 'ad-media' and public.bingo_is_super_user());

-- ---------------------------------------------------------------------------
-- 4. Shared validation + audit helper
-- ---------------------------------------------------------------------------
create or replace function public._bingo_ad_validate(p jsonb)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(p->>'name','') = '' then
    raise exception 'Campaign name is required.';
  end if;
  if not (coalesce(p->>'source_type','') = any(array['image','video','post','html'])) then
    raise exception 'Invalid creative source type.';
  end if;
  if coalesce(p->>'source_type','')='html' and coalesce(p->>'creative_html','')='' then
    raise exception 'Custom HTML/CSS creative cannot be empty.';
  end if;
  if not (coalesce(p->>'destination_type','') = any(array['post','url','none'])) then
    raise exception 'Invalid destination type.';
  end if;
  if coalesce(p->>'destination_type','')='post' and (coalesce(p->>'destination_value','')='' or coalesce(p->>'destination_post_type','')='') then
    raise exception 'A destination post type and ID are required for a post destination.';
  end if;
  if coalesce(p->>'destination_type','')='url' and coalesce(p->>'destination_value','') !~ '^https://' then
    raise exception 'A destination URL must start with https://.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. bingo_ad_save — create (p_id null) or update (draft-safe) a campaign.
--    Always leaves status as draft/scheduled/paused as it already was;
--    only bingo_ad_publish moves a campaign live.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_ad_save(p_id uuid, p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_existing_status text;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may manage advertising campaigns.';
  end if;
  perform public._bingo_ad_validate(p_payload);

  if p_id is null then
    insert into public.bingo_ad_campaigns(
      name, reference, source_type, source_post_type, source_post_id, media_url, creative_html,
      variants, destination_type, destination_post_type, destination_value, starts_at, expires_at, priority, eligible_pages, created_by
    ) values (
      p_payload->>'name', coalesce(p_payload->>'reference',''), p_payload->>'source_type',
      coalesce(p_payload->>'source_post_type',''), coalesce(p_payload->>'source_post_id',''),
      coalesce(p_payload->>'media_url',''), coalesce(p_payload->>'creative_html',''),
      coalesce(p_payload->'variants','{"large":null,"medium":null,"small":null,"micro":null}'::jsonb),
      p_payload->>'destination_type', coalesce(p_payload->>'destination_post_type',''), coalesce(p_payload->>'destination_value',''),
      nullif(p_payload->>'starts_at','')::timestamptz, nullif(p_payload->>'expires_at','')::timestamptz,
      coalesce((p_payload->>'priority')::int,0),
      coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p_payload->'eligible_pages','[]'::jsonb)) x), '{}'),
      auth.uid()
    )
    returning id into v_id;
    insert into public.bingo_ad_audit_log(actor_id,campaign_id,action,details) values (auth.uid(),v_id,'create',p_payload);
    return v_id;
  end if;

  select status into v_existing_status from public.bingo_ad_campaigns where id = p_id;
  if not found then
    raise exception 'Campaign not found.';
  end if;

  update public.bingo_ad_campaigns set
    name = p_payload->>'name',
    reference = coalesce(p_payload->>'reference',''),
    source_type = p_payload->>'source_type',
    source_post_type = coalesce(p_payload->>'source_post_type',''),
    source_post_id = coalesce(p_payload->>'source_post_id',''),
    media_url = coalesce(p_payload->>'media_url',''),
    creative_html = coalesce(p_payload->>'creative_html',''),
    variants = coalesce(p_payload->'variants', variants),
    destination_type = p_payload->>'destination_type',
    destination_post_type = coalesce(p_payload->>'destination_post_type',''),
    destination_value = coalesce(p_payload->>'destination_value',''),
    starts_at = nullif(p_payload->>'starts_at','')::timestamptz,
    expires_at = nullif(p_payload->>'expires_at','')::timestamptz,
    priority = coalesce((p_payload->>'priority')::int, priority),
    eligible_pages = coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p_payload->'eligible_pages','[]'::jsonb)) x), eligible_pages),
    updated_at = now()
  where id = p_id;

  insert into public.bingo_ad_audit_log(actor_id,campaign_id,action,details) values (auth.uid(),p_id,'update',p_payload);
  return p_id;
end;
$$;

revoke all on function public.bingo_ad_save(uuid,jsonb) from public;
grant execute on function public.bingo_ad_save(uuid,jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Lifecycle RPCs — publish / pause / resume / extend / duplicate / retire
--    / delete. Each is Super User only and logs to bingo_ad_audit_log.
-- ---------------------------------------------------------------------------
create or replace function public.bingo_ad_publish(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.bingo_ad_campaigns;
  v_status text;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may publish a campaign.';
  end if;
  select * into v_row from public.bingo_ad_campaigns where id = p_id;
  if not found then raise exception 'Campaign not found.'; end if;
  if v_row.source_type='html' and coalesce(v_row.creative_html,'')='' then
    raise exception 'This campaign has no creative to publish.';
  end if;
  if v_row.source_type in ('image','video') and coalesce(v_row.media_url,'')='' then
    raise exception 'This campaign has no media to publish.';
  end if;
  if v_row.destination_type <> 'none' and coalesce(v_row.destination_value,'')='' then
    raise exception 'This campaign has no valid destination.';
  end if;

  v_status := case when v_row.starts_at is not null and v_row.starts_at > now() then 'scheduled' else 'published' end;

  update public.bingo_ad_campaigns
  set status = v_status,
      starts_at = coalesce(starts_at, now()),
      updated_at = now()
  where id = p_id;

  insert into public.bingo_ad_audit_log(actor_id,campaign_id,action,details) values (auth.uid(),p_id,'publish',jsonb_build_object('status',v_status));
end;
$$;
revoke all on function public.bingo_ad_publish(uuid) from public;
grant execute on function public.bingo_ad_publish(uuid) to authenticated;

create or replace function public.bingo_ad_pause(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may pause a campaign.';
  end if;
  update public.bingo_ad_campaigns set status='paused', updated_at=now()
  where id = p_id and status in ('published','scheduled');
  if not found then raise exception 'Campaign is not currently live or scheduled.'; end if;
  insert into public.bingo_ad_audit_log(actor_id,campaign_id,action) values (auth.uid(),p_id,'pause');
end;
$$;
revoke all on function public.bingo_ad_pause(uuid) from public;
grant execute on function public.bingo_ad_pause(uuid) to authenticated;

create or replace function public.bingo_ad_resume(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.bingo_ad_campaigns;
  v_status text;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may resume a campaign.';
  end if;
  select * into v_row from public.bingo_ad_campaigns where id = p_id;
  if not found then raise exception 'Campaign not found.'; end if;
  if v_row.status <> 'paused' then raise exception 'Only a paused campaign can be resumed.'; end if;
  if v_row.expires_at is not null and v_row.expires_at <= now() then
    raise exception 'This campaign has already expired — extend it first.';
  end if;
  v_status := case when v_row.starts_at is not null and v_row.starts_at > now() then 'scheduled' else 'published' end;
  update public.bingo_ad_campaigns set status=v_status, updated_at=now() where id = p_id;
  insert into public.bingo_ad_audit_log(actor_id,campaign_id,action,details) values (auth.uid(),p_id,'resume',jsonb_build_object('status',v_status));
end;
$$;
revoke all on function public.bingo_ad_resume(uuid) from public;
grant execute on function public.bingo_ad_resume(uuid) to authenticated;

create or replace function public.bingo_ad_extend(p_id uuid, p_new_expiry timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.bingo_ad_campaigns;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may extend a campaign.';
  end if;
  select * into v_row from public.bingo_ad_campaigns where id = p_id;
  if not found then raise exception 'Campaign not found.'; end if;
  if p_new_expiry is null or (v_row.expires_at is not null and p_new_expiry <= v_row.expires_at) then
    raise exception 'The new expiry must be later than the current expiry.';
  end if;
  update public.bingo_ad_campaigns set expires_at = p_new_expiry, updated_at = now() where id = p_id;
  insert into public.bingo_ad_audit_log(actor_id,campaign_id,action,details) values (auth.uid(),p_id,'extend',jsonb_build_object('expires_at',p_new_expiry));
end;
$$;
revoke all on function public.bingo_ad_extend(uuid,timestamptz) from public;
grant execute on function public.bingo_ad_extend(uuid,timestamptz) to authenticated;

create or replace function public.bingo_ad_duplicate(p_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.bingo_ad_campaigns;
  v_new_id uuid;
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may duplicate a campaign.';
  end if;
  select * into v_row from public.bingo_ad_campaigns where id = p_id;
  if not found then raise exception 'Campaign not found.'; end if;

  insert into public.bingo_ad_campaigns(
    name, reference, source_type, source_post_type, source_post_id, media_url, creative_html,
    variants, destination_type, destination_post_type, destination_value, priority, eligible_pages, created_by
  ) values (
    v_row.name || ' (copy)', v_row.reference, v_row.source_type, v_row.source_post_type, v_row.source_post_id,
    v_row.media_url, v_row.creative_html, v_row.variants, v_row.destination_type, v_row.destination_post_type, v_row.destination_value,
    v_row.priority, v_row.eligible_pages, auth.uid()
  )
  returning id into v_new_id;

  insert into public.bingo_ad_audit_log(actor_id,campaign_id,action,details) values (auth.uid(),v_new_id,'duplicate',jsonb_build_object('duplicated_from',p_id));
  return v_new_id;
end;
$$;
revoke all on function public.bingo_ad_duplicate(uuid) from public;
grant execute on function public.bingo_ad_duplicate(uuid) to authenticated;

create or replace function public.bingo_ad_retire(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may retire a campaign.';
  end if;
  update public.bingo_ad_campaigns set status='retired', updated_at=now() where id = p_id;
  if not found then raise exception 'Campaign not found.'; end if;
  insert into public.bingo_ad_audit_log(actor_id,campaign_id,action) values (auth.uid(),p_id,'retire');
end;
$$;
revoke all on function public.bingo_ad_retire(uuid) from public;
grant execute on function public.bingo_ad_retire(uuid) to authenticated;

-- Separate from retire: a hard delete, always confirmed client-side first.
create or replace function public.bingo_ad_delete(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.bingo_is_super_user() then
    raise exception 'Only the Super User may delete a campaign.';
  end if;
  if not exists (select 1 from public.bingo_ad_campaigns where id = p_id) then
    raise exception 'Campaign not found.';
  end if;
  -- Logged before the delete (with the FK still satisfiable) and then
  -- nulled by the FK's own on-delete-set-null once the campaign is gone,
  -- so the audit trail survives the campaign it describes.
  insert into public.bingo_ad_audit_log(actor_id,campaign_id,action) values (auth.uid(),p_id,'delete');
  delete from public.bingo_ad_campaigns where id = p_id;
end;
$$;
revoke all on function public.bingo_ad_delete(uuid) from public;
grant execute on function public.bingo_ad_delete(uuid) to authenticated;
