-- On-device results can inform priority and category. Routine dispatch still needs corroborating report text.
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
  device_result boolean;
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
  photo_clear := coalesce(media->>'vision_status' in ('clear','device_fault') and media->>'category' <> 'Other', false);
  device_result := coalesce(media->>'vision_status' = 'device_fault', false);

  text_reliable := case text_result->>'category'
    when 'Cleaning' then raw_text ~* '\m(spill|spilled|garbage|rubbish|litter|waste bin|dirty floor)\M'
    when 'Plumbing' then raw_text ~* '\m(leak|leaks|leaking|leakage|drip|dripping)\M'
                           and raw_text ~* '\m(sink|tap|faucet|basin)\M'
    when 'Furniture' then raw_text ~* '\m(chair|desk|table|drawer)\M'
    else false end;
  chosen_category := case
    when photo_clear and (not device_result or not text_reliable or media->>'category' = text_result->>'category')
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
    when media->>'vision_status' = 'device_normal'
      then 'The photo shows no obvious fault. Review the description before assigning.'
    when device_result and not text_reliable
      then 'The device detected a possible fault. Confirm it before assigning.'
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
    triage = (i.triage - array['confidence','vision_status','observation','media_kind','routing_reason']) || jsonb_strip_nulls(jsonb_build_object(
      'category', category.name, 'priority', chosen_priority,
      'confidence', case when media->>'kind' is null or not photo_clear then text_result->'confidence' end,
      'model', case when photo_clear then media->>'model' else text_result->>'model' end,
      'vision_status', media->>'vision_status', 'observation', media->>'observation',
      'media_kind', media->>'kind', 'routing_reason', review_reason,
      'review_required', review_reason is not null,
      'routing_mode', case when review_reason is null then 'automatic' else 'manual_review' end
    )),
    target_at = now() + case chosen_priority when 'Critical' then interval '1 hour'
      when 'High' then interval '4 hours' when 'Medium' then interval '1 day' else interval '3 days' end,
    updated_at = now()
  where i.id = target;

  if review_reason is not null then
    perform uni360_private.corrective_log(target, 'Smart triage', concat_ws(' � ', category.name, chosen_priority, review_reason));
    return;
  end if;

  update public.corrective_incident set status = 'approved', approved_at = now() where id = target;
  perform uni360_private.corrective_log(target, 'Report approved', 'Automatically cleared for routine maintenance.');
  perform uni360_private.corrective_dispatch(target, null, 'Automatically routed using role, availability and workload.');
end;
$$;
