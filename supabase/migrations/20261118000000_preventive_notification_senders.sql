begin;

alter table maintenance_api.preventive_notification
  add column sender_id uuid references public.account(user_id);
create index preventive_notification_sender_recipient
  on maintenance_api.preventive_notification(recipient_id, sender_id)
  where sender_id is not null;

-- Older leave decisions retain a reviewer. Work order notifications did not.
update maintenance_api.preventive_notification n
set sender_id = r.reviewed_by
from maintenance_api.worker_leave_request r
where n.leave_request_id = r.id and r.reviewed_by is not null
  and n.title in ('Leave approved', 'Leave rejected');

create function uni360_private.capture_preventive_notification_sender()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  select a.user_id into new.sender_id from public.account a
  where a.user_id = (select auth.uid()) and a.is_active
    and a.role in ('administrator', 'super_administrator');
  return new;
end;
$$;
revoke all on function uni360_private.capture_preventive_notification_sender()
  from public, anon, authenticated;
create trigger capture_preventive_notification_sender
before insert on maintenance_api.preventive_notification
for each row execute function uni360_private.capture_preventive_notification_sender();

create function uni360_private.read_preventive_notifications()
returns table(id uuid, title text, message text, created_at timestamptz,
  read_at timestamptz, sender_name text, sender_photo text)
language sql stable security definer set search_path = '' as $$
  select n.id, n.title, n.message, n.created_at, n.read_at, a.full_name, a.profile_photo_path
  from maintenance_api.preventive_notification n
  left join public.account a on a.user_id = n.sender_id
    and a.role in ('administrator', 'super_administrator')
  where n.recipient_id = (select auth.uid()) and public.can_read_own_workforce(n.recipient_id)
  order by n.created_at desc, n.id desc
  limit 100;
$$;

create function public.read_preventive_notifications()
returns table(id uuid, title text, message text, created_at timestamptz,
  read_at timestamptz, sender_name text, sender_photo text)
language sql stable security invoker set search_path = '' as $$
  select * from uni360_private.read_preventive_notifications();
$$;

create function uni360_private.notification_sender_photo(photo_path text, photo_owner text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from maintenance_api.preventive_notification n
    join public.account a on a.user_id = n.sender_id
    where n.recipient_id = (select auth.uid()) and public.can_read_own_workforce(n.recipient_id)
      and a.user_id::text = photo_owner and a.profile_photo_path = photo_path
      and a.role in ('administrator', 'super_administrator')
  );
$$;

revoke all on function uni360_private.read_preventive_notifications(),
  public.read_preventive_notifications(), uni360_private.notification_sender_photo(text,text)
  from public, anon, authenticated;
grant execute on function uni360_private.read_preventive_notifications(),
  public.read_preventive_notifications(), uni360_private.notification_sender_photo(text,text)
  to authenticated;

create policy notification_sender_photo_read on storage.objects for select to authenticated
  using (bucket_id = 'account-photos' and uni360_private.notification_sender_photo(name, owner_id));

notify pgrst, 'reload schema';
commit;
