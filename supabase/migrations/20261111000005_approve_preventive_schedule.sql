begin;

alter table public.preventive_task_definition add column duration_minutes integer not null default 30
  check (duration_minutes between 1 and 720);
alter table public.worker_profile add column daily_work_limit_minutes integer not null default 480
  check (daily_work_limit_minutes between 1 and 1440);
alter table public.preventive_work_completion add column actual_minutes integer
  check (actual_minutes between 1 and 1440);
grant update (duration_minutes) on public.preventive_task_definition to authenticated;
grant update (actual_minutes) on public.preventive_work_completion to authenticated;
create policy completion_record_time on public.preventive_work_completion for update to authenticated
  using (exists (
    select 1 from public.preventive_work_order o
    join public.preventive_schedule s on s.id = o.schedule_id where o.id = work_order_id
  ));

update public.preventive_facility set metadata = metadata || '{"room_type":"toilet"}'
where id = '36000000-0000-4000-8000-000000000013' and facility_type = 'room';

create or replace function uni360_private.preventive_validate_plan_template() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare
  toilet_task boolean;
begin
  select category = 'Toilet Cleaning' or (category = 'Cleaning' and title = 'Toilet Cleaning')
    into toilet_task
  from public.preventive_task_definition
  where id = new.task_definition_id and (zone_id is null or zone_id = new.zone_id);
  if not found then
    raise exception 'The task template is outside the plan zone.' using errcode = '23514';
  end if;
  if toilet_task and not exists (
    select 1 from public.preventive_facility
    where id = new.facility_id and facility_type = 'room' and metadata->>'room_type' = 'toilet'
  ) then
    raise exception 'Toilet cleaning can only be scheduled at toilet rooms.' using errcode = '23514';
  end if;
  return new;
end;
$$;

create function public.save_preventive_template_schedule(
  target_facilities uuid[], target_template uuid, repeat_frequency text, first_date date, last_date date, times time[]
) returns integer language plpgsql security invoker set search_path = '' as $$
declare
  facility uuid;
begin
  if coalesce(cardinality(target_facilities), 0) = 0 then
    raise exception 'Choose at least one facility.' using errcode = '23514';
  end if;
  for facility in select distinct id from unnest(target_facilities) as f(id) order by id loop
    perform public.save_preventive_facility_schedule(facility, target_template, repeat_frequency, first_date, last_date, times);
  end loop;
  return cardinality(target_facilities);
end;
$$;

-- Preserve the recurrence time when an approved task is staggered within a shift.
create or replace function uni360_private.preventive_order_instructions() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare
  target_facility uuid;
begin
  select p.id, p.facility_id, coalesce(p.campaign_name, d.title), d.instructions, d.checklist
    into new.plan_id, target_facility, new.title, new.instructions, new.checklist
  from public.preventive_schedule s
  join public.preventive_task_plan p on p.id = s.plan_id
  join public.preventive_task_definition d on d.id = p.task_definition_id
  where s.id = new.schedule_id and s.is_active and p.is_active and d.is_active;
  if not found then
    raise exception 'Work orders require an active schedule, plan and task template.' using errcode = '23514';
  end if;
  if (target_facility is not null and not uni360_private.preventive_facility_active(target_facility))
     or exists (
       select 1 from public.preventive_campaign_target t
       where t.plan_id = new.plan_id and not uni360_private.preventive_facility_active(t.facility_id)
     ) then
    raise exception 'Work orders require active target facilities.' using errcode = '23514';
  end if;
  new.occurrence_at := coalesce(new.occurrence_at, new.scheduled_for);
  return new;
end;
$$;

create function uni360_private.plan_preventive_day(work_date date, target_zone uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  opens timestamptz := work_date::timestamp at time zone 'Asia/Kuala_Lumpur';
  closes timestamptz := (work_date + 1)::timestamp at time zone 'Asia/Kuala_Lumpur';
  occupied jsonb;
  draft jsonb := '[]'::jsonb;
  item record;
  choice record;
begin
  if not public.can_manage_workforce() or target_zone is null or not uni360_private.preventive_manage_zone(target_zone) then
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
    'completed', c.work_order_id is not null
  )), '[]'::jsonb) into occupied
  from public.preventive_work_order o
  left join public.preventive_work_completion c on c.work_order_id = o.id
  where o.worker_id is not null and o.cancelled_at is null and o.scheduled_for < closes and o.due_at > opens;

  for item in
    with occurrences as (
      select distinct on (p.id, s.local_time) p.id as plan_id, s.id as schedule_id,
        d.title, d.required_job_role, d.required_skill_id, d.duration_minutes, d.id as template_id,
        f.name as facility, f.id as facility_id, z.name as zone_name,
        ((work_date + s.local_time) at time zone 'Asia/Kuala_Lumpur') as occurrence
      from public.preventive_schedule s
      join public.preventive_task_plan p on p.id = s.plan_id
      join public.preventive_task_definition d on d.id = p.task_definition_id
      join public.preventive_facility f on f.id = p.facility_id
      join public.preventive_zone z on z.id = p.zone_id
      where p.zone_id = target_zone and p.is_active and s.is_active and d.is_active
        and uni360_private.preventive_facility_active(f.id)
        and work_date >= s.starts_on and (s.ends_on is null or work_date <= s.ends_on)
        and (s.frequency = 'daily'
          or (s.frequency = 'weekly' and extract(isodow from work_date) = extract(isodow from s.starts_on))
          or (s.frequency = 'monthly' and extract(day from work_date) = extract(day from s.starts_on)))
        and (not (d.category = 'Toilet Cleaning' or (d.category = 'Cleaning' and d.title = 'Toilet Cleaning'))
          or (f.facility_type = 'room' and f.metadata->>'room_type' = 'toilet'))
      order by p.id, s.local_time, s.starts_on desc, s.id
    ), windows as (
      select o.*, lead(o.occurrence, 1, closes) over (partition by o.plan_id order by o.occurrence) as cutoff
      from occurrences o
    )
    select w.*, existing.id as existing_id
    from windows w left join public.preventive_work_order existing
      on existing.plan_id = w.plan_id and existing.occurrence_at = w.occurrence
    where existing.id is null or (existing.worker_id is null and existing.cancelled_at is null)
    order by w.occurrence, w.cutoff, w.duration_minutes desc, w.facility, w.facility_id, w.schedule_id
  loop
    with busy as (
      select * from jsonb_to_recordset(occupied)
        as b(worker uuid, starts timestamptz, ends timestamptz, minutes integer, completed boolean)
    ), candidates as (
      select w.worker_id, a.full_name, a.employee_id, w.current_workload, w.daily_work_limit_minutes,
        coalesce(t.minutes, 0) as booked, coalesce(t.worked, 0) as worked,
        slot.starts, slot.starts + make_interval(mins => item.duration_minutes) as ends
      from public.worker_profile w join public.account a on a.user_id = w.worker_id
      cross join lateral (
        select sum(b.minutes) as minutes, sum(b.minutes) filter (where b.completed) as worked
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
    order by (booked + item.duration_minutes)::numeric / daily_work_limit_minutes,
      current_workload, starts, employee_id, worker_id limit 1;

    draft := draft || jsonb_build_array(jsonb_build_object(
      'schedule_id', item.schedule_id, 'plan_id', item.plan_id, 'existing_id', item.existing_id,
      'title', item.title, 'facility', item.facility, 'occurrence', item.occurrence, 'duration_minutes', item.duration_minutes,
      'worker_id', choice.worker_id, 'worker_name', choice.full_name, 'employee_id', choice.employee_id,
      'starts', choice.starts, 'ends', choice.ends, 'worked_minutes', choice.worked,
      'booked_before', choice.booked, 'work_limit', choice.daily_work_limit_minutes
    ));
    if choice.worker_id is not null then
      occupied := occupied || jsonb_build_array(jsonb_build_object(
        'worker', choice.worker_id, 'starts', choice.starts, 'ends', choice.ends,
        'minutes', item.duration_minutes, 'completed', false
      ));
    end if;
  end loop;
  return draft;
end;
$$;

create function uni360_private.approve_preventive_day(work_date date, target_zone uuid, reviewed jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  current_draft jsonb;
  item record;
  approved integer := 0;
begin
  perform pg_catalog.pg_advisory_xact_lock(360, 2);
  current_draft := uni360_private.plan_preventive_day(work_date, target_zone);
  if reviewed is distinct from current_draft then
    raise exception 'The schedule or staff availability changed. Generate a new draft and review it again.' using errcode = '23514';
  end if;
  for item in select * from jsonb_to_recordset(current_draft) as d(
    schedule_id uuid, worker_id uuid, existing_id uuid, occurrence timestamptz, starts timestamptz, ends timestamptz
  ) where worker_id is not null loop
    if item.existing_id is null then
      insert into public.preventive_work_order (schedule_id, worker_id, occurrence_at, scheduled_for, due_at)
      values (item.schedule_id, item.worker_id, item.occurrence, item.starts, item.ends);
    else
      update public.preventive_work_order set worker_id = item.worker_id, scheduled_for = item.starts, due_at = item.ends
      where id = item.existing_id and worker_id is null and cancelled_at is null;
      if not found then
        raise exception 'An existing work order changed. Generate a new draft.' using errcode = '23514';
      end if;
    end if;
    approved := approved + 1;
  end loop;
  return approved;
end;
$$;

create function public.preview_preventive_day(work_date date, target_zone uuid) returns jsonb
language sql security invoker set search_path = '' as $$
  select uni360_private.plan_preventive_day(work_date, target_zone);
$$;
create function public.approve_preventive_day(work_date date, target_zone uuid, reviewed jsonb) returns integer
language sql security invoker set search_path = '' as $$
  select uni360_private.approve_preventive_day(work_date, target_zone, reviewed);
$$;

revoke all on function public.save_preventive_template_schedule(uuid[], uuid, text, date, date, time[]),
  uni360_private.plan_preventive_day(date, uuid), uni360_private.approve_preventive_day(date, uuid, jsonb),
  public.preview_preventive_day(date, uuid), public.approve_preventive_day(date, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.save_preventive_template_schedule(uuid[], uuid, text, date, date, time[]),
  uni360_private.plan_preventive_day(date, uuid), uni360_private.approve_preventive_day(date, uuid, jsonb),
  public.preview_preventive_day(date, uuid), public.approve_preventive_day(date, uuid, jsonb)
  to authenticated;

commit;
