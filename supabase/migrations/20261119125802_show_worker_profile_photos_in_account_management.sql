begin;

create or replace function uni360_private.list_managed_accounts(
  search_text text, page_number integer, active_filter boolean
)
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
      select a.user_id, a.employee_id, a.full_name, a.phone, a.is_active,
        case when target_role = 'worker' then a.profile_photo_path end as profile_photo_path
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

-- Allow worker-account administrators to sign the current photo only.
create function uni360_private.administrator_can_read_worker_photo(
  photo_path text, photo_owner text
) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.account a
    where a.user_id = (select auth.uid()) and a.role = 'administrator' and a.is_active
  ) and exists (
    select 1 from public.account w
    where w.role = 'worker'
      and w.user_id::text = photo_owner
      and w.profile_photo_path = photo_path
  );
$$;

revoke all on function uni360_private.administrator_can_read_worker_photo(text, text)
  from public, anon, authenticated;
grant execute on function uni360_private.administrator_can_read_worker_photo(text, text)
  to authenticated;

create policy account_photo_worker_administrator_read
  on storage.objects for select to authenticated
  using (
    bucket_id = 'account-photos'
    and uni360_private.administrator_can_read_worker_photo(name, owner_id)
  );

commit;
