import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const fields = 'user_id,employee_id,full_name,phone,is_active,created_at';
const pageSize = 20;
const json = (value: unknown, status = 200) => Response.json(value, {
  status, headers: { ...cors, 'Cache-Control': 'no-store' },
});
const fail = (message: string, status: number) => json({ error: message }, status);

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (request.method !== 'POST') return fail('Method not allowed.', 405);

  const token = request.headers.get('Authorization')?.match(/^Bearer (\S+)$/i)?.[1];
  if (!token) return fail('Sign in to continue.', 401);
  const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const { data: identity, error: authError } = await client.auth.getUser(token);
    if (authError || !identity.user) return fail('Sign in to continue.', 401);
    const { data: actor, error: actorError } = await client.from('account')
      .select('full_name,role,is_active').eq('user_id', identity.user.id).maybeSingle();
    if (actorError) throw actorError;
    const targetRole = actor?.is_active && actor.role === 'super_administrator' ? 'administrator'
      : actor?.is_active && actor.role === 'administrator' ? 'worker' : null;
    if (!targetRole) return fail('An active administrator account is required.', 403);

    const input = await request.json().catch(() => null);
    if (!input || typeof input !== 'object' || Array.isArray(input)) return fail('Invalid request.', 400);
    if ((input.action === 'edit' || input.action === 'deactivate') &&
        (typeof input.id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(input.id))) {
      return fail('Invalid account identifier.', 400);
    }

    if (input.action === 'list') {
      const search = typeof input.search === 'string' ? input.search.trim().slice(0, 120) : '';
      const page = Number.isInteger(input.page) && input.page >= 0 && input.page <= 10000 ? input.page : 0;
      let query = client.from('account').select(fields).eq('role', targetRole);
      if (search) {
        const pattern = `%${search.replace(/[\\%_*]/g, '\\$&')}%`;
        const quoted = JSON.stringify(pattern);
        query = query.or(`full_name.ilike.${quoted},employee_id.ilike.${quoted}`);
      }
      const { data, error } = await query.order('full_name').order('user_id')
        .range(page * pageSize, (page + 1) * pageSize);
      if (error) throw error;
      return json({ actor, targetRole, rows: data.slice(0, pageSize), hasNext: data.length > pageSize });
    }

    if (input.action === 'deactivate') {
      const { data, error } = await client.from('account').update({ is_active: false })
        .eq('user_id', input.id).eq('role', targetRole).select('user_id').maybeSingle();
      if (error) throw error;
      return data ? json({ ok: true }) : fail('Account not found in your scope.', 404);
    }

    if (input.action !== 'create' && input.action !== 'edit') return fail('Unknown action.', 400);
    const full_name = typeof input.name === 'string' ? input.name.trim() : '';
    const employee_id = typeof input.employeeId === 'string' ? input.employeeId.trim().toUpperCase() : '';
    const phone = typeof input.phone === 'string' ? input.phone.trim() : '';
    if (full_name.length < 2 || full_name.length > 120 || !/^[A-Z0-9-]{1,40}$/.test(employee_id) ||
        (phone && !/^\+?[0-9 ()-]{8,20}$/.test(phone))) {
      return fail('Check the full name, employee ID and phone number.', 400);
    }
    const contact = { full_name, employee_id, phone };
    if (input.action === 'edit') {
      const { data, error } = await client.from('account').update(contact)
        .eq('user_id', input.id).eq('role', targetRole).select('user_id').maybeSingle();
      if (error?.code === '23505') return fail('That employee ID is already in use.', 409);
      if (error) throw error;
      return data ? json({ ok: true }) : fail('Account not found in your scope.', 404);
    }

    const email = typeof input.email === 'string' ? input.email.trim().toLowerCase() : '';
    const password = typeof input.password === 'string' ? input.password : '';
    if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || password.length < 12 || password.length > 72) {
      return fail('Enter a valid email and a temporary password of 12–72 characters.', 400);
    }
    const { data: created, error: createError } = await client.auth.admin.createUser({ email, password, email_confirm: true });
    if (createError || !created.user) {
      if (createError?.code === 'email_exists' || createError?.code === 'user_already_exists') {
        return fail('That email is already in use.', 409);
      }
      return fail('Could not create the sign-in. Check the email and password requirements.', 400);
    }
    const userId = created.user.id;
    const { error: insertError } = await client.from('account').insert({ ...contact, user_id: userId, role: targetRole });
    if (insertError) {
      const { error: cleanupError } = await client.auth.admin.deleteUser(userId);
      if (cleanupError) {
        console.error('Account creation cleanup failed', userId, cleanupError.code);
        return fail('Creation could not be confirmed. Contact the project owner before retrying.', 500);
      }
      if (insertError.code === '23505') return fail('That employee ID is already in use.', 409);
      throw insertError;
    }
    return json({ ok: true }, 201);
  } catch (error) {
    console.error('Manage accounts failed', error instanceof Error ? error.name : 'database error');
    return fail('The account service could not complete this request. Try again.', 500);
  }
});
