begin;

create table public.worker_certification (
  certification_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.worker_profile(worker_id) on delete restrict,
  certification_name text not null check (btrim(certification_name) <> ''),
  certification_no text check (btrim(certification_no) <> ''),
  expiry_date date,
  verified boolean not null default false,
  document_path text unique check (
    document_path ~ ('^' || worker_id || '/' || certification_id || '/[0-9a-f-]{36}\.(jpg|png|webp|pdf)$')
  )
);
create index worker_certification_worker_idx on public.worker_certification(worker_id);

insert into public.worker_certification
  (certification_id, worker_id, certification_name, certification_no, expiry_date, verified)
select ws.worker_skill_id, ws.worker_id, s.skill_name, nullif(btrim(ws.certification_no), ''), ws.expiry_date, ws.verified
from public.worker_skill ws join public.skill s using (skill_id)
where nullif(btrim(ws.certification_no), '') is not null or ws.expiry_date is not null or ws.verified;

alter table public.worker_certification enable row level security;
revoke all on table public.worker_certification from public, anon, authenticated;
grant select, insert, update (certification_name, certification_no, expiry_date, verified, document_path)
  on table public.worker_certification to authenticated;
create policy certification_admin on public.worker_certification for all to authenticated
  using ((select public.can_manage_workforce())) with check ((select public.can_manage_workforce()));
create policy certification_own_read on public.worker_certification for select to authenticated
  using (public.can_read_own_workforce(worker_id));

create function public.add_worker_skill(target_worker uuid, name text) returns uuid
language plpgsql security invoker set search_path = '' as $$
declare
  canonical_name text := btrim(name);
  target_skill uuid;
  assignment_id uuid;
begin
  if not public.can_manage_workforce() then
    raise exception 'An active administrator account is required.' using errcode = '42501';
  end if;
  if canonical_name is null or char_length(canonical_name) not between 1 and 120 then
    raise exception 'Enter a skill name of 1 to 120 characters.' using errcode = '23514';
  end if;

  insert into public.skill (skill_name) values (canonical_name)
  on conflict (lower(btrim(skill_name))) do nothing;
  select skill_id into strict target_skill from public.skill where lower(btrim(skill_name)) = lower(canonical_name);
  insert into public.worker_skill (worker_id, skill_id) values (target_worker, target_skill)
  on conflict (worker_id, skill_id) do nothing;
  select worker_skill_id into strict assignment_id from public.worker_skill
    where worker_id = target_worker and skill_id = target_skill;
  return assignment_id;
end;
$$;
revoke all on function public.add_worker_skill(uuid, text) from public, anon, authenticated;
grant execute on function public.add_worker_skill(uuid, text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('worker-certificates', 'worker-certificates', false, 10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']);

create policy worker_certificate_storage_read on storage.objects for select to authenticated
  using (bucket_id = 'worker-certificates' and (select public.can_manage_workforce()));
create policy worker_certificate_storage_upload on storage.objects for insert to authenticated
  with check (
    bucket_id = 'worker-certificates' and (select public.can_manage_workforce())
    and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp|pdf)$'
  );
create policy worker_certificate_storage_cleanup on storage.objects for delete to authenticated
  using (
    bucket_id = 'worker-certificates' and (select public.can_manage_workforce())
    and not exists (select 1 from public.worker_certification where document_path = storage.objects.name)
  );

commit;
