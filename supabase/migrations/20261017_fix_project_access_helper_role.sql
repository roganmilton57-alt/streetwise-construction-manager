-- Correct the project-access helper to use the authoritative company_member_roles table.
-- Safe to run after 20261015_project_access_foundation.sql.
-- Does not alter existing project, BOQ, material, or workspace data.

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
    select 1
    from public.company_members cm
    join public.company_member_roles cr
      on cr.company_id = cm.company_id
     and cr.user_id = cm.user_id
    where cm.company_id = p_company_id
      and cm.user_id = auth.uid()
      and lower(coalesce(cr.role, '')) in ('administrator', 'admin', 'owner')
  )
  or (
    p_project_id is not null
    and exists (
      select 1
      from public.company_members cm
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

comment on function public.streetwise_can_access_project(uuid, uuid) is
  'True for company administrators (role sourced from company_member_roles) or users assigned to the specific project. Does not secure workspace_data payload until project-scoped storage is deployed.';
