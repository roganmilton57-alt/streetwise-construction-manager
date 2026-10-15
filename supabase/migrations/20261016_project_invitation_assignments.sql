-- Project assignments for Streetwise team invitations.
-- Apply only after 20261015_project_access_foundation.sql.
-- This records assignments at invitation/acceptance time. It does NOT by itself
-- secure workspace_data's company-wide JSON payload; do not claim restricted
-- access is fully enforced until project-scoped workspace storage and RLS ship.

alter table public.company_invitations
  add column if not exists project_ids uuid[] not null default '{}'::uuid[];

create or replace function public.streetwise_accept_pending_company_invites()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  inv record;
  assigned_project_id uuid;
begin
  if new.email is null or new.email_confirmed_at is null then return new; end if;
  if tg_op = 'UPDATE' and old.email_confirmed_at is not null then return new; end if;

  for inv in
    select *
    from public.company_invitations
    where lower(email) = lower(new.email)
      and status = 'pending'
    order by created_at
  loop
    insert into public.company_members(company_id, user_id)
    values (inv.company_id, new.id)
    on conflict do nothing;

    insert into public.company_member_roles(company_id, user_id, role, updated_at, updated_by)
    values (inv.company_id, new.id, inv.role, now(), inv.invited_by)
    on conflict (company_id, user_id) do update
      set role = excluded.role, updated_at = now(), updated_by = excluded.updated_by;

    -- Reconcile only this invited user's project assignments for this company.
    delete from public.project_members
    where company_id = inv.company_id and user_id = new.id;

    if inv.role = 'administrator' or inv.project_access = 'all_current' then
      insert into public.project_members(company_id, project_id, user_id, assigned_by)
      select p.company_id, p.id, new.id, inv.invited_by
      from public.project_records p
      where p.company_id = inv.company_id
      on conflict (company_id, project_id, user_id) do nothing;
    else
      foreach assigned_project_id in array coalesce(inv.project_ids, '{}'::uuid[])
      loop
        insert into public.project_members(company_id, project_id, user_id, assigned_by)
        select p.company_id, p.id, new.id, inv.invited_by
        from public.project_records p
        where p.company_id = inv.company_id and p.id = assigned_project_id
        on conflict (company_id, project_id, user_id) do nothing;
      end loop;
    end if;

    update public.company_invitations
    set status = 'accepted', auth_user_id = new.id, accepted_at = now()
    where id = inv.id;
  end loop;
  return new;
end;
$$;

-- Recreate only the Streetwise invitation trigger.
drop trigger if exists streetwise_accept_company_invites on auth.users;
create trigger streetwise_accept_company_invites
after insert or update of email_confirmed_at on auth.users
for each row execute function public.streetwise_accept_pending_company_invites();
