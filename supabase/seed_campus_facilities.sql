begin;

do $$
declare
  campus_zone uuid;
begin
  insert into public.preventive_zone (name)
    values ('TAR UMT Campus') on conflict (name) do nothing;
  select id into strict campus_zone from public.preventive_zone where name = 'TAR UMT Campus';

  insert into public.preventive_zone_admin (zone_id, administrator_id)
  select campus_zone, a.user_id
  from public.account a join auth.users u on u.id = a.user_id
  where a.role = 'administrator' and a.is_active and u.email = 'admin@uni360.example'
  on conflict do nothing;

  insert into public.preventive_facility (id, zone_id, name, facility_type, metadata)
  values
    ('36100000-0000-4000-8000-000000000001', campus_zone, 'Block D', 'building', '{"floors": 3}'),
    ('36100000-0000-4000-8000-000000000002', campus_zone, 'TARUMT Areana', 'building', '{"floors": 7}'),
    ('36100000-0000-4000-8000-000000000003', campus_zone, 'YumYum Cafeteria', 'building', '{}')
  on conflict (id) do nothing;

  insert into public.preventive_facility (id, zone_id, parent_id, name, facility_type)
  select
    ('36100000-0000-4000-8000-' || lpad((location.floor_base + floor.level)::text, 12, '0'))::uuid,
    campus_zone, location.building,
    case when floor.level = 0 then 'Ground Floor' else 'Level ' || floor.level end, 'floor'
  from (values
    ('36100000-0000-4000-8000-000000000001'::uuid, 10, 1, 3),
    ('36100000-0000-4000-8000-000000000002'::uuid, 20, 0, 6)
  ) as location(building, floor_base, first_level, last_level)
  cross join lateral generate_series(location.first_level, location.last_level) as floor(level)
  on conflict (id) do nothing;

  insert into public.preventive_facility (id, zone_id, parent_id, name, facility_type, metadata)
  select
    ('36100000-0000-4000-8000-' || lpad((100 + parent.number * 2 + toilet.offset_id)::text, 12, '0'))::uuid,
    campus_zone,
    ('36100000-0000-4000-8000-' || lpad(parent.number::text, 12, '0'))::uuid,
    toilet.name, 'room', jsonb_build_object('room_type', 'toilet', 'designation', toilet.designation)
  from (select unnest(array[3, 11, 12, 20, 21, 22, 23, 24, 25, 26]) as number) as parent
  cross join (values
    (0, 'Male Toilet', 'male'), (1, 'Female Toilet', 'female')
  ) as toilet(offset_id, name, designation)
  on conflict (id) do nothing;
end;
$$;

commit;
