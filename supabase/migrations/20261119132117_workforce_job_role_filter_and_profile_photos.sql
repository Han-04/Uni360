begin;

create function uni360_private.workforce_directory(
  search_text text, start_at integer, job_role_filter text
)
returns table (worker_id uuid, full_name text, employee_id text,
  job_role text, employment_status text, profile_photo_path text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.can_manage_workforce() then
    raise exception 'An active administrator account is required.' using errcode = '42501';
  end if;
  return query
    select w.worker_id, a.full_name, a.employee_id, w.job_role, w.employment_status,
      a.profile_photo_path
    from public.worker_profile w join public.account a on a.user_id = w.worker_id
    where a.role = 'worker'
      and (job_role_filter is null or lower(btrim(w.job_role)) = lower(btrim(job_role_filter)))
      and (
        strpos(lower(a.full_name), lower(left(coalesce(search_text, ''), 120))) > 0 or
        strpos(lower(a.employee_id), lower(left(coalesce(search_text, ''), 120))) > 0
      )
    order by a.full_name, w.worker_id
    limit 26 offset greatest(coalesce(start_at, 0), 0);
end;
$$;

create or replace function uni360_private.workforce_directory(search_text text, start_at integer)
returns table (worker_id uuid, full_name text, employee_id text,
  job_role text, employment_status text)
language sql stable security invoker set search_path = '' as $$
  select w.worker_id, w.full_name, w.employee_id, w.job_role, w.employment_status
  from uni360_private.workforce_directory(search_text, start_at, null) w;
$$;

create function public.workforce_directory(
  search_text text, start_at integer, job_role_filter text
)
returns table (worker_id uuid, full_name text, employee_id text,
  job_role text, employment_status text, profile_photo_path text)
language sql stable security invoker set search_path = '' as $$
  select * from uni360_private.workforce_directory(search_text, start_at, job_role_filter);
$$;

create function public.workforce_job_roles()
returns text[] language sql stable security invoker set search_path = '' as $$
  select coalesce(array_agg(roles.label order by roles.sort_key), array[]::text[])
  from (
    select lower(btrim(w.job_role)) as sort_key, min(btrim(w.job_role)) as label
    from maintenance_api.worker_profile w
    where (select public.can_manage_workforce()) and nullif(btrim(w.job_role), '') is not null
    group by lower(btrim(w.job_role))
  ) roles;
$$;

-- Both administrator roles can open the current photo on a worker profile.
create or replace function uni360_private.administrator_can_read_worker_photo(
  photo_path text, photo_owner text
) returns boolean
language sql stable security definer set search_path = '' as $$
  select (select public.can_manage_workforce()) and exists (
    select 1 from public.account w
    where w.role = 'worker'
      and w.user_id::text = photo_owner
      and w.profile_photo_path = photo_path
  );
$$;

revoke all on function uni360_private.workforce_directory(text, integer, text),
  public.workforce_directory(text, integer, text), public.workforce_job_roles()
  from public, anon, authenticated;
grant execute on function uni360_private.workforce_directory(text, integer, text),
  public.workforce_directory(text, integer, text), public.workforce_job_roles()
  to authenticated;

notify pgrst, 'reload schema';
commit;
