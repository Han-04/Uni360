begin;

-- Workers can check catalog visibility only for their own orders or alerts.
-- Facility metadata stays private to administrators.
create function uni360_private.worker_preventive_work_in_catalog(
  target_order uuid, target_facility uuid default null
) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.can_read_own_workforce((select auth.uid()))
    and (
      exists (
        select 1 from public.preventive_work_order o
        where o.id = target_order and o.worker_id = (select auth.uid())
      ) or exists (
        select 1 from maintenance_api.preventive_notification n
        where n.work_order_id = target_order and n.recipient_id = (select auth.uid())
      )
    )
    and coalesce((
      select bool_or(
        not (f.metadata @> '{"catalog_removed": true}'::jsonb
          or f.metadata @> '{"arena_replaced": true}'::jsonb)
      )
      from maintenance_api.preventive_work_order_target t
      join public.preventive_facility f on f.id = t.facility_id
      where t.work_order_id = target_order
        and (target_facility is null or t.facility_id = target_facility)
    ), target_facility is null);
$$;

revoke all on function uni360_private.worker_preventive_work_in_catalog(uuid, uuid)
  from public, anon, authenticated;
grant execute on function uni360_private.worker_preventive_work_in_catalog(uuid, uuid)
  to authenticated;

alter policy order_worker_read on public.preventive_work_order
  using (
    cancelled_at is null and public.can_read_own_workforce(worker_id)
    and uni360_private.worker_preventive_work_in_catalog(id)
  );

-- A mixed-location order still appears for its remaining locations.
create policy worker_preventive_catalog_targets
  on uni360_data.maintenance_scope as restrictive for select to authenticated
  using (
    record_kind <> 'preventive_work_order_target'
    or not (select public.can_read_own_workforce((select auth.uid())))
    or uni360_private.worker_preventive_work_in_catalog(work_order_id, facility_id)
  );

alter policy preventive_notification_read on maintenance_api.preventive_notification
  using (
    public.can_read_own_workforce(recipient_id)
    and (work_order_id is null or uni360_private.worker_preventive_work_in_catalog(work_order_id))
  );

-- The sender-aware RPC bypasses RLS to look up admin profile names and photos.
create or replace function uni360_private.read_preventive_notifications()
returns table(id uuid, title text, message text, created_at timestamptz,
  read_at timestamptz, sender_name text, sender_photo text)
language sql stable security definer set search_path = '' as $$
  select n.id, n.title, n.message, n.created_at, n.read_at, a.full_name, a.profile_photo_path
  from maintenance_api.preventive_notification n
  left join public.account a on a.user_id = n.sender_id
    and a.role in ('administrator', 'super_administrator')
  where n.recipient_id = (select auth.uid()) and public.can_read_own_workforce(n.recipient_id)
    and (n.work_order_id is null or uni360_private.worker_preventive_work_in_catalog(n.work_order_id))
  order by n.created_at desc, n.id desc
  limit 100;
$$;

commit;
