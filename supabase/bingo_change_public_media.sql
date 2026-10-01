-- Real shared category listings and deduplicated media engagement.
-- Counts represent signed-in accounts or anonymous browsers, not verified people.
create table if not exists public.bingo_category_listings (
 id text primary key check (length(id) between 1 and 100),
 user_id uuid not null references auth.users(id) on delete cascade,
 category text not null check (category in ('spare','household','job')),
 status text not null default 'published' check (status in ('published','paused','archived')),
 payload jsonb not null check (jsonb_typeof(payload)='object' and octet_length(payload::text)<100000),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.bingo_category_listings enable row level security;
create index if not exists bingo_category_public_created on public.bingo_category_listings(created_at desc) where status='published';
create index if not exists bingo_category_owner on public.bingo_category_listings(user_id);
create policy bingo_category_read on public.bingo_category_listings for select to anon,authenticated using(status='published' or user_id=(select auth.uid()));
create policy bingo_category_insert on public.bingo_category_listings for insert to authenticated with check(user_id=(select auth.uid()));
create policy bingo_category_update on public.bingo_category_listings for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy bingo_category_delete on public.bingo_category_listings for delete to authenticated using(user_id=(select auth.uid()));
revoke insert,update,delete,truncate,references,trigger on public.bingo_category_listings from anon;
grant select on public.bingo_category_listings to anon;
grant select,insert,update,delete on public.bingo_category_listings to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values ('category-media','category-media',false,20971520,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy bingo_category_media_upload on storage.objects for insert to authenticated with check(bucket_id='category-media' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy bingo_category_media_read on storage.objects for select to anon,authenticated using(bucket_id='category-media' and ((storage.foldername(name))[1]=(select auth.uid())::text or exists(select 1 from public.bingo_category_listings c where c.id=(storage.foldername(name))[2] and c.user_id::text=(storage.foldername(name))[1] and c.status='published')));
create policy bingo_category_media_delete on storage.objects for delete to authenticated using(bucket_id='category-media' and (storage.foldername(name))[1]=(select auth.uid())::text);
create table if not exists public.bingo_media_events (
 post_type text not null,post_id text not null,viewer_key text not null,
 event_type text not null check(event_type in ('view','watch','photo')),
 created_at timestamptz not null default now(),
 primary key(post_type,post_id,viewer_key,event_type)
);
alter table public.bingo_media_events enable row level security;
revoke all on public.bingo_media_events from anon,authenticated;
create index if not exists bingo_media_event_rate on public.bingo_media_events(viewer_key,created_at);
create or replace function public.bingo_media_is_public(p_type text,p_id text) returns boolean language sql stable security definer set search_path='' as $$
 select case p_type
 when 'topic' then exists(select 1 from public.bingo_topics where id::text=p_id and moderation_status='visible')
 when 'vehicle' then exists(select 1 from public.vehicle_listings where id::text=p_id and status in ('published','available'))
 when 'property' then exists(select 1 from public.property_listings where id::text=p_id and status='published')
 when 'food' then exists(select 1 from public.food_businesses where id::text=p_id and status='published' and subscription_expires_at>now())
 when 'spare' then exists(select 1 from public.bingo_category_listings where id=p_id and category in ('spare','household') and status='published')
 when 'job' then exists(select 1 from public.bingo_category_listings where id=p_id and category='job' and status='published')
 else false end;
$$;
revoke all on function public.bingo_media_is_public(text,text) from public,anon,authenticated;
create or replace function public.bingo_media_counts(p_posts jsonb) returns table(post_type text,post_id text,view_count bigint,watch_count bigint,photo_count bigint)
 language sql stable security definer set search_path='' as $$
 with requested as (select distinct x->>'type' as kind,x->>'id' as id from jsonb_array_elements(case when jsonb_typeof(p_posts)='array' then p_posts else '[]'::jsonb end) x limit 100)
 select r.kind,r.id,count(e.*) filter(where e.event_type='view'),count(e.*) filter(where e.event_type='watch'),count(e.*) filter(where e.event_type='photo')
 from requested r left join public.bingo_media_events e on e.post_type=r.kind and e.post_id=r.id
 where public.bingo_media_is_public(r.kind,r.id) group by r.kind,r.id;
$$;
create or replace function public.bingo_record_media_event(p_type text,p_id text,p_visitor uuid,p_event text) returns boolean
 language plpgsql security definer set search_path='' as $$
 declare v_key text;
 begin
 if p_event not in ('view','watch','photo') or p_visitor is null or not public.bingo_media_is_public(p_type,p_id) then return false;end if;
 v_key:=case when auth.uid() is not null then 'member:'||auth.uid()::text else 'browser:'||p_visitor::text end;
 -- Cap new events per identity. Repeats are deduplicated by the primary key.
 if (select count(*) from public.bingo_media_events where viewer_key=v_key and created_at>now()-interval '1 hour')>=240 then return false;end if;
 insert into public.bingo_media_events(post_type,post_id,viewer_key,event_type) values(p_type,p_id,v_key,p_event) on conflict do nothing;
 return found;
 end;
$$;
revoke all on function public.bingo_media_counts(jsonb) from public;
revoke all on function public.bingo_record_media_event(text,text,uuid,text) from public;
grant execute on function public.bingo_media_counts(jsonb),public.bingo_record_media_event(text,text,uuid,text) to anon,authenticated;
notify pgrst,'reload schema';
