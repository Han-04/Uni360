begin;

-- Reuse the Arena and its matching floors so their existing references survive.
do $$
declare
  arena_id uuid;
  floor_id uuid;
  room_id uuid;
  legacy_id uuid;
  level_number integer;
  floor_name text;
  location record;
begin
  perform pg_catalog.pg_advisory_xact_lock(360, 1);

  select id into arena_id
  from public.preventive_facility
  where parent_id is null and facility_type = 'building'
    and lower(name) in ('tarumt arena', 'tarumt areana')
  order by (id = '36100000-0000-4000-8000-000000000002') desc, is_active desc, id
  limit 1;

  if arena_id is null then
    insert into public.preventive_zone (name)
    values ('TAR UMT Campus') on conflict (name) do nothing;
    insert into public.preventive_facility (name, facility_type)
    values ('TARUMT Arena', 'building')
    returning id into arena_id;
  else
    update public.preventive_facility set name = 'TARUMT Arena'
    where id = arena_id and name <> 'TARUMT Arena';
  end if;

  -- Retire only the old seeded toilet placeholders and the omitted Level 1.
  -- A referenced facility must remain in the database for historical records.
  for legacy_id in
    select room.id
    from public.preventive_facility room
    join public.preventive_facility floor on floor.id = room.parent_id
    cross join generate_series(20, 26) as seeded(n)
    where floor.parent_id = arena_id
      and floor.id = ('36100000-0000-4000-8000-' || lpad(seeded.n::text, 12, '0'))::uuid
      and room.id in (
        ('36100000-0000-4000-8000-' || lpad((100 + 2 * seeded.n)::text, 12, '0'))::uuid,
        ('36100000-0000-4000-8000-' || lpad((101 + 2 * seeded.n)::text, 12, '0'))::uuid
      )
      and room.name in ('Male Toilet', 'Female Toilet')
      and room.facility_type = 'room' and room.metadata->>'room_type' = 'toilet'
    union all
    select id
    from public.preventive_facility
    where parent_id = arena_id and id = '36100000-0000-4000-8000-000000000021'
      and name = 'Level 1' and facility_type = 'floor'
    order by 1 desc
  loop
    begin
      delete from public.preventive_facility where id = legacy_id;
    exception when foreign_key_violation then
      update public.preventive_facility
      set is_active = false, metadata = metadata || '{"arena_replaced": true}'::jsonb
      where id = legacy_id;
    end;
  end loop;

  foreach level_number in array array[0, 2, 3, 4, 5, 6] loop
    floor_name := case when level_number = 0 then 'Ground Floor' else 'Level ' || level_number end;
    select id into floor_id
    from public.preventive_facility
    where parent_id = arena_id and facility_type = 'floor' and lower(name) = lower(floor_name)
    order by is_active desc, id limit 1;
    if floor_id is null then
      insert into public.preventive_facility (parent_id, name, facility_type)
      values (arena_id, floor_name, 'floor')
      returning id into floor_id;
    end if;

    for location in
      with rooms (level_no, name, room_type, properties) as (
        select 0, 'T' || lpad(n::text, 3, '0') || case when n in (11,21) then ' - Toilet' else '' end,
          case when n in (11,21) then 'toilet' end,
          array[case when n in (11,21) then 'Fan' else 'Air-conditioning' end]
        from generate_series(1, 21) as ground(n)
        union all
        select 2, 'T' || n || case when n in (211,221,231) then ' - Toilet' else '' end,
          case when n in (211,221,231) then 'toilet' end,
          array[case when n in (211,221,231) then 'Fan' else 'Air-conditioning' end]
        from generate_series(201, 245) as second_floor(n)
        union all
        select 2, hall.name, null, array(select 'Air-conditioning ' || n from generate_series(1,6) as units(n))
        from (values ('EH1 - Exam Hall'), ('EH2 - Exam Hall')) as hall(name)
        union all
        select parking.level_no, 'Parking Area', null, array[]::text[]
        from (values (3), (4), (5)) as parking(level_no)
        union all
        select toilet.level_no, 'T' || toilet.number || ' - Toilet', 'toilet', array['Fan']
        from (values (3,301), (3,302), (4,401), (5,402), (5,501), (5,502), (6,601), (6,602))
          as toilet(level_no, number)
        union all
        values (6, 'Futsal Court', null, array['Fan 1','Fan 2']),
               (6, 'Pickleball Court', null, array['Fan 1','Fan 2']),
               (6, 'Track', null, array[]::text[])
      )
      select name, room_type, properties from rooms where level_no = level_number
    loop
      select id into room_id
      from public.preventive_facility
      where parent_id = floor_id and facility_type = 'room' and lower(name) = lower(location.name)
      order by is_active desc, id limit 1;
      if room_id is null then
        insert into public.preventive_facility (parent_id, name, facility_type, metadata)
        values (floor_id, location.name, 'room',
          jsonb_strip_nulls(jsonb_build_object('room_type', location.room_type)))
        returning id into room_id;
      elsif location.room_type is not null then
        update public.preventive_facility
        set metadata = metadata || jsonb_build_object('room_type', location.room_type)
        where id = room_id;
      end if;

      insert into public.preventive_facility (parent_id, name, facility_type)
      select room_id, property.name, 'asset'
      from unnest(location.properties) as property(name)
      where not exists (
        select 1 from public.preventive_facility existing
        where existing.parent_id = room_id and existing.facility_type = 'asset'
          and lower(existing.name) = lower(property.name)
      );
    end loop;
  end loop;
end;
$$;

commit;
