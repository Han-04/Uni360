begin;

-- Keep shift eligibility and duplicate checks for every day of the week.
do $$
declare
  target regprocedure;
  original text;
  updated text;
begin
  for target, original, updated in
    values
      ('uni360_private.assign_preventive_day(date,uuid,jsonb,jsonb,jsonb)'::regprocedure,
        ' or extract(isodow from work_date) = 7', ''),
      ('uni360_private.auto_schedule_range(uuid[],uuid,text,date,date,time[],integer,jsonb)'::regprocedure,
        'where extract(isodow from first_date + i) <> 7', 'where true'),
      ('uni360_private.preventive_schedule_warnings(jsonb,uuid[],uuid,text,date,date)'::regprocedure,
        'and extract(isodow from first_date + days.offset_days) <> 7', '')
  loop
    if strpos(pg_get_functiondef(target), original) = 0 then
      raise exception 'Expected Sunday restriction in %.', target;
    end if;
    execute replace(replace(pg_get_functiondef(target), original, updated),
      'Choose a valid date from Monday to Saturday.', 'Choose a valid date.');
  end loop;
end;
$$;

create function uni360_private.list_managed_accounts(search_text text, page_number integer, active_filter boolean)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  target_role public.account_role;
  term text := lower(left(btrim(coalesce(search_text, '')), 120));
  first_row integer := case when page_number between 0 and 10000 then page_number * 20 else 0 end;
begin
  select case a.role
    when 'super_administrator' then 'administrator'::public.account_role
    when 'administrator' then 'worker'::public.account_role
    end into target_role
  from public.account a where a.user_id = (select auth.uid()) and a.is_active;
  if target_role is null then
    raise exception 'An active administrator account is required.' using errcode = '42501';
  end if;

  return (
    with page as (
      select a.user_id, a.employee_id, a.full_name, a.phone, a.is_active
      from public.account a
      where a.role = target_role and (active_filter is null or a.is_active = active_filter)
        and (strpos(lower(a.full_name), term) > 0 or strpos(lower(a.employee_id), term) > 0)
      order by a.full_name, a.user_id
      offset first_row limit 21
    )
    select jsonb_build_object(
      'rows', coalesce((select jsonb_agg(to_jsonb(p) order by p.full_name, p.user_id)
        from (select * from page order by full_name, user_id limit 20) p), '[]'::jsonb),
      'hasNext', (select count(*) > 20 from page)
    )
  );
end;
$$;

create function public.list_managed_accounts(search_text text, page_number integer, active_filter boolean)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select uni360_private.list_managed_accounts(search_text, page_number, active_filter);
$$;

revoke all on function uni360_private.list_managed_accounts(text,integer,boolean),
  public.list_managed_accounts(text,integer,boolean) from public, anon, authenticated;
grant execute on function uni360_private.list_managed_accounts(text,integer,boolean),
  public.list_managed_accounts(text,integer,boolean) to authenticated;

notify pgrst, 'reload schema';

commit;
