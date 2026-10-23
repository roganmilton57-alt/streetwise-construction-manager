-- Stock reconciliation adjustments. Additive only; existing receipts and usage remain unchanged.
create table if not exists public.material_adjustment_records (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null,
 project_id uuid not null,
 adjustment_date date not null default current_date,
 category text not null default 'General Site Materials',
 material text not null,
 unit text not null default '',
 quantity numeric(14,3) not null,
 reason text not null,
 notes text not null default '',
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 constraint material_adjustment_quantity_nonzero check (quantity <> 0),
 constraint material_adjustment_project_company_fk foreign key (project_id, company_id)
  references public.project_records(id, company_id) on delete cascade
);
create index if not exists material_adjustment_company_project_date_idx
 on public.material_adjustment_records(company_id, project_id, adjustment_date, created_at);
alter table public.material_adjustment_records enable row level security;
drop policy if exists material_adjustment_select_accessible on public.material_adjustment_records;
create policy material_adjustment_select_accessible on public.material_adjustment_records for select to authenticated
 using (public.streetwise_can_access_project(company_id, project_id));
drop policy if exists material_adjustment_insert_accessible on public.material_adjustment_records;
create policy material_adjustment_insert_accessible on public.material_adjustment_records for insert to authenticated
 with check (created_by = auth.uid() and public.streetwise_can_access_project(company_id, project_id));
drop policy if exists material_adjustment_update_accessible on public.material_adjustment_records;
create policy material_adjustment_update_accessible on public.material_adjustment_records for update to authenticated
 using (public.streetwise_can_access_project(company_id, project_id))
 with check (public.streetwise_can_access_project(company_id, project_id));
drop policy if exists material_adjustment_delete_accessible on public.material_adjustment_records;
create policy material_adjustment_delete_accessible on public.material_adjustment_records for delete to authenticated
 using (public.streetwise_can_access_project(company_id, project_id));
grant select, insert, update, delete on public.material_adjustment_records to authenticated;
comment on table public.material_adjustment_records is
 'Stock reconciliation movements: positive quantity increases stock; negative quantity decreases stock. Existing receipts and usage are retained.';
