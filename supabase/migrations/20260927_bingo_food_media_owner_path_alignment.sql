-- Applied to Bingo App Kenya on 2026-09-27.
-- Align food-media INSERT policy with the application's user_id/business_id/file path.
-- Retain legacy business-first owner uploads and explicitly authorised manager uploads.
drop policy if exists bingo_food_media_upload on storage.objects;
create policy bingo_food_media_upload on storage.objects for insert to authenticated with check (
 bucket_id = 'food-media' and (
  (storage.foldername(name))[1] = (select auth.uid())::text
  or exists (select 1 from public.food_businesses b where b.id::text = (storage.foldername(name))[1] and b.owner_id = (select auth.uid()))
  or exists (select 1 from public.food_businesses b join public.bingo_food_business_manager_access m on m.business_id=b.id where b.id::text = (storage.foldername(name))[2] and b.owner_id::text=(storage.foldername(name))[1] and m.manager_id=(select auth.uid()) and m.status='accepted' and coalesce((m.permissions->>'upload_media')::boolean,false))
 )
);
