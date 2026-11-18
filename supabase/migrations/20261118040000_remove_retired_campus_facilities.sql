begin;

do $$
declare
  facility uuid;
begin
  perform pg_catalog.pg_advisory_xact_lock(360, 1);

  -- Remove leaves first so a parent is kept only if a reference still needs it.
  for facility in
    with recursive removed(id, depth) as (
      select id, 0
      from public.preventive_facility
      where parent_id is null and lower(btrim(name)) in (
        'block d', 'block k', 'block k garden',
        'yumyum cafe', 'yumyum café', 'yumyum cafeteria'
      )
      union all
      select child.id, removed.depth + 1
      from public.preventive_facility child
      join removed on child.parent_id = removed.id
    )
    select id from removed order by depth desc, id
  loop
    begin
      delete from public.preventive_facility where id = facility;
    exception when foreign_key_violation then
      update public.preventive_facility
      set is_active = false, metadata = metadata || '{"catalog_removed": true}'::jsonb
      where id = facility;
    end;
  end loop;
end;
$$;

commit;
