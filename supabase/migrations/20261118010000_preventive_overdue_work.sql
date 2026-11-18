begin;

-- A missed task is overdue from midnight after its scheduled Malaysia date.
-- Keep workflow status so reporting, submissions, and audit history still work.
create index preventive_work_order_pending_by_date
  on public.preventive_work_order(scheduled_for, id)
  where cancelled_at is null and worker_id is not null
    and status in ('assigned', 'in_progress');

do $migration$
declare
  target regprocedure;
  original text;
  anchor constant text := '(\mfor[[:space:]]+update[^;]*;[[:space:]]*if[[:space:]]+not[[:space:]]+found[[:space:]]+then[[:space:]]+raise[[:space:]]+exception[^;]*;[[:space:]]*end[[:space:]]+if[[:space:]]*;)';
  date_guard constant text := $guard$
  if order_row.status in ('assigned', 'in_progress')
    and (order_row.scheduled_for at time zone 'Asia/Kuala_Lumpur')::date
      < (clock_timestamp() at time zone 'Asia/Kuala_Lumpur')::date then
    raise exception 'This work order is overdue. Contact your administrator.' using errcode = '23514';
  end if;$guard$;
begin
  foreach target in array array[
    'uni360_private.worker_work_order_action(uuid,text,integer,boolean,text,text)'::regprocedure,
    'uni360_private.preventive_campus_action(uuid,text,double precision,double precision,double precision,timestamptz,text,text)'::regprocedure
  ] loop
    original := replace(pg_get_functiondef(target), chr(13), '');
    if original !~* anchor then
      raise exception 'Could not install the overdue guard in %.', target;
    end if;
    execute regexp_replace(original, anchor, '\1' || date_guard, 'i');
  end loop;
end;
$migration$;

notify pgrst, 'reload schema';
commit;
