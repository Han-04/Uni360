begin;

alter table public.preventive_schedule add column duration_minutes integer
  check (duration_minutes between 1 and 720);
grant update (duration_minutes) on public.preventive_schedule to authenticated;

create function uni360_private.assign_preventive_day(work_date date, target_zone uuid, requested jsonb, earlier jsonb, prior_load jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  opens timestamptz := work_date::timestamp at time zone 'Asia/Kuala_Lumpur';
  closes timestamptz := (work_date + 1)::timestamp at time zone 'Asia/Kuala_Lumpur';
  occupied jsonb;
  draft jsonb := '[]'::jsonb;
  item record;
  choice record;
begin
  if not public.can_manage_workforce() or (requested is null and (target_zone is null or not uni360_private.preventive_manage_zone(target_zone))) then
    raise exception 'Choose a zone you manage.' using errcode = '42501';
  end if;
  if work_date is null or not isfinite(work_date) or extract(isodow from work_date) = 7 then
    raise exception 'Choose a valid date from Monday to Saturday.' using errcode = '23514';
  end if;

  -- Existing orders in any zone count towards capacity. Their details are never returned.
  select coalesce(jsonb_agg(jsonb_build_object(
    'worker', o.worker_id, 'starts', o.scheduled_for, 'ends', o.due_at,
    'minutes', coalesce(c.actual_minutes, ceil(extract(epoch from
      (least(o.due_at, closes) - greatest(o.scheduled_for, opens))) / 60)::integer),
    'completed', c.work_order_id is not null, 'proposed', false
  )), '[]'::jsonb) into occupied
  from public.preventive_work_order o
  left join public.preventive_work_completion c on c.work_order_id = o.id
  where o.worker_id is not null and o.cancelled_at is null and o.scheduled_for < closes and o.due_at > opens;

  for item in
    with occurrences as (
      select distinct on (p.id, s.local_time) p.id as plan_id, s.id as schedule_id,
        d.title, d.required_job_role, d.required_skill_id, coalesce(s.duration_minutes, d.duration_minutes) as duration_minutes, d.id as template_id,
        f.name as facility, f.id as facility_id, z.name as zone_name,
        ((work_date + s.local_time) at time zone 'Asia/Kuala_Lumpur') as occurrence
      from public.preventive_schedule s
      join public.preventive_task_plan p on p.id = s.plan_id
      join public.preventive_task_definition d on d.id = p.task_definition_id
      join public.preventive_facility f on f.id = p.facility_id
      join public.preventive_zone z on z.id = p.zone_id
      where requested is null and p.zone_id = target_zone and p.is_active and s.is_active and d.is_active
        and uni360_private.preventive_facility_active(f.id)
        and work_date >= s.starts_on and (s.ends_on is null or work_date <= s.ends_on)
        and (s.frequency = 'daily'
          or (s.frequency = 'weekly' and extract(isodow from work_date) = extract(isodow from s.starts_on))
          or (s.frequency = 'monthly' and extract(day from work_date) = extract(day from s.starts_on)))
        and (not (d.category = 'Toilet Cleaning' or (d.category = 'Cleaning' and d.title = 'Toilet Cleaning'))
          or (f.facility_type = 'room' and f.metadata->>'room_type' = 'toilet'))
      order by p.id, s.local_time, s.starts_on desc, s.id
    ), windows as (
      select o.*, lead(o.occurrence, 1, closes) over (partition by o.facility_id, o.template_id order by o.occurrence) as cutoff
      from (
        select * from occurrences
        union all
        select r.* from jsonb_to_recordset(coalesce(requested, '[]'::jsonb)) as r(
          plan_id uuid, schedule_id uuid, title text, required_job_role text, required_skill_id uuid,
          duration_minutes integer, template_id uuid, facility text, facility_id uuid, zone_name text, occurrence timestamptz
        )
      ) o
    )
    select w.*, existing.id as existing_id
    from windows w left join public.preventive_work_order existing
      on existing.plan_id = w.plan_id and existing.occurrence_at = w.occurrence
    where existing.id is null or (existing.worker_id is null and existing.cancelled_at is null)
    order by w.occurrence, w.cutoff, w.duration_minutes desc, w.facility, w.facility_id, w.schedule_id
  loop
    with busy as (
      select * from jsonb_to_recordset(occupied)
        as b(worker uuid, starts timestamptz, ends timestamptz, minutes integer, completed boolean, proposed boolean)
    ), earlier_totals as (
      select worker_id, sum(duration_minutes) as minutes
      from jsonb_to_recordset(earlier) as e(worker_id uuid, duration_minutes integer)
      group by worker_id
    ), candidates as (
      select w.worker_id, a.full_name, a.employee_id, w.current_workload, w.daily_work_limit_minutes,
        coalesce(t.minutes, 0) as booked, coalesce(t.worked, 0) as worked,
        coalesce((prior_load->>w.worker_id::text)::bigint, 0) + coalesce(e.minutes, 0)
          + coalesce(t.added, 0) as range_load,
        slot.starts, slot.starts + make_interval(mins => item.duration_minutes) as ends
      from public.worker_profile w join public.account a on a.user_id = w.worker_id
      left join earlier_totals e on e.worker_id = w.worker_id
      cross join lateral (
        select sum(b.minutes) as minutes, sum(b.minutes) filter (where b.completed) as worked, sum(b.minutes) filter (where b.proposed) as added
        from busy b where b.worker = w.worker_id
      ) t
      cross join lateral (
        select min(start_time) as starts
        from public.worker_availability v
        cross join lateral (
          select greatest(v.shift_start, item.occurrence) as start_time
          union
          select b.ends from busy b where b.worker = w.worker_id and b.ends >= greatest(v.shift_start, item.occurrence)
          union
          select u.shift_end from public.worker_availability u
            where u.worker_id = w.worker_id and lower(btrim(u.availability_status)) = 'unavailable'
              and u.shift_end >= greatest(v.shift_start, item.occurrence) and u.shift_end < v.shift_end
        ) options
        where v.worker_id = w.worker_id and lower(btrim(v.availability_status)) = 'available'
          and lower(btrim(v.leave_status)) in ('none', 'rejected')
          and start_time + make_interval(mins => item.duration_minutes) <= least(v.shift_end, item.cutoff)
          and not exists (
            select 1 from busy b where b.worker = w.worker_id and b.starts < start_time + make_interval(mins => item.duration_minutes)
              and b.ends > start_time
          )
          and not exists (
            select 1 from public.worker_availability u
            where u.worker_id = w.worker_id and lower(btrim(u.availability_status)) = 'unavailable'
              and u.shift_start < start_time + make_interval(mins => item.duration_minutes) and u.shift_end > start_time
          )
      ) slot
      where a.is_active and a.role = 'worker' and lower(btrim(w.employment_status)) = 'active'
        and lower(btrim(w.assigned_zone)) = lower(btrim(item.zone_name))
        and (item.required_job_role is null or lower(btrim(w.job_role)) = lower(btrim(item.required_job_role)))
        and (item.required_skill_id is null or exists (
          select 1 from public.worker_skill ws where ws.worker_id = w.worker_id and ws.skill_id = item.required_skill_id
        ))
        and slot.starts is not null
        and coalesce(t.minutes, 0) + item.duration_minutes <= w.daily_work_limit_minutes
        and not exists (
          select 1 from public.worker_availability leave_record
          where leave_record.worker_id = w.worker_id and lower(btrim(leave_record.leave_status)) = 'approved'
            and leave_record.shift_start < closes and leave_record.shift_end > opens
        )
    )
    select * into choice from candidates
    order by case when requested is null then booked else range_load end, booked,
      current_workload, starts, employee_id, worker_id limit 1;

    draft := draft || jsonb_build_array(jsonb_build_object(
      'schedule_id', item.schedule_id, 'plan_id', item.plan_id, 'existing_id', item.existing_id,
      'title', item.title, 'facility', item.facility, 'facility_id', item.facility_id, 'occurrence', item.occurrence, 'duration_minutes', item.duration_minutes,
      'worker_id', choice.worker_id, 'worker_name', choice.full_name, 'employee_id', choice.employee_id,
      'starts', choice.starts, 'ends', choice.ends, 'worked_minutes', choice.worked,
      'booked_before', choice.booked, 'work_limit', choice.daily_work_limit_minutes
    ));
    if choice.worker_id is not null then
      occupied := occupied || jsonb_build_array(jsonb_build_object(
        'worker', choice.worker_id, 'starts', choice.starts, 'ends', choice.ends,
        'minutes', item.duration_minutes, 'completed', false, 'proposed', true
      ));
    end if;
  end loop;
  return draft;
end;
$$;

create or replace function uni360_private.plan_preventive_day(work_date date, target_zone uuid)
returns jsonb language sql security definer set search_path = '' as $$
  select uni360_private.assign_preventive_day(work_date, target_zone, null, '[]'::jsonb, '{}'::jsonb);
$$;

create function uni360_private.auto_schedule_range(
  target_facilities uuid[], target_template uuid, repeat_frequency text, first_date date,
  last_date date, times time[], work_minutes integer, reviewed jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  definition public.preventive_task_definition%rowtype;
  locations jsonb;
  occupied jsonb;
  slots jsonb;
  draft jsonb := '[]'::jsonb;
  date_cursor date;
  starts timestamptz;
  ends timestamptz;
  item record;
  schedule uuid;
  approved integer := 0;
begin
  if not public.can_manage_workforce() then
    raise exception 'An active administrator account is required.' using errcode = '42501';
  end if;
  if first_date is null or last_date is null or not isfinite(first_date) or not isfinite(last_date)
    or last_date < first_date or repeat_frequency is null or repeat_frequency not in ('daily', 'weekly', 'monthly')
    or work_minutes is null or work_minutes not between 1 and 720 then
    raise exception 'Enter valid start and end dates, a repeat frequency and a duration.' using errcode = '23514';
  end if;
  if coalesce(cardinality(times), 0) = 0
    or cardinality(times) <> (select count(distinct t) from unnest(times) as slots(t))
    or exists (select 1 from unnest(times) as slots(t) where t >= time '24:00') then
    raise exception 'Enter at least one distinct start time.' using errcode = '23514';
  end if;
  if coalesce(cardinality(target_facilities), 0) = 0
    or cardinality(target_facilities) <> (select count(distinct f) from unnest(target_facilities) as choices(f)) then
    raise exception 'Choose at least one location.' using errcode = '23514';
  end if;
  if reviewed is not null then perform pg_catalog.pg_advisory_xact_lock(360, 2); end if;

  select * into definition from public.preventive_task_definition where id = target_template and is_active;
  if not found then raise exception 'Choose an active task template.' using errcode = '23514'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'facility_id', f.id, 'facility', f.name, 'zone_name', z.name, 'plan_id', p.id
  )), '[]'::jsonb) into locations
  from public.preventive_facility f
  join public.preventive_zone z on z.id = f.zone_id
  left join public.preventive_task_plan p on p.facility_id = f.id and p.task_definition_id = target_template
  where f.id = any(target_facilities) and uni360_private.preventive_manage_zone(f.zone_id)
    and uni360_private.preventive_facility_active(f.id)
    and (definition.zone_id is null or f.zone_id = definition.zone_id)
    and (not (definition.category = 'Toilet Cleaning' or (definition.category = 'Cleaning' and definition.title = 'Toilet Cleaning'))
      or (f.facility_type = 'room' and f.metadata->>'room_type' = 'toilet'));
  if jsonb_array_length(locations) <> cardinality(target_facilities) then
    raise exception 'Select active locations in your zones that match the task template.' using errcode = '23514';
  end if;

  starts := first_date::timestamp at time zone 'Asia/Kuala_Lumpur';
  ends := (last_date + 1)::timestamp at time zone 'Asia/Kuala_Lumpur';
  select coalesce(jsonb_object_agg(total.worker_id, total.minutes), '{}'::jsonb) into occupied
  from (
    select o.worker_id, sum(coalesce(c.actual_minutes, ceil(extract(epoch from
      (least(o.due_at, ends) - greatest(o.scheduled_for, starts))) / 60)::integer)) as minutes
    from public.preventive_work_order o
    left join public.preventive_work_completion c on c.work_order_id = o.id
    where o.worker_id is not null and o.cancelled_at is null and o.scheduled_for < ends and o.due_at > starts
    group by o.worker_id
  ) total;

  for date_cursor in select first_date + i from generate_series(0, last_date - first_date) as dates(i)
    where extract(isodow from first_date + i) <> 7
      and (repeat_frequency = 'daily'
        or (repeat_frequency = 'weekly' and mod(i, 7) = 0)
        or (repeat_frequency = 'monthly' and extract(day from first_date + i) = extract(day from first_date)))
    order by i
  loop
    select jsonb_agg(location || jsonb_build_object(
      'title', definition.title, 'required_job_role', definition.required_job_role,
      'required_skill_id', definition.required_skill_id, 'duration_minutes', work_minutes,
      'template_id', definition.id, 'occurrence', (date_cursor + t) at time zone 'Asia/Kuala_Lumpur'
    )) into slots
    from jsonb_array_elements(locations) as x(location) cross join unnest(times) as y(t);
    draft := draft || uni360_private.assign_preventive_day(date_cursor, null, slots, draft, occupied);
  end loop;
  if reviewed is null then return draft; end if;
  if reviewed is distinct from draft then
    raise exception 'The draft changed. Run Auto Schedule again and review the updated assignments.' using errcode = '23514';
  end if;
  if not exists (select 1 from jsonb_array_elements(draft) as rows(row) where row->>'worker_id' is not null) then
    return to_jsonb(0);
  end if;

  perform public.save_preventive_template_schedule(target_facilities, target_template, repeat_frequency, first_date, last_date, times);
  update public.preventive_schedule s set duration_minutes = work_minutes, ends_on = last_date
  from public.preventive_task_plan p
  where p.id = s.plan_id and p.facility_id = any(target_facilities) and p.task_definition_id = target_template
    and s.frequency = repeat_frequency and s.starts_on = first_date and s.local_time = any(times);

  for item in select * from jsonb_to_recordset(draft) as rows(
    facility_id uuid, worker_id uuid, existing_id uuid, occurrence timestamptz, starts timestamptz, ends timestamptz
  ) where worker_id is not null loop
    select s.id into strict schedule from public.preventive_schedule s join public.preventive_task_plan p on p.id = s.plan_id
    where p.facility_id = item.facility_id and p.task_definition_id = target_template and s.frequency = repeat_frequency
      and s.starts_on = first_date and s.local_time = (item.occurrence at time zone 'Asia/Kuala_Lumpur')::time;
    if item.existing_id is null then
      insert into public.preventive_work_order(schedule_id, worker_id, occurrence_at, scheduled_for, due_at)
      values (schedule, item.worker_id, item.occurrence, item.starts, item.ends);
    else
      update public.preventive_work_order set schedule_id = schedule, worker_id = item.worker_id,
        scheduled_for = item.starts, due_at = item.ends
      where id = item.existing_id and worker_id is null and cancelled_at is null;
      if not found then raise exception 'An assignment changed. Generate a new draft.' using errcode = '23514'; end if;
    end if;
    approved := approved + 1;
  end loop;
  return to_jsonb(approved);
end;
$$;

create function public.auto_schedule_preventive_range(
  target_facilities uuid[], target_template uuid, repeat_frequency text, first_date date,
  last_date date, times time[], work_minutes integer, reviewed jsonb default null
) returns jsonb language sql security invoker set search_path = '' as $$
  select uni360_private.auto_schedule_range(target_facilities, target_template, repeat_frequency,
    first_date, last_date, times, work_minutes, reviewed);
$$;

revoke all on function uni360_private.assign_preventive_day(date, uuid, jsonb, jsonb, jsonb),
  uni360_private.auto_schedule_range(uuid[], uuid, text, date, date, time[], integer, jsonb),
  public.auto_schedule_preventive_range(uuid[], uuid, text, date, date, time[], integer, jsonb)
  from public, anon, authenticated;
grant execute on function uni360_private.auto_schedule_range(uuid[], uuid, text, date, date, time[], integer, jsonb),
  public.auto_schedule_preventive_range(uuid[], uuid, text, date, date, time[], integer, jsonb)
  to authenticated;

commit;


