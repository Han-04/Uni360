-- Run on a development project after creating and confirming the three users
-- in Authentication > Users. Replace the sample emails here if needed.
begin;

do $$
declare
  entry record;
  auth_id uuid;
begin
  for entry in
    select * from (values
      ('super-admin@uni360.example', 'SA-2026-001', 'Test Super Administrator', 'super_administrator'),
      ('admin@uni360.example',       'ADM-2026-001', 'Test Administrator',     'administrator'),
      ('worker@uni360.example',      'EMP-2026-001', 'Test Worker',            'worker')
    ) as accounts(email, employee_id, full_name, role)
  loop
    select id into auth_id
    from auth.users
    where lower(email) = lower(entry.email) and email_confirmed_at is not null;

    if auth_id is null then
      raise exception 'Create and confirm the Supabase Auth user % first.', entry.email;
    end if;

    insert into public.account (user_id, employee_id, full_name, role)
    values (auth_id, entry.employee_id, entry.full_name, entry.role::public.account_role)
    on conflict (user_id) do nothing;

    if not exists (
      select 1 from public.account
      where user_id = auth_id and employee_id = entry.employee_id
        and role = entry.role::public.account_role and is_active
    ) then
      raise exception 'Account % already exists with different details or is inactive.', entry.email;
    end if;
  end loop;
end;
$$;

commit;
