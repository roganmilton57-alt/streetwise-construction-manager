import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const roles = new Set(['administrator','project_manager','quantity_surveyor','site_engineer','storekeeper','read_only']);
const projectAccessValues = new Set(['all_current','assigned_only']);

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Use POST.' }, 405);
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) return json({ error: 'Sign in first.' }, 401);

    const callerClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });
    const { data: { user: caller }, error: userErr } = await callerClient.auth.getUser();
    if (userErr || !caller) return json({ error: 'Your session is invalid. Sign in again.' }, 401);

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
    const body = await req.json();
    const companyId = String(body.company_id || '');
    const name = String(body.name || '').trim();
    const email = String(body.email || '').trim().toLowerCase();
    const role = String(body.role || 'storekeeper');
    const projectAccess = String(body.project_access || 'all_current');
    const requestedProjectIds = Array.isArray(body.project_ids)
      ? [...new Set(body.project_ids.map((v: unknown) => String(v)))]
      : [];

    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(companyId)) return json({ error: 'Invalid company ID.' }, 400);
    if (!name || name.length > 120) return json({ error: 'Enter a valid staff name (maximum 120 characters).' }, 400);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) return json({ error: 'Enter a valid email address.' }, 400);
    if (!roles.has(role)) return json({ error: 'Invalid role.' }, 400);
    if (!projectAccessValues.has(projectAccess)) return json({ error: 'Invalid project access choice.' }, 400);
    if (projectAccess === 'assigned_only' && role !== 'administrator' && requestedProjectIds.length === 0) {
      return json({ error: 'Select at least one project for restricted access.' }, 400);
    }
    for (const id of requestedProjectIds) {
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) return json({ error: 'One or more project IDs are invalid.' }, 400);
    }

    const { data: membership, error: memberErr } = await admin.from('company_members')
      .select('user_id').eq('company_id', companyId).eq('user_id', caller.id).maybeSingle();
    if (memberErr || !membership) return json({ error: 'You are not a member of this company.' }, 403);

    const { data: callerRole } = await admin.from('company_member_roles')
      .select('role').eq('company_id', companyId).eq('user_id', caller.id).maybeSingle();
    const { count: adminCount } = await admin.from('company_member_roles')
      .select('*', { count: 'exact', head: true }).eq('company_id', companyId).eq('role', 'administrator');
    if (callerRole?.role !== 'administrator' && (adminCount || 0) > 0) return json({ error: 'Only a company administrator can invite staff.' }, 403);
    if (!callerRole?.role && (adminCount || 0) === 0) {
      const { error: bootstrapErr } = await admin.from('company_member_roles').upsert({
        company_id: companyId, user_id: caller.id, role: 'administrator',
        updated_at: new Date().toISOString(), updated_by: caller.id,
      });
      if (bootstrapErr) return json({ error: 'Could not initialise company administrator: ' + bootstrapErr.message }, 500);
    }
    if (role === 'administrator' && callerRole?.role !== 'administrator' && (adminCount || 0) > 0) {
      return json({ error: 'Only an existing company administrator can invite another administrator.' }, 403);
    }

    // Validate every selected project against the company before storing the invitation.
    let selectedProjectIds: string[] = [];
    if (role === 'administrator' || projectAccess === 'all_current') {
      const { data: projects, error: projectsErr } = await admin.from('project_records')
        .select('id').eq('company_id', companyId);
      if (projectsErr) return json({ error: 'Could not verify company projects: ' + projectsErr.message }, 500);
      selectedProjectIds = (projects || []).map((p: { id: string }) => p.id);
    } else {
      const { data: projects, error: projectsErr } = await admin.from('project_records')
        .select('id').eq('company_id', companyId).in('id', requestedProjectIds);
      if (projectsErr) return json({ error: 'Could not verify selected projects: ' + projectsErr.message }, 500);
      selectedProjectIds = (projects || []).map((p: { id: string }) => p.id);
      if (selectedProjectIds.length !== requestedProjectIds.length) {
        return json({ error: 'One or more selected projects do not belong to this company. Refresh and try again.' }, 400);
      }
    }

    const effectiveAccess = role === 'administrator' ? 'all_current' : projectAccess;
    const { data: invitation, error: inviteRowErr } = await admin.from('company_invitations').upsert({
      company_id: companyId, email, full_name: name, role,
      project_access: effectiveAccess, project_ids: selectedProjectIds,
      invited_by: caller.id, status: 'pending', auth_user_id: null,
    }, { onConflict: 'company_id,email' }).select('id').single();
    if (inviteRowErr) return json({ error: inviteRowErr.message }, 400);

    const { data: usersPage, error: listErr } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
    if (listErr) return json({ error: 'Invitation saved, but could not check existing accounts: ' + listErr.message }, 500);
    const existing = usersPage.users.find((u) => (u.email || '').toLowerCase() === email);

    if (existing) {
      const { error: addErr } = await admin.from('company_members').upsert(
        { company_id: companyId, user_id: existing.id }, { onConflict: 'company_id,user_id' });
      if (addErr) return json({ error: 'User exists, but company membership failed: ' + addErr.message }, 500);

      const { error: roleErr } = await admin.from('company_member_roles').upsert({
        company_id: companyId, user_id: existing.id, role,
        updated_at: new Date().toISOString(), updated_by: caller.id,
      });
      if (roleErr) return json({ error: 'Membership added, but role assignment failed: ' + roleErr.message }, 500);

      // Replace this member's assignment set for this company to match the new invitation.
      const { error: clearErr } = await admin.from('project_members')
        .delete().eq('company_id', companyId).eq('user_id', existing.id);
      if (clearErr) return json({ error: 'Membership saved, but project assignments could not be updated: ' + clearErr.message }, 500);

      if (selectedProjectIds.length) {
        const assignmentRows = selectedProjectIds.map((project_id) => ({
          company_id: companyId, project_id, user_id: existing.id, assigned_by: caller.id,
        }));
        const { error: assignmentErr } = await admin.from('project_members')
          .upsert(assignmentRows, { onConflict: 'company_id,project_id,user_id' });
        if (assignmentErr) return json({ error: 'Membership saved, but project assignments failed: ' + assignmentErr.message }, 500);
      }

      await admin.from('company_invitations').update({
        status: 'accepted', auth_user_id: existing.id, accepted_at: new Date().toISOString(),
      }).eq('id', invitation.id);
      return json({
        message: `${name} has been connected to your company with the ${role.replaceAll('_',' ')} role and ${selectedProjectIds.length} project assignment(s).`,
        status: 'accepted',
      }, 200);
    }

    const redirectTo = Deno.env.get('INVITE_REDIRECT_URL');
    const { error: authInviteErr } = await admin.auth.admin.inviteUserByEmail(email, {
      data: { full_name: name, streetwise_company_invite: invitation.id },
      ...(redirectTo ? { redirectTo } : {}),
    });
    if (authInviteErr) {
      await admin.from('company_invitations').update({ status: 'failed' }).eq('id', invitation.id);
      return json({ error: 'Invitation could not be emailed: ' + authInviteErr.message }, 400);
    }
    return json({
      message: `Invitation email sent to ${email}. Their project assignments will be applied when they accept and confirm their account.`,
      status: 'pending',
    }, 200);
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : 'Unexpected invitation error.' }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}
