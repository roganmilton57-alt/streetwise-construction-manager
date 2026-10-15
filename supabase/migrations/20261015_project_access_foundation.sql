-- Streetwise Construction Manager: project-access foundation
-- Branch: fix/project-access-controls
-- SAFE FOUNDATION ONLY:
-- This migration creates the assignment registry and helper functions.
-- Do not deploy project-level policies until index.html stops reading/writing the
-- company-wide workspace_data.payload directly. That payload contains multiple
-- projects and must be filtered/merged server-side first.

create table if not exists public.project_members (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  project_id uuid not null references public.project_records(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  assigned_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (company_id, project_id, user_id),
  constraint project_members_project_company_fk
    foreign key (project_id, company_id)
    references public.project_records(id, company_id)
    on delete cascade
);

-- The composite foreign key above requires a matching unique key on
-- project_records(id, company_id). Add it only if absent.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.project_records'::regclass
      and conname = 'project_records_id_company_id_key'
  ) then
    alter table public.project_records
      add constraint project_records_id_company_id_key unique (id, company_id);
  end if;
end $$;

create index if not exists project_members_company_user_idx
  on public.project_members(company_id, user_id);
create index if not exists project_members_project_user_idx
  on public.project_members(project_id, user_id);

alter table public.project_members enable row level security;

drop policy if exists project_members_select_company_admin on public.project_members;
create policy project_members_select_company_admin
  on public.project_members for select to authenticated
  using (
    exists (
      select 1 from public.company_members cm
      where cm.company_id = project_members.company_id
        and cm.user_id = auth.uid()
        and lower(cm.role) in ('administrator', 'admin', 'owner')
    )
    or user_id = auth.uid()
  );

drop policy if exists project_members_insert_company_admin on public.project_members;
create policy project_members_insert_company_admin
  on public.project_members for insert to authenticated
  with check (
    assigned_by = auth.uid()
    and exists (
      select 1 from public.company_members cm
      where cm.company_id = project_members.company_id
        and cm.user_id = auth.uid()
        and lower(cm.role) in ('administrator', 'admin', 'owner')
    )
    and exists (
      select 1 from public.project_records p
      where p.id = project_members.project_id
        and p.company_id = project_members.company_id
    )
  );

drop policy if exists project_members_delete_company_admin on public.project_members;
create policy project_members_delete_company_admin
  on public.project_members for delete to authenticated
  using (
    exists (
      select 1 from public.company_members cm
      where cm.company_id = project_members.company_id
        and cm.user_id = auth.uid()
        and lower(cm.role) in ('administrator', 'admin', 'owner')
    )
  );

grant select, insert, delete on public.project_members to authenticated;

create or replace function public.streetwise_can_access_project(
  p_company_id uuid,
  p_project_id uuid
) returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from public.company_members cm
    where cm.company_id = p_company_id
      and cm.user_id = auth.uid()
      and lower(cm.role) in ('administrator', 'admin', 'owner')
  )
  or (
    p_project_id is not null
    and exists (
      select 1 from public.company_members cm
      join public.project_members pm
        on pm.company_id = cm.company_id
       and pm.user_id = cm.user_id
      where cm.company_id = p_company_id
        and cm.user_id = auth.uid()
        and pm.project_id = p_project_id
    )
  );
$$;

revoke all on function public.streetwise_can_access_project(uuid, uuid) from public;
grant execute on function public.streetwise_can_access_project(uuid, uuid) to authenticated;

comment on table public.project_members is
  'Per-user project assignments. Do not treat invitation project_access as enforced until project-scoped payload reads/writes and RLS are deployed.';
comment on function public.streetwise_can_access_project(uuid, uuid) is
  'Returns true for company administrators or users assigned to the specific project. Foundation helper; activate in data-table RLS only with the workspace_data payload isolation update.';
