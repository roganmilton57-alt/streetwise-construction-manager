-- Project-scoped workspace storage foundation.
-- This adds a new table only; it does not migrate, delete, or overwrite legacy
-- workspace_data.payload. Keep legacy data untouched until the app migration
-- has been validated and a controlled backfill is ready.

create table if not exists public.workspace_project_data (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  project_id uuid not null,
  payload jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint workspace_project_data_project_company_fk
    foreign key (project_id, company_id)
    references public.project_records(id, company_id)
    on delete cascade,
  constraint workspace_project_data_project_key
    unique (company_id, project_id)
);

create index if not exists workspace_project_data_company_project_idx
  on public.workspace_project_data(company_id, project_id);

alter table public.workspace_project_data enable row level security;

drop policy if exists workspace_project_data_select_assigned on public.workspace_project_data;
create policy workspace_project_data_select_assigned
  on public.workspace_project_data for select to authenticated
  using (public.streetwise_can_access_project(company_id, project_id));

drop policy if exists workspace_project_data_insert_assigned on public.workspace_project_data;
create policy workspace_project_data_insert_assigned
  on public.workspace_project_data for insert to authenticated
  with check (
    updated_by = auth.uid()
    and public.streetwise_can_access_project(company_id, project_id)
  );

drop policy if exists workspace_project_data_update_assigned on public.workspace_project_data;
create policy workspace_project_data_update_assigned
  on public.workspace_project_data for update to authenticated
  using (public.streetwise_can_access_project(company_id, project_id))
  with check (
    public.streetwise_can_access_project(company_id, project_id)
  );

drop policy if exists workspace_project_data_delete_admin on public.workspace_project_data;
create policy workspace_project_data_delete_admin
  on public.workspace_project_data for delete to authenticated
  using (
    exists (
      select 1
      from public.company_members cm
      join public.company_member_roles cr
        on cr.company_id = cm.company_id
       and cr.user_id = cm.user_id
      where cm.company_id = workspace_project_data.company_id
        and cm.user_id = auth.uid()
        and lower(coalesce(cr.role, '')) in ('administrator', 'admin', 'owner')
    )
  );

grant select, insert, update, delete on public.workspace_project_data to authenticated;

comment on table public.workspace_project_data is
  'Project-isolated JSON workspace. App migration and verified backfill required before this table replaces legacy workspace_data.payload.';
