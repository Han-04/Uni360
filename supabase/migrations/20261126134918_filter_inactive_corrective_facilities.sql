-- Retired locations are retained for history but are unavailable for new corrective reports.
CREATE OR REPLACE FUNCTION uni360_private.corrective_catalog()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with recursive locations(id, parent_id, zone_id, label) as (
    select f.id, f.parent_id, uni360_private.facility_access_zone(f.id), f.name::text label
    from public.preventive_facility f where f.parent_id is null and f.is_active
    union all
    select f.id, f.parent_id, uni360_private.facility_access_zone(f.id), l.label || ' / ' || f.name
    from public.preventive_facility f join locations l on l.id = f.parent_id
    where f.is_active
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
