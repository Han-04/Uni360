begin;

create schema if not exists uni360_private;
revoke all on schema uni360_private from public, anon;
grant usage on schema uni360_private to authenticated;

-- Expose only the worker identifiers needed by the workforce screen.
create function uni360_private.workforce_directory(search_text text, start_at integer)
returns table (worker_id uuid, full_name text, employee_id text,
  job_role text, assigned_zone text, employment_status text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.can_manage_workforce() then
    raise exception 'An active administrator account is required.' using errcode = '42501';
  end if;
  return query
    select w.worker_id, a.full_name, a.employee_id, w.job_role, w.assigned_zone, w.employment_status
    from public.worker_profile w join public.account a on a.user_id = w.worker_id
    where a.role = 'worker' and (
      strpos(lower(a.full_name), lower(left(coalesce(search_text, ''), 120))) > 0 or
      strpos(lower(a.employee_id), lower(left(coalesce(search_text, ''), 120))) > 0
    )
    order by a.full_name, w.worker_id
    limit 26 offset greatest(coalesce(start_at, 0), 0);
end;
$$;

create function public.workforce_directory(search_text text default '', start_at integer default 0)
returns table (worker_id uuid, full_name text, employee_id text,
  job_role text, assigned_zone text, employment_status text)
language sql stable security invoker set search_path = '' as $$
  select * from uni360_private.workforce_directory(search_text, start_at);
$$;

revoke all on function uni360_private.workforce_directory(text, integer),
  public.workforce_directory(text, integer) from public, anon, authenticated;
grant execute on function uni360_private.workforce_directory(text, integer),
  public.workforce_directory(text, integer) to authenticated;

commit;
