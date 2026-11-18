begin;

set local lock_timeout = '8s';

-- Keep the existing administrator access boundaries and corrective routing.
-- Facility records themselves no longer store an access zone.
create table uni360_private.facility_access_scope (
  facility_id uuid primary key references public.preventive_facility(id)
    on delete cascade deferrable initially deferred,
  zone_id uuid not null references public.preventive_zone(id),
  unique (facility_id, zone_id)
);
alter table uni360_private.facility_access_scope enable row level security;
revoke all on uni360_private.facility_access_scope from public, anon, authenticated;

insert into uni360_private.facility_access_scope (facility_id, zone_id)
select id, zone_id from public.preventive_facility;

create function uni360_private.facility_access_zone(target uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select zone_id from uni360_private.facility_access_scope where facility_id = target;
$$;

create function uni360_private.new_facility_access_zone(parent uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select case when parent is not null then uni360_private.facility_access_zone(parent)
    else (
      select z.id from public.preventive_zone z
      where (select auth.uid()) is null or uni360_private.preventive_manage_zone(z.id)
      order by (z.name = 'TAR UMT Campus') desc, z.name, z.id
      limit 1
    ) end;
$$;

create function uni360_private.assign_facility_access_scope()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from uni360_private.facility_access_scope where facility_id = new.id) then
    insert into uni360_private.facility_access_scope (facility_id, zone_id)
    values (new.id, uni360_private.new_facility_access_zone(new.parent_id));
  end if;
  return new;
end;
$$;

revoke all on function uni360_private.facility_access_zone(uuid),
  uni360_private.new_facility_access_zone(uuid),
  uni360_private.assign_facility_access_scope() from public, anon, authenticated;
grant execute on function uni360_private.facility_access_zone(uuid),
  uni360_private.new_facility_access_zone(uuid) to authenticated;

alter policy facility_read on public.preventive_facility using (
  uni360_private.preventive_manage_zone(coalesce(
    uni360_private.facility_access_zone(id), uni360_private.new_facility_access_zone(parent_id)
  ))
);
alter policy facility_create on public.preventive_facility with check (
  uni360_private.preventive_manage_zone(uni360_private.new_facility_access_zone(parent_id))
);
alter policy facility_edit on public.preventive_facility
  using (uni360_private.preventive_manage_zone(uni360_private.facility_access_zone(id)))
  with check (
    uni360_private.preventive_manage_zone(uni360_private.facility_access_zone(id))
    and (parent_id is null or uni360_private.preventive_manage_zone(uni360_private.facility_access_zone(parent_id)))
  );

alter policy scope_read on uni360_data.maintenance_scope using (
  case record_kind
    when 'preventive_zone_admin' then (select uni360_private.preventive_super_admin())
      or (administrator_id = (select auth.uid()) and (select public.can_manage_workforce()))
    when 'preventive_campaign_target' then (select uni360_private.preventive_super_admin())
    when 'preventive_work_order_target' then exists (
      select 1 from public.preventive_work_order o where o.id = maintenance_scope.work_order_id
    )
    when 'corrective_site' then uni360_private.corrective_manage(
      uni360_private.facility_access_zone(site_facility_id)
    )
    else false
  end
);

alter table public.corrective_incident
  drop constraint corrective_incident_facility_id_zone_id_fkey,
  add constraint corrective_incident_facility_scope_fkey foreign key (facility_id, zone_id)
    references uni360_private.facility_access_scope(facility_id, zone_id);
alter table public.preventive_task_plan
  drop constraint preventive_task_plan_facility_id_zone_id_fkey,
  add constraint preventive_task_plan_facility_scope_fkey foreign key (facility_id, zone_id)
    references uni360_private.facility_access_scope(facility_id, zone_id) match full;
alter table public.preventive_facility
  drop constraint preventive_facility_parent_id_zone_id_fkey,
  add constraint preventive_facility_parent_id_fkey foreign key (parent_id)
    references public.preventive_facility(id);

-- Recreate the API views with their existing grants and computed relationships.
drop function maintenance_api.preventive_facility_is_active(maintenance_api.preventive_facility);
drop function maintenance_api.worker_skill(maintenance_api.worker_profile);
drop function maintenance_api.worker_certification(maintenance_api.worker_profile);
drop function maintenance_api.worker_availability(maintenance_api.worker_profile);
drop view maintenance_api.preventive_facility;
drop view maintenance_api.worker_profile;
drop function public.workforce_directory(text, integer);
drop function uni360_private.workforce_directory(text, integer);

alter table public.preventive_facility drop column zone_id;
alter table public.worker_profile drop column assigned_zone;

create trigger assign_facility_access_scope
before insert on public.preventive_facility
for each row execute function uni360_private.assign_facility_access_scope();

create view maintenance_api.preventive_facility with (security_invoker = true) as
  select * from public.preventive_facility;
create view maintenance_api.worker_profile with (security_invoker = true) as
  select * from public.worker_profile;

grant select, insert on maintenance_api.preventive_facility to authenticated;
grant update (name, parent_id, facility_type, metadata, is_active)
  on maintenance_api.preventive_facility to authenticated;
grant select, insert, update on maintenance_api.worker_profile to authenticated;
grant all on maintenance_api.preventive_facility, maintenance_api.worker_profile to service_role;

CREATE OR REPLACE FUNCTION maintenance_api.preventive_facility_is_active(maintenance_api.preventive_facility)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select uni360_private.preventive_facility_active($1.id);
$function$;
revoke all on function maintenance_api.preventive_facility_is_active(maintenance_api.preventive_facility) from public, anon, authenticated;
grant execute on function maintenance_api.preventive_facility_is_active(maintenance_api.preventive_facility) to authenticated;

CREATE OR REPLACE FUNCTION maintenance_api.worker_skill(worker maintenance_api.worker_profile)
 RETURNS SETOF maintenance_api.worker_skill
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select t.* from maintenance_api.worker_skill t where t.worker_id = worker.worker_id;
$function$;
revoke all on function maintenance_api.worker_skill(worker maintenance_api.worker_profile) from public, anon, authenticated;
grant execute on function maintenance_api.worker_skill(worker maintenance_api.worker_profile) to authenticated;

CREATE OR REPLACE FUNCTION maintenance_api.worker_certification(worker maintenance_api.worker_profile)
 RETURNS SETOF maintenance_api.worker_certification
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select t.* from maintenance_api.worker_certification t where t.worker_id = worker.worker_id;
$function$;
revoke all on function maintenance_api.worker_certification(worker maintenance_api.worker_profile) from public, anon, authenticated;
grant execute on function maintenance_api.worker_certification(worker maintenance_api.worker_profile) to authenticated;

CREATE OR REPLACE FUNCTION maintenance_api.worker_availability(worker maintenance_api.worker_profile)
 RETURNS SETOF maintenance_api.worker_availability
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select t.* from maintenance_api.worker_availability t where t.worker_id = worker.worker_id;
$function$;
revoke all on function maintenance_api.worker_availability(worker maintenance_api.worker_profile) from public, anon, authenticated;
grant execute on function maintenance_api.worker_availability(worker maintenance_api.worker_profile) to authenticated;


-- Expose only the worker identifiers needed by the workforce screen.
create function uni360_private.workforce_directory(search_text text, start_at integer)
returns table (worker_id uuid, full_name text, employee_id text,
  job_role text, employment_status text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.can_manage_workforce() then
    raise exception 'An active administrator account is required.' using errcode = '42501';
  end if;
  return query
    select w.worker_id, a.full_name, a.employee_id, w.job_role, w.employment_status
    from public.worker_profile w join public.account a on a.user_id = w.worker_id
    where a.role = 'worker' and (
      strpos(lower(a.full_name), lower(left(coalesce(search_text, ''), 120))) > 0 or
      strpos(lower(a.employee_id), lower(left(coalesce(search_text, ''), 120))) > 0
    )
    order by a.full_name, w.worker_id
    limit 26 offset greatest(coalesce(start_at, 0), 0);
end;
$$;

create function public.workforce_directory(search_text text default '', start_at integer default 0)
returns table (worker_id uuid, full_name text, employee_id text,
  job_role text, employment_status text)
language sql stable security invoker set search_path = '' as $$
  select * from uni360_private.workforce_directory(search_text, start_at);
$$;

revoke all on function uni360_private.workforce_directory(text, integer),
  public.workforce_directory(text, integer) from public, anon, authenticated;
grant execute on function uni360_private.workforce_directory(text, integer),
  public.workforce_directory(text, integer) to authenticated;


-- Allow a template to be used at any facility the administrator manages.
create or replace function uni360_private.preventive_validate_plan_template()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if not exists (
    select 1 from maintenance_api.preventive_task_definition d where d.id = new.task_definition_id
  ) then
    raise exception 'The task template is unavailable.' using errcode = '23514';
  end if;
  return new;
end;
$$;

-- Keep a location tree within its administrative scope. A whole subtree
-- can then be read and checked without crossing an administrator boundary.
create or replace function uni360_private.preventive_facility_tree()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(360, 1);
  if new.parent_id is not null and
     uni360_private.facility_access_zone(new.id) is distinct from
       uni360_private.facility_access_zone(new.parent_id) then
    raise exception 'Choose a parent within the same administrative scope.' using errcode = '23514';
  end if;
  if exists (
    with recursive ancestors(id, parent_id) as (
      select id, parent_id from public.preventive_facility where id = new.parent_id
      union
      select f.id, f.parent_id from public.preventive_facility f join ancestors a on f.id = a.parent_id
    )
    select 1 from ancestors where id = new.id
  ) then
    raise exception 'A facility cannot be its own ancestor.' using errcode = '23514';
  end if;
  return new;
end;
$$;

CREATE OR REPLACE FUNCTION public.save_preventive_facility_schedule(target_facility uuid, target_template uuid, repeat_frequency text, first_date date, last_date date, times time without time zone[], replaced_schedule uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  facility_zone uuid;
  target_plan uuid;
  previous public.preventive_schedule%rowtype;
begin
  select uni360_private.facility_access_zone(id) into facility_zone
  from public.preventive_facility where id = target_facility;
  if not found then
    raise exception 'Facility is outside your assigned zones or is unavailable.' using errcode = '42501';
  end if;
  if not uni360_private.preventive_facility_active(target_facility) then
    raise exception 'Choose an active facility.' using errcode = '23514';
  end if;
  if not exists (
    select 1 from maintenance_api.preventive_task_definition
    where id = target_template and is_active
  ) then
    raise exception 'Choose an active task template.' using errcode = '23514';
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
$function$;

CREATE OR REPLACE FUNCTION uni360_private.assign_preventive_day(work_date date, target_zone uuid, requested jsonb, earlier jsonb, prior_load jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  left join maintenance_api.preventive_work_completion c on c.work_order_id = o.id
  where o.worker_id is not null and o.cancelled_at is null and o.scheduled_for < closes and o.due_at > opens;

  -- Hold the same reservation window checked by the work-order write guard.
  -- Corrective reservations affect start times, while booked/worked minutes
  -- remain the Preventive report totals.
  occupied := occupied || (
    select coalesce(jsonb_agg(jsonb_build_object(
      'worker', i.worker_id, 'starts', i.due_at - interval '1 hour', 'ends', i.due_at,
      'minutes', 0, 'completed', false, 'proposed', false
    )), '[]'::jsonb)
    from public.corrective_incident i
    where i.worker_id is not null and i.status in ('assigned','acknowledged','checked_in','in_progress')
      and i.due_at > greatest(now(), opens) and i.due_at - interval '1 hour' < closes
  );

  for item in
    with occurrences as (
      select distinct on (p.id, s.local_time) p.id as plan_id, s.id as schedule_id,
        d.title, d.required_job_role, d.required_skill_id, coalesce(s.duration_minutes, d.duration_minutes) as duration_minutes, d.id as template_id,
        f.name as facility, f.id as facility_id,
        ((work_date + s.local_time) at time zone 'Asia/Kuala_Lumpur') as occurrence
      from public.preventive_schedule s
      join public.preventive_task_plan p on p.id = s.plan_id
      join maintenance_api.preventive_task_definition d on d.id = p.task_definition_id
      join public.preventive_facility f on f.id = p.facility_id
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
          duration_minutes integer, template_id uuid, facility text, facility_id uuid, occurrence timestamptz
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
        from maintenance_api.worker_availability v
        cross join lateral (
          select greatest(v.shift_start, item.occurrence) as start_time
          union
          select b.ends from busy b where b.worker = w.worker_id and b.ends >= greatest(v.shift_start, item.occurrence)
          union
          select u.shift_end from maintenance_api.worker_availability u
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
            select 1 from maintenance_api.worker_availability u
            where u.worker_id = w.worker_id and lower(btrim(u.availability_status)) = 'unavailable'
              and u.shift_start < start_time + make_interval(mins => item.duration_minutes) and u.shift_end > start_time
          )
      ) slot
      where a.is_active and a.role = 'worker' and lower(btrim(w.employment_status)) = 'active'
        and (item.required_job_role is null or lower(btrim(w.job_role)) = lower(btrim(item.required_job_role)))
        and (item.required_skill_id is null or exists (
          select 1 from maintenance_api.worker_skill ws where ws.worker_id = w.worker_id and ws.skill_id = item.required_skill_id
        ))
        and slot.starts is not null
        and coalesce(t.minutes, 0) + item.duration_minutes <= w.daily_work_limit_minutes
        and not exists (
          select 1 from maintenance_api.worker_availability leave_record
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
$function$;

CREATE OR REPLACE FUNCTION uni360_private.auto_schedule_range(target_facilities uuid[], target_template uuid, repeat_frequency text, first_date date, last_date date, times time without time zone[], work_minutes integer, reviewed jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  definition maintenance_api.preventive_task_definition%rowtype;
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

  select * into definition from maintenance_api.preventive_task_definition
  where id = target_template and is_active
    and (zone_id is null or uni360_private.preventive_manage_zone(zone_id));
  if not found then raise exception 'Choose an active task template.' using errcode = '23514'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'facility_id', f.id, 'facility', f.name, 'plan_id', p.id
  )), '[]'::jsonb) into locations
  from public.preventive_facility f
  left join public.preventive_task_plan p on p.facility_id = f.id and p.task_definition_id = target_template
  where f.id = any(target_facilities) and uni360_private.preventive_manage_zone(uni360_private.facility_access_zone(f.id))
    and uni360_private.preventive_facility_active(f.id)
    and (not (definition.category = 'Toilet Cleaning' or (definition.category = 'Cleaning' and definition.title = 'Toilet Cleaning'))
      or (f.facility_type = 'room' and f.metadata->>'room_type' = 'toilet'));
  if jsonb_array_length(locations) <> cardinality(target_facilities) then
    raise exception 'Select active locations you manage that match the task template.' using errcode = '23514';
  end if;

  starts := first_date::timestamp at time zone 'Asia/Kuala_Lumpur';
  ends := (last_date + 1)::timestamp at time zone 'Asia/Kuala_Lumpur';
  select coalesce(jsonb_object_agg(total.worker_id, total.minutes), '{}'::jsonb) into occupied
  from (
    select o.worker_id, sum(coalesce(c.actual_minutes, ceil(extract(epoch from
      (least(o.due_at, ends) - greatest(o.scheduled_for, starts))) / 60)::integer)) as minutes
    from public.preventive_work_order o
    left join maintenance_api.preventive_work_completion c on c.work_order_id = o.id
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
$function$;

CREATE OR REPLACE FUNCTION uni360_private.leave_replacement(target_order uuid, absent_worker uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select w.worker_id
  from public.preventive_work_order o
  join public.preventive_task_plan p on p.id = o.plan_id
  join maintenance_api.preventive_task_definition t on t.id = p.task_definition_id
  cross join public.worker_profile w
  join public.account a on a.user_id = w.worker_id
  cross join lateral (select
    date_trunc('day',o.scheduled_for at time zone 'Asia/Kuala_Lumpur') as local_day,
    ceil(extract(epoch from (o.due_at - o.scheduled_for)) / 60)::integer as minutes
  ) slot
  cross join lateral (select
    slot.local_day at time zone 'Asia/Kuala_Lumpur' as opens,
    (slot.local_day + interval '1 day') at time zone 'Asia/Kuala_Lumpur' as closes
  ) day
  cross join lateral (
    select coalesce(sum(coalesce(c.actual_minutes, ceil(extract(epoch from
      (least(b.due_at, day.closes) - greatest(b.scheduled_for, day.opens))) / 60)::integer)),0) as booked
    from public.preventive_work_order b
    left join maintenance_api.preventive_work_completion c on c.work_order_id = b.id
    where b.worker_id = w.worker_id and b.cancelled_at is null and b.id <> o.id
      and b.scheduled_for < day.closes and b.due_at > day.opens
  ) load
  where o.id = target_order and o.scheduled_for >= now()
    and w.worker_id <> absent_worker and a.is_active and a.role = 'worker'
    and lower(btrim(w.employment_status)) = 'active'
    and (t.required_job_role is null or lower(btrim(w.job_role)) = lower(btrim(t.required_job_role)))
    and (t.required_skill_id is null or exists (
      select 1 from maintenance_api.worker_skill s where s.worker_id = w.worker_id and s.skill_id = t.required_skill_id))
    and exists (select 1 from maintenance_api.worker_availability v
      where v.worker_id = w.worker_id and lower(btrim(v.availability_status)) = 'available'
        and lower(btrim(v.leave_status)) in ('none','rejected')
        and v.shift_start <= o.scheduled_for and v.shift_end >= o.due_at)
    and not exists (select 1 from maintenance_api.worker_availability v where v.worker_id = w.worker_id
      and ((lower(btrim(v.availability_status)) = 'unavailable'
          and v.shift_start < o.due_at and v.shift_end > o.scheduled_for)
        or (lower(btrim(v.leave_status)) = 'approved'
          and v.shift_start < greatest(day.closes,o.due_at) and v.shift_end > day.opens)))
    and not exists (select 1 from public.preventive_work_order b
      where b.worker_id = w.worker_id and b.cancelled_at is null and b.id <> o.id
        and b.scheduled_for < o.due_at and b.due_at > o.scheduled_for)
    and not exists (select 1 from public.corrective_incident i where i.worker_id = w.worker_id
      and i.status in ('assigned','acknowledged','checked_in','in_progress')
      and i.due_at > greatest(now(), o.scheduled_for) and i.due_at - interval '1 hour' < o.due_at)
    and load.booked + slot.minutes <= w.daily_work_limit_minutes
    and o.due_at <= day.closes
  order by load.booked, w.current_workload, a.employee_id, w.worker_id
  limit 1;
$function$;

-- Corrective incidents keep their existing access scope and stored zone.
-- Worker candidates no longer have a zone. Preserve the RPC response shape.

CREATE OR REPLACE FUNCTION uni360_private.corrective_candidates(target uuid, ignore_scheduled_preventive boolean DEFAULT false)
 RETURNS TABLE(worker_id uuid, worker_name text, job_role text, same_zone boolean, standby boolean, workload integer)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select w.worker_id, a.full_name, w.job_role,
    false, w.standby_status,
    w.current_workload + (
      select count(*)::integer from public.preventive_work_order o where o.worker_id = w.worker_id
        and o.cancelled_at is null and o.status in ('assigned','in_progress')
        and o.scheduled_for < now() + interval '1 day' and o.due_at > now()
    )
  from public.corrective_incident i
  cross join public.worker_profile w join public.account a on a.user_id = w.worker_id
  where i.id = target and a.is_active and a.role = 'worker'
    and lower(btrim(w.employment_status)) = 'active'
    and (i.required_role is not null or i.required_skill_id is not null)
    and (i.required_role is null or lower(btrim(w.job_role)) = lower(i.required_role))
    and (i.required_skill_id is null or exists (
      select 1 from maintenance_api.worker_skill ws join public.skill s using (skill_id)
      where ws.worker_id = w.worker_id and s.skill_id = i.required_skill_id
        and (not s.certification_required
          or (ws.verified and ws.certification_no is not null
            and (ws.expiry_date is null or ws.expiry_date >= (now() at time zone 'Asia/Kuala_Lumpur')::date))
          or exists (select 1 from maintenance_api.worker_certification certificate
            where certificate.worker_id = w.worker_id and certificate.verified
              and lower(btrim(certificate.certification_name)) = lower(btrim(s.skill_name))
              and (certificate.expiry_date is null or certificate.expiry_date >= (now() at time zone 'Asia/Kuala_Lumpur')::date)))
    ))
    and exists (
      select 1 from maintenance_api.worker_availability v where v.worker_id = w.worker_id
        and lower(btrim(v.availability_status)) = 'available'
        and lower(btrim(v.leave_status)) in ('none','rejected')
        and v.shift_start <= now() and v.shift_end >= now() + interval '1 hour'
    )
    and not exists (
      select 1 from maintenance_api.worker_availability v where v.worker_id = w.worker_id
        and (lower(btrim(v.availability_status)) = 'unavailable' or lower(btrim(v.leave_status)) = 'approved')
        and v.shift_start < now() + interval '1 hour' and v.shift_end > now()
    )
    and not exists (
      select 1 from public.corrective_incident other where other.worker_id = w.worker_id and other.id <> i.id
        and other.status in ('assigned','acknowledged','checked_in','in_progress','rework')
    )
    and not exists (
      select 1 from public.preventive_work_order o where o.worker_id = w.worker_id and o.cancelled_at is null
        and (o.status = 'in_progress' or (not ignore_scheduled_preventive and o.status = 'assigned'
          and o.scheduled_for < now() + interval '1 hour' and o.due_at > now()))
    )
  order by case when i.urgency in ('High','Critical') then not w.standby_status else w.standby_status end, 6, w.worker_id;
$function$;

CREATE OR REPLACE FUNCTION uni360_private.corrective_catalog()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with recursive locations(id, parent_id, zone_id, label) as (
    select f.id, f.parent_id, uni360_private.facility_access_zone(f.id), f.name::text label
    from public.preventive_facility f where f.parent_id is null
    union all
    select f.id, f.parent_id, uni360_private.facility_access_zone(f.id), l.label || ' / ' || f.name
    from public.preventive_facility f join locations l on l.id = f.parent_id
  )
  select jsonb_build_object(
    'categories', coalesce((select jsonb_agg(to_jsonb(c) order by c.name) from maintenance_api.corrective_category c
      where c.active and uni360_private.corrective_active()), '[]'::jsonb),
    'facilities', coalesce((select jsonb_agg(jsonb_build_object(
      'id', l.id, 'label', l.label, 'zone', z.name, 'can_manage', uni360_private.corrective_manage(l.zone_id)
    ) order by z.name, l.label) from locations l join public.preventive_zone z on z.id = l.zone_id
      where uni360_private.corrective_active()), '[]'::jsonb),
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', s.skill_id, 'label', s.skill_name) order by s.skill_name)
      from public.skill s where public.can_manage_workforce()), '[]'::jsonb),
    'roles', coalesce((select jsonb_agg(r.job_role order by r.job_role) from
      (select distinct lower(btrim(job_role)) job_role from public.worker_profile where job_role is not null) r
      where public.can_manage_workforce()), '[]'::jsonb)
  );
$function$;

CREATE OR REPLACE FUNCTION uni360_private.corrective_admin_options(target uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
          where t.work_order_id = o.id and (uni360_private.facility_access_zone(f.id) <> incident.zone_id or not uni360_private.corrective_manage(uni360_private.facility_access_zone(f.id)))
        )
    ), '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION uni360_private.corrective_report(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  ) select target, f.id, uni360_private.facility_access_zone(f.id), location_label, item_category, btrim(payload->>'title'),
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
$function$;

CREATE OR REPLACE FUNCTION uni360_private.corrective_configure_site(target uuid, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  zone uuid;
  site maintenance_api.corrective_site%rowtype;
begin
  zone := uni360_private.facility_access_zone(target);
  if zone is null or not uni360_private.corrective_manage(zone) then
    raise exception 'This facility is outside your managed zones.' using errcode = '42501';
  end if;
  insert into maintenance_api.corrective_site (facility_id, latitude, longitude, radius_m)
  values (target, (payload->>'latitude')::double precision, (payload->>'longitude')::double precision, (payload->>'radius_m')::integer)
  on conflict (facility_id) do update set latitude = excluded.latitude, longitude = excluded.longitude,
    radius_m = excluded.radius_m,
    qr_token = case when coalesce((payload->>'rotate')::boolean, false) then excluded.qr_token
                    else corrective_site.qr_token end
  returning * into site;
  return to_jsonb(site);
end;
$function$;

notify pgrst, 'reload schema';

commit;
