-- Applied to Bingo App Kenya Supabase on 2026-09-27.
-- Profile image bucket and authenticated owner-only writes.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('profile-images','profile-images',true,10485760,array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do nothing;
create policy "bingo_profile_images_public_read" on storage.objects for select to public using (bucket_id = 'profile-images');
create policy "bingo_profile_images_owner_insert" on storage.objects for insert to authenticated with check (bucket_id = 'profile-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "bingo_profile_images_owner_update" on storage.objects for update to authenticated using (bucket_id = 'profile-images' and (storage.foldername(name))[1] = (select auth.uid())::text) with check (bucket_id = 'profile-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "bingo_profile_images_owner_delete" on storage.objects for delete to authenticated using (bucket_id = 'profile-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
