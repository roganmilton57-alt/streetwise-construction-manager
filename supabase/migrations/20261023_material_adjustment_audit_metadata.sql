-- Add audit metadata for future stock adjustments. Existing records are preserved.
alter table public.material_adjustment_records
  add column if not exists created_by_email text not null default '';
comment on column public.material_adjustment_records.created_by_email is
  'Email captured at creation for readable adjustment audit history; created_by UUID remains the identity reference.';
