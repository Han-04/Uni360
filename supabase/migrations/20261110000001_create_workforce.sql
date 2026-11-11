begin;

-- Employee number remains canonical in account.employee_id.
alter table public.account add constraint account_user_role_unique unique (user_id, role);

create table public.worker_profile (
  worker_id uuid primary key,
  account_role public.account_role generated always as ('worker'::public.account_role) stored,
  foreign key (worker_id, account_role) references public.account (user_id, role) on delete restrict,
  job_role text check (btrim(job_role) <> ''),
  standby_status boolean not null default false,
  assigned_zone text check (btrim(assigned_zone) <> ''),
  current_workload integer not null default 0 check (current_workload >= 0),
  employment_status text not null default 'unconfigured' check (btrim(employment_status) <> '')
);

create table public.skill (
  skill_id uuid primary key default gen_random_uuid(),
  skill_name text not null check (btrim(skill_name) <> ''),
  certification_required boolean not null default false
);
create unique index skill_name_unique on public.skill (lower(btrim(skill_name)));

create table public.worker_skill (
  worker_skill_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.worker_profile (worker_id) on delete restrict,
  skill_id uuid not null references public.skill (skill_id) on delete restrict,
  certification_no text,
  expiry_date date,
  verified boolean not null default false,
  unique (worker_id, skill_id)
);
create index worker_skill_skill_idx on public.worker_skill (skill_id);

create table public.worker_availability (
  availability_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.worker_profile (worker_id) on delete restrict,
  availability text not null check (btrim(availability) <> ''),
  shift_start timestamptz not null,
  shift_end timestamptz not null check (shift_end > shift_start),
  availability_status text not null check (btrim(availability_status) <> ''),
  leave_status text not null check (btrim(leave_status) <> '')
);
create index worker_availability_shift_idx on public.worker_availability (worker_id, shift_start);

alter table public.worker_profile enable row level security;
alter table public.skill enable row level security;
alter table public.worker_skill enable row level security;
alter table public.worker_availability enable row level security;

-- Account RLS already limits this lookup to the caller's active account.
create function public.can_manage_workforce() returns boolean
language sql stable security invoker set search_path = '' as $$
  select exists (
    select 1 from public.account
    where user_id = (select auth.uid()) and is_active
      and role in ('administrator', 'super_administrator')
  );
$$;

create function public.can_read_own_workforce(target_worker uuid) returns boolean
language sql stable security invoker set search_path = '' as $$
  select target_worker = (select auth.uid()) and exists (
    select 1 from public.account
    where user_id = (select auth.uid()) and is_active and role = 'worker'
  );
$$;

revoke all on function public.can_manage_workforce(), public.can_read_own_workforce(uuid) from public, anon;
grant execute on function public.can_manage_workforce(), public.can_read_own_workforce(uuid) to authenticated;

do $$
declare table_name text;
begin
  foreach table_name in array array['worker_profile', 'skill', 'worker_skill', 'worker_availability'] loop
    execute format('revoke all on table public.%I from public, anon, authenticated', table_name);
    execute format('grant select, insert, update on table public.%I to authenticated', table_name);
    execute format('create policy workforce_admin on public.%I for all to authenticated using ((select public.can_manage_workforce())) with check ((select public.can_manage_workforce()))', table_name);
  end loop;
end;
$$;

grant delete on public.worker_skill, public.worker_availability to authenticated;

create policy own_profile on public.worker_profile for select to authenticated
  using (public.can_read_own_workforce(worker_id));
create policy own_worker_skills on public.worker_skill for select to authenticated
  using (public.can_read_own_workforce(worker_id));
create policy own_availability on public.worker_availability for select to authenticated
  using (public.can_read_own_workforce(worker_id));
create policy assigned_skills on public.skill for select to authenticated
  using (exists (select 1 from public.worker_skill as assignment
                 where assignment.skill_id = skill.skill_id
                   and public.can_read_own_workforce(assignment.worker_id)));

-- Existing workers get a profile without assumed roles, skills or shifts.
insert into public.worker_profile (worker_id)
select user_id from public.account where role = 'worker';

create function public.create_worker_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.role = 'worker' then
    insert into public.worker_profile (worker_id) values (new.user_id)
    on conflict (worker_id) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function public.create_worker_profile() from public, anon, authenticated;
create trigger create_worker_profile_after_account
after insert or update of role on public.account
for each row execute function public.create_worker_profile();

commit;
