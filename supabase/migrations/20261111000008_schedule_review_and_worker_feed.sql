begin;

create function uni360_private.preventive_facility_path(target_id uuid) returns text
language sql stable security invoker set search_path = '' as $$
  with recursive parents(id, parent_id, name, depth) as (
    select id, parent_id, name, 0 from public.preventive_facility where id = target_id
    union all
    select f.id, f.parent_id, f.name, p.depth + 1
      from public.preventive_facility f join parents p on f.id = p.parent_id
  )
  select string_agg(name, ' / ' order by depth desc) from parents;
$$;
revoke all on function uni360_private.preventive_facility_path(uuid) from public, anon, authenticated;

alter table public.preventive_work_order_target add column facility_path text;
update public.preventive_work_order_target
  set facility_path = coalesce(uni360_private.preventive_facility_path(facility_id), facility_name);
alter table public.preventive_work_order_target alter column facility_path set not null;

create or replace function uni360_private.preventive_snapshot_targets() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.preventive_work_order_target (work_order_id, facility_id, facility_name, facility_path)
    select new.id, f.id, f.name, uni360_private.preventive_facility_path(f.id)
    from public.preventive_schedule s
    join public.preventive_task_plan p on p.id = s.plan_id
    join public.preventive_facility f on f.id = p.facility_id or f.id in (
      select t.facility_id from public.preventive_campaign_target t where t.plan_id = p.id
    )
    where s.id = new.schedule_id;
  if not found then
    raise exception 'A work order requires at least one target facility.' using errcode = '23514';
  end if;
  return new;
end;
$$;

alter policy order_worker_read on public.preventive_work_order
  using (cancelled_at is null and public.can_read_own_workforce(worker_id));

-- Only called after the scheduler has validated the actor and locations.
create function uni360_private.preventive_schedule_warnings(
  requested jsonb, target_facilities uuid[], target_template uuid,
  repeat_frequency text, first_date date, last_date date
) returns jsonb language sql stable security invoker set search_path = '' as $$
  with selected_days as (
    select p.id as plan_id, first_date + days.offset_days as work_date
    from public.preventive_task_plan p
    cross join generate_series(0, last_date - first_date) as days(offset_days)
    where target_facilities is not null and p.facility_id = any(target_facilities)
      and p.task_definition_id = target_template and p.is_active
      and extract(isodow from first_date + days.offset_days) <> 7
      and (repeat_frequency = 'daily' or (repeat_frequency = 'weekly' and mod(days.offset_days, 7) = 0)
        or (repeat_frequency = 'monthly' and extract(day from first_date + days.offset_days) = extract(day from first_date)))
  ), draft_days as (
    select distinct x.plan_id, (x.occurrence at time zone 'Asia/Kuala_Lumpur')::date as work_date
    from jsonb_to_recordset(requested) as x(plan_id uuid, occurrence timestamptz)
    where target_facilities is null
  ), warnings as (
    select d.plan_id, d.work_date, s.local_time as slot_time, 'Saved schedule'::text as source
    from selected_days d join public.preventive_schedule s on s.plan_id = d.plan_id
    where s.is_active and s.starts_on <= d.work_date and (s.ends_on is null or s.ends_on >= d.work_date)
      and (s.frequency = 'daily' or (s.frequency = 'weekly' and mod(d.work_date - s.starts_on, 7) = 0)
        or (s.frequency = 'monthly' and extract(day from d.work_date) = extract(day from s.starts_on)))
    union
    select d.plan_id, d.work_date, (o.scheduled_for at time zone 'Asia/Kuala_Lumpur')::time, 'Work order'
    from (select * from selected_days union select * from draft_days) d
    join public.preventive_work_order o on o.plan_id = d.plan_id and o.cancelled_at is null
      and o.scheduled_for >= (d.work_date::timestamp at time zone 'Asia/Kuala_Lumpur')
      and o.scheduled_for < ((d.work_date + 1)::timestamp at time zone 'Asia/Kuala_Lumpur')
    where target_facilities is not null or not exists (
      select 1 from jsonb_to_recordset(requested) as r(existing_id uuid) where r.existing_id = o.id
    )
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'date', w.work_date, 'task', d.title, 'location', uni360_private.preventive_facility_path(p.facility_id),
    'time', w.slot_time, 'source', w.source
  ) order by w.work_date, p.facility_id, w.plan_id, w.slot_time, w.source), '[]'::jsonb)
  from warnings w
  join public.preventive_task_plan p on p.id = w.plan_id
  join public.preventive_task_definition d on d.id = p.task_definition_id;
$$;

create function uni360_private.require_schedule_verification(warnings jsonb, verified jsonb) returns void
language plpgsql security invoker set search_path = '' as $$
begin
  if warnings <> '[]'::jsonb and warnings is distinct from verified then
    raise exception 'Verify the existing tasks at these locations and dates before approving. If the schedule changed, generate a new draft.'
      using errcode = '23514';
  end if;
end;
$$;

create function uni360_private.review_preventive_range(
  target_facilities uuid[], target_template uuid, repeat_frequency text, first_date date,
  last_date date, times time[], work_minutes integer, reviewed jsonb, verified jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  rows jsonb;
  warnings jsonb;
begin
  if reviewed is not null then perform pg_catalog.pg_advisory_xact_lock(360, 2); end if;
  rows := uni360_private.auto_schedule_range(target_facilities, target_template, repeat_frequency,
    first_date, last_date, times, work_minutes, null);
  warnings := uni360_private.preventive_schedule_warnings(rows, target_facilities, target_template,
    repeat_frequency, first_date, last_date);
  if reviewed is null then return jsonb_build_object('rows', rows, 'warnings', warnings); end if;
  perform uni360_private.require_schedule_verification(warnings, verified);
  return uni360_private.auto_schedule_range(target_facilities, target_template, repeat_frequency,
    first_date, last_date, times, work_minutes, reviewed);
end;
$$;

create function uni360_private.review_preventive_day(work_date date, target_zone uuid, reviewed jsonb, verified jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  rows jsonb;
  warnings jsonb;
begin
  if reviewed is not null then perform pg_catalog.pg_advisory_xact_lock(360, 2); end if;
  rows := uni360_private.plan_preventive_day(work_date, target_zone);
  warnings := uni360_private.preventive_schedule_warnings(rows, null, null, null, null, null);
  if reviewed is null then return jsonb_build_object('rows', rows, 'warnings', warnings); end if;
  perform uni360_private.require_schedule_verification(warnings, verified);
  return to_jsonb(uni360_private.approve_preventive_day(work_date, target_zone, reviewed));
end;
$$;

create function public.review_preventive_range(
  target_facilities uuid[], target_template uuid, repeat_frequency text, first_date date,
  last_date date, times time[], work_minutes integer, reviewed jsonb default null, verified jsonb default null
) returns jsonb language sql security invoker set search_path = '' as $$
  select uni360_private.review_preventive_range(target_facilities, target_template, repeat_frequency,
    first_date, last_date, times, work_minutes, reviewed, verified);
$$;

create function public.review_preventive_day(
  work_date date, target_zone uuid, reviewed jsonb default null, verified jsonb default null
) returns jsonb language sql security invoker set search_path = '' as $$
  select uni360_private.review_preventive_day(work_date, target_zone, reviewed, verified);
$$;

revoke execute on function public.approve_preventive_day(date, uuid, jsonb),
  uni360_private.approve_preventive_day(date, uuid, jsonb),
  public.auto_schedule_preventive_range(uuid[], uuid, text, date, date, time[], integer, jsonb),
  uni360_private.auto_schedule_range(uuid[], uuid, text, date, date, time[], integer, jsonb)
  from authenticated;
revoke all on function uni360_private.preventive_schedule_warnings(jsonb, uuid[], uuid, text, date, date),
  uni360_private.require_schedule_verification(jsonb, jsonb),
  uni360_private.review_preventive_range(uuid[], uuid, text, date, date, time[], integer, jsonb, jsonb),
  public.review_preventive_range(uuid[], uuid, text, date, date, time[], integer, jsonb, jsonb),
  uni360_private.review_preventive_day(date, uuid, jsonb, jsonb),
  public.review_preventive_day(date, uuid, jsonb, jsonb) from public, anon, authenticated;
grant execute on function
  uni360_private.review_preventive_range(uuid[], uuid, text, date, date, time[], integer, jsonb, jsonb),
  public.review_preventive_range(uuid[], uuid, text, date, date, time[], integer, jsonb, jsonb),
  uni360_private.review_preventive_day(date, uuid, jsonb, jsonb),
  public.review_preventive_day(date, uuid, jsonb, jsonb) to authenticated;

commit;
