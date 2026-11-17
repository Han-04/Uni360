begin;

set local lock_timeout = '8s';
alter table public.corrective_incident
  add column archived_at timestamptz,
  add column withdrawn_at timestamptz,
  add column prior_report_photos text[] not null default '{}';

create unique index maintenance_scope_unique_qr
  on uni360_data.maintenance_scope(qr_token) where record_kind = 'corrective_site';

create function uni360_private.corrective_photo_diagnostics(diagnostics jsonb, has_photo boolean)
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'evidence_quality', case
      when not has_photo then 'missing'
      when diagnostics->>'quality' in ('clear','dark','bright','low_contrast') then diagnostics->>'quality'
      else 'unchecked'
    end,
    'photo_fingerprint', case when has_photo and diagnostics->>'quality' = 'clear'
      and diagnostics->>'fingerprint' ~ '^[0-9a-f]{16}$' then diagnostics->>'fingerprint' end
  ));
$$;

create or replace function uni360_private.corrective_registered_photo(object_path text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.corrective_incident
    where report_photo = object_path or object_path = any(prior_report_photos))
    or exists (select 1 from maintenance_api.corrective_photo where path = object_path);
$$;

alter policy corrective_evidence_read on storage.objects using (
  bucket_id = 'corrective-evidence' and uni360_private.corrective_active() and (
    (owner_id = auth.uid()::text and not uni360_private.corrective_registered_photo(name))
    or exists (select 1 from public.corrective_incident i
      where i.report_photo = storage.objects.name or (
        storage.objects.name = any(i.prior_report_photos)
        and (i.reporter_id = auth.uid() or uni360_private.corrective_manage(i.zone_id))
      ))
    or exists (select 1 from maintenance_api.corrective_photo p where p.path = storage.objects.name)
  )
);

create or replace function uni360_private.corrective_report(payload jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  target uuid := (payload->>'id')::uuid;
  facility uuid := (payload->>'facility_id')::uuid;
  photo text := nullif(payload->>'photo', '');
  item_category text := coalesce(payload->>'category', 'Other');
  item_urgency text := coalesce(payload->>'urgency', 'Medium');
  site_token text := nullif(btrim(payload->>'qr'), '');
  account_row public.account%rowtype;
  location_label text;
begin
  select * into account_row from public.account where user_id = auth.uid() and is_active;
  if not found then raise exception 'Sign in with an active Uni360 account.' using errcode = '42501'; end if;
  perform pg_catalog.pg_advisory_xact_lock(360, 2);
  if exists (select 1 from public.corrective_incident where id = target and reporter_id = auth.uid()) then
    return target;
  end if;
  if site_token is not null and not exists (select 1 from maintenance_api.corrective_site s
      where s.facility_id = facility and 'uni360:' || s.qr_token::text = site_token) then
    raise exception 'This location QR is no longer valid. Scan again or select the facility manually.';
  end if;
  if not exists (select 1 from maintenance_api.corrective_category c where c.name = item_category and c.active) then
    raise exception 'Select an active report category.';
  end if;
  with recursive ancestors(id, parent_id, label) as (
    select f.id, f.parent_id, f.name from public.preventive_facility f where f.id = facility
    union all
    select p.id, p.parent_id, p.name || ' / ' || a.label
    from public.preventive_facility p join ancestors a on a.parent_id = p.id
  )
  select label into location_label from ancestors where parent_id is null;
  if location_label is null then raise exception 'Select an existing campus facility.'; end if;
  if not uni360_private.preventive_facility_active(facility) then
    raise exception 'This campus location is inactive. Select another facility.';
  end if;
  if photo is null and account_row.role not in ('administrator','super_administrator') then
    raise exception 'Attach a photograph of the fault before submitting.';
  end if;
  if photo is not null and not uni360_private.corrective_owned_photo(photo, target, 'report') then
    raise exception 'The report photograph could not be verified.';
  end if;
  insert into public.corrective_incident (
    id, facility_id, zone_id, facility_name, category, title, description, location_detail, urgency,
    required_role, reporter_id, reporter_name, checklist, report_photo, location_method, triage
  ) select target, f.id, f.zone_id, location_label, item_category, btrim(payload->>'title'),
    btrim(payload->>'description'), btrim(payload->>'location_detail'), item_urgency,
    (select worker_role from maintenance_api.corrective_category c where c.name = item_category),
    account_row.user_id, account_row.full_name,
    array['Assess the fault and secure the affected area',
          'Perform or document the corrective work',
          'Verify the outcome and record any remaining issue'], photo,
    case when site_token is null then 'manual' else 'qr' end,
    uni360_private.corrective_predict(concat_ws(' ', payload->>'title', payload->>'description'),
      item_category, item_urgency, photo is not null)
    || uni360_private.corrective_photo_diagnostics(payload->'photo_diagnostics', photo is not null)
  from public.preventive_facility f where f.id = facility;
  perform uni360_private.corrective_log(target, 'Reported');
  return target;
end;
$$;

create or replace function uni360_private.corrective_reporter(target uuid, command text, payload jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare
  item public.corrective_incident%rowtype;
  note text := btrim(coalesce(payload->>'note', ''));
  rating integer := (payload->>'rating')::integer;
  replacement text := nullif(payload->>'photo', '');
  selected_category text := nullif(payload->>'category', '');
begin
  perform pg_catalog.pg_advisory_xact_lock(360, 2);
  select * into item from public.corrective_incident
    where id = target and reporter_id = auth.uid() and uni360_private.corrective_active() for update;
  if not found then raise exception 'This report is unavailable.' using errcode = '42501'; end if;
  if char_length(note) > 2000 then raise exception 'Keep the message within 2000 characters.'; end if;
  if command in ('edit','withdraw') then
    if item.status not in ('reported','needs_info') or item.approved_at is not null then
      raise exception 'Only reports awaiting review can be edited or withdrawn.';
    end if;
    if command = 'withdraw' then
      update public.corrective_incident set status = 'dismissed', withdrawn_at = now(), updated_at = now()
      where id = target;
      perform uni360_private.corrective_log(target, 'Report withdrawn', note);
      return;
    end if;
    if coalesce(replacement, item.report_photo) is null then
      raise exception 'Attach a photograph of the fault before saving.';
    end if;
    if replacement is not null and not uni360_private.corrective_owned_photo(replacement, target, 'report') then
      raise exception 'The replacement photograph could not be verified.';
    end if;
    if not exists (select 1 from maintenance_api.corrective_category c
      where c.name = selected_category and (c.active or c.name = item.category)) then
      raise exception 'Select an active report category.';
    end if;
    update public.corrective_incident set
      title = btrim(payload->>'title'), description = btrim(payload->>'description'),
      location_detail = btrim(payload->>'location_detail'), category = selected_category,
      required_role = (select c.worker_role from maintenance_api.corrective_category c where c.name = selected_category),
      urgency = coalesce(payload->>'urgency', item.urgency),
      report_photo = coalesce(replacement, item.report_photo),
      prior_report_photos = case when replacement is distinct from item.report_photo and replacement is not null
        and item.report_photo is not null then array_append(prior_report_photos, item.report_photo) else prior_report_photos end,
      triage = uni360_private.corrective_predict(
        concat_ws(' ',payload->>'title',payload->>'description'), selected_category,
        coalesce(payload->>'urgency',item.urgency), coalesce(replacement,item.report_photo) is not null)
        || case when replacement is null then jsonb_strip_nulls(jsonb_build_object(
          'evidence_quality',item.triage->>'evidence_quality','photo_fingerprint',item.triage->>'photo_fingerprint'))
          else uni360_private.corrective_photo_diagnostics(payload->'photo_diagnostics', true) end,
      status = 'reported', updated_at = now()
    where id = target;
    perform uni360_private.corrective_log(target, 'Pending report updated');
  elsif command = 'reply' and item.status = 'needs_info' then
    if char_length(note) < 3 then raise exception 'Enter the requested information.'; end if;
    update public.corrective_incident set status = 'reported', updated_at = now() where id = target;
    perform uni360_private.corrective_log(target, 'Additional information provided', note);
  elsif command = 'feedback' and (item.status = 'resolved' or (item.status = 'merged' and item.linked_status = 'resolved'))
      and item.feedback_rating is null then
    if rating is null or rating not between 1 and 5 then raise exception 'Select a rating from 1 to 5.'; end if;
    update public.corrective_incident set feedback_rating = rating, feedback_comment = nullif(note,''),
      updated_at = now() where id = target;
    perform uni360_private.corrective_log(target, 'Reporter feedback received', concat_ws(' · ', rating || '/5', nullif(note,'')));
    if coalesce((payload->>'unresolved')::boolean, false) then
      update public.corrective_incident set status = 'reported', worker_id = null, worker_name = null,
        attempt = attempt + 1, approved_at = null, resolved_at = null, due_at = null,
        target_at = null, archived_at = null, updated_at = now()
        where id = coalesce(item.merged_into, target) and status = 'resolved';
      if found then
        perform uni360_private.corrective_log(coalesce(item.merged_into, target), 'Issue reopened',
          case when item.merged_into is null then note else 'A linked reporter indicated that the fault persists.' end);
      end if;
    end if;
  else
    raise exception 'The current report status does not allow this action.';
  end if;
end;
$$;

create or replace function uni360_private.corrective_admin(target uuid, command text, payload jsonb)
returns text language plpgsql security definer set search_path = '' as $$
declare
  item public.corrective_incident%rowtype;
  note text := left(btrim(coalesce(payload->>'note','')), 2000);
  chosen uuid := (payload->>'worker_id')::uuid;
  order_id uuid := (payload->>'order_id')::uuid;
  new_start timestamptz := (payload->>'new_start')::timestamptz;
  order_row public.preventive_work_order%rowtype;
  new_end timestamptz;
  notify_group text := coalesce(payload->>'notify_group', 'both');
  selected_category text := payload->>'category';
  category_row maintenance_api.corrective_category%rowtype;
  primary_case public.corrective_incident%rowtype;
  result text;
begin
  perform pg_catalog.pg_advisory_xact_lock(360, 2);
  select * into item from public.corrective_incident where id = target for update;
  if not found or not uni360_private.corrective_manage(item.zone_id) then
    raise exception 'This incident is outside your managed zones.' using errcode = '42501';
  end if;
  if command in ('archive','restore') then
    if item.status not in ('resolved','rejected','dismissed') then
      raise exception 'Only closed cases can be archived or restored.';
    end if;
    if (command = 'archive') = (item.archived_at is not null) then return item.status; end if;
    if note = '' then raise exception 'Enter a reason for this archive decision.'; end if;
    update public.corrective_incident set archived_at = case when command = 'archive' then now() end,
      updated_at = now() where id = target;
    perform uni360_private.corrective_log(target,
      case when command = 'archive' then 'Case archived' else 'Case restored from archive' end, note);
    return item.status;
  end if;
  if command in ('dispatch','assign','escalate','external','dismiss','requirements','mark_deferrable','postpone')
    and item.status not in ('reported','needs_info','inspection','approved','escalated','assigned','acknowledged','checked_in','external','rework') then
    raise exception 'The current incident status does not allow this action.';
  end if;
  if command in ('review_approve','request_information','inspect','merge') then
    if item.status not in ('reported','needs_info','inspection','approved') then
      raise exception 'Only cases awaiting assignment can be reviewed or merged.';
    end if;
    if command = 'review_approve' then
      select * into category_row from maintenance_api.corrective_category
        where name = coalesce(selected_category, item.category) and active;
      if not found then raise exception 'Select an active category before approval.'; end if;
      update public.corrective_incident set status = 'approved', approved_at = now(),
        category = category_row.name, urgency = coalesce(payload->>'urgency', urgency),
        target_at = now() + case coalesce(payload->>'urgency', urgency)
          when 'Critical' then interval '1 hour' when 'High' then interval '4 hours'
          when 'Medium' then interval '1 day' else interval '3 days' end,
        required_role = case when category_row.name = item.category then required_role else category_row.worker_role end,
        required_skill_id = case when category_row.name = item.category then required_skill_id end,
        updated_at = now() where id = target;
      perform uni360_private.corrective_log(target, 'Report approved',
        concat_ws(' · ', category_row.name, coalesce(payload->>'urgency', item.urgency), nullif(note,'')));
      return 'approved';
    end if;
    if note = '' then raise exception 'Enter a reason for this review decision.'; end if;
    if command = 'merge' then
      select * into primary_case from public.corrective_incident
      where id = (payload->>'primary_id')::uuid and id <> target and facility_id = item.facility_id
        and status not in ('merged','resolved','rejected','dismissed') for update;
      if not found or exists (select 1 from public.corrective_incident where merged_into = target) then
        raise exception 'Select an unresolved case at the same facility and keep any existing primary case.';
      end if;
      update public.corrective_incident set status = 'merged', merged_into = primary_case.id,
        linked_reference = primary_case.reference, linked_status = primary_case.status, updated_at = now() where id = target;
      perform uni360_private.corrective_log(target, 'Report merged', note);
      perform uni360_private.corrective_log(primary_case.id, 'Duplicate report linked', 'Report CM-' || item.reference);
      return 'merged';
    end if;
    result := case when command = 'inspect' then 'inspection' else 'needs_info' end;
    update public.corrective_incident set status = result, approved_at = null, updated_at = now() where id = target;
    perform uni360_private.corrective_log(target, case when command = 'inspect' then 'Inspection requested'
      else 'More information requested' end, note);
    return result;
  elsif command = 'requirements' then
    if item.status not in ('reported','approved','escalated','external') then
      raise exception 'Escalate the incident before changing the requirements of an assigned job.';
    end if;
    update public.corrective_incident set required_role = nullif(lower(btrim(payload->>'role')), ''),
      required_skill_id = (payload->>'skill_id')::uuid,
      urgency = coalesce(payload->>'urgency', urgency), updated_at = now() where id = target;
    perform uni360_private.corrective_log(target, 'Assignment requirements updated', note);
    return item.status;
  elsif command in ('dispatch','assign') then
    if item.approved_at is null then raise exception 'Approve this report before assigning work.'; end if;
    if command = 'assign' and chosen is null then raise exception 'Select a worker.'; end if;
    perform uni360_private.corrective_log(target, 'Verified by administrator', note);
    return uni360_private.corrective_dispatch(target, chosen, note);
  elsif command in ('mark_deferrable','postpone') then
    if note = '' then raise exception 'Enter a reason for changing preventive work.'; end if;
    select * into order_row from public.preventive_work_order o where o.id = order_id
      and o.status = 'assigned' and o.cancelled_at is null
      and o.id::text in (select value->>'id' from jsonb_array_elements(uni360_private.corrective_admin_options(target)->'preventive'))
      for update;
    if not found then raise exception 'This preventive order is unavailable or has started.'; end if;
    if command = 'mark_deferrable' then
      insert into maintenance_api.corrective_deferrable_order(order_id, marked_by) values (order_row.id, auth.uid()) on conflict do nothing;
      perform uni360_private.corrective_log(target, 'Preventive order marked lower priority', order_row.title || ' · ' || note);
      return item.status;
    end if;
    if not exists (select 1 from maintenance_api.corrective_deferrable_order p where p.order_id = order_row.id) then
      raise exception 'Only work explicitly marked lower priority can be postponed.';
    end if;
    new_end := new_start + (order_row.due_at - order_row.scheduled_for);
    if new_start is null or new_start < greatest(order_row.scheduled_for, now() + interval '1 hour')
      or exists (select 1 from public.preventive_work_order o where o.worker_id = order_row.worker_id
        and o.id <> order_id and o.cancelled_at is null and o.status in ('assigned','in_progress')
        and o.scheduled_for < new_end and o.due_at > new_start)
      or not exists (select 1 from maintenance_api.worker_availability v where v.worker_id = order_row.worker_id
        and lower(btrim(v.availability_status)) = 'available' and lower(btrim(v.leave_status)) in ('none','rejected')
        and v.shift_start <= new_start and v.shift_end >= new_end)
      or exists (select 1 from maintenance_api.worker_availability v where v.worker_id = order_row.worker_id
        and (lower(btrim(v.availability_status)) = 'unavailable' or lower(btrim(v.leave_status)) = 'approved')
        and v.shift_start < new_end and v.shift_end > new_start) then
      raise exception 'Choose a later time within the worker shift with no conflicting assignment.';
    end if;
    update public.preventive_work_order set scheduled_for = new_start, due_at = new_end where id = order_id;
    perform uni360_private.corrective_log(target, 'Preventive work postponed', order_row.title || ' · ' || note);
    return item.status;
  elsif command in ('escalate','external','dismiss') then
    if note = '' then raise exception 'Enter a reason.'; end if;
    if notify_group not in ('both','zone','supervisors') then raise exception 'Select a notification group.'; end if;
    result := case command when 'escalate' then 'escalated' when 'external' then 'external' else 'dismissed' end;
    update public.corrective_incident set status = result, worker_id = null, worker_name = null,
      attempt = attempt + (status = 'checked_in')::integer,
      due_at = null, urgency = coalesce(payload->>'urgency', urgency), updated_at = now() where id = target;
    perform uni360_private.corrective_log(target, case command when 'escalate' then 'Escalated'
      when 'external' then 'External assistance required' else 'Report dismissed' end,
      case when command = 'escalate' then concat_ws(' · ', note,
        'Urgency ' || coalesce(payload->>'urgency', item.urgency),
        case notify_group when 'zone' then 'Zone administrators notified'
          when 'supervisors' then 'Super administrators notified'
          else 'Zone and super administrators notified' end)
      else note end, notify_group);
    if item.worker_id is not null then
      insert into maintenance_api.corrective_notification(recipient_id, incident_id, title, incident_title)
      values (item.worker_id, target, 'Assignment withdrawn', item.title);
    end if;
  elsif command in ('approve','rework','reject') and item.status = 'submitted' then
    if note = '' then raise exception 'Enter review remarks.'; end if;
    result := case command when 'approve' then 'resolved' when 'rework' then 'rework' else 'rejected' end;
    update public.corrective_incident set status = result, attempt = attempt + (command = 'rework')::integer,
      resolved_at = case when command = 'approve' then now() end, updated_at = now() where id = target;
    perform uni360_private.corrective_log(target, case command when 'approve' then 'Work approved'
      when 'rework' then 'Rework requested' else 'Evidence rejected' end, note);
  else
    raise exception 'The current incident status does not allow this action.';
  end if;
  return result;
end;
$$;

create or replace function uni360_private.corrective_admin_options(target uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare incident public.corrective_incident%rowtype;
begin
  select * into incident from public.corrective_incident where id = target;
  if not found or not uni360_private.corrective_manage(incident.zone_id) then
    raise exception 'This incident is outside your managed zones.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'triage', incident.triage || jsonb_build_object(
      'review_required', coalesce((incident.triage->>'confidence')::numeric,0) < 60
        or coalesce(incident.triage->>'evidence_quality','unchecked') <> 'clear',
      'evidence_quality', coalesce(incident.triage->>'evidence_quality',
        case when incident.report_photo is null then 'missing' else 'unchecked' end)),
    'team', (select team from maintenance_api.corrective_category where name = incident.category),
    'duplicates', coalesce((
      select jsonb_agg(to_jsonb(matches) order by matches.similarity desc, matches.reference desc)
      from (
        select i.id, i.reference, i.title, i.status, i.category, i.created_at,
          greatest(round(100 * compared.score), coalesce(visual.score, 0)) similarity,
          round(100 * compared.score) text_similarity, visual.score photo_similarity
        from public.corrective_incident i
        cross join lateral (select uni360_private.corrective_similarity(
          uni360_private.corrective_terms(i.title || ' ' || i.description),
          uni360_private.corrective_terms(incident.title || ' ' || incident.description)
        ) score) compared
        cross join lateral (select case
          when i.triage->>'photo_fingerprint' ~ '^[0-9a-f]{16}$'
            and incident.triage->>'photo_fingerprint' ~ '^[0-9a-f]{16}$'
          then round(100 * (64 - bit_count(
            ('x' || (i.triage->>'photo_fingerprint'))::bit(64)
            # ('x' || (incident.triage->>'photo_fingerprint'))::bit(64)
          ))::numeric / 64) end score) visual
        where i.id <> target and i.facility_id = incident.facility_id
          and i.status not in ('resolved','rejected','dismissed','merged')
          and (compared.score >= .15 or visual.score >= 90 or (i.category = incident.category and compared.score > 0))
        order by similarity desc, i.created_at desc limit 5
      ) matches
    ), '[]'::jsonb),
    'candidates', coalesce((select jsonb_agg(to_jsonb(c)) from uni360_private.corrective_candidates(target) c), '[]'::jsonb),
    'preventive', coalesce((
      select jsonb_agg(jsonb_build_object('id', o.id, 'plan_id', o.plan_id, 'title', o.title,
        'start', o.scheduled_for, 'worker', a.full_name, 'deferrable', p.order_id is not null) order by o.scheduled_for)
      from public.preventive_work_order o join public.account a on a.user_id = o.worker_id
      left join maintenance_api.corrective_deferrable_order p on p.order_id = o.id
      where incident.urgency in ('High','Critical') and o.status = 'assigned' and o.cancelled_at is null
        and o.scheduled_for < now() + interval '1 hour' and o.due_at > now()
        and exists (select 1 from uni360_private.corrective_candidates(target, true) c where c.worker_id = o.worker_id)
        and exists (select 1 from maintenance_api.preventive_work_order_target t where t.work_order_id = o.id)
        and not exists (
          select 1 from maintenance_api.preventive_work_order_target t join public.preventive_facility f on f.id = t.facility_id
          where t.work_order_id = o.id and (f.zone_id <> incident.zone_id or not uni360_private.corrective_manage(f.zone_id))
        )
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function uni360_private.corrective_lookup_qr(code text) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare facility uuid;
begin
  if not uni360_private.corrective_active() then raise exception 'Sign in to scan a facility QR.' using errcode = '42501'; end if;
  select facility_id into facility from maintenance_api.corrective_site where 'uni360:' || qr_token::text = btrim(code) and uni360_private.preventive_facility_active(facility_id);
  if not found then raise exception 'This QR code is not a registered Uni360 facility.'; end if;
  return facility;
end;
$$;

create or replace function uni360_private.corrective_log(
  target uuid, event_name text, details text default '', escalation_to text default 'both'
) returns void language plpgsql security invoker set search_path = '' as $$
begin
  insert into maintenance_api.corrective_event (incident_id, actor_id, actor_name, event, note)
  select target, user_id, full_name, event_name, coalesce(details, '')
  from public.account where user_id = auth.uid() and is_active;
  insert into maintenance_api.corrective_notification (recipient_id, incident_id, title, incident_title)
  select a.user_id, i.id, event_name, i.title
  from public.corrective_incident i join public.account a on a.is_active and (
    (a.user_id = i.worker_id and event_name in ('Assigned','Reassigned','Work approved','Rework requested','Evidence rejected'))
    or (a.user_id = i.reporter_id and event_name in ('Reported','Report approved','More information requested','Inspection requested','Report merged','Assigned','Reassigned','Escalated','External assistance required','Work approved','Evidence rejected','Report dismissed','Issue reopened','Report withdrawn'))
    or (event_name in ('Reported','Pending report updated','Report withdrawn','Additional information provided','Issue reopened','Escalated','Evidence submitted','External assistance required','Worker requested assistance') and (
      (escalation_to in ('both','supervisors') and a.role = 'super_administrator')
      or (escalation_to in ('both','zone') and exists (select 1 from maintenance_api.preventive_zone_admin za
        where za.zone_id = i.zone_id and za.administrator_id = a.user_id))
    ))
  )
  where i.id = target;
  if event_name in ('Assigned','Reassigned','Work approved','Rework requested','Evidence rejected','Report dismissed','Issue reopened') then
    insert into maintenance_api.corrective_notification(recipient_id, incident_id, title, incident_title)
    select i.reporter_id, i.id, event_name, i.title
    from public.corrective_incident i join public.account a on a.user_id = i.reporter_id and a.is_active
    where i.merged_into = target;
  end if;
end;
$$;

revoke all on function uni360_private.corrective_photo_diagnostics(jsonb,boolean)
  from public, anon, authenticated;

notify pgrst, 'reload schema';

commit;

select count(*) filter (where table_schema = 'public') as public_table_editor_entries,
  count(*) as application_tables
from information_schema.tables
where table_schema in ('public','uni360_data','uni360_private','maintenance_api') and table_type = 'BASE TABLE';
