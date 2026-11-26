-- Run on the Uni360 demonstration project. All records have stable IDs and
-- are labelled [Demo]. Pass the email of an administrator with facility access.
do $demo$
declare
  admin_email constant text := 'admin@uni360.example';
  demo_key constant text := 'uni360-corrective-admin-demo-v1';
  checklist constant text[] := array['Inspect the fault', 'Complete the repair', 'Check the result'];
  admin public.account%rowtype;
  technician public.account%rowtype;
  fixture record;
  facility record;
  category_name text;
  case_id uuid;
  reported_at timestamptz;
  has_worker boolean;
  completed boolean;
  event_name text;
  reporter_id uuid;
  reporter_name text;
  created_cases integer := 0;
begin
  perform pg_advisory_xact_lock(360, 2);

  select a.* into strict admin from public.account a
  join auth.users u on u.id = a.user_id
  where lower(u.email) = lower(admin_email) and a.is_active
    and a.role in ('administrator', 'super_administrator');

  -- Use the existing test login if available. Otherwise use a demo-only worker
  -- with no password or shifts, disabled for sign-in and automatic assignment.
  select a.* into technician from public.account a
  join auth.users u on u.id = a.user_id
  join public.worker_profile w on w.worker_id = a.user_id
  where u.email = 'worker@uni360.example' and a.role = 'worker' and a.is_active;
  if not found then
    insert into auth.users(id, aud, role, email)
    values (md5(demo_key || ':technician')::uuid, 'authenticated', 'authenticated',
            'corrective-demo-worker@uni360.example')
    on conflict (id) do nothing;
    insert into public.account(user_id, employee_id, full_name, role, is_active)
    values (md5(demo_key || ':technician')::uuid, 'DEMO-CM-01',
            'Demo Maintenance Worker', 'worker', false)
    on conflict (user_id) do nothing;
    select a.* into strict technician from public.account a
    join public.worker_profile w on w.worker_id = a.user_id
    where a.user_id = md5(demo_key || ':technician')::uuid
      and a.employee_id = 'DEMO-CM-01' and a.role = 'worker' and not a.is_active;
  end if;

  for fixture in select * from (values
    (1, 'reported', 'Medium', 'Plumbing', 'Tap dripping into wash basin', 'Wash basin'),
    (2, 'reported', 'High', 'Electrical', 'Light flickers above the corridor', 'Main corridor'),
    (3, 'reported', 'Medium', 'Furniture', 'Loose chair leg in study area', 'Study area'),
    (4, 'needs_info', 'Low', 'Cleaning', 'Rubbish left outside the door', 'Doorway'),
    (5, 'inspection', 'High', 'Building', 'Door fails to close securely', 'Side entrance'),
    (6, 'approved', 'Medium', 'Plumbing', 'Blocked washroom drain', 'Washroom'),
    (7, 'approved', 'Low', 'Furniture', 'Damaged shelf bracket', 'Storage corner'),
    (8, 'approved', 'Medium', 'Air conditioning', 'Air conditioner blowing warm air', 'Teaching area'),
    (9, 'escalated', 'High', 'Electrical', 'Lighting circuit needs a technician', 'Ground floor'),
    (10, 'external', 'High', 'Lift', 'Lift door sticks while opening', 'Lift landing'),
    (11, 'submitted', 'Medium', 'Cleaning', 'Mud tracked across the floor', 'Entrance'),
    (12, 'submitted', 'Low', 'Cleaning', 'Overflowing bin in the common area', 'Common area'),
    (13, 'submitted', 'Medium', 'Cleaning', 'Drink spilled near the stairs', 'Stair landing'),
    (14, 'submitted', 'Low', 'Cleaning', 'Handrails need cleaning', 'Exit stairwell'),
    (15, 'submitted', 'Medium', 'Cleaning', 'Small puddle from tracked rain', 'Main entrance'),
    (16, 'assigned', 'Medium', 'Cleaning', 'Wet tiles in the corridor', 'Corridor'),
    (17, 'assigned', 'Low', 'Cleaning', 'Waste bin needs emptying', 'Common area'),
    (18, 'assigned', 'Low', 'Cleaning', 'Dust on shared worktables', 'Worktables'),
    (19, 'assigned', 'Medium', 'Cleaning', 'Slippery floor outside a classroom', 'Classroom entrance'),
    (20, 'assigned', 'Low', 'Cleaning', 'Paper litter on the stair landing', 'Stair landing'),
    (21, 'resolved', 'Medium', 'Cleaning', 'Sticky residue on the entrance floor', 'Main entrance'),
    (22, 'resolved', 'Low', 'Cleaning', 'Dirty door handles', 'Side entrance'),
    (23, 'dismissed', 'Low', 'Other', 'Reporter withdrew a duplicate concern', 'Reception')
  ) as examples(n, status, priority, category, title, location)
  loop
    select f.id, s.zone_id, uni360_private.preventive_facility_path(f.id) as path
      into strict facility
    from public.preventive_facility f
    join uni360_private.facility_access_scope s on s.facility_id = f.id
    where uni360_private.preventive_facility_active(f.id)
      and (admin.role = 'super_administrator' or exists (
        select 1 from maintenance_api.preventive_zone_admin za
        where za.administrator_id = admin.user_id and za.zone_id = s.zone_id
      ))
    order by md5(f.id::text || fixture.n)
    limit 1;
    select c.name into strict category_name from maintenance_api.corrective_category c
    where c.active order by (c.name = fixture.category) desc, (c.name = 'Other') desc, c.name limit 1;

    case_id := md5(demo_key || ':' || admin.user_id || ':' || fixture.n)::uuid;
    reported_at := now() - fixture.n * interval '36 hours';
    completed := fixture.status in ('submitted', 'resolved');
    has_worker := completed or fixture.status = 'assigned';
    reporter_id := case when has_worker then admin.user_id else technician.user_id end;
    reporter_name := case when has_worker then admin.full_name else technician.full_name end;
    event_name := case fixture.status
      when 'reported' then 'Reported'
      when 'needs_info' then 'More information requested'
      when 'inspection' then 'Inspection requested'
      when 'approved' then 'Report approved'
      when 'escalated' then 'Escalated'
      when 'external' then 'External assistance required'
      when 'assigned' then 'Assigned'
      when 'submitted' then 'Evidence submitted'
      when 'resolved' then 'Work approved'
      when 'dismissed' then 'Report withdrawn'
    end;

    insert into public.corrective_incident (
      id, facility_id, zone_id, facility_name, category, title, description, location_detail,
      urgency, reporter_id, reporter_name, worker_id, worker_name, status, checklist,
      approved_at, created_at, updated_at, resolved_at, archived_at, withdrawn_at, triage
    ) values (
      case_id, facility.id, facility.zone_id, facility.path, category_name,
      '[Demo] ' || fixture.title, 'Supervisor demo. Sample report: ' || fixture.title || '.',
      fixture.location, fixture.priority, reporter_id, reporter_name,
      case when has_worker then technician.user_id end,
      case when has_worker then technician.full_name end,
      fixture.status, checklist,
      case when has_worker or fixture.status in ('approved', 'escalated', 'external')
        then reported_at + interval '20 minutes' end,
      reported_at, reported_at + interval '3 hours',
      case when fixture.status = 'resolved' then reported_at + interval '3 hours' end,
      case when fixture.n = 22 then reported_at + interval '3 hours' end,
      case when fixture.n = 23 then reported_at + interval '1 hour' end,
      jsonb_build_object('demo_seed', demo_key, 'demo_record', true)
    ) on conflict (id) do nothing;
    if not found then continue; end if;
    created_cases := created_cases + 1;

    if completed then
      insert into maintenance_api.corrective_visit (
        incident_id, attempt, worker_id, check_in_at, started_at, accuracy_m,
        distance_m, checklist_checked, notes, submitted_at
      ) values (
        case_id, 1, technician.user_id, reported_at + interval '1 hour',
        reported_at + interval '65 minutes', 10, 4, array[0, 1, 2],
        '[Demo] The area was cleaned and checked again. Sample completion notes only.',
        reported_at + interval '2 hours'
      );
    end if;

    insert into maintenance_api.corrective_event (
      incident_id, actor_id, actor_name, event, note, occurred_at
    ) values (
      case_id, reporter_id, reporter_name, 'Reported',
      'Sample incident for the supervisor demonstration.', reported_at
    );
    if fixture.status <> 'reported' then
      insert into maintenance_api.corrective_event (
        incident_id, actor_id, actor_name, event, note, occurred_at
      ) values (
        case_id,
        case when fixture.status = 'submitted' then technician.user_id
             when fixture.status = 'dismissed' then reporter_id else admin.user_id end,
        case when fixture.status = 'submitted' then technician.full_name
             when fixture.status = 'dismissed' then reporter_name else admin.full_name end,
        event_name, '[Demo] Sample workflow activity.', reported_at + interval '3 hours'
      );
    end if;
  end loop;
  raise notice '% corrective demo records added.', created_cases;
end;
$demo$;

select status, count(*) as demo_records
from public.corrective_incident
where triage->>'demo_seed' = 'uni360-corrective-admin-demo-v1'
group by status order by status;
