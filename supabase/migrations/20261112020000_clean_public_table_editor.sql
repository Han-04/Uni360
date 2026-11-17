begin;

set local lock_timeout = '8s';
set local search_path = pg_catalog, pg_temp;

create schema maintenance_api;
revoke all on schema maintenance_api from public, anon, authenticated;
grant usage on schema maintenance_api to authenticated, service_role;

-- These computed relationships are recreated with the new API row types below.
drop function public.preventive_task_definition(public.preventive_task_plan);
drop function public.preventive_work_order_target(public.preventive_work_order);
drop function public.preventive_work_evidence(public.preventive_work_order);
drop function public.preventive_work_completion(public.preventive_work_order);
drop function public.worker_skill(public.worker_profile);
drop function public.skill(public.worker_skill);
drop function public.worker_certification(public.worker_profile);
drop function public.worker_availability(public.worker_profile);

-- Moving the views preserves their definitions, grants, defaults, and the
-- dependencies held by existing table and Storage policies.
alter view public.corrective_category set schema maintenance_api;
alter view public.corrective_deferrable_order set schema maintenance_api;
alter view public.corrective_event set schema maintenance_api;
alter view public.corrective_notification set schema maintenance_api;
alter view public.corrective_photo set schema maintenance_api;
alter view public.corrective_position set schema maintenance_api;
alter view public.corrective_site set schema maintenance_api;
alter view public.corrective_visit set schema maintenance_api;
alter view public.preventive_campaign_target set schema maintenance_api;
alter view public.preventive_task_definition set schema maintenance_api;
alter view public.preventive_work_completion set schema maintenance_api;
alter view public.preventive_work_evidence set schema maintenance_api;
alter view public.preventive_work_order_target set schema maintenance_api;
alter view public.preventive_zone_admin set schema maintenance_api;
alter view public.worker_availability set schema maintenance_api;
alter view public.worker_certification set schema maintenance_api;
alter view public.worker_skill set schema maintenance_api;

-- SQL and PL/pgSQL bodies defined as text still have schema-qualified names.
-- Recreate only functions which refer to one of the moved views.
do $$
declare
  old_reference constant text := '\mpublic\.(corrective_category|corrective_deferrable_order|corrective_event|corrective_notification|corrective_photo|corrective_position|corrective_site|corrective_visit|preventive_campaign_target|preventive_task_definition|preventive_work_completion|preventive_work_evidence|preventive_work_order_target|preventive_zone_admin|worker_availability|worker_certification|worker_skill)\M';
  definition text;
begin
  for definition in
    select pg_get_functiondef(p.oid)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'uni360_private') and p.prokind = 'f'
      and p.prosrc ~ old_reference
  loop
    execute regexp_replace(definition, old_reference, 'maintenance_api.\1', 'g');
  end loop;
end;
$$;

-- PostgREST embeds resolve within the selected API schema. These security
-- invoker views let a request embed both core tables and moved views together.
create view maintenance_api.preventive_facility with (security_invoker = true) as
  select * from public.preventive_facility;
create view maintenance_api.preventive_schedule with (security_invoker = true) as
  select * from public.preventive_schedule;
create view maintenance_api.preventive_task_plan with (security_invoker = true) as
  select * from public.preventive_task_plan;
create view maintenance_api.preventive_work_order with (security_invoker = true) as
  select * from public.preventive_work_order;
create view maintenance_api.preventive_zone with (security_invoker = true) as
  select * from public.preventive_zone;
create view maintenance_api.skill with (security_invoker = true) as
  select * from public.skill;
create view maintenance_api.worker_profile with (security_invoker = true) as
  select * from public.worker_profile;

-- Match the existing table and column grants. The source tables' row policies
-- still decide which records can be read or changed through each view.
do $$
declare
  relation_name text;
  privilege record;
begin
  foreach relation_name in array array['preventive_facility', 'preventive_schedule', 'preventive_task_plan', 'preventive_work_order', 'preventive_zone', 'skill', 'worker_profile']
  loop
    execute format('revoke all on maintenance_api.%I from public, anon, authenticated, service_role', relation_name);
    for privilege in
      with source as (
        select c.oid, c.relowner, c.relacl from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public' and c.relname = relation_name
      )
      select null::name as column_name, a.grantee, a.privilege_type, a.is_grantable
      from source s cross join lateral aclexplode(coalesce(s.relacl, acldefault('r', s.relowner))) a
      where a.grantee in ('authenticated'::regrole, 'service_role'::regrole)
        and a.privilege_type in ('SELECT','INSERT','UPDATE','DELETE')
      union all
      select c.attname, a.grantee, a.privilege_type, a.is_grantable
      from source s join pg_attribute c on c.attrelid = s.oid and c.attnum > 0 and not c.attisdropped
      cross join lateral aclexplode(c.attacl) a
      where a.grantee in ('authenticated'::regrole, 'service_role'::regrole)
        and a.privilege_type in ('SELECT','INSERT','UPDATE')
    loop
      execute format('grant %s%s on maintenance_api.%I to %I%s', privilege.privilege_type,
        case when privilege.column_name is null then '' else format(' (%I)', privilege.column_name) end,
        relation_name, pg_get_userbyid(privilege.grantee),
        case when privilege.is_grantable then ' with grant option' else '' end);
    end loop;
  end loop;
end;
$$;

create function maintenance_api.preventive_task_definition(plan maintenance_api.preventive_task_plan)
returns setof maintenance_api.preventive_task_definition rows 1
language sql stable security invoker set search_path = '' as $$
  select t.* from maintenance_api.preventive_task_definition t where t.id = plan.task_definition_id;
$$;

create function maintenance_api.preventive_schedule(plan maintenance_api.preventive_task_plan)
returns setof maintenance_api.preventive_schedule
language sql stable security invoker set search_path = '' as $$
  select t.* from maintenance_api.preventive_schedule t where t.plan_id = plan.id;
$$;

create function maintenance_api.preventive_task_plan(work maintenance_api.preventive_work_order)
returns setof maintenance_api.preventive_task_plan rows 1
language sql stable security invoker set search_path = '' as $$
  select t.* from maintenance_api.preventive_task_plan t where t.id = work.plan_id;
$$;

create function maintenance_api.preventive_work_order_target(work maintenance_api.preventive_work_order)
returns setof maintenance_api.preventive_work_order_target
language sql stable security invoker set search_path = '' as $$
  select t.* from maintenance_api.preventive_work_order_target t where t.work_order_id = work.id;
$$;

create function maintenance_api.preventive_work_evidence(work maintenance_api.preventive_work_order)
returns setof maintenance_api.preventive_work_evidence
language sql stable security invoker set search_path = '' as $$
  select t.* from maintenance_api.preventive_work_evidence t where t.work_order_id = work.id;
$$;

create function maintenance_api.preventive_work_completion(work maintenance_api.preventive_work_order)
returns setof maintenance_api.preventive_work_completion rows 1
language sql stable security invoker set search_path = '' as $$
  select t.* from maintenance_api.preventive_work_completion t where t.work_order_id = work.id;
$$;

create function maintenance_api.worker_skill(worker maintenance_api.worker_profile)
returns setof maintenance_api.worker_skill
language sql stable security invoker set search_path = '' as $$
  select t.* from maintenance_api.worker_skill t where t.worker_id = worker.worker_id;
$$;

create function maintenance_api.skill(assignment maintenance_api.worker_skill)
returns setof maintenance_api.skill rows 1
language sql stable security invoker set search_path = '' as $$
  select t.* from maintenance_api.skill t where t.skill_id = assignment.skill_id;
$$;

create function maintenance_api.worker_certification(worker maintenance_api.worker_profile)
returns setof maintenance_api.worker_certification
language sql stable security invoker set search_path = '' as $$
  select t.* from maintenance_api.worker_certification t where t.worker_id = worker.worker_id;
$$;

create function maintenance_api.worker_availability(worker maintenance_api.worker_profile)
returns setof maintenance_api.worker_availability
language sql stable security invoker set search_path = '' as $$
  select t.* from maintenance_api.worker_availability t where t.worker_id = worker.worker_id;
$$;

create function maintenance_api.preventive_facility_is_active(maintenance_api.preventive_facility)
returns boolean language sql stable security invoker set search_path = '' as $$
  select uni360_private.preventive_facility_active($1.id);
$$;

revoke all on function
  maintenance_api.preventive_task_definition(maintenance_api.preventive_task_plan),
  maintenance_api.preventive_schedule(maintenance_api.preventive_task_plan),
  maintenance_api.preventive_task_plan(maintenance_api.preventive_work_order),
  maintenance_api.preventive_work_order_target(maintenance_api.preventive_work_order),
  maintenance_api.preventive_work_evidence(maintenance_api.preventive_work_order),
  maintenance_api.preventive_work_completion(maintenance_api.preventive_work_order),
  maintenance_api.worker_skill(maintenance_api.worker_profile),
  maintenance_api.skill(maintenance_api.worker_skill),
  maintenance_api.worker_certification(maintenance_api.worker_profile),
  maintenance_api.worker_availability(maintenance_api.worker_profile),
  maintenance_api.preventive_facility_is_active(maintenance_api.preventive_facility)
  from public, anon, authenticated;
grant execute on function
  maintenance_api.preventive_task_definition(maintenance_api.preventive_task_plan),
  maintenance_api.preventive_schedule(maintenance_api.preventive_task_plan),
  maintenance_api.preventive_task_plan(maintenance_api.preventive_work_order),
  maintenance_api.preventive_work_order_target(maintenance_api.preventive_work_order),
  maintenance_api.preventive_work_evidence(maintenance_api.preventive_work_order),
  maintenance_api.preventive_work_completion(maintenance_api.preventive_work_order),
  maintenance_api.worker_skill(maintenance_api.worker_profile),
  maintenance_api.skill(maintenance_api.worker_skill),
  maintenance_api.worker_certification(maintenance_api.worker_profile),
  maintenance_api.worker_availability(maintenance_api.worker_profile),
  maintenance_api.preventive_facility_is_active(maintenance_api.preventive_facility)
  to authenticated, service_role;

-- Preserve explicitly configured schemas and the hosted Supabase defaults.
-- The new schema exposes the same role-scoped endpoints. Raw storage stays
-- outside the Data API.
do $$
declare
  database_name text := current_database();
  schema_list text;
  setting_database oid;
  this_database oid := (select oid from pg_database where datname = database_name);
begin
  select substr(setting, length('pgrst.db_schemas=') + 1), setdatabase
    into schema_list, setting_database
  from pg_db_role_setting config cross join lateral unnest(config.setconfig) setting
  where config.setrole = 'authenticator'::regrole and config.setdatabase in (0, this_database)
    and setting like 'pgrst.db_schemas=%'
  order by config.setdatabase desc
  limit 1;

  if schema_list is null then
    schema_list := case when to_regnamespace('graphql_public') is null then 'public' else 'public,graphql_public' end;
  end if;
  if 'uni360_data' = any(regexp_split_to_array(schema_list, '\s*,\s*')) then
    raise exception 'The shared maintenance storage must be outside the Data API.';
  end if;
  if not 'maintenance_api' = any(regexp_split_to_array(schema_list, '\s*,\s*')) then
    schema_list := schema_list || ',maintenance_api';
  end if;
  if setting_database = this_database then
    execute format('alter role authenticator in database %I set pgrst.db_schemas = %L', database_name, schema_list);
  else
    execute format('alter role authenticator set pgrst.db_schemas = %L', schema_list);
  end if;
end;
$$;

do $$
declare
  public_entries integer;
  physical_tables integer;
begin
  select count(*) into public_entries
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p','v','m','f');
  select count(*) into physical_tables
  from information_schema.tables
  where table_schema in ('public','uni360_data','uni360_private','maintenance_api') and table_type = 'BASE TABLE';
  if public_entries <> 9 or physical_tables <> 15
    or exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind in ('v','m','f')) then
    raise exception 'Expected 9 public tables and 15 physical application tables, found % public entries and % physical tables.',
      public_entries, physical_tables;
  end if;
  if has_schema_privilege('anon', 'maintenance_api', 'USAGE')
    or has_schema_privilege('anon', 'uni360_data', 'USAGE')
    or not has_schema_privilege('authenticated', 'maintenance_api', 'USAGE') then
    raise exception 'The API schema privileges are incorrect.';
  end if;
end;
$$;

notify pgrst, 'reload config';
notify pgrst, 'reload schema';

commit;

select count(*) filter (where table_schema = 'public') as public_table_editor_entries,
  count(*) filter (where table_type = 'BASE TABLE') as application_tables,
  count(*) filter (where table_schema = 'public' and table_type <> 'BASE TABLE') as public_views
from information_schema.tables
where table_schema in ('public','uni360_data','uni360_private','maintenance_api');
