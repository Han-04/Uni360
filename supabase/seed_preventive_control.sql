-- Demo data. Run after all migrations and demo account setup.
begin;

insert into public.preventive_zone (id, name) values
  ('36000000-0000-4000-8000-000000000001', 'Engineering Block'),
  ('36000000-0000-4000-8000-000000000002', 'Residential Campus')
on conflict (id) do nothing;

do $$
declare
  demo_admin uuid;
begin
  select a.user_id into strict demo_admin
  from public.account a join auth.users u on u.id = a.user_id
  where a.role = 'administrator' and a.is_active and u.email = 'admin@uni360.example';

  insert into maintenance_api.preventive_zone_admin (zone_id, administrator_id)
    values ('36000000-0000-4000-8000-000000000001', demo_admin)
    on conflict do nothing;
end;
$$;

insert into uni360_private.facility_access_scope (facility_id, zone_id)
values ('36000000-0000-4000-8000-000000000016', '36000000-0000-4000-8000-000000000002')
on conflict (facility_id) do nothing;

insert into public.preventive_facility (id, parent_id, name, facility_type, metadata) values
  ('36000000-0000-4000-8000-000000000016', null, 'Hostel Courtyard', 'outdoor_area', '{}')
on conflict (id) do nothing;

insert into maintenance_api.preventive_task_definition
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
  ('36000000-0000-4000-8000-000000000033', '36000000-0000-4000-8000-000000000023',
    null, null, 'Monthly Campus Mosquito Control')
on conflict (id) do nothing;

insert into maintenance_api.preventive_campaign_target (plan_id, facility_id) values
  ('36000000-0000-4000-8000-000000000033', '36000000-0000-4000-8000-000000000016')
on conflict do nothing;

insert into public.preventive_schedule (id, plan_id, frequency, starts_on, local_time) values
  ('36000000-0000-4000-8000-000000000044', '36000000-0000-4000-8000-000000000033', 'monthly', '2026-11-16', '09:00')
on conflict (id) do nothing;

insert into public.preventive_work_order (id, schedule_id, scheduled_for, due_at)
select '36000000-0000-4000-8000-000000000055', s.id,
  '2026-11-16 09:00+08'::timestamptz, '2026-11-16 11:00+08'::timestamptz
from public.preventive_schedule s
join public.preventive_task_plan p on p.id = s.plan_id and p.is_active
join maintenance_api.preventive_task_definition d on d.id = p.task_definition_id and d.is_active
where s.id = '36000000-0000-4000-8000-000000000044' and s.is_active
  and not exists (
    select 1 from public.preventive_work_order where id = '36000000-0000-4000-8000-000000000055'
  )
  and not exists (
    select 1 from maintenance_api.preventive_campaign_target t
    where t.plan_id = p.id and not uni360_private.preventive_facility_active(t.facility_id)
  )
on conflict (id) do nothing;

commit;
