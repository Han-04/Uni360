begin;
set local plpgsql.check_asserts = on;

do $test$
declare
  zone uuid := gen_random_uuid();
  facility uuid := gen_random_uuid();
  inactive_building uuid := gen_random_uuid();
  inactive_floor uuid := gen_random_uuid();
  active_floor_in_inactive_building uuid := gen_random_uuid();
  reporter uuid := gen_random_uuid();
  worker uuid := gen_random_uuid();
  administrator uuid := gen_random_uuid();
  administrator_report uuid := gen_random_uuid();
  routine_id uuid := gen_random_uuid();
  hazard_id uuid := gen_random_uuid();
  video_id uuid := gen_random_uuid();
  duplicate_id uuid := gen_random_uuid();
  fallback_id uuid := gen_random_uuid();
  photo_only_id uuid := gen_random_uuid();
  normal_photo_id uuid := gen_random_uuid();
  video_path text := reporter || '/' || video_id || '/report/' || gen_random_uuid() || '.mp4';
  routine_path text := reporter || '/' || routine_id || '/report/' || gen_random_uuid() || '.jpg';
  hazard_path text := reporter || '/' || hazard_id || '/report/' || gen_random_uuid() || '.jpg';
  duplicate_path text := reporter || '/' || duplicate_id || '/report/' || gen_random_uuid() || '.jpg';
  fallback_path text := reporter || '/' || fallback_id || '/report/' || gen_random_uuid() || '.jpg';
  photo_only_path text := reporter || '/' || photo_only_id || '/report/' || gen_random_uuid() || '.jpg';
  replacement_path text := reporter || '/' || photo_only_id || '/report/' || gen_random_uuid() || '.jpg';
  normal_photo_path text := reporter || '/' || normal_photo_id || '/report/' || gen_random_uuid() || '.jpg';
  payload jsonb := jsonb_build_object('facility_id', facility, 'location_detail', 'Desk by the entrance');
  catalog_facilities jsonb;
begin
  insert into auth.users(id, aud, role, email)
  select id, 'authenticated', 'authenticated', id || '@corrective-test.invalid'
  from unnest(array[reporter, worker, administrator]) as fixture(id);
  insert into public.account(user_id, employee_id, full_name, role) values
    (reporter, upper(reporter::text), 'Intake Test Reporter', 'reporter'),
    (worker, upper(worker::text), 'Intake Test Furniture Worker', 'worker'),
    (administrator, upper(administrator::text), 'Intake Test Administrator', 'super_administrator');
  insert into public.preventive_zone(id, name) values (zone, 'Intake test ' || zone);
  insert into uni360_private.facility_access_scope(facility_id, zone_id)
  select fixture, zone
  from unnest(array[facility, inactive_building, inactive_floor, active_floor_in_inactive_building]) as fixture;
  insert into public.preventive_facility(id, name, facility_type, parent_id, is_active) values
    (facility, 'Intake test facility', 'building', null, true),
    (inactive_building, 'Retired test building', 'building', null, false),
    (inactive_floor, 'Retired test floor', 'floor', facility, false),
    (active_floor_in_inactive_building, 'Test floor in retired building', 'floor', inactive_building, true);
  insert into maintenance_api.corrective_site(facility_id, latitude, longitude, radius_m)
  values (facility, 3.215, 101.728, 60);
  update maintenance_api.corrective_category set worker_role = 'intake test carpenter' where name = 'Furniture';
  update public.worker_profile set job_role = 'intake test carpenter', employment_status = 'active'
  where worker_id = worker;
  insert into maintenance_api.worker_availability(worker_id, availability, shift_start, shift_end, availability_status, leave_status)
  values (worker, 'Scheduled', now() - interval '30 minutes', now() + interval '3 hours', 'Available', 'None');

  insert into storage.objects(bucket_id, name, owner_id)
  select 'corrective-evidence', path, reporter::text
  from unnest(array[routine_path, hazard_path, video_path, duplicate_path, fallback_path, photo_only_path, replacement_path, normal_photo_path]) as fixture(path);

  perform set_config('role', 'service_role', true);
  assert (public.corrective_media_receipt(routine_path, reporter)->>'state') = 'claimed';
  assert (public.corrective_media_receipt(routine_path, reporter,
    '{"kind":"photo","vision_status":"vision_fault","priority":"Medium","category":"Furniture","model":"nvidia/nemotron-3.5-super-vl:free","observation":"Loose joint on a chair"}')->>'state') = 'complete';
  assert (public.corrective_media_receipt(hazard_path, reporter)->>'state') = 'claimed';
  assert (public.corrective_media_receipt(hazard_path, reporter,
    '{"kind":"photo","vision_status":"clear","priority":"Critical","category":"Electrical","model":"fixture","observation":"Visible damage and sparks"}')->>'state') = 'complete';
  assert (public.corrective_media_receipt(duplicate_path, reporter)->>'state') = 'claimed';
  assert (public.corrective_media_receipt(duplicate_path, reporter,
    '{"kind":"photo","vision_status":"clear","priority":"Low","category":"Furniture","model":"fixture"}')->>'state') = 'complete';
  assert (public.corrective_media_receipt(fallback_path, reporter)->>'state') = 'claimed';
  assert (public.corrective_media_receipt(fallback_path, reporter,
    '{"kind":"photo","vision_status":"not_configured"}')->>'state') = 'complete';
  assert (public.corrective_media_receipt(photo_only_path, reporter)->>'state') = 'claimed';
  assert (public.corrective_media_receipt(photo_only_path, reporter,
    '{"kind":"photo","vision_status":"skipped"}')->>'state') = 'complete';
  assert (public.corrective_media_receipt(photo_only_path, reporter)->>'state') = 'claimed';
  assert (public.corrective_media_receipt(photo_only_path, reporter)->>'state') = 'busy';
  assert (public.corrective_media_receipt(photo_only_path, reporter,
    '{"kind":"photo","vision_status":"vision_fault","priority":"Medium","category":"Plumbing","model":"nvidia/nemotron-3.5-super-vl:free","observation":"Possible visible leak from sink plumbing."}')->>'state') = 'complete';
  assert (public.corrective_media_receipt(photo_only_path, reporter)->>'state') = 'complete';
  assert (public.corrective_media_receipt(replacement_path, reporter)->>'state') = 'claimed';
  assert (public.corrective_media_receipt(replacement_path, reporter,
    '{"kind":"photo","vision_status":"normal","observation":"No obvious visible fault in the photo."}')->>'state') = 'complete';
  assert (public.corrective_media_receipt(normal_photo_path, reporter)->>'state') = 'claimed';
  assert (public.corrective_media_receipt(normal_photo_path, reporter,
    '{"kind":"photo","vision_status":"normal","model":"nvidia/nemotron-3.5-super-vl:free"}')->>'state') = 'complete';

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', reporter::text, true);
  catalog_facilities := public.corrective_catalog()->'facilities';
  assert exists (select 1 from jsonb_array_elements(catalog_facilities) entry
    where entry->>'id' = facility::text), 'The active facility is missing from the reporter catalog.';
  assert not exists (select 1 from jsonb_array_elements(catalog_facilities) entry
    where entry->>'id' in (inactive_building::text, inactive_floor::text, active_floor_in_inactive_building::text)),
    'The reporter catalog included a retired facility or a child of one.';

  assert public.corrective_report(payload || jsonb_build_object(
    'id', routine_id, 'photo', routine_path, 'urgency', 'Critical',
    'title', 'Chair has a loose joint', 'description', 'The chair frame has a loose joint and needs a minor repair.'
  )) = routine_id;
  assert exists (select 1 from public.corrective_incident i
    where i.id = routine_id and i.status = 'assigned' and i.worker_id = worker
      and i.category = 'Furniture' and i.urgency in ('Low','Medium')
      and i.triage->>'routing_mode' = 'automatic'), 'Routine report did not auto-assign.';
  assert exists (select 1 from maintenance_api.corrective_notification n
    where n.incident_id = routine_id and n.title = 'Assigned'), 'Reporter did not receive the assignment update.';

  perform public.corrective_report(payload || jsonb_build_object(
    'id', duplicate_id, 'photo', duplicate_path,
    'title', 'Chair has a loose joint', 'description', 'The chair frame has a loose joint and needs a minor repair.'
  ));
  assert exists (select 1 from public.corrective_incident i
    where i.id = duplicate_id and i.status = 'reported'
      and i.triage->>'routing_reason' = 'A similar open report exists at this facility.'), 'A duplicate bypassed review.';

  perform public.corrective_report(payload || jsonb_build_object(
    'id', hazard_id, 'photo', hazard_path, 'urgency', 'Low',
    'title', 'Outlet cover looks damaged', 'description', 'There appears to be damage around the outlet.'
  ));
  assert exists (select 1 from public.corrective_incident i
    where i.id = hazard_id and i.status = 'reported' and i.worker_id is null
      and i.category = 'Electrical' and i.urgency = 'Critical'), 'Vision hazard was not routed for review.';

  perform public.corrective_report(payload || jsonb_build_object(
    'id', photo_only_id, 'photo', photo_only_path, 'location_detail', 'Lower washroom',
    'title', 'Please inspect the fixture', 'description', 'Please see the attached picture at this location.'
  ));
  assert exists (select 1 from public.corrective_incident i
    where i.id = photo_only_id and i.status = 'reported' and i.worker_id is null
      and i.category = 'Plumbing' and i.urgency = 'Medium'
      and i.triage->>'vision_status' = 'vision_fault'
      and i.triage->>'photo_category' = 'Plumbing' and i.triage->>'photo_priority' = 'Medium'
      and i.triage->>'observation' = 'Possible visible leak from sink plumbing.'
      and i.description = 'Please see the attached picture at this location.'),
    'Report fields and the photo assessment should be stored independently.';

  perform set_config('request.jwt.claim.sub', worker::text, true);
  begin
    perform public.corrective_reporter(photo_only_id, 'edit', '{"title":"Worker edit"}');
    raise exception 'A worker edited another reporter''s incident.';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claim.sub', administrator::text, true);
  begin
    perform public.corrective_reporter(photo_only_id, 'edit', '{"title":"Administrator edit"}');
    raise exception 'An administrator edited another reporter''s incident.';
  exception when insufficient_privilege then null;
  end;
  assert public.corrective_report(payload || jsonb_build_object(
    'id', administrator_report, 'title', 'Inspect a campus fixture',
    'description', 'The fixture needs a closer inspection by staff.'
  )) = administrator_report;
  perform public.corrective_reporter(administrator_report, 'edit', jsonb_build_object(
    'title', 'Inspect the campus fixture again', 'description', 'Staff should inspect the fixture from both sides.',
    'location_detail', 'Entrance'
  ));
  assert exists (select 1 from public.corrective_incident i where i.id = administrator_report
    and i.reporter_id = administrator and i.report_photo is null and i.title = 'Inspect the campus fixture again'),
    'An administrator should be able to edit their own pending report without a photo.';
  perform set_config('request.jwt.claim.sub', reporter::text, true);
  perform public.corrective_reporter(photo_only_id, 'edit', jsonb_build_object(
    'title', 'Please inspect the sink fixture', 'description', 'The photo shows the fixture before any repair.',
    'location_detail', 'Lower washroom'
  ));
  assert exists (select 1 from public.corrective_incident i
    where i.id = photo_only_id and i.title = 'Please inspect the sink fixture'
      and i.report_photo = photo_only_path and i.triage->>'photo_category' = 'Plumbing'),
    'The owner could not edit the report while retaining the photo and its finding.';
  perform public.corrective_reporter(photo_only_id, 'edit', jsonb_build_object(
    'title', 'Please inspect the sink fixture', 'description', 'The replacement shows the same fixture from farther away.',
    'location_detail', 'Lower washroom', 'photo', replacement_path
  ));
  assert exists (select 1 from public.corrective_incident i
    where i.id = photo_only_id and i.report_photo = replacement_path
      and photo_only_path = any(i.prior_report_photos) and i.triage->>'vision_status' = 'normal'
      and i.triage->>'photo_category' is null),
    'The replacement should update the finding while retaining the original attachment.';
  assert exists (select 1 from storage.objects o
    where o.bucket_id = 'corrective-evidence' and o.name = photo_only_path),
    'The owner should be able to open the original attachment.';

  perform public.corrective_report(payload || jsonb_build_object(
    'id', normal_photo_id, 'photo', normal_photo_path, 'location_detail', 'Upper washroom',
    'title', 'Smoke near the wall outlet', 'description', 'The fault is intermittent and smoke appeared earlier.'
  ));
  assert exists (select 1 from public.corrective_incident i
    where i.id = normal_photo_id and i.status = 'reported' and i.urgency = 'Critical'
      and i.triage->>'vision_status' = 'normal'), 'A normal photograph cannot lower a reported hazard.';

  perform public.corrective_report(payload || jsonb_build_object(
    'id', fallback_id, 'photo', fallback_path, 'location_detail', 'Chair by the window',
    'title', 'Broken chair seat and loose leg',
    'description', 'The chair seat is loose and the broken chair leg needs a minor repair.'
  ));
  assert exists (select 1 from public.corrective_incident i
    where i.id = fallback_id and i.status = 'escalated' and i.worker_id is null
      and i.category = 'Furniture' and i.triage->>'vision_status' = 'not_configured'),
    'Text fallback should escalate when the only eligible worker is already assigned.';

  begin
    perform public.corrective_report(payload || jsonb_build_object(
      'id', video_id, 'photo', video_path, 'title', 'Video report evidence',
      'description', 'Attached a video showing an issue near a different door.'
    ));
    raise exception 'An unchecked video was accepted.' using errcode = 'XX000';
  exception when raise_exception then
    if sqlerrm not like '%could not be verified%' then raise; end if;
  end;
  perform set_config('role', 'service_role', true);
  assert (public.corrective_media_receipt(video_path, reporter)->>'state') = 'claimed';
  assert (public.corrective_media_receipt(video_path, reporter, '{"kind":"video"}')->>'state') = 'complete';
  perform set_config('role', 'authenticated', true);
  perform public.corrective_report(payload || jsonb_build_object(
    'id', video_id, 'photo', video_path, 'title', 'Video report evidence',
    'description', 'Attached a video showing an issue near a different door.'
  ));
  assert exists (select 1 from public.corrective_incident i where i.id = video_id
    and i.report_photo = video_path and i.triage->>'media_kind' = 'video');
end;
$test$;

select 'Smart intake checks passed' as result;
rollback;
