begin;

alter type public.account_role add value if not exists 'reporter';

create table public.corrective_category (
  name text primary key check (char_length(btrim(name)) between 2 and 60),
  team text not null check (char_length(btrim(team)) between 2 and 80),
  worker_role text,
  active boolean not null default true
);

insert into public.corrective_category(name, team, worker_role) values
  ('Plumbing','Plumbing','plumber'), ('Electrical','Electrical','electrician'),
  ('Air conditioning','Mechanical','air conditioning technician'), ('Lift','Lift services','lift technician'),
  ('Furniture','Building maintenance','carpenter'), ('Building','Building maintenance','maintenance technician'),
  ('Pest control','Pest control','pest control'), ('Cleaning','Housekeeping','cleaner'),
  ('Security','Security','security'), ('Grounds','Grounds maintenance','gardener'),
  ('Other','Facilities dispatch',null);

create table uni360_private.corrective_training_example (
  category text not null references public.corrective_category(name),
  description text not null
);
alter table uni360_private.corrective_training_example enable row level security;
revoke all on table uni360_private.corrective_training_example from public, anon, authenticated;
insert into uni360_private.corrective_training_example values
  ('Plumbing','water leakage dripping pipe under sink tap leaking'), ('Plumbing','toilet blocked clogged overflow overflowing drain'),
  ('Plumbing','burst pipe flooded water broken faucet leaking valve'), ('Plumbing','sink tap has no water or low water pressure'),
  ('Electrical','exposed live electrical wire wiring sparks smoke burnt power socket'),
  ('Electrical','faulty light lamp bulb flickering classroom lighting'), ('Electrical','electrical breaker trip power outage socket switch'),
  ('Electrical','plug socket loose broken burned electrical outlet'), ('Air conditioning','air conditioning unit not cooling warm room thermostat'),
  ('Air conditioning','air conditioner dripping condensate indoor ac filter'), ('Air conditioning','aircon unit making loud rattling noise blowing hot air'),
  ('Lift','elevator lift stopped stuck people trapped between floors'), ('Lift','lift elevator doors open close stuck out of service'),
  ('Furniture','broken chair seat loose desk table leg furniture'), ('Furniture','desk drawer hinge cabinet damaged furniture'),
  ('Building','cracked wall ceiling roof plaster leak building damage'), ('Building','door lock jammed broken window glass damaged floor tiles'),
  ('Pest control','cockroach rats rodent ants infestation pests mosquitoes'), ('Pest control','bees wasp nest insect infestation near walkway'),
  ('Cleaning','dirty spill rubbish overflowing bin floor needs cleaning'), ('Cleaning','sticky floor broken glass spill garbage washroom'),
  ('Security','door access keycard entry gate security theft'), ('Security','unauthorised access broken security camera cctv'),
  ('Grounds','fallen tree branch garden grass landscaping overgrown'), ('Grounds','damaged lawn outdoor pathway branches garden');

create table public.corrective_site (
  facility_id uuid primary key references public.preventive_facility(id),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  radius_m integer not null check (radius_m between 15 and 500),
  qr_token uuid not null default gen_random_uuid()
);

create table public.corrective_incident (
  id uuid primary key,
  reference bigint generated always as identity unique,
  facility_id uuid not null,
  zone_id uuid not null,
  foreign key (facility_id, zone_id) references public.preventive_facility(id, zone_id),
  facility_name text not null,
  category text not null references public.corrective_category(name),
  title text not null check (char_length(title) between 5 and 100),
  description text not null check (char_length(description) between 10 and 2000),
  location_detail text not null check (char_length(location_detail) between 3 and 160),
  urgency text not null check (urgency in ('Low','Medium','High','Critical')),
  location_method text not null default 'manual' check (location_method in ('manual','qr')),
  approved_at timestamptz,
  triage jsonb not null default '{}',
  merged_into uuid references public.corrective_incident(id),
  linked_reference bigint,
  linked_status text,
  feedback_rating integer check (feedback_rating between 1 and 5),
  feedback_comment text,
  required_role text,
  required_skill_id uuid references public.skill(skill_id),
  reporter_id uuid not null references public.account(user_id),
  reporter_name text not null,
  worker_id uuid references public.worker_profile(worker_id),
  worker_name text,
  status text not null default 'reported' check (status in
    ('reported','needs_info','inspection','approved','merged','assigned','acknowledged','checked_in','in_progress','submitted','rework','rejected','resolved','escalated','external','dismissed')),
  checklist text[] not null,
  report_photo text unique,
  attempt integer not null default 1 check (attempt > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  target_at timestamptz,
  due_at timestamptz
);

create index corrective_incident_zone_idx on public.corrective_incident(zone_id, created_at desc);
create index corrective_incident_worker_idx on public.corrective_incident(worker_id, updated_at desc);
create index corrective_incident_reporter_idx on public.corrective_incident(reporter_id, created_at desc);
create index corrective_incident_facility_idx on public.corrective_incident(facility_id, created_at desc);
create index corrective_incident_merged_idx on public.corrective_incident(merged_into) where merged_into is not null;

create table public.corrective_visit (
  incident_id uuid not null references public.corrective_incident(id),
  attempt integer not null,
  worker_id uuid not null references public.worker_profile(worker_id),
  check_in_at timestamptz not null default now(),
  started_at timestamptz,
  accuracy_m double precision not null,
  distance_m double precision not null,
  checklist_checked integer[] not null default '{}',
  notes text,
  submitted_at timestamptz,
  primary key (incident_id, attempt)
);

create table public.corrective_position (
  incident_id uuid not null,
  attempt integer not null,
  latitude double precision not null,
  longitude double precision not null,
  primary key (incident_id, attempt),
  foreign key (incident_id, attempt) references public.corrective_visit(incident_id, attempt)
);

create table public.corrective_photo (
  path text primary key,
  incident_id uuid not null,
  attempt integer not null,
  foreign key (incident_id, attempt) references public.corrective_visit(incident_id, attempt),
  captured_at timestamptz not null default now()
);
create index corrective_photo_visit_idx on public.corrective_photo(incident_id, attempt);

create table public.corrective_event (
  id bigint generated always as identity primary key,
  incident_id uuid not null references public.corrective_incident(id),
  actor_id uuid not null references public.account(user_id),
  actor_name text not null,
  event text not null,
  note text not null default '',
  occurred_at timestamptz not null default now()
);
create index corrective_event_incident_idx on public.corrective_event(incident_id, id desc);

-- Only explicitly classified, unstarted preventive work can be postponed.
create table public.corrective_deferrable_order (
  order_id uuid primary key references public.preventive_work_order(id),
  marked_by uuid not null references public.account(user_id),
  marked_at timestamptz not null default now()
);

create table public.corrective_notification (
  id bigint generated always as identity primary key,
  recipient_id uuid not null references public.account(user_id),
  incident_id uuid not null references public.corrective_incident(id),
  title text not null,
  incident_title text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index corrective_notification_recipient_idx on public.corrective_notification(recipient_id, id desc);

alter table public.corrective_category enable row level security;
alter table public.corrective_site enable row level security;
alter table public.corrective_incident enable row level security;
alter table public.corrective_visit enable row level security;
alter table public.corrective_position enable row level security;
alter table public.corrective_photo enable row level security;
alter table public.corrective_event enable row level security;
alter table public.corrective_deferrable_order enable row level security;
alter table public.corrective_notification enable row level security;

create function uni360_private.corrective_active() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.account where user_id = auth.uid() and is_active);
$$;

create function uni360_private.corrective_manage(target_zone uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.can_manage_workforce() and uni360_private.preventive_manage_zone(target_zone);
$$;

create function uni360_private.corrective_access(target uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select uni360_private.corrective_active() and exists (
    select 1 from public.corrective_incident i where i.id = target and (
      i.worker_id = auth.uid() or i.reporter_id = auth.uid()
      or uni360_private.corrective_manage(i.zone_id)
    )
  );
$$;

do $$
declare item text;
begin
  foreach item in array array['corrective_category','corrective_site','corrective_incident','corrective_visit','corrective_position','corrective_photo',
                              'corrective_event','corrective_deferrable_order','corrective_notification'] loop
    execute format('revoke all on table public.%I from public, anon, authenticated', item);
    execute format('grant select on table public.%I to authenticated', item);
  end loop;
end;
$$;
create policy corrective_category_read on public.corrective_category for select to authenticated
  using (uni360_private.corrective_active());
create policy corrective_category_manage on public.corrective_category for all to authenticated
  using (public.can_manage_workforce()) with check (public.can_manage_workforce());
grant insert, update (team, worker_role, active) on public.corrective_category to authenticated;
create policy corrective_incident_read on public.corrective_incident for select to authenticated
  using (uni360_private.corrective_access(id));
create policy corrective_visit_read on public.corrective_visit for select to authenticated
  using (exists (select 1 from public.corrective_incident i where i.id = incident_id and
    (uni360_private.corrective_manage(i.zone_id) or (i.worker_id = auth.uid() and corrective_visit.worker_id = auth.uid()))));
create policy corrective_position_read on public.corrective_position for select to authenticated
  using (exists (select 1 from public.corrective_incident i where i.id = incident_id
    and uni360_private.corrective_manage(i.zone_id)));
create policy corrective_photo_read on public.corrective_photo for select to authenticated
  using (exists (select 1 from public.corrective_visit v
    where v.incident_id = corrective_photo.incident_id and v.attempt = corrective_photo.attempt));
create policy corrective_event_read on public.corrective_event for select to authenticated
  using (uni360_private.corrective_access(incident_id));
create policy corrective_site_read on public.corrective_site for select to authenticated
  using (exists (select 1 from public.preventive_facility f where f.id = facility_id
    and uni360_private.corrective_manage(f.zone_id)));

create policy corrective_notification_read on public.corrective_notification for select to authenticated
  using (recipient_id = auth.uid() and uni360_private.corrective_active());
create policy corrective_notification_update on public.corrective_notification for update to authenticated
  using (recipient_id = auth.uid() and uni360_private.corrective_active())
  with check (recipient_id = auth.uid() and uni360_private.corrective_active());
grant update (read_at) on table public.corrective_notification to authenticated;

create function uni360_private.corrective_registered_photo(object_path text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.corrective_incident where report_photo = object_path)
      or exists (select 1 from public.corrective_photo where path = object_path);
$$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('corrective-evidence', 'corrective-evidence', false, 10485760, array['image/jpeg','image/png','image/webp']);

create policy corrective_evidence_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'corrective-evidence' and uni360_private.corrective_active()
  and split_part(name, '/', 1) = auth.uid()::text
  and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/(report|work)/[0-9a-f-]{36}\.(jpg|png|webp)$'
  and (split_part(name, '/', 3) = 'report' or exists (
    select 1 from public.corrective_incident i where i.id::text = split_part(name, '/', 2)
      and i.worker_id = auth.uid() and i.status = 'in_progress'
  ))
);
create policy corrective_evidence_read on storage.objects for select to authenticated using (
  bucket_id = 'corrective-evidence' and uni360_private.corrective_active() and (
    (owner_id = auth.uid()::text and not uni360_private.corrective_registered_photo(name))
    or exists (select 1 from public.corrective_incident i where i.report_photo = storage.objects.name)
    or exists (select 1 from public.corrective_photo p where p.path = storage.objects.name)
  )
);
create policy corrective_evidence_remove_draft on storage.objects for delete to authenticated using (
  bucket_id = 'corrective-evidence' and uni360_private.corrective_active() and owner_id = auth.uid()::text
  and not uni360_private.corrective_registered_photo(name)
);

create function uni360_private.corrective_log(
  target uuid, event_name text, details text default '', escalation_to text default 'both'
) returns void language plpgsql security invoker set search_path = '' as $$
begin
  insert into public.corrective_event (incident_id, actor_id, actor_name, event, note)
  select target, user_id, full_name, event_name, coalesce(details, '')
  from public.account where user_id = auth.uid() and is_active;
  insert into public.corrective_notification (recipient_id, incident_id, title, incident_title)
  select a.user_id, i.id, event_name, i.title
  from public.corrective_incident i join public.account a on a.is_active and (
    (a.user_id = i.worker_id and event_name in ('Assigned','Reassigned','Work approved','Rework requested','Evidence rejected'))
    or (a.user_id = i.reporter_id and event_name in ('Reported','Report approved','More information requested','Inspection requested','Report merged','Assigned','Reassigned','Escalated','External assistance required','Work approved','Evidence rejected','Report dismissed','Issue reopened'))
    or (event_name in ('Reported','Additional information provided','Issue reopened','Escalated','Evidence submitted','External assistance required','Worker requested assistance') and (
      (escalation_to in ('both','supervisors') and a.role = 'super_administrator')
      or (escalation_to in ('both','zone') and exists (select 1 from public.preventive_zone_admin za
        where za.zone_id = i.zone_id and za.administrator_id = a.user_id))
    ))
  )
  where i.id = target;
  if event_name in ('Assigned','Reassigned','Work approved','Rework requested','Evidence rejected','Report dismissed','Issue reopened') then
    insert into public.corrective_notification(recipient_id, incident_id, title, incident_title)
    select i.reporter_id, i.id, event_name, i.title
    from public.corrective_incident i join public.account a on a.user_id = i.reporter_id and a.is_active
    where i.merged_into = target;
  end if;
end;
$$;

create function uni360_private.corrective_sync_linked() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if old.status is distinct from new.status and new.merged_into is null then
    update public.corrective_incident set linked_status = new.status, updated_at = now() where merged_into = new.id;
  end if;
  return new;
end;
$$;
create trigger corrective_sync_linked after update of status on public.corrective_incident
for each row execute function uni360_private.corrective_sync_linked();

create function uni360_private.corrective_terms(value text) returns text[]
language sql immutable set search_path = '' as $$
  select array(select distinct token from regexp_split_to_table(lower(value), '[^a-z0-9]+') as token
    where length(token) >= 3 and token not in ('the','and','for','are','with','was','not','this','there','from','has','near'));
$$;

create function uni360_private.corrective_similarity(a text[], b text[]) returns numeric
language sql immutable set search_path = '' as $$
  select coalesce((select count(*)::numeric from (select unnest(a) intersect select unnest(b)) x)
    / nullif((select count(*) from (select unnest(a) union select unnest(b)) y), 0), 0);
$$;

create function uni360_private.corrective_predict(input_text text, suggested text, reported_priority text, has_photo boolean)
returns jsonb language sql stable set search_path = '' as $$
  with nearest as (
    select e.category, uni360_private.corrective_similarity(
      uni360_private.corrective_terms(input_text), uni360_private.corrective_terms(e.description)
    ) score
    from uni360_private.corrective_training_example e join public.corrective_category c on c.name = e.category
    where c.active order by score desc, e.category, e.description limit 5
  ), ranked as (
    select category, sum(score) weight, max(score) best_score
    from nearest where score > 0 group by category
    order by weight desc, best_score desc, category
  )
  select jsonb_build_object(
    'category', coalesce((select category from ranked limit 1), suggested),
    'confidence', (select round(100 * weight / sum(weight) over (), 0) from ranked limit 1),
    'priority', case when input_text ~* 'exposed.{0,18}(wire|wiring)|sparks|smoke|fire|trapped|live wire' then 'Critical'
      when input_text ~* 'flood|burst pipe|overflow|power outage|out of service' then
        case when reported_priority = 'Critical' then 'Critical' else 'High' end
      else reported_priority end,
    'evidence_attached', has_photo,
    'model', 'Text similarity classifier v1'
  );
$$;

create function uni360_private.corrective_owned_photo(photo text, target uuid, kind text)
returns boolean language sql stable security invoker set search_path = '' as $$
  select exists (
    select 1 from storage.objects o where o.bucket_id = 'corrective-evidence' and o.name = photo
      and o.owner_id = auth.uid()::text
      and split_part(o.name, '/', 2) = target::text and split_part(o.name, '/', 3) = kind
  );
$$;

create function uni360_private.corrective_candidates(target uuid, ignore_scheduled_preventive boolean default false)
returns table (worker_id uuid, worker_name text, job_role text, same_zone boolean, standby boolean, workload integer)
language sql stable security invoker set search_path = '' as $$
  select w.worker_id, a.full_name, w.job_role,
    coalesce(lower(btrim(w.assigned_zone)) = lower(z.name), false), w.standby_status,
    w.current_workload + (
      select count(*)::integer from public.preventive_work_order o where o.worker_id = w.worker_id
        and o.cancelled_at is null and o.status in ('assigned','in_progress')
        and o.scheduled_for < now() + interval '1 day' and o.due_at > now()
    )
  from public.corrective_incident i join public.preventive_zone z on z.id = i.zone_id
  cross join public.worker_profile w join public.account a on a.user_id = w.worker_id
  where i.id = target and a.is_active and a.role = 'worker'
    and lower(btrim(w.employment_status)) = 'active'
    and (i.required_role is not null or i.required_skill_id is not null)
    and (i.required_role is null or lower(btrim(w.job_role)) = lower(i.required_role))
    and (i.required_skill_id is null or exists (
      select 1 from public.worker_skill ws join public.skill s using (skill_id)
      where ws.worker_id = w.worker_id and s.skill_id = i.required_skill_id
        and (not s.certification_required
          or (ws.verified and ws.certification_no is not null
            and (ws.expiry_date is null or ws.expiry_date >= (now() at time zone 'Asia/Kuala_Lumpur')::date))
          or exists (select 1 from public.worker_certification certificate
            where certificate.worker_id = w.worker_id and certificate.verified
              and lower(btrim(certificate.certification_name)) = lower(btrim(s.skill_name))
              and (certificate.expiry_date is null or certificate.expiry_date >= (now() at time zone 'Asia/Kuala_Lumpur')::date)))
    ))
    and exists (
      select 1 from public.worker_availability v where v.worker_id = w.worker_id
        and lower(btrim(v.availability_status)) = 'available'
        and lower(btrim(v.leave_status)) in ('none','rejected')
        and v.shift_start <= now() and v.shift_end >= now() + interval '1 hour'
    )
    and not exists (
      select 1 from public.worker_availability v where v.worker_id = w.worker_id
        and (lower(btrim(v.availability_status)) = 'unavailable' or lower(btrim(v.leave_status)) = 'approved')
        and v.shift_start < now() + interval '1 hour' and v.shift_end > now()
    )
    and not exists (
      select 1 from public.corrective_incident other where other.worker_id = w.worker_id and other.id <> i.id
        and other.status in ('assigned','acknowledged','checked_in','in_progress','rework')
    )
    and not exists (
      select 1 from public.preventive_work_order o where o.worker_id = w.worker_id and o.cancelled_at is null
        and (o.status = 'in_progress' or (not ignore_scheduled_preventive and o.status = 'assigned'
          and o.scheduled_for < now() + interval '1 hour' and o.due_at > now()))
    )
  order by 4 desc, case when i.urgency in ('High','Critical') then not w.standby_status else w.standby_status end, 6, w.worker_id;
$$;

create function uni360_private.corrective_dispatch(target uuid, chosen uuid, note text default '')
returns text language plpgsql security invoker set search_path = '' as $$
declare candidate record;
previous public.corrective_incident%rowtype;
begin
  -- The preventive scheduler uses the same advisory lock when publishing schedules.
  perform pg_catalog.pg_advisory_xact_lock(360, 2);
  select * into candidate from uni360_private.corrective_candidates(target) c
  where chosen is null or c.worker_id = chosen limit 1;
  if not found then
    if chosen is not null then raise exception 'This worker is no longer eligible or available.'; end if;
    update public.corrective_incident set status = 'escalated', worker_id = null, worker_name = null,
      attempt = attempt + (status = 'checked_in')::integer, due_at = null, updated_at = now() where id = target;
    perform uni360_private.corrective_log(target, 'Escalated', 'No eligible worker is available for the next hour.');
    return 'escalated';
  end if;
  select * into previous from public.corrective_incident where id = target;
  update public.corrective_incident set status = 'assigned', worker_id = candidate.worker_id,
    worker_name = candidate.worker_name, attempt = attempt + (status = 'checked_in')::integer,
    due_at = now() + interval '1 hour', updated_at = now() where id = target;
  if previous.worker_id is not null and previous.worker_id <> candidate.worker_id then
    perform uni360_private.corrective_log(target, 'Reassigned',
      concat(previous.worker_name, ' → ', candidate.worker_name, case when note <> '' then ' · ' || note end));
    insert into public.corrective_notification(recipient_id, incident_id, title, incident_title)
    values (previous.worker_id, target, 'Assignment transferred', previous.title);
  else
    perform uni360_private.corrective_log(target, 'Assigned', concat(candidate.worker_name, case when note <> '' then ' · ' || note end));
  end if;
  return 'assigned';
end;
$$;

create function uni360_private.corrective_catalog()
returns jsonb language sql stable security definer set search_path = '' as $$
  with recursive locations as (
    select f.id, f.parent_id, f.zone_id, f.name::text label
    from public.preventive_facility f where f.parent_id is null
    union all
    select f.id, f.parent_id, f.zone_id, l.label || ' / ' || f.name
    from public.preventive_facility f join locations l on l.id = f.parent_id
  )
  select jsonb_build_object(
    'categories', coalesce((select jsonb_agg(to_jsonb(c) order by c.name) from public.corrective_category c
      where c.active and uni360_private.corrective_active()), '[]'::jsonb),
    'facilities', coalesce((select jsonb_agg(jsonb_build_object(
      'id', l.id, 'label', l.label, 'zone', z.name, 'can_manage', uni360_private.corrective_manage(l.zone_id)
    ) order by z.name, l.label) from locations l join public.preventive_zone z on z.id = l.zone_id
      where uni360_private.corrective_active()), '[]'::jsonb),
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', s.skill_id, 'label', s.skill_name) order by s.skill_name)
      from public.skill s where public.can_manage_workforce()), '[]'::jsonb),
    'roles', coalesce((select jsonb_agg(r.job_role order by r.job_role) from
      (select distinct lower(btrim(job_role)) job_role from public.worker_profile where job_role is not null) r
      where public.can_manage_workforce()), '[]'::jsonb)
  );
$$;

create function uni360_private.corrective_report(payload jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  target uuid := (payload->>'id')::uuid;
  facility uuid := (payload->>'facility_id')::uuid;
  photo text := nullif(payload->>'photo', '');
  item_category text := coalesce(payload->>'category', 'Other');
  item_urgency text := coalesce(payload->>'urgency', 'Medium');
  site_token text := nullif(btrim(payload->>'qr'), '');
  account_row public.account%rowtype;
  location_label text;
begin
  select * into account_row from public.account where user_id = auth.uid() and is_active;
  if not found then raise exception 'Sign in with an active Uni360 account.' using errcode = '42501'; end if;
  perform pg_catalog.pg_advisory_xact_lock(360, 2);
  if exists (select 1 from public.corrective_incident where id = target and reporter_id = auth.uid()) then
    return target;
  end if;
  if site_token is not null and not exists (select 1 from public.corrective_site s
      where s.facility_id = facility and 'uni360:' || s.qr_token::text = site_token) then
    raise exception 'This location QR is no longer valid. Scan again or select the facility manually.';
  end if;
  if not exists (select 1 from public.corrective_category c where c.name = item_category and c.active) then
    raise exception 'Select an active report category.';
  end if;
  with recursive ancestors(id, parent_id, label) as (
    select f.id, f.parent_id, f.name from public.preventive_facility f where f.id = facility
    union all
    select p.id, p.parent_id, p.name || ' / ' || a.label
    from public.preventive_facility p join ancestors a on a.parent_id = p.id
  )
  select label into location_label from ancestors where parent_id is null;
  if location_label is null then raise exception 'Select an existing campus facility.'; end if;
  if photo is not null and not uni360_private.corrective_owned_photo(photo, target, 'report') then
    raise exception 'The report photograph could not be verified.';
  end if;
  insert into public.corrective_incident (
    id, facility_id, zone_id, facility_name, category, title, description, location_detail, urgency,
    required_role, reporter_id, reporter_name, checklist, report_photo, location_method, triage
  ) select target, f.id, f.zone_id, location_label, item_category, btrim(payload->>'title'),
    btrim(payload->>'description'), btrim(payload->>'location_detail'), item_urgency,
    (select worker_role from public.corrective_category c where c.name = item_category),
    account_row.user_id, account_row.full_name,
    array['Assess the fault and secure the affected area',
          'Perform or document the corrective work',
          'Verify the outcome and record any remaining issue'], photo,
    case when site_token is null then 'manual' else 'qr' end,
    uni360_private.corrective_predict(concat_ws(' ', payload->>'title', payload->>'description'),
      item_category, item_urgency, photo is not null)
  from public.preventive_facility f where f.id = facility;
  perform uni360_private.corrective_log(target, 'Reported');
  return target;
end;
$$;

create function uni360_private.corrective_admin_options(target uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare incident public.corrective_incident%rowtype;
begin
  select * into incident from public.corrective_incident where id = target;
  if not found or not uni360_private.corrective_manage(incident.zone_id) then
    raise exception 'This incident is outside your managed zones.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'triage', incident.triage,
    'team', (select team from public.corrective_category where name = incident.category),
    'duplicates', coalesce((
      select jsonb_agg(to_jsonb(matches) order by matches.similarity desc, matches.reference desc)
      from (
        select i.id, i.reference, i.title, i.status, round(100 * compared.score) similarity
        from public.corrective_incident i
        cross join lateral (select uni360_private.corrective_similarity(
          uni360_private.corrective_terms(i.title || ' ' || i.description),
          uni360_private.corrective_terms(incident.title || ' ' || incident.description)
        ) score) compared
        where i.id <> target and i.facility_id = incident.facility_id
          and i.status not in ('resolved','rejected','dismissed','merged')
          and (compared.score >= .15 or (i.category = incident.category and compared.score > 0))
        order by compared.score desc, i.created_at desc limit 5
      ) matches
    ), '[]'::jsonb),
    'candidates', coalesce((select jsonb_agg(to_jsonb(c)) from uni360_private.corrective_candidates(target) c), '[]'::jsonb),
    'preventive', coalesce((
      select jsonb_agg(jsonb_build_object('id', o.id, 'plan_id', o.plan_id, 'title', o.title,
        'start', o.scheduled_for, 'worker', a.full_name, 'deferrable', p.order_id is not null) order by o.scheduled_for)
      from public.preventive_work_order o join public.account a on a.user_id = o.worker_id
      left join public.corrective_deferrable_order p on p.order_id = o.id
      where incident.urgency in ('High','Critical') and o.status = 'assigned' and o.cancelled_at is null
        and o.scheduled_for < now() + interval '1 hour' and o.due_at > now()
        and exists (select 1 from uni360_private.corrective_candidates(target, true) c where c.worker_id = o.worker_id)
        and exists (select 1 from public.preventive_work_order_target t where t.work_order_id = o.id)
        and not exists (
          select 1 from public.preventive_work_order_target t join public.preventive_facility f on f.id = t.facility_id
          where t.work_order_id = o.id and (f.zone_id <> incident.zone_id or not uni360_private.corrective_manage(f.zone_id))
        )
    ), '[]'::jsonb)
  );
end;
$$;

create function uni360_private.corrective_admin(target uuid, command text, payload jsonb)
returns text language plpgsql security definer set search_path = '' as $$
declare
  item public.corrective_incident%rowtype;
  note text := left(btrim(coalesce(payload->>'note','')), 2000);
  chosen uuid := (payload->>'worker_id')::uuid;
  order_id uuid := (payload->>'order_id')::uuid;
  new_start timestamptz := (payload->>'new_start')::timestamptz;
  order_row public.preventive_work_order%rowtype;
  new_end timestamptz;
  notify_group text := coalesce(payload->>'notify_group', 'both');
  selected_category text := payload->>'category';
  category_row public.corrective_category%rowtype;
  primary_case public.corrective_incident%rowtype;
  result text;
begin
  perform pg_catalog.pg_advisory_xact_lock(360, 2);
  select * into item from public.corrective_incident where id = target for update;
  if not found or not uni360_private.corrective_manage(item.zone_id) then
    raise exception 'This incident is outside your managed zones.' using errcode = '42501';
  end if;
  if command in ('dispatch','assign','escalate','external','dismiss','requirements','mark_deferrable','postpone')
    and item.status not in ('reported','needs_info','inspection','approved','escalated','assigned','acknowledged','checked_in','external','rework') then
    raise exception 'The current incident status does not allow this action.';
  end if;
  if command in ('review_approve','request_information','inspect','merge') then
    if item.status not in ('reported','needs_info','inspection','approved') then
      raise exception 'Only cases awaiting assignment can be reviewed or merged.';
    end if;
    if command = 'review_approve' then
      select * into category_row from public.corrective_category
        where name = coalesce(selected_category, item.category) and active;
      if not found then raise exception 'Select an active category before approval.'; end if;
      update public.corrective_incident set status = 'approved', approved_at = now(),
        category = category_row.name, urgency = coalesce(payload->>'urgency', urgency),
        target_at = now() + case coalesce(payload->>'urgency', urgency)
          when 'Critical' then interval '1 hour' when 'High' then interval '4 hours'
          when 'Medium' then interval '1 day' else interval '3 days' end,
        required_role = case when category_row.name = item.category then required_role else category_row.worker_role end,
        required_skill_id = case when category_row.name = item.category then required_skill_id end,
        updated_at = now() where id = target;
      perform uni360_private.corrective_log(target, 'Report approved',
        concat_ws(' · ', category_row.name, coalesce(payload->>'urgency', item.urgency), nullif(note,'')));
      return 'approved';
    end if;
    if note = '' then raise exception 'Enter a reason for this review decision.'; end if;
    if command = 'merge' then
      select * into primary_case from public.corrective_incident
      where id = (payload->>'primary_id')::uuid and id <> target and facility_id = item.facility_id
        and status not in ('merged','resolved','rejected','dismissed') for update;
      if not found or exists (select 1 from public.corrective_incident where merged_into = target) then
        raise exception 'Select an unresolved case at the same facility and keep any existing primary case.';
      end if;
      update public.corrective_incident set status = 'merged', merged_into = primary_case.id,
        linked_reference = primary_case.reference, linked_status = primary_case.status, updated_at = now() where id = target;
      perform uni360_private.corrective_log(target, 'Report merged', note);
      perform uni360_private.corrective_log(primary_case.id, 'Duplicate report linked', 'Report CM-' || item.reference);
      return 'merged';
    end if;
    result := case when command = 'inspect' then 'inspection' else 'needs_info' end;
    update public.corrective_incident set status = result, approved_at = null, updated_at = now() where id = target;
    perform uni360_private.corrective_log(target, case when command = 'inspect' then 'Inspection requested'
      else 'More information requested' end, note);
    return result;
  elsif command = 'requirements' then
    if item.status not in ('reported','approved','escalated','external') then
      raise exception 'Escalate the incident before changing the requirements of an assigned job.';
    end if;
    update public.corrective_incident set required_role = nullif(lower(btrim(payload->>'role')), ''),
      required_skill_id = (payload->>'skill_id')::uuid,
      urgency = coalesce(payload->>'urgency', urgency), updated_at = now() where id = target;
    perform uni360_private.corrective_log(target, 'Assignment requirements updated', note);
    return item.status;
  elsif command in ('dispatch','assign') then
    if item.approved_at is null then raise exception 'Approve this report before assigning work.'; end if;
    if command = 'assign' and chosen is null then raise exception 'Select a worker.'; end if;
    perform uni360_private.corrective_log(target, 'Verified by administrator', note);
    return uni360_private.corrective_dispatch(target, chosen, note);
  elsif command in ('mark_deferrable','postpone') then
    if note = '' then raise exception 'Enter a reason for changing preventive work.'; end if;
    select * into order_row from public.preventive_work_order o where o.id = order_id
      and o.status = 'assigned' and o.cancelled_at is null
      and o.id::text in (select value->>'id' from jsonb_array_elements(uni360_private.corrective_admin_options(target)->'preventive'))
      for update;
    if not found then raise exception 'This preventive order is unavailable or has started.'; end if;
    if command = 'mark_deferrable' then
      insert into public.corrective_deferrable_order(order_id, marked_by) values (order_row.id, auth.uid()) on conflict do nothing;
      perform uni360_private.corrective_log(target, 'Preventive order marked lower priority', order_row.title || ' · ' || note);
      return item.status;
    end if;
    if not exists (select 1 from public.corrective_deferrable_order p where p.order_id = order_row.id) then
      raise exception 'Only work explicitly marked lower priority can be postponed.';
    end if;
    new_end := new_start + (order_row.due_at - order_row.scheduled_for);
    if new_start is null or new_start < greatest(order_row.scheduled_for, now() + interval '1 hour')
      or exists (select 1 from public.preventive_work_order o where o.worker_id = order_row.worker_id
        and o.id <> order_id and o.cancelled_at is null and o.status in ('assigned','in_progress')
        and o.scheduled_for < new_end and o.due_at > new_start)
      or not exists (select 1 from public.worker_availability v where v.worker_id = order_row.worker_id
        and lower(btrim(v.availability_status)) = 'available' and lower(btrim(v.leave_status)) in ('none','rejected')
        and v.shift_start <= new_start and v.shift_end >= new_end)
      or exists (select 1 from public.worker_availability v where v.worker_id = order_row.worker_id
        and (lower(btrim(v.availability_status)) = 'unavailable' or lower(btrim(v.leave_status)) = 'approved')
        and v.shift_start < new_end and v.shift_end > new_start) then
      raise exception 'Choose a later time within the worker shift with no conflicting assignment.';
    end if;
    update public.preventive_work_order set scheduled_for = new_start, due_at = new_end where id = order_id;
    perform uni360_private.corrective_log(target, 'Preventive work postponed', order_row.title || ' · ' || note);
    return item.status;
  elsif command in ('escalate','external','dismiss') then
    if note = '' then raise exception 'Enter a reason.'; end if;
    if notify_group not in ('both','zone','supervisors') then raise exception 'Select a notification group.'; end if;
    result := case command when 'escalate' then 'escalated' when 'external' then 'external' else 'dismissed' end;
    update public.corrective_incident set status = result, worker_id = null, worker_name = null,
      attempt = attempt + (status = 'checked_in')::integer,
      due_at = null, urgency = coalesce(payload->>'urgency', urgency), updated_at = now() where id = target;
    perform uni360_private.corrective_log(target, case command when 'escalate' then 'Escalated'
      when 'external' then 'External assistance required' else 'Report dismissed' end,
      case when command = 'escalate' then concat_ws(' · ', note,
        'Urgency ' || coalesce(payload->>'urgency', item.urgency),
        case notify_group when 'zone' then 'Zone administrators notified'
          when 'supervisors' then 'Super administrators notified'
          else 'Zone and super administrators notified' end)
      else note end, notify_group);
    if item.worker_id is not null then
      insert into public.corrective_notification(recipient_id, incident_id, title, incident_title)
      values (item.worker_id, target, 'Assignment withdrawn', item.title);
    end if;
  elsif command in ('approve','rework','reject') and item.status = 'submitted' then
    if note = '' then raise exception 'Enter review remarks.'; end if;
    result := case command when 'approve' then 'resolved' when 'rework' then 'rework' else 'rejected' end;
    update public.corrective_incident set status = result, attempt = attempt + (command = 'rework')::integer,
      resolved_at = case when command = 'approve' then now() end, updated_at = now() where id = target;
    perform uni360_private.corrective_log(target, case command when 'approve' then 'Work approved'
      when 'rework' then 'Rework requested' else 'Evidence rejected' end, note);
  else
    raise exception 'The current incident status does not allow this action.';
  end if;
  return result;
end;
$$;

create function uni360_private.corrective_geofence(facility uuid, lat double precision, lon double precision, accuracy double precision)
returns double precision language plpgsql stable security invoker set search_path = '' as $$
declare
  site public.corrective_site%rowtype;
  distance double precision;
begin
  select * into site from public.corrective_site where facility_id = facility;
  if not found then raise exception 'Ask your administrator to configure this facility check-in site.'; end if;
  if lat is null or lon is null or accuracy is null or lat not between -90 and 90 or lon not between -180 and 180
    or accuracy not between 0 and least(50, site.radius_m) then
    raise exception 'Location accuracy is too low. Move to an open area and try again.';
  end if;
  distance := 12742000 * asin(sqrt(least(1.0, power(sin(radians(lat - site.latitude) / 2), 2)
    + cos(radians(lat)) * cos(radians(site.latitude)) * power(sin(radians(lon - site.longitude) / 2), 2))));
  if distance > site.radius_m then raise exception 'You are outside the facility geofence.'; end if;
  return distance;
end;
$$;

create function uni360_private.corrective_location(target uuid, payload jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  facility uuid;
  accuracy double precision := (payload->>'accuracy')::double precision;
begin
  select facility_id into facility from public.corrective_incident where id = target and worker_id = auth.uid()
    and status = 'acknowledged' and public.can_read_own_workforce(worker_id);
  if not found then raise exception 'This assignment is unavailable for check-in.' using errcode = '42501'; end if;
  return jsonb_build_object('distance_m', uni360_private.corrective_geofence(facility,
    (payload->>'latitude')::double precision, (payload->>'longitude')::double precision, accuracy),
    'accuracy_m', accuracy);
end;
$$;

create function uni360_private.corrective_worker(target uuid, command text, payload jsonb)
returns text language plpgsql security definer set search_path = '' as $$
declare
  item public.corrective_incident%rowtype;
  token uuid;
  lat double precision := (payload->>'latitude')::double precision;
  lon double precision := (payload->>'longitude')::double precision;
  accuracy double precision := (payload->>'accuracy')::double precision;
  distance double precision;
  photo text := payload->>'photo';
  checked integer[];
  note text := btrim(coalesce(payload->>'notes', ''));
  result text;
begin
  if command in ('check_in','start') then perform pg_catalog.pg_advisory_xact_lock(360, 2); end if;
  select * into item from public.corrective_incident where id = target and worker_id = auth.uid()
    and public.can_read_own_workforce(worker_id) for update;
  if not found then raise exception 'This assignment is unavailable to your account.' using errcode = '42501'; end if;
  if command = 'acknowledge' and item.status in ('assigned','rework','acknowledged') then
    if item.status = 'acknowledged' then return item.status; end if;
    result := 'acknowledged';
    perform uni360_private.corrective_log(target, case when item.status = 'rework' then 'Rework acknowledged'
      else 'Assignment acknowledged' end, left(note, 2000));
  elsif command = 'check_in' and item.status in ('acknowledged','checked_in','in_progress') then
    if item.status <> 'acknowledged' then return item.status; end if;
    if not exists (select 1 from uni360_private.corrective_candidates(target) c where c.worker_id = auth.uid()) then
      raise exception 'Your shift, qualifications or current work conflicts with this visit. Contact dispatch.';
    end if;
    distance := uni360_private.corrective_geofence(item.facility_id, lat, lon, accuracy);
    select qr_token into token from public.corrective_site where facility_id = item.facility_id;
    if payload->>'qr' is distinct from 'uni360:' || token::text then
      raise exception 'This QR code does not match the assigned facility.';
    end if;
    insert into public.corrective_visit (incident_id, attempt, worker_id, accuracy_m, distance_m)
      values (target, item.attempt, auth.uid(), accuracy, distance);
    insert into public.corrective_position (incident_id, attempt, latitude, longitude)
      values (target, item.attempt, lat, lon);
    result := 'checked_in';
    perform uni360_private.corrective_log(target, 'Geofence and QR verified');
  elsif command = 'start' and item.status in ('checked_in','in_progress') then
    if item.status = 'in_progress' then return item.status; end if;
    if not exists (select 1 from uni360_private.corrective_candidates(target) c where c.worker_id = auth.uid()) then
      raise exception 'Your shift or current work conflicts with this visit. Contact dispatch.';
    end if;
    update public.corrective_visit set started_at = now() where incident_id = target and attempt = item.attempt;
    if not found then raise exception 'Verify the facility check-in before starting work.'; end if;
    result := 'in_progress';
    perform uni360_private.corrective_log(target, 'Work started');
  elsif command = 'request_help' and item.status in ('assigned','acknowledged','checked_in','in_progress','submitted','rework') then
    if char_length(note) not between 3 and 2000 then raise exception 'Enter a message of 3 to 2000 characters.'; end if;
    perform uni360_private.corrective_log(target, 'Worker requested assistance', note);
    update public.corrective_incident set updated_at = now() where id = target;
    return item.status;
  elsif command = 'photo' and item.status = 'in_progress' then
    if exists (select 1 from public.corrective_photo where path = photo and incident_id = target and attempt = item.attempt) then
      return item.status;
    end if;
    if not uni360_private.corrective_owned_photo(photo, target, 'work') then raise exception 'The photograph could not be verified.'; end if;
    if (select count(*) from public.corrective_photo where incident_id = target and attempt = item.attempt) >= 5 then
      raise exception 'This visit already has five photographs.';
    end if;
    insert into public.corrective_photo (path, incident_id, attempt) values (photo, target, item.attempt);
    return item.status;
  elsif command = 'checklist' and item.status = 'in_progress' then
    select array(select distinct value::integer from jsonb_array_elements_text(payload->'checked') order by value::integer) into checked;
    if exists (select 1 from unnest(checked) n where n < 0 or n >= cardinality(item.checklist)) then
      raise exception 'The checklist contains an invalid item.';
    end if;
    update public.corrective_visit set checklist_checked = checked where incident_id = target and attempt = item.attempt;
    return item.status;
  elsif command = 'draft' and item.status = 'in_progress' then
    if char_length(note) > 2000 then raise exception 'Keep draft notes within 2000 characters.'; end if;
    update public.corrective_visit set notes = nullif(note, '') where incident_id = target and attempt = item.attempt;
    return item.status;
  elsif command = 'submit' and item.status in ('in_progress','submitted') then
    if item.status = 'submitted' then return item.status; end if;
    if not exists (select 1 from public.corrective_visit v where v.incident_id = target and v.attempt = item.attempt
      and cardinality(v.checklist_checked) = cardinality(item.checklist)) then raise exception 'Complete every checklist item.'; end if;
    if not exists (select 1 from public.corrective_photo where incident_id = target and attempt = item.attempt) then
      raise exception 'Capture at least one completion photograph.';
    end if;
    if payload->>'confirmed' is distinct from 'true' then
      raise exception 'Confirm that the checklist was completed correctly.';
    end if;
    if char_length(note) not between 3 and 2000 then
      raise exception 'Enter completion notes of 3 to 2000 characters.';
    end if;
    update public.corrective_visit set notes = note, submitted_at = now()
      where incident_id = target and attempt = item.attempt;
    result := 'submitted';
    perform uni360_private.corrective_log(target, 'Evidence submitted');
  else
    raise exception 'Refresh the assignment before trying this action.';
  end if;
  update public.corrective_incident set status = result, updated_at = now(),
    due_at = case when command in ('check_in','start') then now() + interval '1 hour' else due_at end where id = target;
  return result;
end;
$$;

create function uni360_private.corrective_configure_site(target uuid, payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  zone uuid;
  site public.corrective_site%rowtype;
begin
  select zone_id into zone from public.preventive_facility where id = target;
  if zone is null or not uni360_private.corrective_manage(zone) then
    raise exception 'This facility is outside your managed zones.' using errcode = '42501';
  end if;
  insert into public.corrective_site (facility_id, latitude, longitude, radius_m)
  values (target, (payload->>'latitude')::double precision, (payload->>'longitude')::double precision, (payload->>'radius_m')::integer)
  on conflict (facility_id) do update set latitude = excluded.latitude, longitude = excluded.longitude,
    radius_m = excluded.radius_m,
    qr_token = case when coalesce((payload->>'rotate')::boolean, false) then excluded.qr_token
                    else corrective_site.qr_token end
  returning * into site;
  return to_jsonb(site);
end;
$$;

create function uni360_private.corrective_protect_preventive_slot() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.worker_id is not null and new.cancelled_at is null and new.status in ('assigned','in_progress')
    and exists (
      select 1 from public.corrective_incident i where i.worker_id = new.worker_id
        and i.status in ('assigned','acknowledged','checked_in','in_progress')
        and ((new.status = 'in_progress' and i.status = 'in_progress')
          or (i.due_at > greatest(now(), new.scheduled_for)
            and (new.status = 'in_progress' or new.due_at > i.due_at - interval '1 hour')))
    ) then
    raise exception 'This preventive work conflicts with an active corrective assignment. Choose a later slot or another worker.';
  end if;
  return new;
end;
$$;
create trigger corrective_protect_preventive_slot
before insert or update of worker_id, scheduled_for, due_at, status on public.preventive_work_order
for each row execute function uni360_private.corrective_protect_preventive_slot();

create function uni360_private.corrective_lookup_qr(code text) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare facility uuid;
begin
  if not uni360_private.corrective_active() then raise exception 'Sign in to scan a facility QR.' using errcode = '42501'; end if;
  select facility_id into facility from public.corrective_site where 'uni360:' || qr_token::text = btrim(code);
  if not found then raise exception 'This QR code is not a registered Uni360 facility.'; end if;
  return facility;
end;
$$;

create function uni360_private.corrective_reporter(target uuid, command text, payload jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare
  item public.corrective_incident%rowtype;
  note text := btrim(coalesce(payload->>'note', ''));
  rating integer := (payload->>'rating')::integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(360, 2);
  select * into item from public.corrective_incident
    where id = target and reporter_id = auth.uid() and uni360_private.corrective_active() for update;
  if not found then raise exception 'This report is unavailable.' using errcode = '42501'; end if;
  if char_length(note) > 2000 then raise exception 'Keep the message within 2000 characters.'; end if;
  if command = 'reply' and item.status = 'needs_info' then
    if char_length(note) < 3 then raise exception 'Enter the requested information.'; end if;
    update public.corrective_incident set status = 'reported', updated_at = now() where id = target;
    perform uni360_private.corrective_log(target, 'Additional information provided', note);
  elsif command = 'feedback' and (item.status = 'resolved' or (item.status = 'merged' and item.linked_status = 'resolved'))
      and item.feedback_rating is null then
    if rating is null or rating not between 1 and 5 then raise exception 'Select a rating from 1 to 5.'; end if;
    update public.corrective_incident set feedback_rating = rating, feedback_comment = nullif(note,''),
      updated_at = now() where id = target;
    perform uni360_private.corrective_log(target, 'Reporter feedback received', concat_ws(' · ', rating || '/5', nullif(note,'')));
    if coalesce((payload->>'unresolved')::boolean, false) then
      update public.corrective_incident set status = 'reported', worker_id = null, worker_name = null,
        attempt = attempt + 1, approved_at = null, resolved_at = null, due_at = null,
        target_at = null, updated_at = now()
        where id = coalesce(item.merged_into, target) and status = 'resolved';
      if found then
        perform uni360_private.corrective_log(coalesce(item.merged_into, target), 'Issue reopened',
          case when item.merged_into is null then note else 'A linked reporter indicated that the fault persists.' end);
      end if;
    end if;
  else
    raise exception 'The current report status does not allow this action.';
  end if;
end;
$$;

create function uni360_private.corrective_provision_reporter() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  campus_id text := upper(btrim(new.raw_user_meta_data->>'campus_id'));
  name text := btrim(new.raw_user_meta_data->>'full_name');
begin
  if new.raw_user_meta_data->>'uni360_role' = 'reporter' and new.email_confirmed_at is not null
     and lower(new.email) ~ '^[^@]+@(student[.])?tarc[.]edu[.]my$'
     and campus_id ~ '^[A-Z0-9-]{3,40}$' and char_length(name) between 2 and 120 then
    insert into public.account(user_id, employee_id, full_name, role)
    values (new.id, campus_id, name, 'reporter') on conflict do nothing;
  end if;
  return new;
end;
$$;

create trigger corrective_provision_reporter after insert or update of email_confirmed_at on auth.users
for each row execute function uni360_private.corrective_provision_reporter();

create function public.corrective_catalog() returns jsonb
language sql stable security invoker set search_path = '' as $$ select uni360_private.corrective_catalog(); $$;
create function public.corrective_report(payload jsonb) returns uuid
language sql security invoker set search_path = '' as $$ select uni360_private.corrective_report(payload); $$;
create function public.corrective_admin_options(target uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select uni360_private.corrective_admin_options(target); $$;
create function public.corrective_admin(target uuid, command text, payload jsonb) returns text
language sql security invoker set search_path = '' as $$ select uni360_private.corrective_admin(target, command, payload); $$;
create function public.corrective_worker(target uuid, command text, payload jsonb) returns text
language sql security invoker set search_path = '' as $$ select uni360_private.corrective_worker(target, command, payload); $$;
create function public.corrective_location(target uuid, payload jsonb) returns jsonb
language sql stable security invoker set search_path = '' as $$ select uni360_private.corrective_location(target, payload); $$;
create function public.corrective_configure_site(target uuid, payload jsonb) returns jsonb
language sql security invoker set search_path = '' as $$ select uni360_private.corrective_configure_site(target, payload); $$;
create function public.corrective_lookup_qr(code text) returns uuid
language sql stable security invoker set search_path = '' as $$ select uni360_private.corrective_lookup_qr(code); $$;
create function public.corrective_reporter(target uuid, command text, payload jsonb) returns void
language sql security invoker set search_path = '' as $$ select uni360_private.corrective_reporter(target, command, payload); $$;

revoke all on function uni360_private.corrective_log(uuid,text,text,text),
  uni360_private.corrective_sync_linked(), uni360_private.corrective_provision_reporter(),
  uni360_private.corrective_terms(text), uni360_private.corrective_similarity(text[],text[]),
  uni360_private.corrective_predict(text,text,text,boolean),
  uni360_private.corrective_protect_preventive_slot(),
  uni360_private.corrective_geofence(uuid,double precision,double precision,double precision),
  uni360_private.corrective_owned_photo(text,uuid,text), uni360_private.corrective_candidates(uuid,boolean),
  uni360_private.corrective_dispatch(uuid,uuid,text) from public, anon, authenticated;

do $$
declare signature text;
declare schema_name text;
begin
  foreach signature in array array['corrective_catalog()','corrective_report(jsonb)','corrective_admin_options(uuid)',
      'corrective_admin(uuid,text,jsonb)','corrective_worker(uuid,text,jsonb)','corrective_location(uuid,jsonb)',
      'corrective_configure_site(uuid,jsonb)','corrective_lookup_qr(text)','corrective_reporter(uuid,text,jsonb)'] loop
    foreach schema_name in array array['public','uni360_private'] loop
      execute format('revoke all on function %I.%s from public, anon, authenticated', schema_name, signature);
      execute format('grant execute on function %I.%s to authenticated', schema_name, signature);
    end loop;
  end loop;
end;
$$;
revoke all on function uni360_private.corrective_active(), uni360_private.corrective_manage(uuid),
  uni360_private.corrective_access(uuid), uni360_private.corrective_registered_photo(text)
  from public, anon, authenticated;
grant execute on function uni360_private.corrective_active(), uni360_private.corrective_manage(uuid),
  uni360_private.corrective_access(uuid), uni360_private.corrective_registered_photo(text) to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.corrective_incident, public.corrective_notification;
  end if;
end;
$$;

notify pgrst, 'reload schema';

commit;
