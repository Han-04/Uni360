begin;

-- Keep the work-time override when an existing rule is moved to a new time.

create or replace function public.save_preventive_facility_schedule(
  target_facility uuid, target_template uuid, repeat_frequency text,
  first_date date, last_date date, times time[], replaced_schedule uuid default null
) returns uuid
language plpgsql security invoker set search_path = '' as $$
declare
  facility_zone uuid;
  target_plan uuid;
  previous public.preventive_schedule%rowtype;
begin
  select zone_id into facility_zone from public.preventive_facility where id = target_facility;
  if not found then
    raise exception 'Facility is outside your assigned zones or is unavailable.' using errcode = '42501';
  end if;
  if not uni360_private.preventive_facility_active(target_facility) then
    raise exception 'Choose an active facility.' using errcode = '23514';
  end if;
  if not exists (
    select 1 from public.preventive_task_definition
    where id = target_template and is_active and (zone_id is null or zone_id = facility_zone)
  ) then
    raise exception 'Choose an active task template available in this zone.' using errcode = '23514';
  end if;
  if repeat_frequency is null or repeat_frequency not in ('daily', 'weekly', 'monthly')
     or first_date is null or last_date < first_date then
    raise exception 'Choose a frequency and valid start and end dates.' using errcode = '23514';
  end if;
  if coalesce(cardinality(times), 0) = 0
     or exists (select 1 from unnest(times) as slot(value) where value is null)
     or cardinality(times) <> (select count(distinct value) from unnest(times) as slot(value)) then
    raise exception 'Enter at least one time. Each time must be different.' using errcode = '23514';
  end if;
  if replaced_schedule is not null and cardinality(times) <> 1 then
    raise exception 'Edit one schedule time at a time.' using errcode = '23514';
  end if;

  insert into public.preventive_task_plan (facility_id, zone_id, task_definition_id)
  values (target_facility, facility_zone, target_template)
  on conflict (facility_id, task_definition_id) do nothing;

  select id into strict target_plan from public.preventive_task_plan
  where facility_id = target_facility and task_definition_id = target_template for update;
  update public.preventive_task_plan set is_active = true where id = target_plan and not is_active;

  if replaced_schedule is not null then
    select * into previous from public.preventive_schedule
      where id = replaced_schedule and plan_id = target_plan and is_active for update;
    if not found then
      raise exception 'This schedule has changed. Reopen it and try again.' using errcode = '23514';
    end if;
    if exists (
      select 1 from public.preventive_schedule
      where plan_id = target_plan and is_active and id <> previous.id
        and frequency = repeat_frequency and starts_on = first_date and local_time = times[1]
    ) then
      raise exception 'This frequency, start date and time already exist.' using errcode = '23514';
    end if;
    if previous.frequency <> repeat_frequency or previous.starts_on <> first_date or previous.local_time <> times[1] then
      update public.preventive_schedule set is_active = false where id = previous.id;
    end if;
  end if;

  insert into public.preventive_schedule (plan_id, frequency, starts_on, ends_on, local_time, duration_minutes)
  select target_plan, repeat_frequency, first_date, last_date, slot.value, previous.duration_minutes from unnest(times) as slot(value)
  on conflict (plan_id, frequency, starts_on, local_time) do update
    set is_active = true, ends_on = excluded.ends_on,
        duration_minutes = coalesce(excluded.duration_minutes, preventive_schedule.duration_minutes)
    where not preventive_schedule.is_active or preventive_schedule.id = replaced_schedule;
  return target_plan;
end;
$$;

commit;
