begin;

alter table public.preventive_facility add column is_active boolean not null default true;
alter table public.preventive_task_definition
  add column is_active boolean not null default true,
  add column zone_id uuid references public.preventive_zone(id);
create index preventive_task_definition_zone_idx on public.preventive_task_definition(zone_id);

-- A NULL zone makes a task template campus-wide. Existing templates are shared.
drop policy facility_create on public.preventive_facility;
create policy facility_create on public.preventive_facility for insert to authenticated
  with check (uni360_private.preventive_manage_zone(zone_id));
grant update (is_active) on public.preventive_facility to authenticated;

drop policy definition_read on public.preventive_task_definition;
drop policy definition_manage on public.preventive_task_definition;
create policy definition_read on public.preventive_task_definition for select to authenticated
  using (
    (zone_id is null and (select public.can_manage_workforce()))
    or uni360_private.preventive_manage_zone(zone_id)
  );
create policy definition_create on public.preventive_task_definition for insert to authenticated
  with check (uni360_private.preventive_manage_zone(zone_id));
create policy definition_edit on public.preventive_task_definition for update to authenticated
  using (uni360_private.preventive_manage_zone(zone_id))
  with check (uni360_private.preventive_manage_zone(zone_id));
grant update (is_active) on public.preventive_task_definition to authenticated;

-- Facility-specific plans may use shared templates or templates from their own
-- zone. Campus campaigns use shared templates.
create function uni360_private.preventive_validate_plan_template() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if not exists (
    select 1 from public.preventive_task_definition d
    where d.id = new.task_definition_id and (d.zone_id is null or d.zone_id = new.zone_id)
  ) then
    raise exception 'The task template is outside the plan zone.' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger preventive_validate_plan_template
before insert or update of task_definition_id, zone_id on public.preventive_task_plan
for each row execute function uni360_private.preventive_validate_plan_template();

create function uni360_private.preventive_facility_active(target_id uuid) returns boolean
language sql stable security invoker set search_path = '' as $$
  with recursive ancestors as (
    select id, parent_id, is_active from public.preventive_facility where id = target_id
    union all
    select f.id, f.parent_id, f.is_active from public.preventive_facility f join ancestors a on f.id = a.parent_id
  )
  select coalesce(bool_and(is_active), false) from ancestors;
$$;

-- Public invoker wrapper for reporting effective state on the catalog list.
create function public.preventive_facility_is_active(public.preventive_facility) returns boolean
language sql stable security invoker set search_path = '' as $$
  select uni360_private.preventive_facility_active($1.id);
$$;

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
  new.occurrence_at := new.scheduled_for;
  return new;
end;
$$;

revoke all on function uni360_private.preventive_validate_plan_template(),
  uni360_private.preventive_facility_active(uuid),
  public.preventive_facility_is_active(public.preventive_facility) from public, anon, authenticated;
grant execute on function uni360_private.preventive_facility_active(uuid),
  public.preventive_facility_is_active(public.preventive_facility) to authenticated;

commit;
