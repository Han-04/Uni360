-- Visual suggestions need corroborating report text for routine automatic dispatch.
create or replace function uni360_private.corrective_apply_smart_triage(target uuid, allow_dispatch boolean)
returns void language plpgsql security invoker set search_path = '' as $$
declare
  incident public.corrective_incident%rowtype;
  category maintenance_api.corrective_category%rowtype;
  raw_text text;
  text_result jsonb;
  media jsonb;
  chosen_category text;
  chosen_priority text;
  severity integer;
  photo_clear boolean;
  text_reliable boolean;
  requires_text boolean;
  duplicate_found boolean;
  review_reason text;
  priorities constant text[] := array['Low','Medium','High','Critical'];
begin
  select * into incident from public.corrective_incident i
  where i.id = target and i.reporter_id = auth.uid() and i.status = 'reported' for update;
  if not found then return; end if;

  raw_text := concat_ws(' ', incident.title, incident.description);
  text_result := uni360_private.corrective_predict(raw_text, 'Other', 'Medium', incident.report_photo is not null);
  media := coalesce(uni360_private.corrective_media_result(incident.report_photo, incident.reporter_id), '{}'::jsonb);
  photo_clear := coalesce(media->>'vision_status' in ('clear','device_fault','gemini_fault','vision_fault') and media->>'category' <> 'Other', false);
  requires_text := coalesce(media->>'vision_status' in ('device_fault','gemini_fault','vision_fault'), false);

  text_reliable := case text_result->>'category'
    when 'Cleaning' then raw_text ~* '\m(spill|spilled|garbage|rubbish|litter|waste bin|dirty floor)\M'
    when 'Plumbing' then raw_text ~* '\m(leak|leaks|leaking|leakage|drip|dripping)\M'
                           and raw_text ~* '\m(sink|tap|faucet|basin)\M'
    when 'Furniture' then raw_text ~* '\m(chair|desk|table|drawer)\M'
    else false end;
  chosen_category := case
    when photo_clear and (not requires_text or not text_reliable or media->>'category' = text_result->>'category')
      then media->>'category'
    else text_result->>'category'
  end;

  -- Conservative severity uses whichever evidence indicates the greater impact.
  severity := greatest(
    array_position(priorities, case
      when raw_text ~* 'exposed.{0,18}(wire|wiring)|sparks?|smoke|fire|trapped|live wir' then 'Critical'
      when raw_text ~* 'flood|burst pipe|overflowing water|water.{0,24}(socket|outlet|wiring)|power outage|out of service|broken glass|chemical spill|blocked exit' then 'High'
      when text_reliable and text_result->>'category' = 'Cleaning' then 'Low'
      when photo_clear and not text_reliable then 'Low'
      else text_result->>'priority' end),
    case when photo_clear or media->>'priority' in ('High','Critical') then array_position(priorities, media->>'priority') end,
    1
  );
  chosen_priority := priorities[severity];
  select * into category from maintenance_api.corrective_category c
  where c.active and c.name = chosen_category;
  if not found then
    select * into category from maintenance_api.corrective_category c
    where c.active order by (c.name = 'Other') desc, c.name limit 1;
    chosen_category := 'Other';
  end if;
  if category.name is null then raise exception 'Enable a corrective category before submitting.'; end if;

  select exists (
    select 1 from public.corrective_incident other
    where other.id <> target and other.facility_id = incident.facility_id
      and other.created_at > now() - interval '72 hours'
      and other.status not in ('resolved','dismissed','rejected','merged')
      and (lower(btrim(other.title)) = lower(btrim(incident.title))
        or (other.category = category.name
          and lower(btrim(other.location_detail)) = lower(btrim(incident.location_detail)))
        or (incident.triage->>'photo_fingerprint' is not null
          and other.triage->>'photo_fingerprint' = incident.triage->>'photo_fingerprint'))
  ) into duplicate_found;

  review_reason := case
    when severity >= 3 then 'High or critical priority requires immediate administrator review.'
    when duplicate_found then 'A similar open report exists at this facility.'
    when not allow_dispatch then 'Updated report awaits administrator review.'
    when photo_clear and text_reliable and media->>'category' <> text_result->>'category'
      then 'The image assessment and report text suggest different categories.'
    when media->>'vision_status' in ('device_normal','normal')
      then 'The photo shows no obvious fault. Review the description before assigning.'
    when requires_text and not text_reliable
      then 'The photo suggests a possible fault. Confirm it before assigning.'
    when media->>'vision_status' in ('unclear','device_unclear') or incident.triage->>'evidence_quality' in ('dark','bright','low_contrast')
      then 'The photograph needs a human check.'
    when chosen_category not in ('Cleaning','Furniture','Plumbing') or category.worker_role is null
      then 'The fault needs administrator verification before assignment.'
    when incident.report_photo is null or (not photo_clear and not text_reliable)
      then 'The available evidence needs administrator verification.'
    when media->>'kind' is null then 'The attachment could not be checked automatically.'
    when not exists (select 1 from maintenance_api.corrective_site s where s.facility_id = incident.facility_id)
      then 'Set up the facility QR and check-in location before dispatch.'
  end;

  update public.corrective_incident i set
    category = category.name, urgency = chosen_priority,
    required_role = category.worker_role,
    required_skill_id = case when i.category = category.name then i.required_skill_id end,
    triage = (i.triage - array['confidence','vision_status','observation','photo_category','photo_priority','media_kind','routing_reason']) || jsonb_strip_nulls(jsonb_build_object(
      'category', category.name, 'priority', chosen_priority,
      'confidence', case when media->>'kind' is null or not photo_clear then text_result->'confidence' end,
      'model', case when photo_clear then media->>'model' else text_result->>'model' end,
      'vision_status', media->>'vision_status', 'observation', media->>'observation',
      'photo_category', case when photo_clear then media->>'category' end,
      'photo_priority', case when photo_clear then media->>'priority' end,
      'media_kind', media->>'kind', 'routing_reason', review_reason,
      'review_required', review_reason is not null,
      'routing_mode', case when review_reason is null then 'automatic' else 'manual_review' end
    )),
    target_at = now() + case chosen_priority when 'Critical' then interval '1 hour'
      when 'High' then interval '4 hours' when 'Medium' then interval '1 day' else interval '3 days' end,
    updated_at = now()
  where i.id = target;

  if review_reason is not null then
    perform uni360_private.corrective_log(target, 'Smart triage', concat_ws(' - ', category.name, chosen_priority, review_reason));
    return;
  end if;

  update public.corrective_incident set status = 'approved', approved_at = now() where id = target;
  perform uni360_private.corrective_log(target, 'Report approved', 'Automatically cleared for routine maintenance.');
  perform uni360_private.corrective_dispatch(target, null, 'Automatically routed using role, availability and workload.');
end;
$$;

-- Old opt-out receipts can be claimed once when the reporter resubmits the photo.

create or replace function public.corrective_media_receipt(object_path text, media_owner uuid, result jsonb default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  object_key uuid;
  existing uni360_private.corrective_media_checks%rowtype;
begin
  if split_part(object_path, '/', 1) <> media_owner::text
      or split_part(object_path, '/', 3) <> 'report'
      or not exists (select 1 from public.account a where a.user_id = media_owner and a.is_active) then
    return jsonb_build_object('state', 'missing');
  end if;
  select o.id into object_key from storage.objects o
  where o.bucket_id = 'corrective-evidence' and o.name = object_path and o.owner_id = media_owner::text;
  if not found then return jsonb_build_object('state', 'missing'); end if;
  perform pg_catalog.pg_advisory_xact_lock(hashtextextended(media_owner::text, 9841));
  select * into existing from uni360_private.corrective_media_checks c where c.object_id = object_key;
  if existing.evidence is not null and
      (result is not null or existing.evidence->>'vision_status' is distinct from 'skipped') then
    return jsonb_build_object('state', 'complete', 'result', existing.evidence);
  end if;
  if result is not null then
    update uni360_private.corrective_media_checks c set evidence = result
    where c.object_id = object_key and c.owner_id = media_owner;
    if not found then return jsonb_build_object('state', 'missing'); end if;
    return jsonb_build_object('state', 'complete', 'result', result);
  end if;
  if existing.evidence is null and existing.checked_at > now() - interval '45 seconds' then
    return jsonb_build_object('state', 'busy');
  end if;
  if (select count(*) from uni360_private.corrective_media_checks c
      where c.owner_id = media_owner and c.checked_at > now() - interval '1 hour') >= 20 then
    return jsonb_build_object('state', 'limited');
  end if;
  insert into uni360_private.corrective_media_checks (object_id, owner_id, path)
  values (object_key, media_owner, object_path)
  on conflict (object_id) do update set checked_at = now(), evidence = null
    where uni360_private.corrective_media_checks.evidence is null
      or uni360_private.corrective_media_checks.evidence->>'vision_status' = 'skipped';
  return jsonb_build_object('state', 'claimed');
end;
$$;

-- Keep report evidence optional for administrators editing a report they filed.

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
    if coalesce(replacement, item.report_photo) is null and not exists (
      select 1 from public.account a where a.user_id = auth.uid()
        and a.is_active and a.role in ('administrator','super_administrator')
    ) then
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
    perform uni360_private.corrective_log(target, 'Reporter feedback received', concat_ws(' � ', rating || '/5', nullif(note,'')));
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
