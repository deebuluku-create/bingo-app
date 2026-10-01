-- Additive sound integration. Originals can only be registered by the trusted worker.
create table public.bingo_sounds (
 id uuid primary key default gen_random_uuid(), original_uploader_id uuid not null references auth.users(id),
 source_topic_id uuid not null references public.bingo_topics(id), title text not null check(length(title)<=80),
 pcm_hash text not null unique check(length(pcm_hash)=64), fingerprint jsonb not null,
 duration real not null check(duration>0 and duration<=180), audio_path text not null,
 created_at timestamptz not null default now()
);
alter table public.bingo_topics add column sound_id uuid references public.bingo_sounds(id);
create index bingo_topics_sound_idx on public.bingo_topics(sound_id) where sound_id is not null;
create table public.bingo_sound_jobs (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id),
 kind text not null check(kind in ('recognise','compose')), source_topic_id uuid references public.bingo_topics(id),
 sound_id uuid references public.bingo_sounds(id), input_path text, caption text not null default '',
 state text not null default 'queued' check(state in ('queued','processing','ready','failed','review')),
 output_path text, error text, created_at timestamptz not null default now(), started_at timestamptz,
 check((kind='recognise' and source_topic_id is not null) or (kind='compose' and sound_id is not null and input_path is not null))
);
create index bingo_sound_jobs_queue_idx on public.bingo_sound_jobs(state,created_at);
create index bingo_sound_jobs_owner_idx on public.bingo_sound_jobs(user_id,created_at);
create unique index bingo_sound_source_job_idx on public.bingo_sound_jobs(source_topic_id) where kind='recognise';
create table public.bingo_sound_processor (id boolean primary key default true check(id), heartbeat timestamptz not null);
alter table public.bingo_sounds enable row level security;
alter table public.bingo_sound_jobs enable row level security;
alter table public.bingo_sound_processor enable row level security;
revoke all on public.bingo_sounds,public.bingo_sound_jobs,public.bingo_sound_processor from anon,authenticated;
grant select on public.bingo_sounds to anon,authenticated;
grant select on public.bingo_sound_jobs to authenticated;
grant all on public.bingo_sounds,public.bingo_sound_jobs,public.bingo_sound_processor to service_role;
create policy sound_visible on public.bingo_sounds for select to anon,authenticated using (exists(select 1 from public.bingo_topics t where t.id=source_topic_id and t.moderation_status='visible'));
create policy sound_job_owner on public.bingo_sound_jobs for select to authenticated using ((select auth.uid())=user_id);
create function public.bingo_sound_credit_locked() returns trigger language plpgsql set search_path='' as $$ begin
 if new.original_uploader_id<>old.original_uploader_id or new.source_topic_id<>old.source_topic_id or new.pcm_hash<>old.pcm_hash then raise exception 'Original sound attribution is immutable'; end if;return new;end $$;
create trigger bingo_sound_credit_locked before update on public.bingo_sounds for each row execute function public.bingo_sound_credit_locked();
revoke all on function public.bingo_sound_credit_locked() from public,anon,authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('sound-inputs','sound-inputs',false,78643200,array['video/mp4','video/webm','video/quicktime','image/jpeg','image/png','image/webp']),
 ('sound-audio','sound-audio',false,78643200,array['audio/mp4']) on conflict(id) do nothing;
create policy sound_input_upload on storage.objects for insert to authenticated with check(bucket_id='sound-inputs' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy sound_input_read on storage.objects for select to authenticated using(bucket_id='sound-inputs' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy sound_audio_read on storage.objects for select to anon,authenticated using(bucket_id='sound-audio' and exists(select 1 from public.bingo_sounds s where s.audio_path=name));
create function public.bingo_sound_processor_online() returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.bingo_sound_processor where heartbeat>now()-interval '90 seconds') $$;
revoke all on function public.bingo_sound_processor_online() from public;
grant execute on function public.bingo_sound_processor_online() to anon,authenticated;
create function public.bingo_queue_sound(p_topic uuid default null,p_sound uuid default null,p_path text default null,p_caption text default '') returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();jid uuid;src public.bingo_topics;
begin
 if uid is null then raise exception 'Sign in before using sounds';end if;
 if length(coalesce(p_caption,''))>1000 then raise exception 'Caption is too long';end if;
 if p_topic is not null then
  select * into src from public.bingo_topics where id=p_topic and moderation_status='visible';
  if not found then raise exception 'This public post is unavailable';end if;
  if src.sound_id is not null then return null;end if;
  if not exists(select 1 from jsonb_array_elements(src.media) m where m->>'type'='video' and m->>'path' is not null) then raise exception 'No saved video soundtrack is available';end if;
  select id into jid from public.bingo_sound_jobs where source_topic_id=p_topic and kind='recognise';if found then return jid;end if;
 else
  if not exists(select 1 from public.bingo_sounds s join public.bingo_topics t on t.id=s.source_topic_id where s.id=p_sound and t.moderation_status='visible') then raise exception 'Selected sound is unavailable';end if;
  if p_path is null or split_part(p_path,'/',1)<>uid::text or not exists(select 1 from storage.objects where bucket_id='sound-inputs' and name=p_path) then raise exception 'Upload your own photo or video first';end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
 if (select count(*) from public.bingo_sound_jobs where user_id=uid and created_at>now()-interval '1 day')>=20 then raise exception 'Daily sound processing limit reached';end if;
 insert into public.bingo_sound_jobs(user_id,kind,source_topic_id,sound_id,input_path,caption)
 values(uid,case when p_topic is null then 'compose' else 'recognise' end,p_topic,p_sound,p_path,coalesce(p_caption,''))
 on conflict(source_topic_id) where kind='recognise' do nothing returning id into jid;
 if jid is null then select id into jid from public.bingo_sound_jobs where source_topic_id=p_topic and kind='recognise';end if;
 return jid;
end $$;
revoke all on function public.bingo_queue_sound(uuid,uuid,text,text) from public,anon;
grant execute on function public.bingo_queue_sound(uuid,uuid,text,text) to authenticated;
create function public.bingo_claim_sound_job() returns setof public.bingo_sound_jobs language plpgsql security invoker set search_path='' as $$
begin
 perform pg_advisory_xact_lock(188917,1);
 insert into public.bingo_sound_processor values(true,now()) on conflict(id) do update set heartbeat=excluded.heartbeat;
 -- Never reassign a timed-out job while a stale worker might still commit its credit.
 if exists(select 1 from public.bingo_sound_jobs where state='processing') then return;end if;
 return query update public.bingo_sound_jobs set state='processing',started_at=now() where id=(select id from public.bingo_sound_jobs where state='queued' order by created_at for update skip locked limit 1) returning *;
end $$;
revoke all on function public.bingo_claim_sound_job() from public,anon,authenticated;
grant execute on function public.bingo_claim_sound_job() to service_role;
notify pgrst,'reload schema';
-- Index original uploads in their original publication order, including existing videos.
create function public.bingo_enqueue_original_video() returns trigger language plpgsql security definer set search_path='' as $$ begin
 if new.moderation_status='visible' and new.sound_id is null and exists(select 1 from jsonb_array_elements(new.media) m where m->>'type'='video' and m->>'path' is not null) then
 insert into public.bingo_sound_jobs(user_id,kind,source_topic_id,created_at) values(new.user_id,'recognise',new.id,new.created_at) on conflict(source_topic_id) where kind='recognise' do nothing;
 end if;return new;end $$;
revoke all on function public.bingo_enqueue_original_video() from public,anon,authenticated;
create trigger bingo_enqueue_original_video after insert or update of media,moderation_status on public.bingo_topics for each row execute function public.bingo_enqueue_original_video();
insert into public.bingo_sound_jobs(user_id,kind,source_topic_id,created_at)
select user_id,'recognise',id,created_at from public.bingo_topics t where moderation_status='visible' and sound_id is null and exists(select 1 from jsonb_array_elements(t.media) m where m->>'type'='video' and m->>'path' is not null)
on conflict(source_topic_id) where kind='recognise' do nothing;
