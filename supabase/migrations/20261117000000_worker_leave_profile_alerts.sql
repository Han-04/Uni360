begin;

alter table public.account add column profile_photo_path text;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('account-photos','account-photos',false,5242880,array['image/jpeg','image/png','image/webp']);

create policy account_photo_read on storage.objects for select to authenticated
  using (bucket_id = 'account-photos' and owner_id = (select auth.uid())::text
    and exists (select 1 from public.account a where a.user_id = (select auth.uid()) and a.is_active));
create policy account_photo_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'account-photos'
    and split_part(name, '/', 1) = (select auth.uid())::text
    and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$'
    and exists (select 1 from public.account a where a.user_id = (select auth.uid()) and a.is_active));
create policy account_photo_cleanup on storage.objects for delete to authenticated
  using (bucket_id = 'account-photos' and owner_id = (select auth.uid())::text
    and exists (select 1 from public.account a where a.user_id = (select auth.uid()) and a.is_active
      and a.profile_photo_path is distinct from storage.objects.name));

create function uni360_private.save_account_profile(target_account uuid, name text, phone_number text, photo text)
returns public.account language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  updated public.account;
begin
  if actor is null or actor is distinct from target_account then
    raise exception 'Sign in to update your own profile.' using errcode = '42501';
  end if;
  if photo is not null and (
    split_part(photo, '/', 1) is distinct from actor::text
    or not exists (select 1 from storage.objects s where s.bucket_id = 'account-photos'
      and s.name = photo and s.owner_id = actor::text)
  ) then
    raise exception 'Choose a photo uploaded from your own account.' using errcode = '42501';
  end if;
  update public.account a set full_name = btrim(save_account_profile.name),
    phone = btrim(phone_number), profile_photo_path = coalesce(photo, a.profile_photo_path)
  where a.user_id = actor and a.is_active returning * into updated;
  if not found then
    raise exception 'Your profile is unavailable. Sign in again.' using errcode = '42501';
  end if;
  return updated;
end;
$$;

create table maintenance_api.worker_leave_request (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.worker_profile(worker_id),
  leave_type text not null check (leave_type in ('annual','medical','emergency','other')),
  starts_on date not null,
  ends_on date not null check (ends_on between starts_on and starts_on + 365),
  reason text not null check (char_length(btrim(reason)) between 1 and 1000),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.account(user_id),
  review_note text,
  availability_id uuid unique,
  reassigned_count integer not null default 0,
  uncovered_count integer not null default 0,
  active_count integer not null default 0
);
create index worker_leave_requests_by_worker on maintenance_api.worker_leave_request(worker_id, starts_on, ends_on);
create index worker_leave_requests_by_status on maintenance_api.worker_leave_request(status, requested_at);
alter table maintenance_api.worker_leave_request enable row level security;
revoke all on maintenance_api.worker_leave_request from public, anon, authenticated;
grant select on maintenance_api.worker_leave_request to authenticated;
create policy worker_leave_request_read on maintenance_api.worker_leave_request for select to authenticated
  using (public.can_read_own_workforce(worker_id) or (select public.can_manage_workforce()));

create table maintenance_api.preventive_notification (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.account(user_id),
  work_order_id uuid references public.preventive_work_order(id) on delete set null,
  leave_request_id uuid references maintenance_api.worker_leave_request(id),
  title text not null,
  message text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index preventive_notification_feed
  on maintenance_api.preventive_notification(recipient_id, created_at desc, id);
alter table maintenance_api.preventive_notification enable row level security;
revoke all on maintenance_api.preventive_notification from public, anon, authenticated;
grant select, update (read_at) on maintenance_api.preventive_notification to authenticated;
create policy preventive_notification_read on maintenance_api.preventive_notification for select to authenticated
  using (public.can_read_own_workforce(recipient_id));
create policy preventive_notification_mark_read on maintenance_api.preventive_notification for update to authenticated
  using (public.can_read_own_workforce(recipient_id))
  with check (public.can_read_own_workforce(recipient_id));

create function uni360_private.notify_preventive_work() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  label text;
  body text;
begin
  if new.worker_id is null or new.cancelled_at is not null then return new; end if;
  if tg_op = 'INSERT' then
    if new.status = 'assigned' then label := 'New task assigned'; end if;
  elsif new.worker_id is distinct from old.worker_id and new.status = 'assigned' then
    label := 'New task assigned';
  elsif new.status is distinct from old.status then
    if new.status = 'completed' then
      label := 'Task approved';
      body := new.title || ' was approved by your administrator.';
    elsif old.status = 'submitted' and new.status = 'in_progress' then
      label := 'Task returned for changes';
      body := new.title || ' · ' || new.review_note;
    end if;
  end if;
  if label is not null then
    insert into maintenance_api.preventive_notification(recipient_id,work_order_id,title,message)
    values (new.worker_id,new.id,label,coalesce(body, new.title || ' · ' ||
      to_char(new.scheduled_for at time zone 'Asia/Kuala_Lumpur','DD Mon YYYY, HH24:MI') || ' Malaysia time'));
  end if;
  return new;
end;
$$;
create trigger notify_preventive_work after insert or update of worker_id,status on public.preventive_work_order
for each row execute function uni360_private.notify_preventive_work();

-- Surface completions approved before the Notifications feed was introduced.
insert into maintenance_api.preventive_notification(recipient_id,work_order_id,title,message,created_at)
select o.worker_id,o.id,'Task approved',o.title || ' was approved by your administrator.',c.completed_at
from public.preventive_work_order o join maintenance_api.preventive_work_completion c on c.work_order_id = o.id
where o.status = 'completed' and o.cancelled_at is null and o.worker_id is not null;

insert into maintenance_api.preventive_notification(recipient_id,work_order_id,title,message)
select o.worker_id,o.id,'Scheduled task',o.title || ' · ' ||
  to_char(o.scheduled_for at time zone 'Asia/Kuala_Lumpur','DD Mon YYYY, HH24:MI') || ' Malaysia time'
from public.preventive_work_order o
where o.status = 'assigned' and o.cancelled_at is null and o.worker_id is not null
  and o.due_at >= now();

create function uni360_private.submit_worker_leave(kind text, first_day date, last_day date, explanation text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  worker uuid := auth.uid();
  request_id uuid;
begin
  if not public.can_read_own_workforce(worker) then
    raise exception 'An active worker account is required.' using errcode = '42501';
  end if;
  if first_day is null or last_day is null or first_day < (now() at time zone 'Asia/Kuala_Lumpur')::date
    or last_day not between first_day and first_day + 365 then
    raise exception 'Choose today or a future start date and an end date within one year.' using errcode = '23514';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(360, 2);
  if exists (select 1 from maintenance_api.worker_leave_request r
    where r.worker_id = worker and r.status in ('pending','approved')
      and r.starts_on <= last_day and r.ends_on >= first_day) then
    raise exception 'You already have a pending or approved request for these dates.' using errcode = '23514';
  end if;
  insert into maintenance_api.worker_leave_request(worker_id,leave_type,starts_on,ends_on,reason)
    values (worker,kind,first_day,last_day,btrim(explanation)) returning id into request_id;
  return request_id;
end;
$$;

-- Keep the approved slot and apply the same eligibility, workload and
-- cross-module reservation checks as the preventive scheduler.
create function uni360_private.leave_replacement(target_order uuid, absent_worker uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select w.worker_id
  from public.preventive_work_order o
  join public.preventive_task_plan p on p.id = o.plan_id
  join maintenance_api.preventive_task_definition t on t.id = p.task_definition_id
  left join public.preventive_zone z on z.id = p.zone_id
  join public.worker_profile absent on absent.worker_id = absent_worker
  join public.worker_profile w on lower(btrim(w.assigned_zone)) =
    lower(btrim(coalesce(z.name, absent.assigned_zone)))
  join public.account a on a.user_id = w.worker_id
  cross join lateral (select
    date_trunc('day',o.scheduled_for at time zone 'Asia/Kuala_Lumpur') as local_day,
    ceil(extract(epoch from (o.due_at - o.scheduled_for)) / 60)::integer as minutes
  ) slot
  cross join lateral (select
    slot.local_day at time zone 'Asia/Kuala_Lumpur' as opens,
    (slot.local_day + interval '1 day') at time zone 'Asia/Kuala_Lumpur' as closes
  ) day
  cross join lateral (
    select coalesce(sum(coalesce(c.actual_minutes, ceil(extract(epoch from
      (least(b.due_at, day.closes) - greatest(b.scheduled_for, day.opens))) / 60)::integer)),0) as booked
    from public.preventive_work_order b
    left join maintenance_api.preventive_work_completion c on c.work_order_id = b.id
    where b.worker_id = w.worker_id and b.cancelled_at is null and b.id <> o.id
      and b.scheduled_for < day.closes and b.due_at > day.opens
  ) load
  where o.id = target_order and o.scheduled_for >= now()
    and w.worker_id <> absent_worker and a.is_active and a.role = 'worker'
    and lower(btrim(w.employment_status)) = 'active'
    and (t.required_job_role is null or lower(btrim(w.job_role)) = lower(btrim(t.required_job_role)))
    and (t.required_skill_id is null or exists (
      select 1 from maintenance_api.worker_skill s where s.worker_id = w.worker_id and s.skill_id = t.required_skill_id))
    and exists (select 1 from maintenance_api.worker_availability v
      where v.worker_id = w.worker_id and lower(btrim(v.availability_status)) = 'available'
        and lower(btrim(v.leave_status)) in ('none','rejected')
        and v.shift_start <= o.scheduled_for and v.shift_end >= o.due_at)
    and not exists (select 1 from maintenance_api.worker_availability v where v.worker_id = w.worker_id
      and ((lower(btrim(v.availability_status)) = 'unavailable'
          and v.shift_start < o.due_at and v.shift_end > o.scheduled_for)
        or (lower(btrim(v.leave_status)) = 'approved'
          and v.shift_start < greatest(day.closes,o.due_at) and v.shift_end > day.opens)))
    and not exists (select 1 from public.preventive_work_order b
      where b.worker_id = w.worker_id and b.cancelled_at is null and b.id <> o.id
        and b.scheduled_for < o.due_at and b.due_at > o.scheduled_for)
    and not exists (select 1 from public.corrective_incident i where i.worker_id = w.worker_id
      and i.status in ('assigned','acknowledged','checked_in','in_progress')
      and i.due_at > greatest(now(), o.scheduled_for) and i.due_at - interval '1 hour' < o.due_at)
    and load.booked + slot.minutes <= w.daily_work_limit_minutes
    and o.due_at <= day.closes
  order by load.booked, w.current_workload, a.employee_id, w.worker_id
  limit 1;
$$;

create function uni360_private.review_worker_leave(target_request uuid, approve boolean, feedback text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  request maintenance_api.worker_leave_request;
  opens timestamptz;
  closes timestamptz;
  leave_slot uuid;
  replacement uuid;
  target_order uuid;
  reassigned integer := 0;
  uncovered integer := 0;
  active integer := 0;
  result text;
begin
  if not public.can_manage_workforce() then
    raise exception 'An active administrator account is required.' using errcode = '42501';
  end if;
  if approve is null or (not approve and nullif(btrim(feedback),'') is null) then
    raise exception 'Give a reason when rejecting a request.' using errcode = '23514';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(360, 2);
  select * into request from maintenance_api.worker_leave_request r where r.id = target_request for update;
  if not found or request.status <> 'pending' then
    raise exception 'This request is no longer pending. Refresh the list.' using errcode = '23514';
  end if;
  result := case when approve then 'approved' else 'rejected' end;
  if approve then
    if request.ends_on < (now() at time zone 'Asia/Kuala_Lumpur')::date then
      raise exception 'These leave dates have passed.' using errcode = '23514';
    end if;
    opens := request.starts_on::timestamp at time zone 'Asia/Kuala_Lumpur';
    closes := (request.ends_on + 1)::timestamp at time zone 'Asia/Kuala_Lumpur';
    insert into maintenance_api.worker_availability
      (worker_id,availability,shift_start,shift_end,availability_status,leave_status)
    values (request.worker_id,'Approved leave',opens,closes,'unavailable','approved')
    returning availability_id into leave_slot;

    select count(*) into active from public.preventive_work_order
      where worker_id = request.worker_id and status = 'in_progress' and cancelled_at is null
        and scheduled_for < closes and due_at > opens;
    for target_order in select id from public.preventive_work_order
      where worker_id = request.worker_id and status = 'assigned' and cancelled_at is null
        and scheduled_for < closes and due_at > opens
      order by scheduled_for,id for update
    loop
      replacement := uni360_private.leave_replacement(target_order, request.worker_id);
      update public.preventive_work_order set worker_id = replacement where id = target_order;
      if replacement is null then uncovered := uncovered + 1;
      else reassigned := reassigned + 1;
      end if;
    end loop;
  end if;

  update maintenance_api.worker_leave_request set status = result, reviewed_at = now(), reviewed_by = auth.uid(),
    review_note = nullif(btrim(feedback),''), availability_id = leave_slot,
    reassigned_count = reassigned, uncovered_count = uncovered, active_count = active
  where id = target_request;
  insert into maintenance_api.preventive_notification(recipient_id,leave_request_id,title,message)
  values (request.worker_id,target_request,case when approve then 'Leave approved' else 'Leave rejected' end,
    to_char(request.starts_on,'DD Mon YYYY') || case when request.ends_on <> request.starts_on
      then ' to ' || to_char(request.ends_on,'DD Mon YYYY') else '' end ||
      coalesce(' · ' || nullif(btrim(feedback),''),''));
  return jsonb_build_object('status',result,'reassigned',reassigned,'uncovered',uncovered,'active',active);
end;
$$;

create function uni360_private.protect_approved_leave_slot() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.record_kind = 'worker_availability' and exists (
    select 1 from maintenance_api.worker_leave_request r where r.availability_id = old.availability_id
  ) then
    raise exception 'This availability comes from an approved leave request.' using errcode = '23514';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger protect_approved_leave_slot before update or delete on uni360_data.maintenance_workforce
for each row execute function uni360_private.protect_approved_leave_slot();

create function public.save_account_profile(target_account uuid, name text, phone_number text, photo text default null)
returns public.account language sql security invoker set search_path = '' as $$
  select uni360_private.save_account_profile(target_account,name,phone_number,photo);
$$;
create function public.submit_worker_leave(kind text, first_day date, last_day date, explanation text)
returns uuid language sql security invoker set search_path = '' as $$
  select uni360_private.submit_worker_leave(kind,first_day,last_day,explanation);
$$;
create function public.review_worker_leave(target_request uuid, approve boolean, feedback text default null)
returns jsonb language sql security invoker set search_path = '' as $$
  select uni360_private.review_worker_leave(target_request,approve,feedback);
$$;

revoke all on function uni360_private.notify_preventive_work(), uni360_private.protect_approved_leave_slot(),
  uni360_private.leave_replacement(uuid,uuid),
  uni360_private.save_account_profile(uuid,text,text,text), public.save_account_profile(uuid,text,text,text),
  uni360_private.submit_worker_leave(text,date,date,text), public.submit_worker_leave(text,date,date,text),
  uni360_private.review_worker_leave(uuid,boolean,text), public.review_worker_leave(uuid,boolean,text)
from public, anon, authenticated;
grant execute on function uni360_private.save_account_profile(uuid,text,text,text), public.save_account_profile(uuid,text,text,text),
  uni360_private.submit_worker_leave(text,date,date,text), public.submit_worker_leave(text,date,date,text),
  uni360_private.review_worker_leave(uuid,boolean,text), public.review_worker_leave(uuid,boolean,text)
to authenticated;

commit;
