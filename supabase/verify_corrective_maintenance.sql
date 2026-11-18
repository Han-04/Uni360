-- Run on a development Supabase database after applying the corrective migration.
-- The fixture records are rolled back. This checks SQL and RLS, not device hardware.
begin;

set local plpgsql.check_asserts = on;

do $$
declare
  zone uuid := gen_random_uuid();
  facility uuid := gen_random_uuid();
  admin_id uuid := gen_random_uuid();
  fixture_worker uuid := gen_random_uuid();
  reporter_id uuid := gen_random_uuid();
  linked_reporter uuid := gen_random_uuid();
  incident uuid := gen_random_uuid();
  escalation uuid := gen_random_uuid();
  linked_case uuid := gen_random_uuid();
  withdrawn_case uuid := gen_random_uuid();
  token text;
  intake_photo text := reporter_id || '/' || incident || '/report/' || gen_random_uuid() || '.jpg';
  replacement_photo text := reporter_id || '/' || incident || '/report/' || gen_random_uuid() || '.jpg';
  escalation_photo text := reporter_id || '/' || escalation || '/report/' || gen_random_uuid() || '.jpg';
  linked_photo text := linked_reporter || '/' || linked_case || '/report/' || gen_random_uuid() || '.jpg';
  withdrawn_photo text := reporter_id || '/' || withdrawn_case || '/report/' || gen_random_uuid() || '.jpg';
  photograph text := fixture_worker || '/' || incident || '/work/' || gen_random_uuid() || '.jpg';
  report jsonb := jsonb_build_object('id', incident, 'facility_id', facility, 'category', 'Plumbing',
    'urgency', 'Critical', 'title', 'Verification burst pipe', 'location_detail', 'Ground floor',
    'description', 'Water is dripping from a leaking pipe under the sink.');
  check_in jsonb := '{"latitude":3.215,"longitude":101.728,"accuracy":8}'::jsonb;
begin
  insert into auth.users(id, aud, role, email)
  select id, 'authenticated', 'authenticated', id || '@corrective-test.invalid'
  from unnest(array[admin_id, fixture_worker, reporter_id, linked_reporter]) as fixture(id);

  insert into public.account(user_id, employee_id, full_name, role) values
    (admin_id, upper(admin_id::text), 'Corrective Test Admin', 'administrator'),
    (fixture_worker, upper(fixture_worker::text), 'Corrective Test Plumber', 'worker'),
    (reporter_id, upper(reporter_id::text), 'Corrective Test Reporter', 'reporter'),
    (linked_reporter, upper(linked_reporter::text), 'Corrective Linked Reporter', 'reporter');

  insert into public.preventive_zone(id, name) values (zone, 'Corrective test ' || zone);
  insert into maintenance_api.preventive_zone_admin(zone_id, administrator_id) values (zone, admin_id);
  insert into uni360_private.facility_access_scope(facility_id, zone_id) values (facility, zone);
  insert into public.preventive_facility(id, name, facility_type)
  values (facility, 'Verification facility', 'building');

  update public.worker_profile set job_role = 'Plumber',
    standby_status = true, employment_status = 'active' where worker_id = fixture_worker;
  insert into maintenance_api.worker_availability(worker_id, availability, shift_start, shift_end, availability_status, leave_status)
  values (fixture_worker, 'Scheduled', now() - interval '30 minutes', now() + interval '3 hours', 'Available', 'None');

  insert into storage.objects(bucket_id, name, owner_id) values
    ('corrective-evidence', intake_photo, reporter_id::text),
    ('corrective-evidence', replacement_photo, reporter_id::text),
    ('corrective-evidence', escalation_photo, reporter_id::text),
    ('corrective-evidence', linked_photo, linked_reporter::text),
    ('corrective-evidence', withdrawn_photo, reporter_id::text);

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  token := 'uni360:' || (public.corrective_configure_site(facility, '{
    "latitude":3.215,"longitude":101.728,"radius_m":60
  }'::jsonb)->>'qr_token');

  perform set_config('request.jwt.claim.sub', reporter_id::text, true);
  assert public.corrective_lookup_qr(token) = facility, 'The QR did not resolve to the shared facility.';
  begin
    perform public.corrective_report(report);
    raise exception 'The report was accepted without evidence.';
  exception when raise_exception then
    if sqlerrm <> 'Attach a photograph of the fault before submitting.' then raise; end if;
  end;
  report := report || jsonb_build_object('photo', intake_photo,
    'photo_diagnostics', '{"quality":"clear","fingerprint":"a5a5a5a5a5a5a5a5"}'::jsonb);
  assert public.corrective_report(report || jsonb_build_object('qr', token)) = incident, 'Report was not registered.';
  assert public.corrective_report(report) = incident, 'Report retries must be idempotent.';
  assert (select i.status = 'reported' and i.worker_id is null and i.location_method = 'qr'
    from public.corrective_incident i where i.id = incident), 'Report bypassed administrator review.';

  perform public.corrective_reporter(incident, 'edit', report || jsonb_build_object('photo', replacement_photo,
    'description', 'Water is dripping from a leaking pipe under the sink. The floor is wet.'));
  assert exists (select 1 from public.corrective_incident
    where id = incident and report_photo = replacement_photo and intake_photo = any(prior_report_photos)
      and triage->>'evidence_quality' = 'clear');
  perform public.corrective_report(report || jsonb_build_object('id', withdrawn_case, 'photo', withdrawn_photo));
  perform public.corrective_reporter(withdrawn_case, 'withdraw', '{}');
  assert exists (select 1 from public.corrective_incident
    where id = withdrawn_case and status = 'dismissed' and withdrawn_at is not null);
  perform public.corrective_report(report || jsonb_build_object('id', escalation, 'photo', escalation_photo, 'category', 'Other'));
  begin
    perform public.corrective_admin(incident, 'dismiss', '{"note":"Forbidden action"}');
    raise exception 'An ordinary worker was able to run an administrator action.';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  assert (public.corrective_admin_options(incident)->'triage'->>'category') = 'Plumbing', 'Text triage did not rank Plumbing first.';
  assert jsonb_array_length(public.corrective_admin_options(incident)->'duplicates') = 1, 'Same-facility duplicate was not found.';
  assert (public.corrective_admin_options(incident)->'duplicates'->0->>'photo_similarity')::integer = 100,
    'Similar photo evidence did not appear in duplicate review.';
  begin
    perform public.corrective_admin(incident, 'dispatch', '{}');
    raise exception 'Dispatch succeeded before approval.';
  exception when raise_exception then
    if sqlerrm <> 'Approve this report before assigning work.' then raise; end if;
  end;
  assert public.corrective_admin(incident, 'request_information', '{"note":"Which pipe?"}') = 'needs_info';
  perform set_config('request.jwt.claim.sub', reporter_id::text, true);
  perform public.corrective_reporter(incident, 'reply', '{"note":"The pipe underneath the sink."}');
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  assert public.corrective_admin(incident, 'review_approve', '{"category":"Plumbing","urgency":"High"}') = 'approved';
  assert public.corrective_admin(incident, 'dispatch', '{}') = 'assigned';
  assert (select i.worker_id = fixture_worker from public.corrective_incident i where i.id = incident);
  assert public.corrective_admin(escalation, 'review_approve', '{"category":"Other","urgency":"High"}') = 'approved';
  assert public.corrective_admin(escalation, 'dispatch', '{}') = 'escalated';

  perform set_config('request.jwt.claim.sub', linked_reporter::text, true);
  perform public.corrective_report(report || jsonb_build_object('id', linked_case, 'photo', linked_photo));
  assert not exists (select 1 from public.corrective_incident where id = incident),
    'A reporter could read another reporter''s source report.';
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  assert public.corrective_admin(linked_case, 'merge',
    jsonb_build_object('primary_id', incident, 'note', 'Same burst pipe')) = 'merged';

  perform set_config('request.jwt.claim.sub', fixture_worker::text, true);
  assert exists (select 1 from maintenance_api.corrective_notification
    where incident_id = incident and title = 'Assigned'), 'The worker did not receive an assignment alert.';
  assert not exists (select 1 from public.corrective_incident where id = escalation),
    'Another worker can read an unrelated incident.';
  assert public.corrective_worker(incident, 'acknowledge', '{}') = 'acknowledged';
  begin
    perform public.corrective_worker(incident, 'check_in', check_in || '{"qr":"wrong"}'::jsonb);
    raise exception 'The wrong facility QR was accepted.';
  exception when raise_exception then
    if sqlerrm <> 'This QR code does not match the assigned facility.' then raise; end if;
  end;
  begin
    perform public.corrective_worker(incident, 'check_in', check_in || jsonb_build_object('qr', token, 'latitude', 4));
    raise exception 'An out-of-bounds position was accepted.';
  exception when raise_exception then
    if sqlerrm <> 'You are outside the facility geofence.' then raise; end if;
  end;
  assert (public.corrective_location(incident, check_in)->>'distance_m')::numeric < 1;
  assert public.corrective_worker(incident, 'check_in', check_in || jsonb_build_object('qr', token)) = 'checked_in';
  assert public.corrective_worker(incident, 'start', '{}') = 'in_progress';
  assert public.corrective_worker(incident, 'draft', '{"notes":"Saved draft"}') = 'in_progress';
  assert exists (select 1 from maintenance_api.corrective_visit where incident_id = incident and notes = 'Saved draft');
  assert not exists (select 1 from maintenance_api.corrective_position where incident_id = incident),
    'A worker could read detailed GPS records.';
  perform public.corrective_worker(incident, 'checklist', '{"checked":[0,1,2]}');
  begin
    perform public.corrective_worker(incident, 'submit', '{"notes":"Verified by test","confirmed":true}');
    raise exception 'An assignment was submitted without a photograph.';
  exception when raise_exception then
    if sqlerrm <> 'Capture at least one completion photograph.' then raise; end if;
  end;

  -- The storage row stands in for a successful upload during this database-only check.
  perform set_config('role', 'none', true);
  insert into storage.objects(bucket_id, name, owner_id) values ('corrective-evidence', photograph, fixture_worker::text);
  perform set_config('role', 'authenticated', true);
  perform public.corrective_worker(incident, 'photo', jsonb_build_object('photo', photograph));
  assert public.corrective_worker(incident, 'submit', '{"notes":"Verified by test","confirmed":true}') = 'submitted';

  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  assert exists (select 1 from maintenance_api.corrective_position where incident_id = incident), 'Admin could not read check-in.';
  assert exists (select 1 from maintenance_api.corrective_notification
    where incident_id = escalation and title = 'Escalated'), 'The managed-zone admin did not receive escalation.';
  assert public.corrective_admin(incident, 'approve', '{"note":"Repair verified by test"}') = 'resolved';
  assert public.corrective_admin(incident, 'archive', '{"note":"Closed and retained for audit."}') = 'resolved';
  assert exists (select 1 from public.corrective_incident where id = incident and archived_at is not null);
  assert public.corrective_admin(incident, 'restore', '{"note":"Restore to the closed queue."}') = 'resolved';
  assert exists (select 1 from public.corrective_incident where id = incident and archived_at is null);
  assert public.corrective_admin(incident, 'archive', '{"note":"Archive for the reopen test."}') = 'resolved';

  perform set_config('request.jwt.claim.sub', fixture_worker::text, true);
  assert exists (select 1 from maintenance_api.corrective_notification
    where incident_id = incident and title = 'Work approved'), 'The worker did not receive the review outcome.';
  perform set_config('request.jwt.claim.sub', linked_reporter::text, true);
  assert exists (select 1 from maintenance_api.corrective_notification
    where incident_id = linked_case and title = 'Work approved'), 'The linked reporter did not receive the closure alert.';
  assert (select linked_status = 'resolved' from public.corrective_incident where id = linked_case);
  perform public.corrective_reporter(linked_case, 'feedback',
    '{"rating":2,"note":"The pipe is still leaking.","unresolved":true}');
  assert (select linked_status = 'reported' from public.corrective_incident where id = linked_case);
  perform set_config('role', 'none', true);
  assert exists (select 1 from public.corrective_incident where id = incident and status = 'reported' and archived_at is null);
  raise notice 'Corrective lifecycle and access checks passed.';
end;
$$;

rollback;

select to_regclass('public.corrective_incident') is not null as installed_workflow_verified,
  (select not public from storage.buckets where id = 'corrective-evidence') as evidence_bucket_private;
