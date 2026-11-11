begin;

create type public.account_role as enum (
  'super_administrator',
  'administrator',
  'worker'
);

create table public.account (
  user_id uuid primary key references auth.users (id) on delete restrict,
  employee_id text not null unique check (employee_id ~ '^[A-Z0-9-]+$'),
  full_name text not null check (char_length(btrim(full_name)) between 2 and 120),
  phone text not null default '' check (phone = '' or phone ~ '^\+?[0-9 ()-]{8,20}$'),
  role public.account_role not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.account enable row level security;
revoke all on table public.account from public, anon, authenticated;
grant select on table public.account to authenticated;
grant update (full_name, phone) on table public.account to authenticated;
grant select, insert, update on table public.account to service_role;

create policy "Active users can read their own account"
  on public.account for select to authenticated
  using (user_id = (select auth.uid()) and is_active);

create policy "Active users can update their own contact details"
  on public.account for update to authenticated
  using (user_id = (select auth.uid()) and is_active)
  with check (user_id = (select auth.uid()) and is_active);

comment on table public.account is
  'Uni360 role and profile per Supabase Auth user. Deactivate with is_active to preserve the account.';

commit;
