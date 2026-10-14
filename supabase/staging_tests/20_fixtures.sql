-- Fixtures inserted as postgres (bypasses RLS). IDs are fixed for the tests.
insert into auth.users(id) values ('aaaaaaaa-0000-0000-0000-000000000001'),('bbbbbbbb-0000-0000-0000-000000000002') on conflict do nothing;
insert into storage.buckets(id,name,public) values ('topic-media','topic-media',false) on conflict do nothing;
insert into storage.objects(bucket_id,name,owner,metadata) values
 ('topic-media','aaaaaaaa-0000-0000-0000-000000000001/a0000000-0000-0000-0000-000000000002/x.webm','aaaaaaaa-0000-0000-0000-000000000001','{"size":2000}'),
 ('topic-media','aaaaaaaa-0000-0000-0000-000000000001/a0000000-0000-0000-0000-000000000003/1.webm','aaaaaaaa-0000-0000-0000-000000000001','{"size":1000}'),
 ('topic-media','aaaaaaaa-0000-0000-0000-000000000001/a0000000-0000-0000-0000-000000000003/empty.webm','aaaaaaaa-0000-0000-0000-000000000001','{"size":0}'),
 ('topic-media','aaaaaaaa-0000-0000-0000-000000000001/a0000000-0000-0000-0000-000000000004/1.webm','aaaaaaaa-0000-0000-0000-000000000001','{"size":500}'),
 ('topic-media','bbbbbbbb-0000-0000-0000-000000000002/b0000000-0000-0000-0000-000000000005/1.webm','bbbbbbbb-0000-0000-0000-000000000002','{"size":700}');
-- Legacy rows created BEFORE the migration (old schema, no media_status column yet).
insert into public.bingo_topics(id,user_id,body) values
 ('a0000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','legacy text-only post');
insert into public.bingo_topics(id,user_id,body,media) values
 ('a0000000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001','legacy video post',
  '[{"type":"video","path":"aaaaaaaa-0000-0000-0000-000000000001/a0000000-0000-0000-0000-000000000002/x.webm","name":"x.webm"}]');
