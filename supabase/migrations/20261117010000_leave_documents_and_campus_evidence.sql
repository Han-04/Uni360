begin;

alter table maintenance_api.worker_leave_request
  add column document_path text unique,
  add column document_name text,
  add constraint worker_leave_document_complete check (
    (document_path is null and document_name is null)
    or (document_path is not null and document_name is not null
      and char_length(btrim(document_name)) between 1 and 255)
  );

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('leave-documents', 'leave-documents', false, 10485760,
  array['application/pdf','image/jpeg','image/png','image/webp']);

create policy leave_document_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'leave-documents'
    and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(pdf|jpg|png|webp)$'
    and split_part(name, '/', 1) = (select auth.uid())::text
    and public.can_read_own_workforce((select auth.uid())));
create policy leave_document_read on storage.objects for select to authenticated
  using (bucket_id = 'leave-documents' and (
    (owner_id = (select auth.uid())::text and public.can_read_own_workforce((select auth.uid())))
    or exists (select 1 from maintenance_api.worker_leave_request r
      where r.document_path = storage.objects.name)
  ));
create policy leave_document_cleanup on storage.objects for delete to authenticated
  using (bucket_id = 'leave-documents' and owner_id = (select auth.uid())::text
    and public.can_read_own_workforce((select auth.uid()))
    and not exists (select 1 from maintenance_api.worker_leave_request r
      where r.document_path = storage.objects.name));

create function uni360_private.submit_worker_leave_with_document(
  kind text, first_day date, last_day date, explanation text, document text, filename text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  worker uuid := auth.uid();
  request_id uuid;
begin
  if not public.can_read_own_workforce(worker) then
    raise exception 'An active worker account is required.' using errcode = '42501';
  end if;
  if document is null or document !~ ('^' || worker || '/[0-9a-f-]{36}\.(pdf|jpg|png|webp)$')
    or not exists (select 1 from storage.objects o
      where o.bucket_id = 'leave-documents' and o.name = document and o.owner_id = worker::text)
  then
    raise exception 'Upload a supporting document from your own account.' using errcode = '23514';
  end if;
  if filename is null or char_length(btrim(filename)) not between 1 and 255 then
    raise exception 'Choose a supporting document with a valid filename.' using errcode = '23514';
  end if;

  request_id := uni360_private.submit_worker_leave(kind, first_day, last_day, explanation);
  update maintenance_api.worker_leave_request
    set document_path = document, document_name = btrim(filename)
    where id = request_id;
  return request_id;
end;
$$;

create function public.submit_worker_leave_with_document(
  kind text, first_day date, last_day date, explanation text, document text, filename text
) returns uuid language sql security invoker set search_path = '' as $$
  select uni360_private.submit_worker_leave_with_document(kind, first_day, last_day, explanation, document, filename);
$$;

alter table public.preventive_work_order add column location_verified_at timestamptz;

-- The maintenance_api view was created with SELECT * and keeps a fixed column list.
create or replace view maintenance_api.preventive_work_order with (security_invoker = true) as
  select * from public.preventive_work_order;
grant select (location_verified_at) on maintenance_api.preventive_work_order to authenticated;

-- TAR UMT Kuala Lumpur campus outline. Data © OpenStreetMap contributors (ODbL).
-- Source: https://www.openstreetmap.org/way/421754739
create function uni360_private.require_tar_umt_fix(
  latitude double precision, longitude double precision, accuracy double precision, fix_at timestamptz
) returns void language plpgsql stable set search_path = '' as $$
declare
  boundary constant polygon := '(
    (101.7248779,3.2168235),(101.7256488,3.2174668),(101.7256794,3.2177158),
    (101.726406,3.2181519),(101.7270506,3.2183938),(101.7282973,3.2183954),
    (101.7292789,3.2183505),(101.7306461,3.218533),(101.7318332,3.2184341),
    (101.7341577,3.2184227),(101.7341734,3.2171545),(101.7345021,3.2172294),
    (101.734667,3.217373),(101.7354553,3.2184446),(101.7356951,3.2181939),
    (101.7354796,3.2180063),(101.7351553,3.2176121),(101.7349774,3.2171743),
    (101.7351836,3.2168512),(101.7352492,3.2163668),(101.7358183,3.2164324),
    (101.7358953,3.2159552),(101.7355741,3.215813),(101.734729,3.2157603),
    (101.7343225,3.2156779),(101.7338717,3.2156474),(101.733425,3.2155203),
    (101.7330312,3.2153056),(101.7324152,3.2148373),(101.7317368,3.2143536),
    (101.7314919,3.2140305),(101.7313806,3.213976),(101.7304977,3.2145949),
    (101.7300605,3.2150169),(101.7299843,3.2151121),(101.7296452,3.2152326),
    (101.7293113,3.2152556),(101.7290423,3.2152276),(101.7284914,3.215077),
    (101.7282689,3.2150047),(101.7277252,3.21451),(101.7273667,3.214138),
    (101.7270742,3.2137653),(101.7269242,3.2136495),(101.7267576,3.2135388),
    (101.7261481,3.2132686),(101.7259625,3.2133481),(101.7259025,3.2141702),
    (101.7257337,3.214795),(101.7252646,3.2159169),(101.7248592,3.2166502)
  )'::polygon;
begin
  if fix_at is null or fix_at not between now() - interval '2 minutes' and now() + interval '15 seconds' then
    raise exception 'Get a fresh GPS reading and try again.' using errcode = '23514';
  end if;
  if accuracy is null or accuracy not between 0.01 and 50 then
    raise exception 'GPS accuracy is too low. Enable precise location or move to an open area.' using errcode = '23514';
  end if;
  if latitude is null or longitude is null or latitude not between -90 and 90
    or longitude not between -180 and 180 or not (boundary @> point(longitude, latitude)) then
    raise exception 'Your GPS reading is outside the TAR UMT Kuala Lumpur campus.' using errcode = '23514';
  end if;
end;
$$;

alter policy preventive_evidence_upload on storage.objects
  with check (
    bucket_id = 'preventive-work-evidence'
    and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/camera-[0-9a-f]{32}\.(jpg|png|webp)$'
    and split_part(name, '/', 1) = (select auth.uid())::text
    and exists (select 1 from public.preventive_work_order o
      where o.id::text = split_part(name, '/', 2) and o.worker_id = (select auth.uid())
        and o.status = 'in_progress' and o.cancelled_at is null
        and public.can_read_own_workforce(o.worker_id))
  );

create function uni360_private.require_preventive_submission_evidence()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'submitted' and new.status = 'in_progress' then
    new.location_verified_at := null;
  end if;
  if new.status = 'submitted' and old.status is distinct from new.status then
    if new.location_verified_at is distinct from now() then
      raise exception 'Verify your campus location before submitting.' using errcode = '23514';
    end if;
    if not exists (select 1 from maintenance_api.preventive_work_evidence e
      where e.work_order_id = new.id and split_part(e.path, '/', 3) like 'camera-%') then
      raise exception 'Take an evidence photo with the in-app camera before submitting.' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger require_preventive_submission_evidence before update of status
  on public.preventive_work_order for each row execute function uni360_private.require_preventive_submission_evidence();

create function uni360_private.preventive_campus_action(
  target_order uuid, action text, latitude double precision, longitude double precision,
  accuracy double precision, fix_at timestamptz, photo text, notes text
) returns text language plpgsql security definer set search_path = '' as $$
declare
  order_row public.preventive_work_order;
begin
  select * into order_row from public.preventive_work_order o
  where o.id = target_order and o.worker_id = (select auth.uid())
    and o.cancelled_at is null and public.can_read_own_workforce(o.worker_id)
  for update;
  if not found then
    raise exception 'This work order is unavailable to your account.' using errcode = '42501';
  end if;
  if action = 'submit' and order_row.status = 'submitted' then return 'submitted'; end if;
  if order_row.status <> 'in_progress' then
    raise exception 'Start the task before verifying your location or taking evidence.' using errcode = '23514';
  end if;

  perform uni360_private.require_tar_umt_fix(latitude, longitude, accuracy, fix_at);
  case action
    when 'verify' then
      update public.preventive_work_order set location_verified_at = now() where id = target_order;
    when 'camera' then
      if photo is null or photo !~ ('^' || order_row.worker_id || '/' || target_order || '/camera-[0-9a-f]{32}\.(jpg|png|webp)$')
        or not exists (select 1 from storage.objects s where s.bucket_id = 'preventive-work-evidence'
          and s.name = photo and s.owner_id = order_row.worker_id::text)
      then
        raise exception 'Take and attach a photo for this work order.' using errcode = '23514';
      end if;
      insert into maintenance_api.preventive_work_evidence (path, work_order_id)
      select photo, target_order
      where not exists (select 1 from maintenance_api.preventive_work_evidence e where e.path = photo);
      update public.preventive_work_order set location_verified_at = now() where id = target_order;
    when 'submit' then
      update public.preventive_work_order set location_verified_at = now() where id = target_order;
      return uni360_private.worker_work_order_action(target_order, 'submit', null, null, null, notes);
    else
      raise exception 'Unsupported work order action.' using errcode = '23514';
  end case;
  return 'in_progress';
end;
$$;

create function public.preventive_campus_action(
  target_order uuid, action text, latitude double precision, longitude double precision,
  accuracy double precision, fix_at timestamptz, photo text default null, notes text default null
) returns text language sql security invoker set search_path = '' as $$
  select uni360_private.preventive_campus_action(target_order,action,latitude,longitude,accuracy,fix_at,photo,notes);
$$;

revoke all on function uni360_private.require_tar_umt_fix(double precision,double precision,double precision,timestamptz),
  uni360_private.require_preventive_submission_evidence(),
  uni360_private.preventive_campus_action(uuid,text,double precision,double precision,double precision,timestamptz,text,text),
  public.preventive_campus_action(uuid,text,double precision,double precision,double precision,timestamptz,text,text),
  uni360_private.submit_worker_leave_with_document(text,date,date,text,text,text),
  public.submit_worker_leave_with_document(text,date,date,text,text,text)
from public, anon, authenticated;
grant execute on function
  uni360_private.preventive_campus_action(uuid,text,double precision,double precision,double precision,timestamptz,text,text),
  public.preventive_campus_action(uuid,text,double precision,double precision,double precision,timestamptz,text,text),
  uni360_private.submit_worker_leave_with_document(text,date,date,text,text,text),
  public.submit_worker_leave_with_document(text,date,date,text,text,text)
to authenticated;

notify pgrst, 'reload schema';

commit;
