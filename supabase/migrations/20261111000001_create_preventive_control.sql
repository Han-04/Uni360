begin;

create table public.preventive_zone (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (btrim(name) <> '')
);

create table public.preventive_zone_admin (
  zone_id uuid not null references public.preventive_zone(id),
  administrator_id uuid not null,
  account_role public.account_role generated always as ('administrator'::public.account_role) stored,
  foreign key (administrator_id, account_role) references public.account(user_id, role),
  primary key (zone_id, administrator_id)
);

create table public.preventive_facility (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid not null references public.preventive_zone(id),
  parent_id uuid,
  name text not null check (btrim(name) <> ''),
  facility_type text not null check (facility_type in ('building', 'floor', 'room', 'outdoor_area', 'asset', 'other')),
  metadata jsonb not null default '{}' check (jsonb_typeof(metadata) = 'object'),
  unique (id, zone_id),
  foreign key (parent_id, zone_id) references public.preventive_facility(id, zone_id),
  check (parent_id is distinct from id)
);
create index preventive_facility_parent_idx on public.preventive_facility(parent_id);

create table public.preventive_task_definition (
  id uuid primary key default gen_random_uuid(),
  title text not null check (btrim(title) <> ''),
  instructions text not null check (btrim(instructions) <> ''),
  category text not null check (btrim(category) <> ''),
  required_job_role text check (btrim(required_job_role) <> ''),
  required_skill_id uuid references public.skill(skill_id),
  checklist text[] not null default '{}'
);

-- A facility plan applies a reusable template at one location. A campaign
-- plan gets its locations from preventive_campaign_target.
create table public.preventive_task_plan (
  id uuid primary key default gen_random_uuid(),
  task_definition_id uuid not null references public.preventive_task_definition(id),
  facility_id uuid,
  zone_id uuid,
  campaign_name text check (btrim(campaign_name) <> ''),
  is_active boolean not null default true,
  foreign key (facility_id, zone_id) references public.preventive_facility(id, zone_id) match full,
  check ((facility_id is null) = (campaign_name is not null)),
  unique (facility_id, task_definition_id)
);

create table public.preventive_campaign_target (
  plan_id uuid not null references public.preventive_task_plan(id),
  facility_id uuid not null references public.preventive_facility(id),
  primary key (plan_id, facility_id)
);

-- Multiple daily slots model twice-daily work. Weekly and monthly rules
-- use the weekday or day of month from starts_on.
create table public.preventive_schedule (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.preventive_task_plan(id),
  frequency text not null check (frequency in ('daily', 'weekly', 'monthly')),
  starts_on date not null,
  ends_on date check (ends_on >= starts_on),
  local_time time not null check (local_time < time '24:00'),
  is_active boolean not null default true,
  unique (plan_id, frequency, starts_on, local_time)
);

create table public.preventive_work_order (
  id uuid primary key default gen_random_uuid(),
  schedule_id uuid not null references public.preventive_schedule(id),
  plan_id uuid not null references public.preventive_task_plan(id),
  worker_id uuid references public.worker_profile(worker_id),
  occurrence_at timestamptz not null,
  scheduled_for timestamptz not null,
  due_at timestamptz not null check (due_at > scheduled_for),
  cancelled_at timestamptz,
  title text not null,
  instructions text not null,
  checklist text[] not null,
  unique (plan_id, occurrence_at)
);
create index preventive_work_order_worker_idx on public.preventive_work_order(worker_id, scheduled_for);

create table public.preventive_work_order_target (
  work_order_id uuid not null references public.preventive_work_order(id),
  facility_id uuid not null references public.preventive_facility(id),
  facility_name text not null,
  primary key (work_order_id, facility_id)
);

-- A completion is a separate record so workers cannot change assignment,
-- instructions, or scheduling fields.
create table public.preventive_work_completion (
  work_order_id uuid primary key references public.preventive_work_order(id),
  worker_id uuid not null default auth.uid() references public.worker_profile(worker_id),
  completed_at timestamptz not null default now(),
  notes text not null default '',
  photo_path text check (btrim(photo_path) <> '')
);

create function uni360_private.preventive_super_admin() returns boolean
language sql stable security invoker set search_path = '' as $$
  select exists (select 1 from public.account where user_id = (select auth.uid())
    and is_active and role = 'super_administrator');
$$;

create function uni360_private.preventive_manage_zone(target_zone uuid) returns boolean
language sql stable security invoker set search_path = '' as $$
  select (select uni360_private.preventive_super_admin()) or exists (
    select 1 from public.preventive_zone_admin
    where zone_id = target_zone and administrator_id = (select auth.uid())
  );
$$;

create function uni360_private.preventive_facility_tree() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(360, 1);
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
create trigger preventive_facility_tree
before insert or update of parent_id on public.preventive_facility
for each row execute function uni360_private.preventive_facility_tree();

create function uni360_private.preventive_order_instructions() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  select p.id, coalesce(p.campaign_name, d.title), d.instructions, d.checklist
    into strict new.plan_id, new.title, new.instructions, new.checklist
  from public.preventive_schedule s
  join public.preventive_task_plan p on p.id = s.plan_id
  join public.preventive_task_definition d on d.id = p.task_definition_id
  where s.id = new.schedule_id and s.is_active and p.is_active;
  new.occurrence_at := new.scheduled_for;
  return new;
end;
$$;
create trigger preventive_order_instructions
before insert on public.preventive_work_order
for each row execute function uni360_private.preventive_order_instructions();

create function uni360_private.preventive_snapshot_targets() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.preventive_work_order_target (work_order_id, facility_id, facility_name)
    select new.id, f.id, f.name
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
create trigger preventive_snapshot_targets
after insert on public.preventive_work_order
for each row execute function uni360_private.preventive_snapshot_targets();

create function uni360_private.preventive_validate_completion() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- Serialize completion with cancellation or reassignment.
  perform 1 from public.preventive_work_order
    where id = new.work_order_id and worker_id = new.worker_id and cancelled_at is null
    for update;
  if not found then
    raise exception 'This work order is not assigned to this worker or has been cancelled.' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger preventive_validate_completion
before insert on public.preventive_work_completion
for each row execute function uni360_private.preventive_validate_completion();

create function uni360_private.preventive_lock_completed_order() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if exists (select 1 from public.preventive_work_completion where work_order_id = old.id) then
    raise exception 'A completed work order cannot be changed.' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger preventive_lock_completed_order
before update on public.preventive_work_order
for each row execute function uni360_private.preventive_lock_completed_order();

revoke all on function uni360_private.preventive_super_admin(), uni360_private.preventive_manage_zone(uuid),
  uni360_private.preventive_facility_tree(), uni360_private.preventive_order_instructions(),
  uni360_private.preventive_snapshot_targets(), uni360_private.preventive_validate_completion(),
  uni360_private.preventive_lock_completed_order() from public, anon, authenticated;
grant execute on function uni360_private.preventive_super_admin(), uni360_private.preventive_manage_zone(uuid) to authenticated;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'preventive_zone', 'preventive_zone_admin', 'preventive_facility', 'preventive_task_definition',
    'preventive_task_plan', 'preventive_campaign_target', 'preventive_schedule',
    'preventive_work_order', 'preventive_work_order_target', 'preventive_work_completion'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from public, anon, authenticated', table_name);
    execute format('grant select on table public.%I to authenticated', table_name);
  end loop;
end;
$$;

grant insert, update (name) on public.preventive_zone to authenticated;
grant insert, delete on public.preventive_zone_admin to authenticated;
grant insert, update (parent_id, name, facility_type, metadata) on public.preventive_facility to authenticated;
grant insert, update (title, instructions, category, required_job_role, required_skill_id, checklist)
  on public.preventive_task_definition to authenticated;
grant insert, update (campaign_name, is_active) on public.preventive_task_plan to authenticated;
grant insert, delete on public.preventive_campaign_target to authenticated;
grant insert, update (frequency, starts_on, ends_on, local_time, is_active) on public.preventive_schedule to authenticated;
grant insert (schedule_id, worker_id, scheduled_for, due_at), update (worker_id, scheduled_for, due_at, cancelled_at)
  on public.preventive_work_order to authenticated;
grant insert (work_order_id, notes, photo_path) on public.preventive_work_completion to authenticated;

create policy zone_read on public.preventive_zone for select to authenticated
  using (uni360_private.preventive_manage_zone(id));
create policy zone_manage on public.preventive_zone for all to authenticated
  using ((select uni360_private.preventive_super_admin())) with check ((select uni360_private.preventive_super_admin()));
create policy zone_admin_read on public.preventive_zone_admin for select to authenticated
  using (administrator_id = (select auth.uid()) and (select public.can_manage_workforce()));
create policy zone_admin_manage on public.preventive_zone_admin for all to authenticated
  using ((select uni360_private.preventive_super_admin())) with check ((select uni360_private.preventive_super_admin()));
create policy facility_read on public.preventive_facility for select to authenticated
  using (uni360_private.preventive_manage_zone(zone_id));
create policy facility_create on public.preventive_facility for insert to authenticated
  with check ((select uni360_private.preventive_super_admin()));
create policy facility_edit on public.preventive_facility for update to authenticated
  using (uni360_private.preventive_manage_zone(zone_id)) with check (uni360_private.preventive_manage_zone(zone_id));
create policy definition_read on public.preventive_task_definition for select to authenticated
  using ((select public.can_manage_workforce()));
create policy definition_manage on public.preventive_task_definition for all to authenticated
  using ((select uni360_private.preventive_super_admin())) with check ((select uni360_private.preventive_super_admin()));
create policy plan_manage on public.preventive_task_plan for all to authenticated
  using (uni360_private.preventive_manage_zone(zone_id)) with check (uni360_private.preventive_manage_zone(zone_id));
create policy campaign_target_manage on public.preventive_campaign_target for all to authenticated
  using ((select uni360_private.preventive_super_admin())) with check (
    (select uni360_private.preventive_super_admin()) and exists (
      select 1 from public.preventive_task_plan p where p.id = plan_id and p.facility_id is null
    )
  );
create policy schedule_manage on public.preventive_schedule for all to authenticated
  using (exists (select 1 from public.preventive_task_plan p where p.id = plan_id))
  with check (exists (select 1 from public.preventive_task_plan p where p.id = plan_id));
create policy order_manage on public.preventive_work_order for all to authenticated
  using (exists (select 1 from public.preventive_schedule s where s.id = schedule_id))
  with check (exists (select 1 from public.preventive_schedule s where s.id = schedule_id));
create policy order_worker_read on public.preventive_work_order for select to authenticated
  using (public.can_read_own_workforce(worker_id));
create policy order_target_read on public.preventive_work_order_target for select to authenticated
  using (exists (select 1 from public.preventive_work_order o where o.id = work_order_id));
create policy completion_read on public.preventive_work_completion for select to authenticated
  using (exists (select 1 from public.preventive_work_order o where o.id = work_order_id));
create policy completion_submit on public.preventive_work_completion for insert to authenticated
  with check (public.can_read_own_workforce(worker_id) and exists (
    select 1 from public.preventive_work_order o
    where o.id = work_order_id and o.worker_id = (select auth.uid()) and o.cancelled_at is null
  ));

commit;
