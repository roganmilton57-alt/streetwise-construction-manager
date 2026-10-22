-- Add durable receipt traceability fields to material records.
-- Additive only: existing rows and stock values are preserved.
alter table public.material_records
  add column if not exists delivery_note text not null default '',
  add column if not exists vehicle_reg text not null default '',
  add column if not exists received_time text not null default '',
  add column if not exists received_by text not null default '';
