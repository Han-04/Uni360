-- Demo data. Run after the preventive control migration and demo account setup.
begin;

insert into public.preventive_zone (id, name) values
  ('36000000-0000-4000-8000-000000000001', 'Engineering Block'),
  ('36000000-0000-4000-8000-000000000002', 'Residential Campus')
on conflict (id) do nothing;

do $$
declare
  demo_admin uuid;
  demo_worker uuid;
begin
  select a.user_id into strict demo_admin
  from public.account a join auth.users u on u.id = a.user_id
  where a.role = 'administrator' and a.is_active and u.email = 'admin@uni360.example';
  select a.user_id into strict demo_worker
  from public.account a join auth.users u on u.id = a.user_id
  where a.role = 'worker' and a.is_active and a.employee_id = 'EMP-2026-001' and u.email = 'worker@uni360.example';
  perform 1 from public.worker_profile where worker_id = demo_worker;
  if not found then raise exception 'The demo worker must have a workforce profile.'; end if;

  insert into public.preventive_zone_admin (zone_id, administrator_id)
    values ('36000000-0000-4000-8000-000000000001', demo_admin)
    on conflict do nothing;
end;
$$;

insert into public.preventive_facility (id, zone_id, parent_id, name, facility_type, metadata) values
  ('36000000-0000-4000-8000-000000000011', '36000000-0000-4000-8000-000000000001', null, 'Block K', 'building', '{"floors": 3}'),
  ('36000000-0000-4000-8000-000000000012', '36000000-0000-4000-8000-000000000001', '36000000-0000-4000-8000-000000000011', 'Ground Floor', 'floor', '{}'),
  ('36000000-0000-4000-8000-000000000013', '36000000-0000-4000-8000-000000000001', '36000000-0000-4000-8000-000000000012', 'Ground Floor Toilet', 'room', '{"fixtures": 6}'),
  ('36000000-0000-4000-8000-000000000014', '36000000-0000-4000-8000-000000000001', '36000000-0000-4000-8000-000000000012', 'Gym Room', 'room', '{}'),
  ('36000000-0000-4000-8000-000000000015', '36000000-0000-4000-8000-000000000001', null, 'Block K Garden', 'outdoor_area', '{}'),
  ('36000000-0000-4000-8000-000000000016', '36000000-0000-4000-8000-000000000002', null, 'Hostel Courtyard', 'outdoor_area', '{}')
on conflict (id) do nothing;

insert into public.preventive_task_definition
  (id, title, instructions, category, required_job_role, required_skill_id, checklist)
values
  ('36000000-0000-4000-8000-000000000021', 'Toilet Cleaning',
    'Clean the fixtures and floor, replenish supplies, and report any faults.', 'Cleaning', 'Cleaner', null,
    array['Clean fixtures', 'Mop floor', 'Refill soap and paper']),
  ('36000000-0000-4000-8000-000000000022', 'Facility Safety Inspection',
    'Walk through the room and record visible defects for follow-up.', 'Inspection', 'Facilities Maintenance Technician',
    (select skill_id from public.skill where lower(btrim(skill_name)) = 'preventive inspection'),
    array['Check lighting', 'Check exit access', 'Record defects']),
  ('36000000-0000-4000-8000-000000000023', 'Mosquito Control Site Check',
    'Inspect the assigned outdoor sites and record locations requiring follow-up.', 'Pest Control', 'Pest Control Technician', null,
    array['Check for standing water', 'Record affected locations', 'Submit site notes'])
on conflict (id) do nothing;

insert into public.preventive_task_plan (id, task_definition_id, facility_id, zone_id, campaign_name) values
  ('36000000-0000-4000-8000-000000000031', '36000000-0000-4000-8000-000000000021',
    '36000000-0000-4000-8000-000000000013', '36000000-0000-4000-8000-000000000001', null),
  ('36000000-0000-4000-8000-000000000032', '36000000-0000-4000-8000-000000000022',
    '36000000-0000-4000-8000-000000000014', '36000000-0000-4000-8000-000000000001', null),
  ('36000000-0000-4000-8000-000000000033', '36000000-0000-4000-8000-000000000023',
    null, null, 'Monthly Campus Mosquito Control')
on conflict (id) do nothing;

insert into public.preventive_campaign_target (plan_id, facility_id) values
  ('36000000-0000-4000-8000-000000000033', '36000000-0000-4000-8000-000000000015'),
  ('36000000-0000-4000-8000-000000000033', '36000000-0000-4000-8000-000000000016')
on conflict do nothing;

insert into public.preventive_schedule (id, plan_id, frequency, starts_on, local_time) values
  ('36000000-0000-4000-8000-000000000041', '36000000-0000-4000-8000-000000000031', 'daily', '2026-11-12', '08:00'),
  ('36000000-0000-4000-8000-000000000042', '36000000-0000-4000-8000-000000000031', 'daily', '2026-11-12', '15:00'),
  ('36000000-0000-4000-8000-000000000043', '36000000-0000-4000-8000-000000000032', 'weekly', '2026-11-05', '10:00'),
  ('36000000-0000-4000-8000-000000000044', '36000000-0000-4000-8000-000000000033', 'monthly', '2026-11-16', '09:00')
on conflict (id) do nothing;

insert into public.preventive_work_order (id, schedule_id, worker_id, scheduled_for, due_at)
select sample.id, sample.schedule_id, worker.user_id, sample.scheduled_for, sample.due_at
from (values
  ('36000000-0000-4000-8000-000000000051'::uuid, '36000000-0000-4000-8000-000000000041'::uuid, false, '2026-11-12 08:00+08'::timestamptz, '2026-11-12 09:00+08'::timestamptz),
  ('36000000-0000-4000-8000-000000000052', '36000000-0000-4000-8000-000000000042', false, '2026-11-12 15:00+08', '2026-11-12 16:00+08'),
  ('36000000-0000-4000-8000-000000000053', '36000000-0000-4000-8000-000000000043', true, '2026-11-12 10:00+08', '2026-11-12 11:00+08'),
  ('36000000-0000-4000-8000-000000000054', '36000000-0000-4000-8000-000000000043', true, '2026-11-05 10:00+08', '2026-11-05 11:00+08'),
  ('36000000-0000-4000-8000-000000000055', '36000000-0000-4000-8000-000000000044', false, '2026-11-16 09:00+08', '2026-11-16 11:00+08')
) sample(id, schedule_id, assigned, scheduled_for, due_at)
left join public.account worker on sample.assigned and worker.employee_id = 'EMP-2026-001'
on conflict (id) do nothing;

insert into public.preventive_work_completion (work_order_id, worker_id, completed_at, notes)
select id, worker_id, '2026-11-05 10:35+08', 'Demo inspection complete. Lighting and exit access were clear.'
from public.preventive_work_order where id = '36000000-0000-4000-8000-000000000054'
  and worker_id = (select user_id from public.account where employee_id = 'EMP-2026-001')
  and cancelled_at is null
on conflict (work_order_id) do nothing;

commit;
