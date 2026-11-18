-- Change the worker email below and run the entire query.
with
worker as (
  select a.user_id, a.full_name
  from public.account a
  join auth.users u on u.id = a.user_id
  join public.worker_profile p on p.worker_id = a.user_id
  where lower(u.email) = lower('worker@uni360.example')
    and a.role = 'worker' and a.is_active
  order by a.user_id limit 1
),
reporter as (
  select user_id, full_name from public.account
  where is_active and role in ('administrator', 'super_administrator')
  order by (role = 'super_administrator') desc, user_id limit 1
),
facility as (
  select f.id, scope.zone_id, uni360_private.preventive_facility_path(f.id) as path
  from public.preventive_facility f
  join uni360_private.facility_access_scope scope on scope.facility_id = f.id
  where uni360_private.preventive_facility_active(f.id)
  order by exists (
    select 1 from maintenance_api.corrective_site s where s.facility_id = f.id
  ) desc, f.name, f.id limit 1
),
examples(n, title, category, location) as (values
  (1, 'Wet floor at entrance', 'Cleaning', 'Main entrance'),
  (2, 'Overflowing waste bin', 'Cleaning', 'Common area'),
  (3, 'Mud tracked into corridor', 'Cleaning', 'Main corridor'),
  (4, 'Spilled drink near stairs', 'Cleaning', 'Stair landing'),
  (5, 'Dirty handrails by exit', 'Cleaning', 'Exit stairwell'),
  (6, 'Leaking tap', 'Plumbing', 'Wash basin'),
  (7, 'Flickering corridor light', 'Electrical', 'Main corridor'),
  (8, 'Loose chair leg', 'Furniture', 'Seating area'),
  (9, 'Door fails to latch', 'Building', 'Side entrance'),
  (10, 'Air conditioner blows warm air', 'Air conditioning', 'Indoor common area')
),
cases as (
  select e.*, md5('uni360-corrective-mobile-demo-v1:' || w.user_id || ':' || e.n)::uuid as id
  from examples e cross join worker w
),
added as (
  insert into public.corrective_incident (
    id, facility_id, zone_id, facility_name, category, title, description,
    location_detail, urgency, reporter_id, reporter_name, worker_id, worker_name,
    status, approved_at, checklist
  )
  select e.id, f.id, f.zone_id, f.path, c.name, '[Demo] ' || e.title,
    'Demo incident for practice. Issue reported: ' || e.title || '.', e.location, 'Medium',
    case when e.n <= 5 then a.user_id else w.user_id end,
    case when e.n <= 5 then a.full_name else w.full_name end,
    case when e.n <= 5 then w.user_id end,
    case when e.n <= 5 then w.full_name end,
    case when e.n <= 5 then 'assigned' else 'reported' end,
    case when e.n <= 5 then now() end,
    array['Inspect the area', 'Complete the repair', 'Verify the result']
  from cases e cross join worker w cross join reporter a cross join facility f
  cross join lateral (
    select name from maintenance_api.corrective_category where active
    order by (name = e.category) desc, (name = 'Other') desc, name limit 1
  ) c
  on conflict (id) do nothing
  returning id, title, reporter_id, reporter_name, worker_id
),
history as (
  insert into maintenance_api.corrective_event (incident_id, actor_id, actor_name, event)
  select id, reporter_id, reporter_name,
    case when worker_id is null then 'Reported' else 'Assigned' end
  from added
),
notifications as (
  insert into maintenance_api.corrective_notification (recipient_id, incident_id, title, incident_title)
  select worker_id, id, '[Demo] Assigned', title from added where worker_id is not null
  returning incident_id
),
visible_cases as (
  select reporter_id, worker_id from added
  union all
  select i.reporter_id, i.worker_id from public.corrective_incident i join cases e on e.id = i.id
)
select
  case
    when not exists (select 1 from worker) then 'No active worker found for that email'
    when not exists (select 1 from reporter) then 'No active administrator found'
    when not exists (select 1 from facility) then 'No active campus facility with an access zone found'
    when not exists (select 1 from maintenance_api.corrective_category where active)
      then 'No active corrective category found'
    else 'Demo records ready'
  end as result,
  (select count(*) from visible_cases where worker_id = (select user_id from worker)) as assigned,
  (select count(*) from visible_cases where reporter_id = (select user_id from worker)) as my_reports,
  (select count(*) from notifications) + (
    select count(*) from maintenance_api.corrective_notification n join cases e on e.id = n.incident_id
    where n.recipient_id = (select user_id from worker) and n.title = '[Demo] Assigned'
  ) as updates;
