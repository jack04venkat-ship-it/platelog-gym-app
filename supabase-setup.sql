create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('t', 'c')),
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  tid uuid not null references public.profiles(id) on delete cascade,
  uid uuid unique references public.profiles(id) on delete set null,
  email text not null default '',
  name text not null,
  invite text unique,
  plan jsonb not null default '{}'::jsonb,
  diet jsonb not null default '{"kcal":2200,"protein":120,"note":""}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.client_data (
  client_id uuid primary key references public.clients(id) on delete cascade,
  logs jsonb not null default '[]'::jsonb,
  food jsonb not null default '[]'::jsonb,
  weights jsonb not null default '[]'::jsonb,
  mins integer not null default 45 check (mins > 0),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.clients enable row level security;
alter table public.client_data enable row level security;

revoke all on public.profiles, public.clients, public.client_data from public, anon, authenticated;
grant select on public.profiles to authenticated;
grant select on public.clients to authenticated;
grant insert (id, tid, email, name, invite, plan, diet) on public.clients to authenticated;
grant update (email, name, invite, plan, diet) on public.clients to authenticated;
grant select, insert, update on public.client_data to authenticated;

drop policy if exists "Read own or linked trainer profile" on public.profiles;
create policy "Read own or linked trainer profile"
  on public.profiles for select to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1 from public.clients
      where clients.uid = (select auth.uid())
        and clients.tid = profiles.id
    )
  );

drop policy if exists "Read trainer or linked client records" on public.clients;
create policy "Read trainer or linked client records"
  on public.clients for select to authenticated
  using (tid = (select auth.uid()) or uid = (select auth.uid()));

drop policy if exists "Trainer creates own client records" on public.clients;
create policy "Trainer creates own client records"
  on public.clients for insert to authenticated
  with check (tid = (select auth.uid()) and uid is null);

drop policy if exists "Trainer updates own client records" on public.clients;
create policy "Trainer updates own client records"
  on public.clients for update to authenticated
  using (tid = (select auth.uid()))
  with check (tid = (select auth.uid()));

drop policy if exists "Read related client data" on public.client_data;
create policy "Read related client data"
  on public.client_data for select to authenticated
  using (
    exists (
      select 1 from public.clients
      where clients.id = client_data.client_id
        and (clients.tid = (select auth.uid()) or clients.uid = (select auth.uid()))
    )
  );

drop policy if exists "Insert related client data" on public.client_data;
create policy "Insert related client data"
  on public.client_data for insert to authenticated
  with check (
    exists (
      select 1 from public.clients
      where clients.id = client_data.client_id
        and (clients.tid = (select auth.uid()) or clients.uid = (select auth.uid()))
    )
  );

drop policy if exists "Update related client data" on public.client_data;
create policy "Update related client data"
  on public.client_data for update to authenticated
  using (
    exists (
      select 1 from public.clients
      where clients.id = client_data.client_id
        and (clients.tid = (select auth.uid()) or clients.uid = (select auth.uid()))
    )
  )
  with check (
    exists (
      select 1 from public.clients
      where clients.id = client_data.client_id
        and (clients.tid = (select auth.uid()) or clients.uid = (select auth.uid()))
    )
  );

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  signup_role text := new.raw_user_meta_data ->> 'role';
  signup_name text := trim(coalesce(new.raw_user_meta_data ->> 'name', ''));
begin
  if signup_role not in ('t', 'c') or signup_name = '' then
    raise exception 'A valid account role and name are required';
  end if;

  insert into public.profiles (id, role, name)
  values (new.id, signup_role, signup_name);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_plate_log on auth.users;
create trigger on_auth_user_created_plate_log
  after insert on auth.users
  for each row execute function public.create_profile_for_new_user();

create or replace function public.redeem_invite(invite_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  linked_id uuid;
  account_role text;
  account_email text;
begin
  if auth.uid() is null then
    raise exception 'Sign in before redeeming an invite';
  end if;

  select role into account_role
  from public.profiles
  where id = auth.uid();
  if account_role is distinct from 'c' then
    raise exception 'Only client accounts can redeem trainer invites';
  end if;

  select email into account_email from auth.users where id = auth.uid();
  update public.clients
  set uid = auth.uid(), invite = null, email = coalesce(account_email, email)
  where invite = upper(trim(invite_code)) and uid is null
  returning id into linked_id;

  if linked_id is null then
    select id into linked_id from public.clients where uid = auth.uid();
  end if;
  if linked_id is null then
    raise exception 'That invite code is invalid or has already been used';
  end if;
  return linked_id;
end;
$$;

revoke all on function public.create_profile_for_new_user() from public, anon, authenticated;
revoke all on function public.redeem_invite(text) from public, anon;
grant execute on function public.redeem_invite(text) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'clients'
  ) then
    alter publication supabase_realtime add table public.clients;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'client_data'
  ) then
    alter publication supabase_realtime add table public.client_data;
  end if;
end;
$$;
