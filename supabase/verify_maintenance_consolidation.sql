-- Run after the consolidation with a database administrator connection.
-- All test users and maintenance records are rolled back.
begin;

set local plpgsql.check_asserts = on;

do $$
declare
  zone uuid := gen_random_uuid();
  facility uuid := gen_random_uuid();
  manager uuid := gen_random_uuid();
  technician uuid := gen_random_uuid();
  reporter uuid := gen_random_uuid();
  incident uuid := gen_random_uuid();
  template uuid;
  assignment uuid;
  required_skill uuid;
  task maintenance_api.preventive_work_order%rowtype;
  draft jsonb;
  work_date date := (now() at time zone 'Asia/Kuala_Lumpur')::date + 1;
  original_start timestamptz;
  release_at timestamptz;
  picture text;
  notification bigint;
  read_at timestamptz;
begin
  assert (select count(*) = 15 from information_schema.tables
    where table_schema in ('public', 'uni360_data') and table_type = 'BASE TABLE'),
    'Expected 15 core maintenance tables.';
  assert (select count(*) between 1 and 15 and bool_and(table_type = 'BASE TABLE')
    from information_schema.tables where table_schema = 'public'),
    'The default Table Editor list should contain only core tables.';
  assert not has_schema_privilege('anon', 'maintenance_api', 'USAGE');
  assert not has_schema_privilege('anon', 'uni360_data', 'USAGE');
  assert not has_table_privilege('anon', 'maintenance_api.preventive_work_evidence', 'SELECT');
  assert not has_table_privilege('anon', 'maintenance_api.corrective_notification', 'SELECT');
  assert not has_column_privilege('authenticated', 'maintenance_api.corrective_notification', 'recipient_id', 'UPDATE');
  assert not has_column_privilege('authenticated', 'maintenance_api.preventive_work_completion', 'notes', 'UPDATE');
  assert (select count(*) = 2 from storage.buckets
    where id in ('preventive-work-evidence', 'corrective-evidence') and not public);
  assert exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
    and schemaname = 'uni360_data' and tablename = 'maintenance_activity');

  if extract(isodow from work_date) = 7 then work_date := work_date + 1; end if;
  original_start := (work_date + time '10:00') at time zone 'Asia/Kuala_Lumpur';
  release_at := original_start + interval '30 minutes';

  insert into auth.users(id, aud, role, email)
  select id, 'authenticated', 'authenticated', id || '@maintenance-test.invalid'
  from unnest(array[manager, technician, reporter]) as fixture(id);
  insert into public.account(user_id, employee_id, full_name, role) values
    (manager, upper(manager::text), 'Maintenance Test Manager', 'administrator'),
    (technician, upper(technician::text), 'Maintenance Test Technician', 'worker'),
    (reporter, upper(reporter::text), 'Maintenance Test Reporter', 'reporter');
  insert into public.preventive_zone(id, name) values (zone, 'Maintenance test ' || zone);
  insert into maintenance_api.preventive_zone_admin(zone_id, administrator_id) values (zone, manager);
  insert into uni360_private.facility_access_scope(facility_id, zone_id) values (facility, zone);
  insert into public.preventive_facility(id, name, facility_type)
  values (facility, 'Shared test facility', 'building');
  update public.worker_profile set job_role = 'Plumber',
    employment_status = 'active' where worker_id = technician;
  insert into public.corrective_incident(id, facility_id, zone_id, facility_name, category,
    title, description, location_detail, urgency, reporter_id, reporter_name, worker_id, worker_name,
    status, due_at, checklist)
  values (incident, facility, zone, 'Shared test facility', 'Plumbing', 'Test corrective reservation',
    'Plumbing repair for the shared scheduling test.', 'Ground floor', 'High', reporter,
    'Maintenance Test Reporter', technician, 'Maintenance Test Technician', 'assigned', release_at, '{}');
  insert into maintenance_api.corrective_notification(incident_id, recipient_id, title, incident_title)
  values (incident, technician, 'Test assignment', 'Shared maintenance test') returning id into notification;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', manager::text, true);
  assignment := public.add_worker_skill(technician, 'Maintenance test ' || zone);
  assert public.add_worker_skill(technician, 'Maintenance test ' || zone) = assignment,
    'Adding the same worker skill should be idempotent.';
  select s.skill_id into strict required_skill from maintenance_api.worker_skill s where s.worker_skill_id = assignment;
  insert into maintenance_api.worker_certification(worker_id, certification_name, verified)
    values (technician, 'Test certificate', true);
  insert into maintenance_api.worker_availability(worker_id, availability, shift_start, shift_end, availability_status, leave_status)
    values (technician, 'Scheduled', original_start - interval '2 hours', release_at + interval '3 hours', 'Available', 'None');
  insert into maintenance_api.preventive_task_definition(title, instructions, category, zone_id, required_job_role, required_skill_id, checklist)
    values ('Inspect valves', 'Inspect the isolation valves.', 'Plumbing', zone, 'Plumber', required_skill, array['Check valve'])
    returning id into template;

  draft := public.review_preventive_range(array[facility], template, 'daily', work_date, work_date, array[time '10:00'], 30);
  assert (draft->'rows'->0->>'worker_id')::uuid = technician, 'Scheduler did not use the shared worker, skill and shift.';
  assert (draft->'rows'->0->>'starts')::timestamptz = release_at, 'Scheduler draft overlaps a Corrective reservation.';
  assert public.review_preventive_range(array[facility], template, 'daily', work_date, work_date,
    array[time '10:00'], 30, draft->'rows', draft->'warnings') = '1'::jsonb, 'Schedule approval did not create one work order.';

  select o.* into strict task from maintenance_api.preventive_work_order o
    join maintenance_api.preventive_task_plan p on p.id = o.plan_id where p.task_definition_id = template;
  assert task.scheduled_for = release_at;
  assert (select d.id = template from maintenance_api.preventive_task_plan p
    cross join lateral maintenance_api.preventive_task_definition(p) d where p.id = task.plan_id);
  assert (select t.facility_id = facility from maintenance_api.preventive_work_order_target(task) t);
  assert (select maintenance_api.preventive_facility_is_active(f)
    from maintenance_api.preventive_facility f where f.id = facility);
  perform set_config('role', 'none', true);
  begin
    update public.preventive_work_order set scheduled_for = original_start, due_at = release_at where id = task.id;
    raise exception 'Preventive work was allowed to overlap a Corrective reservation.';
  exception when raise_exception then
    if sqlerrm <> 'This preventive work conflicts with an active corrective assignment. Choose a later slot or another worker.' then
      raise;
    end if;
  end;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', reporter::text, true);
  assert public.mark_corrective_notification_read(notification) is null, 'A reporter can mark another user''s alert.';
  assert not exists (select 1 from public.preventive_work_order where id = task.id);
  assert not exists (select 1 from maintenance_api.preventive_work_order_target(task));

  perform set_config('request.jwt.claim.sub', technician::text, true);
  assert (select count(*) = 1 from maintenance_api.worker_profile w
    cross join lateral maintenance_api.worker_skill(w) ws cross join lateral maintenance_api.skill(ws) s
    where w.worker_id = technician and s.skill_id = required_skill);
  assert (select count(*) = 1 from maintenance_api.worker_profile w
    cross join lateral maintenance_api.worker_certification(w) c where w.worker_id = technician and c.verified);
  assert (select count(*) = 1 from maintenance_api.worker_profile w
    cross join lateral maintenance_api.worker_availability(w) a where w.worker_id = technician);
  read_at := public.mark_corrective_notification_read(notification);
  assert read_at is not null and public.mark_corrective_notification_read(notification) = read_at;
  assert public.worker_work_order_action(task.id, 'start') = 'in_progress';
  assert public.worker_work_order_action(task.id, 'check', 0, true) = 'in_progress';

  picture := technician || '/' || task.id || '/camera-' || replace(gen_random_uuid()::text, '-', '') || '.jpg';
  insert into storage.objects(bucket_id, name, owner_id) values ('preventive-work-evidence', picture, technician::text);
  assert public.preventive_campus_action(task.id, 'camera', 3.2162, 101.7298, 12, now(), picture) = 'in_progress';
  assert public.preventive_campus_action(task.id, 'camera', 3.2162, 101.7298, 12, now(), picture) = 'in_progress';
  assert (select count(*) = 1 from maintenance_api.preventive_work_evidence(task) e where e.path = picture);
  assert public.preventive_campus_action(task.id, 'submit', 3.2162, 101.7298, 12, now(),
    notes => 'Valves inspected') = 'submitted';

  perform set_config('request.jwt.claim.sub', manager::text, true);
  assert public.review_work_submission(task.id, false, 'Check the isolation valve again.') = 'in_progress';
  perform set_config('request.jwt.claim.sub', technician::text, true);
  assert public.preventive_campus_action(task.id, 'submit', 3.2162, 101.7298, 12, now(),
    notes => 'Valves inspected again') = 'submitted';
  perform set_config('request.jwt.claim.sub', manager::text, true);
  assert public.review_work_submission(task.id, true) = 'completed';
  assert public.review_work_submission(task.id, true) = 'completed';
  update maintenance_api.preventive_work_completion set actual_minutes = 26 where work_order_id = task.id;
  assert (select o.status = 'completed' from maintenance_api.preventive_work_order o where o.id = task.id);
  assert (select c.actual_minutes = 26 and c.photo_path = picture and c.notes = 'Valves inspected again'
    from maintenance_api.preventive_work_completion(task) c);
  perform set_config('role', 'none', true);
end;
$$;

rollback;

select count(*) filter (where table_schema = 'public')::int as public_table_editor_entries,
  count(*)::int as core_maintenance_tables, count(*) = 15 as shared_workflow_verified
from information_schema.tables
where table_schema in ('public', 'uni360_data') and table_type = 'BASE TABLE';
