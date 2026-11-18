-- Run after migrations with a database administrator connection.
-- All fixtures and role changes are rolled back.
begin;

set local plpgsql.check_asserts = on;

do $$
declare
  manager uuid := gen_random_uuid();
  limited_admin uuid := gen_random_uuid();
  inactive_worker uuid := gen_random_uuid();
  zones uuid[] := array[gen_random_uuid(), gen_random_uuid()];
  facilities uuid[] := array[gen_random_uuid(), gen_random_uuid()];
  added_facility uuid;
  workers uuid[] := array[gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
                          gen_random_uuid(), gen_random_uuid(), gen_random_uuid()];
  role_name text := 'Verification Cleaner ' || manager;
  work_day date := (now() at time zone 'Asia/Kuala_Lumpur')::date + 7;
  template uuid := gen_random_uuid();
  draft jsonb;
  leave_request uuid;
  initial_order uuid;
  filtered_accounts jsonb;
begin
  assert not exists (select 1 from information_schema.columns
    where table_schema in ('public', 'maintenance_api')
      and ((table_name = 'worker_profile' and column_name = 'assigned_zone')
        or (table_name = 'preventive_facility' and column_name = 'zone_id'))),
    'Facility and workforce APIs must omit zone fields.';
  work_day := work_day + (7 - extract(isodow from work_day)::integer);

  insert into auth.users(id, email)
  select id, id || '@campus-scheduling-test.invalid'
  from unnest(array[manager, limited_admin, inactive_worker] || workers) as fixture(id);
  insert into public.account(user_id, employee_id, full_name, role) values
    (manager, upper(manager::text), 'Scheduling Test Super Administrator', 'super_administrator'),
    (limited_admin, upper(limited_admin::text), 'Scheduling Test Administrator', 'administrator');
  insert into public.account(user_id, employee_id, full_name, role)
  select id, upper(id::text), 'Scheduling Test Worker ' || n, 'worker'
  from unnest(workers) with ordinality as fixture(id, n);
  insert into public.account(user_id, employee_id, full_name, role, is_active)
  values (inactive_worker, upper(inactive_worker::text), 'Scheduling Test Inactive Worker', 'worker', false);

  insert into public.preventive_zone(id, name)
  select id, 'Scheduling Test Scope ' || id from unnest(zones) as fixture(id);
  insert into maintenance_api.preventive_zone_admin(zone_id, administrator_id)
  values (zones[1], limited_admin);
  insert into uni360_private.facility_access_scope(facility_id, zone_id)
  select * from unnest(facilities, zones);
  insert into public.preventive_facility(id, name, facility_type)
  select id, 'Test Block ' || n, 'building'
  from unnest(facilities) with ordinality as fixture(id, n);
  insert into maintenance_api.preventive_task_definition
    (id, title, instructions, category, zone_id, required_job_role, checklist)
  values (template, 'Test campus cleaning', 'Clean the block', 'Cleaning',
    zones[1], role_name, array['Mop the floor']);

  update public.worker_profile w set
    job_role = case when n = 4 then 'Security Guard' else role_name end,
    employment_status = 'active',
    current_workload = case when n <= 3 then n else 0 end,
    daily_work_limit_minutes = case when n = 6 then 60 else 90 end
  from unnest(workers) with ordinality as fixture(id, n)
  where w.worker_id = id;
  insert into maintenance_api.worker_availability
    (worker_id, availability, shift_start, shift_end, availability_status, leave_status)
  select id, 'Scheduled shift',
    (work_day + time '08:00') at time zone 'Asia/Kuala_Lumpur',
    (work_day + time '17:00') at time zone 'Asia/Kuala_Lumpur',
    case when n = 5 then 'unavailable' else 'available' end, 'none'
  from unnest(workers) with ordinality as fixture(id, n);

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', limited_admin::text, true);
  filtered_accounts := public.list_managed_accounts(inactive_worker::text, 0, false);
  assert jsonb_array_length(filtered_accounts->'rows') = 1 and
    (filtered_accounts->'rows'->0->>'user_id')::uuid = inactive_worker;
  assert public.list_managed_accounts(inactive_worker::text, 0, true)->'rows' = '[]'::jsonb;
  assert (select count(*) = 1 from maintenance_api.preventive_facility where id = any(facilities)),
    'Facility visibility must follow existing administrator permissions.';
  insert into maintenance_api.preventive_facility(parent_id, name, facility_type)
  values (facilities[1], 'Test room', 'room') returning id into added_facility;
  assert added_facility is not null, 'Creating and returning a facility must work with no zone input.';
  begin
    perform public.review_preventive_range(array[facilities[2]], template, 'daily',
      work_day, work_day, array[time '11:00'], 90);
    raise exception 'An administrator generated work for an inaccessible facility.';
  exception when check_violation then null;
  end;

  perform set_config('request.jwt.claim.sub', manager::text, true);
  assert public.list_managed_accounts(limited_admin::text, 0, true)->'rows'->0->>'user_id' = limited_admin::text;
  assert public.list_managed_accounts(inactive_worker::text, 0, false)->'rows' = '[]'::jsonb;
  draft := public.review_preventive_range(facilities, template, 'daily',
    work_day, work_day, array[time '11:00'], 90);
  assert jsonb_array_length(draft->'rows') = 2, 'Expected one assignment per block.';
  assert (draft->'rows'->0->>'worker_id')::uuid = workers[1] and
         (draft->'rows'->1->>'worker_id')::uuid = workers[2],
    'Assignments should use the lowest-load available workers with the required role and time.';
  assert public.review_preventive_range(facilities, template, 'daily',
    work_day, work_day, array[time '11:00'], 90, draft->'rows', draft->'warnings') = '2'::jsonb,
    'Campus-wide Sunday draft must be approvable.';
  draft := public.review_preventive_range(facilities, template, 'daily',
    work_day, work_day, array[time '14:00'], 90);
  assert jsonb_array_length(draft->'warnings') > 0, 'Sunday duplicate warnings must still be generated.';

  select o.id into strict initial_order
  from public.preventive_work_order o
  join public.preventive_task_plan p on p.id = o.plan_id
  where p.task_definition_id = template and p.facility_id = facilities[1]
    and o.worker_id = workers[1];
  perform set_config('request.jwt.claim.sub', workers[1]::text, true);
  begin
    perform public.list_managed_accounts('', 0, null);
    raise exception 'A worker could list managed accounts.';
  exception when insufficient_privilege then null;
  end;
  leave_request := public.submit_worker_leave('annual', work_day, work_day, 'Scheduling test');
  perform set_config('request.jwt.claim.sub', manager::text, true);
  assert (public.review_worker_leave(leave_request, true)->>'reassigned')::integer = 1,
    'Leave approval must reassign the worker’s scheduled task.';
  assert (select worker_id = workers[3] from maintenance_api.preventive_work_order where id = initial_order),
    'Replacement must use the remaining qualified worker within their daily limit.';
end;
$$;

rollback;
