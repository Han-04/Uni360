begin;

insert into public.preventive_zone (name)
values ('TAR UMT Campus') on conflict (name) do nothing;

insert into maintenance_api.preventive_zone_admin (zone_id, administrator_id)
select z.id, a.user_id
from public.preventive_zone z
cross join public.account a
join auth.users u on u.id = a.user_id
where z.name = 'TAR UMT Campus'
  and a.role = 'administrator' and a.is_active and u.email = 'admin@uni360.example'
on conflict do nothing;

commit;
