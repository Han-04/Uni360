begin;

alter table public.preventive_work_order
  add column status text not null default 'assigned'
    check (status in ('assigned', 'in_progress', 'submitted', 'completed')),
  add column checked_items integer[] not null default '{}',
  add column started_at timestamptz,
  add column submitted_at timestamptz,
  add column worker_notes text not null default '',
  add column review_note text not null default '';

create index preventive_work_order_submitted_idx
  on public.preventive_work_order(submitted_at, id)
  where status = 'submitted' and cancelled_at is null;

create or replace function uni360_private.preventive_lock_completed_order() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if old.status <> 'assigned' and (
    new.worker_id is distinct from old.worker_id or new.schedule_id is distinct from old.schedule_id
    or new.scheduled_for is distinct from old.scheduled_for or new.due_at is distinct from old.due_at
  ) then
    raise exception 'Work that has started cannot be reassigned or rescheduled.' using errcode = '23514';
  end if;
  if old.status = 'completed' and new.cancelled_at is distinct from old.cancelled_at then
    raise exception 'Completed work cannot be cancelled.' using errcode = '23514';
  end if;
  return new;
end;
$$;

update public.preventive_work_order o set status = 'completed'
where exists (select 1 from public.preventive_work_completion c where c.work_order_id = o.id);

-- Completion rows represent approved work and continue to support worked-time reporting.
revoke insert (work_order_id, notes, photo_path) on public.preventive_work_completion from authenticated;

create function uni360_private.mark_preventive_work_completed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.preventive_work_order set status = 'completed' where id = new.work_order_id;
  return new;
end;
$$;
create trigger mark_preventive_work_completed after insert on public.preventive_work_completion
for each row execute function uni360_private.mark_preventive_work_completed();

create table public.preventive_work_evidence (
  path text primary key,
  work_order_id uuid not null references public.preventive_work_order(id),
  created_at timestamptz not null default now()
);
create index preventive_work_evidence_order_idx on public.preventive_work_evidence(work_order_id, created_at);
alter table public.preventive_work_evidence enable row level security;
revoke all on public.preventive_work_evidence from public, anon, authenticated;
grant select on public.preventive_work_evidence to authenticated;
create policy work_evidence_read on public.preventive_work_evidence for select to authenticated
  using (exists (select 1 from public.preventive_work_order o where o.id = work_order_id and o.cancelled_at is null));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('preventive-work-evidence', 'preventive-work-evidence', false, 10485760,
  array['image/jpeg', 'image/png', 'image/webp']);

create policy preventive_evidence_upload on storage.objects for insert to authenticated
  with check (
    bucket_id = 'preventive-work-evidence'
    and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f]{32}\.(jpg|png|webp)$'
    and split_part(name, '/', 1) = (select auth.uid())::text
    and exists (
      select 1 from public.preventive_work_order o
      where o.id::text = split_part(name, '/', 2) and o.worker_id = (select auth.uid())
        and o.status = 'in_progress' and o.cancelled_at is null
        and public.can_read_own_workforce(o.worker_id)
    )
  );
create policy preventive_evidence_read on storage.objects for select to authenticated
  using (
    bucket_id = 'preventive-work-evidence' and (
      exists (select 1 from public.preventive_work_evidence e where e.path = storage.objects.name)
      or (
        owner_id = (select auth.uid())::text and exists (
          select 1 from public.preventive_work_order o
          where o.id::text = split_part(name, '/', 2) and o.worker_id = (select auth.uid())
            and o.status = 'in_progress' and o.cancelled_at is null
        )
      )
    )
  );
create policy preventive_evidence_cleanup on storage.objects for delete to authenticated
  using (
    bucket_id = 'preventive-work-evidence' and owner_id = (select auth.uid())::text
    and not exists (select 1 from public.preventive_work_evidence e where e.path = storage.objects.name)
  );

create function uni360_private.worker_work_order_action(
  target_order uuid, action text, item_index integer, item_checked boolean, evidence_path text, notes text
) returns text language plpgsql security definer set search_path = '' as $$
declare
  order_row public.preventive_work_order%rowtype;
begin
  select * into order_row from public.preventive_work_order
  where id = target_order and worker_id = (select auth.uid()) and cancelled_at is null
    and public.can_read_own_workforce(worker_id)
  for update;
  if not found then
    raise exception 'This work order is unavailable to your account.' using errcode = '42501';
  end if;

  if action = 'start' and order_row.status in ('assigned', 'in_progress') then
    update public.preventive_work_order
      set status = 'in_progress', started_at = coalesce(started_at, now()) where id = target_order;
    return 'in_progress';
  end if;
  if action = 'submit' and order_row.status = 'submitted' then
    return 'submitted';
  end if;
  if order_row.status <> 'in_progress' then
    raise exception 'This work order is currently read-only.' using errcode = '23514';
  end if;

  case action
    when 'check' then
      if item_index is null or item_index < 0 or item_index >= cardinality(order_row.checklist) or item_checked is null then
        raise exception 'Choose a valid checklist item.' using errcode = '23514';
      end if;
      update public.preventive_work_order
        set checked_items = array(
          select distinct n from unnest(array_remove(order_row.checked_items, item_index)
            || case when item_checked then array[item_index] else '{}'::integer[] end) as items(n) order by n
        ) where id = target_order;
    when 'attach' then
      if evidence_path is null or evidence_path !~ ('^' || order_row.worker_id || '/' || target_order || '/[0-9a-f]{32}\.(jpg|png|webp)$')
         or not exists (
           select 1 from storage.objects where bucket_id = 'preventive-work-evidence' and name = evidence_path
             and owner_id = order_row.worker_id::text
         ) then
        raise exception 'Upload a photo for this work order before attaching it.' using errcode = '23514';
      end if;
      insert into public.preventive_work_evidence(path, work_order_id)
      values (evidence_path, target_order) on conflict (path) do nothing;
    when 'submit' then
      if cardinality(order_row.checked_items) <> cardinality(order_row.checklist) then
        raise exception 'Tick every checklist item before submitting.' using errcode = '23514';
      end if;
      if not exists (select 1 from public.preventive_work_evidence where work_order_id = target_order) then
        raise exception 'Upload at least one evidence photo before submitting.' using errcode = '23514';
      end if;
      update public.preventive_work_order
        set status = 'submitted', submitted_at = now(), worker_notes = btrim(coalesce(notes, '')), review_note = ''
        where id = target_order;
      return 'submitted';
    else
      raise exception 'Unsupported work order action.' using errcode = '23514';
  end case;
  return 'in_progress';
end;
$$;

create function uni360_private.review_work_submission(target_order uuid, approve boolean, feedback text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  order_row public.preventive_work_order%rowtype;
begin
  if not public.can_manage_workforce() then
    raise exception 'An active administrator account is required.' using errcode = '42501';
  end if;
  select o.* into order_row from public.preventive_work_order o
  join public.preventive_task_plan p on p.id = o.plan_id
  where o.id = target_order and o.cancelled_at is null and uni360_private.preventive_manage_zone(p.zone_id)
  for update of o;
  if not found then
    raise exception 'This work order is outside your scope or is unavailable.' using errcode = '42501';
  end if;
  if order_row.status = 'completed' and approve then return 'completed'; end if;
  if order_row.status <> 'submitted' or approve is null then
    raise exception 'Refresh the queue. This work order is no longer awaiting review.' using errcode = '23514';
  end if;
  if approve then
    insert into public.preventive_work_completion(work_order_id, worker_id, notes, photo_path)
    values (target_order, order_row.worker_id, order_row.worker_notes, (
      select path from public.preventive_work_evidence where work_order_id = target_order order by created_at, path limit 1
    ));
    return 'completed';
  end if;
  if nullif(btrim(feedback), '') is null then
    raise exception 'Enter feedback so the worker knows what to fix.' using errcode = '23514';
  end if;
  update public.preventive_work_order set status = 'in_progress', submitted_at = null, review_note = btrim(feedback)
  where id = target_order;
  return 'in_progress';
end;
$$;

create function public.worker_work_order_action(
  target_order uuid, action text, item_index integer default null, item_checked boolean default null,
  evidence_path text default null, notes text default null
) returns text language sql security invoker set search_path = '' as $$
  select uni360_private.worker_work_order_action(target_order, action, item_index, item_checked, evidence_path, notes);
$$;
create function public.review_work_submission(target_order uuid, approve boolean, feedback text default null)
returns text language sql security invoker set search_path = '' as $$
  select uni360_private.review_work_submission(target_order, approve, feedback);
$$;

revoke all on function uni360_private.mark_preventive_work_completed(),
  uni360_private.worker_work_order_action(uuid, text, integer, boolean, text, text),
  uni360_private.review_work_submission(uuid, boolean, text),
  public.worker_work_order_action(uuid, text, integer, boolean, text, text),
  public.review_work_submission(uuid, boolean, text) from public, anon, authenticated;
grant execute on function uni360_private.worker_work_order_action(uuid, text, integer, boolean, text, text),
  uni360_private.review_work_submission(uuid, boolean, text),
  public.worker_work_order_action(uuid, text, integer, boolean, text, text),
  public.review_work_submission(uuid, boolean, text) to authenticated;

commit;
