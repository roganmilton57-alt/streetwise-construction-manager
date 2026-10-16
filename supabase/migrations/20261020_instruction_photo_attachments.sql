-- Private photo storage for Site Instructions / RFIs.
-- Photos are stored under company UUID / project UUID / instruction ID / filename.
-- No existing records or storage objects are changed or deleted by this migration.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'site-instruction-photos',
  'site-instruction-photos',
  false,
  10485760,
  array['image/jpeg','image/png','image/webp','image/heic','image/heif','image/gif']
)
on conflict (id) do update
set public = false,
    file_size_limit = 10485760,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists site_instruction_photos_read_assigned_project on storage.objects;
create policy site_instruction_photos_read_assigned_project
on storage.objects for select to authenticated
using (
  bucket_id = 'site-instruction-photos'
  and cardinality(storage.foldername(name)) = 3
  and public.streetwise_can_access_project(
    ((storage.foldername(name))[1])::uuid,
    ((storage.foldername(name))[2])::uuid
  )
);

drop policy if exists site_instruction_photos_upload_assigned_project on storage.objects;
create policy site_instruction_photos_upload_assigned_project
on storage.objects for insert to authenticated
with check (
  bucket_id = 'site-instruction-photos'
  and cardinality(storage.foldername(name)) = 3
  and public.streetwise_can_access_project(
    ((storage.foldername(name))[1])::uuid,
    ((storage.foldername(name))[2])::uuid
  )
);

drop policy if exists site_instruction_photos_update_assigned_project on storage.objects;
create policy site_instruction_photos_update_assigned_project
on storage.objects for update to authenticated
using (
  bucket_id = 'site-instruction-photos'
  and cardinality(storage.foldername(name)) = 3
  and public.streetwise_can_access_project(
    ((storage.foldername(name))[1])::uuid,
    ((storage.foldername(name))[2])::uuid
  )
)
with check (
  bucket_id = 'site-instruction-photos'
  and cardinality(storage.foldername(name)) = 3
  and public.streetwise_can_access_project(
    ((storage.foldername(name))[1])::uuid,
    ((storage.foldername(name))[2])::uuid
  )
);

drop policy if exists site_instruction_photos_delete_assigned_project on storage.objects;
create policy site_instruction_photos_delete_assigned_project
on storage.objects for delete to authenticated
using (
  bucket_id = 'site-instruction-photos'
  and cardinality(storage.foldername(name)) = 3
  and public.streetwise_can_access_project(
    ((storage.foldername(name))[1])::uuid,
    ((storage.foldername(name))[2])::uuid
  )
);
