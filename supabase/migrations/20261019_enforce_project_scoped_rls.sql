-- Enforce project-level RLS after the app reads/writes workspace_project_data.
-- Apply only after 20261017_fix_project_access_helper_role.sql and
-- 20261018_workspace_project_data.sql, and after deploying the updated app.
-- Legacy workspace_data is restricted to company admins; its payload contains
-- multiple projects. No rows are deleted or rewritten by this migration.

create or replace function public.streetwise_is_company_admin(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.company_members cm
    join public.company_member_roles cr
      on cr.company_id = cm.company_id
     and cr.user_id = cm.user_id
    where cm.company_id = p_company_id
      and cm.user_id = auth.uid()
      and lower(coalesce(cr.role, '')) in ('administrator', 'admin', 'owner')
  );
$$;
revoke all on function public.streetwise_is_company_admin(uuid) from public;
grant execute on function public.streetwise_is_company_admin(uuid) to authenticated;

do $$
declare t text; pol record;
begin
  foreach t in array array[
    'project_records','boq_items','material_records',
    'material_usage_records','material_categories','workspace_data'
  ] loop
    for pol in
      select policyname from pg_policies
      where schemaname='public' and tablename=t
    loop
      execute format('drop policy if exists %I on public.%I', pol.policyname, t);
    end loop;
  end loop;
end $$;

-- Project metadata: members see only assigned projects; administrators manage all.
alter table public.project_records enable row level security;
create policy project_records_select_accessible on public.project_records
for select to authenticated
using (public.streetwise_can_access_project(company_id, id));
create policy project_records_insert_admin on public.project_records
for insert to authenticated
with check (public.streetwise_is_company_admin(company_id));
create policy project_records_update_admin on public.project_records
for update to authenticated
using (public.streetwise_is_company_admin(company_id))
with check (public.streetwise_is_company_admin(company_id));
create policy project_records_delete_admin on public.project_records
for delete to authenticated
using (public.streetwise_is_company_admin(company_id));

-- Project-scoped records.
alter table public.boq_items enable row level security;
create policy boq_items_select_accessible on public.boq_items for select to authenticated
using (public.streetwise_can_access_project(company_id, project_id));
create policy boq_items_insert_accessible on public.boq_items for insert to authenticated
with check (public.streetwise_can_access_project(company_id, project_id));
create policy boq_items_update_accessible on public.boq_items for update to authenticated
using (public.streetwise_can_access_project(company_id, project_id))
with check (public.streetwise_can_access_project(company_id, project_id));
create policy boq_items_delete_accessible on public.boq_items for delete to authenticated
using (public.streetwise_can_access_project(company_id, project_id));

alter table public.material_records enable row level security;
create policy material_records_select_accessible on public.material_records for select to authenticated
using (
  (project_id is not null and public.streetwise_can_access_project(company_id, project_id))
  or (project_id is null and public.streetwise_is_company_admin(company_id))
);
create policy material_records_insert_accessible on public.material_records for insert to authenticated
with check (
  (project_id is not null and public.streetwise_can_access_project(company_id, project_id))
  or (project_id is null and public.streetwise_is_company_admin(company_id))
);
create policy material_records_update_accessible on public.material_records for update to authenticated
using (
  (project_id is not null and public.streetwise_can_access_project(company_id, project_id))
  or (project_id is null and public.streetwise_is_company_admin(company_id))
)
with check (
  (project_id is not null and public.streetwise_can_access_project(company_id, project_id))
  or (project_id is null and public.streetwise_is_company_admin(company_id))
);
create policy material_records_delete_accessible on public.material_records for delete to authenticated
using (
  (project_id is not null and public.streetwise_can_access_project(company_id, project_id))
  or (project_id is null and public.streetwise_is_company_admin(company_id))
);

alter table public.material_usage_records enable row level security;
create policy material_usage_select_accessible on public.material_usage_records for select to authenticated
using (public.streetwise_can_access_project(company_id, project_id));
create policy material_usage_insert_accessible on public.material_usage_records for insert to authenticated
with check (public.streetwise_can_access_project(company_id, project_id));
create policy material_usage_update_accessible on public.material_usage_records for update to authenticated
using (public.streetwise_can_access_project(company_id, project_id))
with check (public.streetwise_can_access_project(company_id, project_id));
create policy material_usage_delete_accessible on public.material_usage_records for delete to authenticated
using (public.streetwise_can_access_project(company_id, project_id));

alter table public.material_categories enable row level security;
create policy material_categories_select_accessible on public.material_categories for select to authenticated
using (
  (project_id is not null and public.streetwise_can_access_project(company_id, project_id))
  or (project_id is null and public.streetwise_is_company_admin(company_id))
);
create policy material_categories_insert_accessible on public.material_categories for insert to authenticated
with check (
  (project_id is not null and public.streetwise_can_access_project(company_id, project_id))
  or (project_id is null and public.streetwise_is_company_admin(company_id))
);
create policy material_categories_update_accessible on public.material_categories for update to authenticated
using (
  (project_id is not null and public.streetwise_can_access_project(company_id, project_id))
  or (project_id is null and public.streetwise_is_company_admin(company_id))
)
with check (
  (project_id is not null and public.streetwise_can_access_project(company_id, project_id))
  or (project_id is null and public.streetwise_is_company_admin(company_id))
);
create policy material_categories_delete_accessible on public.material_categories for delete to authenticated
using (
  (project_id is not null and public.streetwise_can_access_project(company_id, project_id))
  or (project_id is null and public.streetwise_is_company_admin(company_id))
);

-- The old single-row JSON payload remains readable/writable only by administrators.
alter table public.workspace_data enable row level security;
create policy workspace_data_admin_only on public.workspace_data
for all to authenticated
using (public.streetwise_is_company_admin(company_id))
with check (public.streetwise_is_company_admin(company_id));

comment on function public.streetwise_is_company_admin(uuid) is
  'Company administrator check based on company_member_roles.';
