-- Rows created AFTER the migration.
insert into public.bingo_topics(id,user_id,body,media_status) values
 ('a0000000-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000001','pending media post','pending');
insert into public.bingo_topics(id,user_id,body,media_status,created_at) values
 ('a0000000-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000001','old abandoned post','pending', now() - interval '25 hours');
insert into public.bingo_topics(id,user_id,body,media_status) values
 ('b0000000-0000-0000-0000-000000000005','bbbbbbbb-0000-0000-0000-000000000002','B pending post','pending');
