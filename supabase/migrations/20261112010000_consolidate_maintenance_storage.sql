begin;

set local search_path = pg_catalog, pg_temp;
set local lock_timeout = '8s';

-- The API views keep existing Flutter and portal deployments compatible.
-- The new storage schema is outside the Supabase Data API's exposed schemas.
create schema uni360_data;
revoke all on schema uni360_data from public, anon, authenticated;
grant usage on schema uni360_data to authenticated, service_role;

create temporary table _maintenance_sources (
  source_schema text not null,
  source_name text primary key,
  storage_name text not null,
  aliases jsonb not null default '{}',
  relation oid
) on commit drop;

insert into _maintenance_sources(source_schema, source_name, storage_name, aliases) values
  ('public','worker_skill','maintenance_workforce','{}'),
  ('public','worker_certification','maintenance_workforce','{}'),
  ('public','worker_availability','maintenance_workforce','{}'),
  ('public','preventive_zone_admin','maintenance_scope','{}'),
  ('public','preventive_campaign_target','maintenance_scope','{}'),
  ('public','preventive_work_order_target','maintenance_scope','{}'),
  ('public','corrective_site','maintenance_scope','{"facility_id":"site_facility_id"}'),
  ('public','corrective_deferrable_order','maintenance_scope','{}'),
  ('public','corrective_visit','maintenance_execution','{}'),
  ('public','corrective_position','maintenance_execution','{"incident_id":"position_incident_id","attempt":"position_attempt"}'),
  ('public','preventive_work_completion','maintenance_execution','{}'),
  ('public','corrective_photo','maintenance_evidence','{"path":"corrective_path"}'),
  ('public','preventive_work_evidence','maintenance_evidence','{}'),
  ('public','corrective_event','maintenance_activity','{"id":"event_id"}'),
  ('public','corrective_notification','maintenance_activity','{"id":"notification_id"}'),
  ('public','corrective_category','maintenance_template','{}'),
  ('public','preventive_task_definition','maintenance_template','{}'),
  ('uni360_private','corrective_training_example','maintenance_template','{"category":"example_category","description":"example_description"}');

update _maintenance_sources
set relation = to_regclass(format('%I.%I', source_schema, source_name));

do $$
declare
  missing text;
  sources text;
begin
  select string_agg(s.source_name, ', ') into missing
  from _maintenance_sources s left join pg_class c on c.oid = s.relation
  where c.relkind is distinct from 'r';
  if missing is not null then
    raise exception 'Apply the previous Uni360 migrations before consolidating. Missing base tables: %', missing;
  end if;

  select string_agg(format('%I.%I', source_schema, source_name), ', ' order by source_schema, source_name)
    into sources from _maintenance_sources;
  execute 'lock table ' || sources || ' in access exclusive mode';
end;
$$;

create temporary table _maintenance_columns on commit drop as
select s.relation, s.source_name, s.storage_name, a.attnum, a.attname::text as source_column,
  coalesce(s.aliases->>a.attname, a.attname) as storage_column,
  format_type(a.atttypid, a.atttypmod) as data_type, a.attnotnull, a.attidentity,
  pg_get_expr(d.adbin, d.adrelid) as default_expr
from _maintenance_sources s
join pg_attribute a on a.attrelid = s.relation and a.attnum > 0 and not a.attisdropped
left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum;

create function pg_temp.maintenance_columns(target oid, keys smallint[]) returns text
language sql stable set search_path = pg_catalog, pg_temp as $$
  select string_agg(quote_ident(coalesce(m.storage_column, a.attname)), ', ' order by k.ordinality)
  from unnest(keys) with ordinality k(attnum, ordinality)
  join pg_attribute a on a.attrelid = target and a.attnum = k.attnum
  left join _maintenance_columns m on m.relation = target and m.attnum = k.attnum;
$$;

create function pg_temp.maintenance_relation(target oid) returns text
language sql stable set search_path = pg_catalog, pg_temp as $$
  select format('%I.%I', 'uni360_data', m.storage_name)
  from _maintenance_sources m where m.relation = target;
$$;

-- Policies on tables which stay in place can have an OID dependency on an old
-- table. Rebind these to the corresponding view with the original expression.
create temporary table _maintenance_external_policies on commit drop as
select p.polname, n.nspname as schema_name, c.relname as relation_name, p.polcmd, p.polpermissive,
  pg_get_expr(p.polqual, p.polrelid) as using_expr, pg_get_expr(p.polwithcheck, p.polrelid) as check_expr,
  (select string_agg(case when r = 0 then 'PUBLIC' else quote_ident(pg_get_userbyid(r)) end, ', ')
    from unnest(p.polroles) r) as roles
from pg_policy p join pg_class c on c.oid = p.polrelid join pg_namespace n on n.oid = c.relnamespace
where not exists (select 1 from _maintenance_sources s where s.relation = p.polrelid)
  and exists (
    select 1 from pg_depend d join _maintenance_sources s on s.relation = d.refobjid
    where d.classid = 'pg_policy'::regclass and d.objid = p.oid and d.refclassid = 'pg_class'::regclass
  );

create temporary table _maintenance_keys on commit drop as
select x.conname, x.conrelid, x.confrelid, x.contype, x.conkey, x.confkey,
  x.confmatchtype, x.confupdtype, x.confdeltype, x.condeferrable, x.condeferred, x.convalidated,
  pg_get_expr(x.conbin, x.conrelid) as check_expr,
  format('%I.%I', ns.nspname, cl.relname) as original_relation
from pg_constraint x join pg_class cl on cl.oid = x.conrelid join pg_namespace ns on ns.oid = cl.relnamespace
where (x.contype in ('p','u','c','f') and exists (
  select 1 from _maintenance_sources s where s.relation = x.conrelid
)) or (x.contype = 'f' and exists (
  select 1 from _maintenance_sources s where s.relation = x.confrelid
));

create temporary table _maintenance_grants on commit drop as
select s.source_schema, s.source_name, null::text as source_column, acl.grantee, acl.privilege_type, acl.is_grantable
from _maintenance_sources s join pg_class c on c.oid = s.relation
cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
where acl.grantee <> c.relowner and acl.privilege_type in ('SELECT','INSERT','UPDATE','DELETE')
union all
select s.source_schema, s.source_name, a.attname, acl.grantee, acl.privilege_type, acl.is_grantable
from _maintenance_sources s join pg_attribute a on a.attrelid = s.relation and a.attnum > 0 and not a.attisdropped
join pg_class c on c.oid = s.relation
cross join lateral aclexplode(a.attacl) acl
where acl.grantee <> c.relowner and acl.privilege_type in ('SELECT','INSERT','UPDATE');

create sequence uni360_data.maintenance_event_id_seq;
create sequence uni360_data.maintenance_notification_id_seq;

-- A discriminator plus CHECK constraints retain each row type's required
-- fields. The views supply the discriminator and the original SQL defaults.
do $$
declare
  group_name text;
  source record;
  column_info record;
  key_info record;
  definitions text;
  permitted_fields text;
  required_fields text;
  projected text;
  destination_columns text;
  original_columns text;
  predicate text;
  default_value text;
  old_sequence text;
  last_number bigint;
  sequence_called boolean;
  new_sequence text;
begin
  for group_name in select distinct storage_name from _maintenance_sources order by storage_name loop
    if exists (
      select 1 from _maintenance_columns where storage_name = group_name
      group by storage_column having count(distinct data_type) > 1
    ) then
      raise exception 'Incompatible shared column types in %.', group_name;
    end if;

    select string_agg(format('%I %s', storage_column, data_type), ', ' order by storage_column)
      into definitions
    from (select distinct storage_column, data_type from _maintenance_columns where storage_name = group_name) fields;

    execute format('create table uni360_data.%I (
      storage_id bigint generated always as identity primary key,
      record_kind text not null, %s
    )', group_name, definitions);
    execute format('alter table uni360_data.%I enable row level security', group_name);
    execute format('revoke all on uni360_data.%I from public, anon, authenticated, service_role', group_name);
    execute format('grant select, insert, update, delete on uni360_data.%I to authenticated, service_role', group_name);
  end loop;

  for source in select * from _maintenance_sources order by source_schema, source_name loop
    select string_agg(format('%I is not null', storage_column), ' and ' order by attnum)
      into required_fields from _maintenance_columns where relation = source.relation and attnotnull;
    select string_agg(format('%I is null', field), ' and ' order by field) into permitted_fields
    from (
      select distinct storage_column as field from _maintenance_columns where storage_name = source.storage_name
      except select storage_column from _maintenance_columns where relation = source.relation
    ) remaining;
    execute format('alter table uni360_data.%I add constraint %I check (
      record_kind <> %L or (%s and %s))', source.storage_name, 'shape_' || source.source_name,
      source.source_name, coalesce(required_fields, 'true'), coalesce(permitted_fields, 'true'));

    for key_info in select * from _maintenance_keys where conrelid = source.relation and contype in ('p','u','c') loop
      if key_info.contype = 'c' then
        predicate := key_info.check_expr;
        for column_info in select source_column, storage_column from _maintenance_columns
          where relation = source.relation and source_column <> storage_column loop
          predicate := regexp_replace(predicate, '\m' || column_info.source_column || '\M', column_info.storage_column, 'g');
        end loop;
        execute format('alter table uni360_data.%I add constraint %I check (record_kind <> %L or (%s))',
          source.storage_name, key_info.conname, source.source_name, predicate);
      else
        execute format('alter table uni360_data.%I add constraint %I unique (%s)',
          source.storage_name, key_info.conname, pg_temp.maintenance_columns(source.relation, key_info.conkey));
      end if;
    end loop;

    select string_agg(quote_ident(storage_column), ', ' order by attnum),
      string_agg(quote_ident(source_column), ', ' order by attnum),
      string_agg(format('%I as %I', storage_column, source_column), ', ' order by attnum)
    into destination_columns, original_columns, projected
    from _maintenance_columns where relation = source.relation;

    execute format('insert into uni360_data.%I (record_kind, %s) select %L, %s from %I.%I',
      source.storage_name, destination_columns, source.source_name, original_columns, source.source_schema, source.source_name);

    execute format('alter table %I.%I rename to %I', source.source_schema, source.source_name,
      '_before_' || source.source_name);
    execute format('create view %I.%I with (security_invoker = true) as
      select %s, record_kind from uni360_data.%I where record_kind = %L with local check option',
      source.source_schema, source.source_name, projected, source.storage_name, source.source_name);
    execute format('alter view %I.%I alter column record_kind set default %L',
      source.source_schema, source.source_name, source.source_name);
    execute format('revoke all on %I.%I from public, anon, authenticated, service_role',
      source.source_schema, source.source_name);

    for column_info in select * from _maintenance_columns where relation = source.relation
      and (default_expr is not null or attidentity <> '') loop
      default_value := column_info.default_expr;
      if column_info.attidentity <> '' then
        old_sequence := pg_get_serial_sequence(format('%I.%I', source.source_schema, '_before_' || source.source_name),
          column_info.source_column);
        new_sequence := case source.source_name
          when 'corrective_event' then 'uni360_data.maintenance_event_id_seq'
          when 'corrective_notification' then 'uni360_data.maintenance_notification_id_seq' end;
        if new_sequence is null or old_sequence is null then
          raise exception 'Unexpected identity column on %.%.', source.source_name, column_info.source_column;
        end if;
        execute format('select last_value, is_called from %s', old_sequence) into last_number, sequence_called;
        perform setval(new_sequence::regclass, last_number, sequence_called);
        default_value := format('nextval(%L::regclass)', new_sequence);
      end if;
      execute format('alter view %I.%I alter column %I set default %s',
        source.source_schema, source.source_name, column_info.source_column, default_value);
    end loop;
  end loop;

  for group_name in select distinct storage_name from _maintenance_sources order by storage_name loop
    select string_agg(quote_literal(source_name), ', ' order by source_name) into definitions
    from _maintenance_sources where storage_name = group_name;
    execute format('alter table uni360_data.%I add constraint valid_record_kind check (record_kind in (%s))',
      group_name, definitions);
  end loop;
end;
$$;

-- Recreate foreign keys against the physical tables. Shared columns only need
-- one FK when several former tables had the same relationship.
create temporary table _maintenance_foreign_keys (definition text primary key) on commit drop;

do $$
declare
  item record;
  original_schema text;
  original_name text;
  target_relation text;
  referenced_relation text;
  definition text;
begin
  for item in select k.*, s.source_schema, s.source_name
    from _maintenance_keys k left join _maintenance_sources s on s.relation = k.conrelid
    where k.contype = 'f'
    order by k.original_relation, k.conname
  loop
    target_relation := coalesce(pg_temp.maintenance_relation(item.conrelid), item.original_relation);
    referenced_relation := coalesce(pg_temp.maintenance_relation(item.confrelid), item.confrelid::regclass::text);
    definition := format('foreign key (%s) references %s (%s)%s%s%s%s%s',
      pg_temp.maintenance_columns(item.conrelid, item.conkey),
      referenced_relation, pg_temp.maintenance_columns(item.confrelid, item.confkey),
      case item.confmatchtype when 'f' then ' match full' else '' end,
      case item.confupdtype when 'r' then ' on update restrict' when 'c' then ' on update cascade'
        when 'n' then ' on update set null' when 'd' then ' on update set default' else '' end,
      case item.confdeltype when 'r' then ' on delete restrict' when 'c' then ' on delete cascade'
        when 'n' then ' on delete set null' when 'd' then ' on delete set default' else '' end,
      case when item.condeferrable then ' deferrable' || case when item.condeferred then ' initially deferred' else '' end else '' end,
      case when item.convalidated then '' else ' not valid' end
    );
    if item.source_name is null then
      execute format('alter table %s drop constraint %I', item.original_relation, item.conname);
    end if;
    insert into _maintenance_foreign_keys values (target_relation || ' ' || definition) on conflict do nothing;
    if found then
      execute format('alter table %s add constraint %I %s', target_relation, item.conname, definition);
    end if;
  end loop;
end;
$$;

-- Check all source rows in both directions, including nulls and duplicates.
-- The migration aborts before retiring an original if any record differs.
do $$
declare
  source record;
  grants_row record;
  same_rows boolean;
  source_count bigint;
begin
  for source in select * from _maintenance_sources loop
    execute format('select not exists (
        (select to_jsonb(s) from %1$I.%2$I s except all select to_jsonb(v) - ''record_kind'' from %1$I.%3$I v)
        union all
        (select to_jsonb(v) - ''record_kind'' from %1$I.%3$I v except all select to_jsonb(s) from %1$I.%2$I s)
      )', source.source_schema, '_before_' || source.source_name, source.source_name) into same_rows;
    if not same_rows then
      raise exception 'Data comparison failed for %.%. Migration rolled back.', source.source_schema, source.source_name;
    end if;
    execute format('select count(*) from %I.%I', source.source_schema, source.source_name) into source_count;
    raise notice 'Verified % rows for %.%.', source_count, source.source_schema, source.source_name;
  end loop;

  for grants_row in select * from _maintenance_grants loop
    execute format('grant %s%s on %I.%I to %s%s', grants_row.privilege_type,
      case when grants_row.source_column is null then '' else format(' (%I)', grants_row.source_column) end,
      grants_row.source_schema, grants_row.source_name,
      case when grants_row.grantee = 0 then 'PUBLIC' else quote_ident(pg_get_userbyid(grants_row.grantee)) end,
      case when grants_row.is_grantable then ' with grant option' else '' end
    );
  end loop;
end;
$$;

-- Membership remains restricted to active administrators. Reading it in this
-- helper avoids RLS re-entering maintenance_scope through a facility policy.
create or replace function uni360_private.preventive_manage_zone(target_zone uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.account a
    where a.user_id = (select auth.uid()) and a.is_active and (
      a.role = 'super_administrator' or (a.role = 'administrator' and exists (
        select 1 from uni360_data.maintenance_scope s
        where s.record_kind = 'preventive_zone_admin' and s.zone_id = target_zone and s.administrator_id = a.user_id
      ))
    )
  );
$$;

alter table uni360_data.maintenance_scope add constraint zone_admin_role_matches
  check (record_kind <> 'preventive_zone_admin' or account_role = 'administrator'::public.account_role);

create policy workforce_read on uni360_data.maintenance_workforce for select to authenticated
  using ((select public.can_manage_workforce()) or public.can_read_own_workforce(worker_id));
create policy workforce_write on uni360_data.maintenance_workforce for all to authenticated
  using ((select public.can_manage_workforce())) with check ((select public.can_manage_workforce()));

create policy scope_read on uni360_data.maintenance_scope for select to authenticated using (
  case record_kind
    when 'preventive_zone_admin' then (select uni360_private.preventive_super_admin())
      or (administrator_id = (select auth.uid()) and (select public.can_manage_workforce()))
    when 'preventive_campaign_target' then (select uni360_private.preventive_super_admin())
    when 'preventive_work_order_target' then exists (
      select 1 from public.preventive_work_order o where o.id = maintenance_scope.work_order_id
    )
    when 'corrective_site' then exists (
      select 1 from public.preventive_facility f where f.id = maintenance_scope.site_facility_id
        and uni360_private.corrective_manage(f.zone_id)
    )
    else false
  end
);
create policy scope_manage on uni360_data.maintenance_scope for all to authenticated
  using (record_kind in ('preventive_zone_admin','preventive_campaign_target') and (select uni360_private.preventive_super_admin()))
  with check (record_kind in ('preventive_zone_admin','preventive_campaign_target')
    and (select uni360_private.preventive_super_admin())
    and (record_kind <> 'preventive_campaign_target' or exists (
      select 1 from public.preventive_task_plan p where p.id = maintenance_scope.plan_id and p.facility_id is null
    ))
  );

create policy execution_read on uni360_data.maintenance_execution for select to authenticated using (
  case record_kind
    when 'corrective_visit' then exists (
      select 1 from public.corrective_incident i where i.id = maintenance_execution.incident_id
        and (uni360_private.corrective_manage(i.zone_id)
          or (i.worker_id = auth.uid() and maintenance_execution.worker_id = auth.uid()))
    )
    when 'corrective_position' then exists (
      select 1 from public.corrective_incident i where i.id = maintenance_execution.position_incident_id
        and uni360_private.corrective_manage(i.zone_id)
    )
    when 'preventive_work_completion' then exists (
      select 1 from public.preventive_work_order o where o.id = maintenance_execution.work_order_id
    )
    else false
  end
);
create policy execution_record_time on uni360_data.maintenance_execution for update to authenticated
  using (record_kind = 'preventive_work_completion' and exists (
    select 1 from public.preventive_work_order o
    join public.preventive_schedule s on s.id = o.schedule_id where o.id = maintenance_execution.work_order_id
  ));

create policy evidence_read on uni360_data.maintenance_evidence for select to authenticated using (
  case record_kind
    when 'corrective_photo' then exists (
      select 1 from public.corrective_visit v
      where v.incident_id = maintenance_evidence.incident_id and v.attempt = maintenance_evidence.attempt
    )
    when 'preventive_work_evidence' then exists (
      select 1 from public.preventive_work_order o where o.id = maintenance_evidence.work_order_id and o.cancelled_at is null
    )
    else false
  end
);

create policy activity_read on uni360_data.maintenance_activity for select to authenticated using (
  case record_kind
    when 'corrective_event' then uni360_private.corrective_access(incident_id)
    when 'corrective_notification' then recipient_id = auth.uid() and uni360_private.corrective_active()
    else false
  end
);
create policy activity_mark_read on uni360_data.maintenance_activity for update to authenticated
  using (record_kind = 'corrective_notification' and recipient_id = auth.uid() and uni360_private.corrective_active())
  with check (record_kind = 'corrective_notification' and recipient_id = auth.uid() and uni360_private.corrective_active());

create policy template_read on uni360_data.maintenance_template for select to authenticated using (
  case record_kind
    when 'corrective_category' then uni360_private.corrective_active()
    when 'preventive_task_definition' then (zone_id is null and (select public.can_manage_workforce()))
      or uni360_private.preventive_manage_zone(zone_id)
    else false
  end
);
create policy template_create on uni360_data.maintenance_template for insert to authenticated with check (
  (record_kind = 'corrective_category' and (select public.can_manage_workforce()))
  or (record_kind = 'preventive_task_definition' and uni360_private.preventive_manage_zone(zone_id))
);
create policy template_update on uni360_data.maintenance_template for update to authenticated
  using ((record_kind = 'corrective_category' and (select public.can_manage_workforce()))
    or (record_kind = 'preventive_task_definition' and uni360_private.preventive_manage_zone(zone_id)))
  with check ((record_kind = 'corrective_category' and (select public.can_manage_workforce()))
    or (record_kind = 'preventive_task_definition' and uni360_private.preventive_manage_zone(zone_id)));

-- Execution hooks apply to approved preventive completion records only.
create trigger preventive_validate_completion before insert on uni360_data.maintenance_execution
for each row when (new.record_kind = 'preventive_work_completion')
execute function uni360_private.preventive_validate_completion();

create trigger mark_preventive_work_completed after insert on uni360_data.maintenance_execution
for each row when (new.record_kind = 'preventive_work_completion')
execute function uni360_private.mark_preventive_work_completed();

create index maintenance_worker_shifts on uni360_data.maintenance_workforce(worker_id, shift_start)
  where record_kind = 'worker_availability';
create index maintenance_worker_skills on uni360_data.maintenance_workforce(skill_id)
  where record_kind = 'worker_skill';
create index maintenance_worker_certificates on uni360_data.maintenance_workforce(worker_id)
  where record_kind = 'worker_certification';
create index maintenance_scope_qr on uni360_data.maintenance_scope(qr_token)
  where record_kind = 'corrective_site';
create index maintenance_preventive_evidence on uni360_data.maintenance_evidence(work_order_id, created_at)
  where record_kind = 'preventive_work_evidence';
create index maintenance_corrective_evidence on uni360_data.maintenance_evidence(incident_id, attempt)
  where record_kind = 'corrective_photo';
create index maintenance_incident_history on uni360_data.maintenance_activity(incident_id, event_id desc)
  where record_kind = 'corrective_event';
create index maintenance_recipient_notifications on uni360_data.maintenance_activity(recipient_id, notification_id desc)
  where record_kind = 'corrective_notification';

create function public.mark_corrective_notification_read(notification_id bigint) returns timestamptz
language sql security invoker set search_path = '' as $$
  update public.corrective_notification n
  set read_at = coalesce(n.read_at, statement_timestamp())
  where n.id = notification_id and n.recipient_id = (select auth.uid())
  returning n.read_at;
$$;
revoke all on function public.mark_corrective_notification_read(bigint) from public, anon, authenticated;
grant execute on function public.mark_corrective_notification_read(bigint) to authenticated;

-- Keep the original PostgREST embed names and cardinalities. The public
-- views enforce their grants and policies when a caller embeds these rows.
create function public.preventive_task_definition(plan public.preventive_task_plan)
returns setof public.preventive_task_definition rows 1 language sql stable security invoker set search_path = '' as $$
  select d.* from public.preventive_task_definition d where d.id = plan.task_definition_id;
$$;
create function public.preventive_work_order_target(work public.preventive_work_order)
returns setof public.preventive_work_order_target language sql stable security invoker set search_path = '' as $$
  select t.* from public.preventive_work_order_target t where t.work_order_id = work.id;
$$;
create function public.preventive_work_evidence(work public.preventive_work_order)
returns setof public.preventive_work_evidence language sql stable security invoker set search_path = '' as $$
  select e.* from public.preventive_work_evidence e where e.work_order_id = work.id;
$$;
create function public.preventive_work_completion(work public.preventive_work_order)
returns setof public.preventive_work_completion rows 1 language sql stable security invoker set search_path = '' as $$
  select c.* from public.preventive_work_completion c where c.work_order_id = work.id;
$$;
create function public.worker_skill(worker public.worker_profile)
returns setof public.worker_skill language sql stable security invoker set search_path = '' as $$
  select s.* from public.worker_skill s where s.worker_id = worker.worker_id;
$$;
create function public.skill(assignment public.worker_skill)
returns setof public.skill rows 1 language sql stable security invoker set search_path = '' as $$
  select s.* from public.skill s where s.skill_id = assignment.skill_id;
$$;
create function public.worker_certification(worker public.worker_profile)
returns setof public.worker_certification language sql stable security invoker set search_path = '' as $$
  select c.* from public.worker_certification c where c.worker_id = worker.worker_id;
$$;
create function public.worker_availability(worker public.worker_profile)
returns setof public.worker_availability language sql stable security invoker set search_path = '' as $$
  select a.* from public.worker_availability a where a.worker_id = worker.worker_id;
$$;
revoke all on function
  public.preventive_task_definition(public.preventive_task_plan),
  public.preventive_work_order_target(public.preventive_work_order),
  public.preventive_work_evidence(public.preventive_work_order),
  public.preventive_work_completion(public.preventive_work_order),
  public.worker_skill(public.worker_profile), public.skill(public.worker_skill),
  public.worker_certification(public.worker_profile), public.worker_availability(public.worker_profile)
  from public, anon, authenticated;
grant execute on function
  public.preventive_task_definition(public.preventive_task_plan),
  public.preventive_work_order_target(public.preventive_work_order),
  public.preventive_work_evidence(public.preventive_work_order),
  public.preventive_work_completion(public.preventive_work_order),
  public.worker_skill(public.worker_profile), public.skill(public.worker_skill),
  public.worker_certification(public.worker_profile), public.worker_availability(public.worker_profile)
  to authenticated, service_role;

do $$
declare
  policy_row record;
  originals text;
begin
  for policy_row in select * from _maintenance_external_policies loop
    execute format('drop policy %I on %I.%I', policy_row.polname, policy_row.schema_name, policy_row.relation_name);
    execute format('create policy %I on %I.%I as %s for %s to %s%s%s',
      policy_row.polname, policy_row.schema_name, policy_row.relation_name,
      case when policy_row.polpermissive then 'permissive' else 'restrictive' end,
      case policy_row.polcmd when 'r' then 'select' when 'a' then 'insert' when 'w' then 'update'
        when 'd' then 'delete' else 'all' end,
      policy_row.roles,
      case when policy_row.using_expr is not null then format(' using (%s)', policy_row.using_expr) else '' end,
      case when policy_row.check_expr is not null then format(' with check (%s)', policy_row.check_expr) else '' end
    );
  end loop;

  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table uni360_data.maintenance_activity;
  end if;

  select string_agg(format('%I.%I', source_schema, '_before_' || source_name), ', ')
    into originals from _maintenance_sources;
  execute 'drop table ' || originals;
end;
$$;

-- SQL Editor returns a result row for this check. A row with 15 and TRUE
-- confirms the exact number of physical Uni360 application tables.
do $$
declare
  table_count integer;
begin
  select count(*) into table_count from information_schema.tables
  where table_schema in ('public','uni360_data') and table_type = 'BASE TABLE';
  if table_count <> 15 then raise exception 'Expected 15 physical application tables, found %.', table_count; end if;
end;
$$;

create or replace function uni360_private.assign_preventive_day(work_date date, target_zone uuid, requested jsonb, earlier jsonb, prior_load jsonb)
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

create or replace function uni360_private.worker_work_order_action(
  target_order uuid, action text, item_index integer, item_checked boolean, evidence_path text, notes text
) returns text language plpgsql security definer set search_path = '' as $$
declare
  order_row public.preventive_work_order%rowtype;
begin
  -- Use the same lock as Corrective dispatch and check-in before locking the
  -- work-order row. This makes simultaneous starts see the other reservation.
  if action = 'start' then perform pg_catalog.pg_advisory_xact_lock(360, 2); end if;
  select * into order_row from public.preventive_work_order
  where id = target_order and worker_id = (select auth.uid()) and cancelled_at is null
    and public.can_read_own_workforce(worker_id)
  for update;
  if not found then
    raise exception 'This work order is unavailable to your account.' using errcode = '42501';
  end if;

  if action = 'start' and order_row.status in ('assigned', 'in_progress') then
    update public.preventive_work_order
      set status = 'in_progress', started_at = coalesce(started_at, now()) where id = target_order;
    return 'in_progress';
  end if;
  if action = 'submit' and order_row.status = 'submitted' then
    return 'submitted';
  end if;
  if order_row.status <> 'in_progress' then
    raise exception 'This work order is currently read-only.' using errcode = '23514';
  end if;

  case action
    when 'check' then
      if item_index is null or item_index < 0 or item_index >= cardinality(order_row.checklist) or item_checked is null then
        raise exception 'Choose a valid checklist item.' using errcode = '23514';
      end if;
      update public.preventive_work_order
        set checked_items = array(
          select distinct n from unnest(array_remove(order_row.checked_items, item_index)
            || case when item_checked then array[item_index] else '{}'::integer[] end) as items(n) order by n
        ) where id = target_order;
    when 'attach' then
      if evidence_path is null or evidence_path !~ ('^' || order_row.worker_id || '/' || target_order || '/[0-9a-f]{32}\.(jpg|png|webp)$')
         or not exists (
           select 1 from storage.objects where bucket_id = 'preventive-work-evidence' and name = evidence_path
             and owner_id = order_row.worker_id::text
         ) then
        raise exception 'Upload a photo for this work order before attaching it.' using errcode = '23514';
      end if;
      insert into public.preventive_work_evidence(path, work_order_id)
      values (evidence_path, target_order) on conflict (path) do nothing;
    when 'submit' then
      if cardinality(order_row.checked_items) <> cardinality(order_row.checklist) then
        raise exception 'Tick every checklist item before submitting.' using errcode = '23514';
      end if;
      if not exists (select 1 from public.preventive_work_evidence where work_order_id = target_order) then
        raise exception 'Upload at least one evidence photo before submitting.' using errcode = '23514';
      end if;
      update public.preventive_work_order
        set status = 'submitted', submitted_at = now(), worker_notes = btrim(coalesce(notes, '')), review_note = ''
        where id = target_order;
      return 'submitted';
    else
      raise exception 'Unsupported work order action.' using errcode = '23514';
  end case;
  return 'in_progress';
end;
$$;

notify pgrst, 'reload schema';

commit;

select
  count(*)::integer as application_tables,
  count(*) = 15 as consolidation_verified,
  (select not b.public from storage.buckets b where b.id = 'corrective-evidence') as corrective_evidence_private,
  (select not b.public from storage.buckets b where b.id = 'preventive-work-evidence') as preventive_evidence_private
from information_schema.tables
where table_schema in ('public','uni360_data') and table_type = 'BASE TABLE';


