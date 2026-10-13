-- ORAVENA — initial production database
-- Run this entire file once in Supabase SQL Editor.
-- Primary administrator: amerihgg@gmail.com

begin;

create extension if not exists pgcrypto;

create table if not exists public.app_config (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

insert into public.app_config(key,value)
values ('primary_admin_email','amerihgg@gmail.com')
on conflict (key) do update set value=excluded.value,updated_at=now();

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text unique,
  full_name text not null default '',
  account_type text not null default 'patient'
    check (account_type in ('admin','doctor','employee','patient')),
  job_title text,
  phone text,
  status text not null default 'active'
    check (status in ('active','suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles add column if not exists email text;
create unique index if not exists profiles_email_unique
  on public.profiles(lower(email)) where email is not null;

create table if not exists public.staff_permissions (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  sections text[] not null default '{}',
  permission_templates text[] not null default '{}',
  updated_at timestamptz not null default now()
);

create sequence if not exists public.patient_file_seq start 1001;

create table if not exists public.patients (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid references auth.users(id) on delete set null,
  file_number text unique not null
    default ('OR-' || nextval('public.patient_file_seq')),
  full_name text not null,
  email text,
  phone text not null,
  national_id text,
  age integer check (age between 0 and 120),
  birth_date date,
  blood_type text,
  allergy text,
  chronic_conditions text,
  current_medications text,
  doctor_notes text,
  emergency_contact text,
  balance numeric(12,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists patients_phone_unique
  on public.patients(phone);

create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  full_name text not null,
  email text,
  phone text not null,
  national_id text,
  age integer check (age between 0 and 120),
  service text not null,
  appointment_date date,
  appointment_time time,
  doctor_id uuid references public.profiles(id) on delete set null,
  status text not null default 'new_request'
    check (status in ('new_request','confirmed','changed','cancelled','completed')),
  change_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.clinic_records (
  id uuid primary key default gen_random_uuid(),
  record_type text not null check (record_type in (
    'session','treatment_plan','prescription','imaging','tooth','finance',
    'inventory','lab','message','notification','audit','setting'
  )),
  patient_id uuid references public.patients(id) on delete cascade,
  owner_user_id uuid references auth.users(id) on delete set null,
  payload jsonb not null default '{}',
  patient_visible boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists appointments_patient_idx on public.appointments(patient_id);
create index if not exists appointments_status_idx on public.appointments(status);
create index if not exists clinic_records_type_idx on public.clinic_records(record_type);
create index if not exists clinic_records_patient_idx on public.clinic_records(patient_id);

create or replace function public.primary_admin_email()
returns text language sql stable security definer set search_path=public
as $$
  select lower(value) from public.app_config where key='primary_admin_email'
$$;

create or replace function public.is_primary_admin()
returns boolean language sql stable security definer set search_path=public
as $$
  select lower(coalesce(auth.jwt()->>'email',''))=public.primary_admin_email()
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$
  select public.is_primary_admin() or exists(
    select 1 from public.profiles p
    where p.id=auth.uid() and p.account_type='admin' and p.status='active'
  )
$$;

create or replace function public.allowed_section(section_name text)
returns boolean language sql stable security definer set search_path=public
as $$
  select public.is_admin() or exists(
    select 1 from public.staff_permissions sp
    join public.profiles p on p.id=sp.user_id
    where sp.user_id=auth.uid() and p.status='active'
      and section_name=any(sp.sections)
  )
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  insert into public.profiles(id,email,full_name,account_type,status)
  values(
    new.id,
    lower(new.email),
    coalesce(new.raw_user_meta_data->>'full_name',''),
    case when lower(coalesce(new.email,''))=public.primary_admin_email()
      then 'admin' else 'patient' end,
    'active'
  )
  on conflict (id) do update set
    email=excluded.email,
    account_type=case when excluded.email=public.primary_admin_email()
      then 'admin' else public.profiles.account_type end,
    status=case when excluded.email=public.primary_admin_email()
      then 'active' else public.profiles.status end,
    updated_at=now();
  return new;
end
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert or update of email on auth.users
for each row execute function public.handle_new_user();

insert into public.profiles(id,email,full_name,account_type,status)
select id,lower(email),coalesce(raw_user_meta_data->>'full_name',''),'admin','active'
from auth.users
where lower(email)='amerihgg@gmail.com'
on conflict (id) do update set
  email=excluded.email,account_type='admin',status='active',updated_at=now();

create or replace function public.protect_primary_admin()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  if lower(coalesce(old.email,''))=public.primary_admin_email() then
    if tg_op='DELETE' then
      raise exception 'The ORAVENA primary administrator cannot be deleted';
    end if;
    if lower(coalesce(new.email,''))<>public.primary_admin_email()
       or new.account_type<>'admin' or new.status<>'active' then
      raise exception 'The ORAVENA primary administrator cannot be demoted or suspended';
    end if;
  end if;
  return case when tg_op='DELETE' then old else new end;
end
$$;

drop trigger if exists protect_primary_admin_profile on public.profiles;
create trigger protect_primary_admin_profile
before update or delete on public.profiles
for each row execute function public.protect_primary_admin();

create or replace function public.current_account_access()
returns jsonb language sql stable security definer set search_path=public
as $$
  select jsonb_build_object(
    'user_id',p.id,
    'email',p.email,
    'full_name',p.full_name,
    'account_type',p.account_type,
    'job_title',p.job_title,
    'status',p.status,
    'sections',case when public.is_admin()
      then array['dashboard','appointments','patients','sessions','odontogram',
        'plans','prescriptions','imaging','finance','inventory','labs','staff',
        'messages','reports','audit','settings']::text[]
      else coalesce(sp.sections,'{}'::text[]) end,
    'permission_templates',coalesce(sp.permission_templates,'{}'::text[]),
    'is_primary_admin',public.is_primary_admin()
  )
  from public.profiles p
  left join public.staff_permissions sp on sp.user_id=p.id
  where p.id=auth.uid() and p.status='active'
$$;

create or replace function public.create_appointment_request(
  p_full_name text,
  p_email text,
  p_phone text,
  p_national_id text,
  p_age integer,
  p_service text
) returns uuid language plpgsql security definer set search_path=public
as $$
declare
  v_patient_id uuid;
  v_appointment_id uuid;
begin
  if length(trim(p_full_name))<2
     or position('@' in trim(p_email))<2
     or length(trim(p_phone))<6
     or length(trim(p_service))<2
     or p_age not between 0 and 120 then
    raise exception 'Invalid appointment data';
  end if;

  select id into v_patient_id
  from public.patients where phone=trim(p_phone) limit 1;

  if v_patient_id is null then
    insert into public.patients(auth_user_id,full_name,email,phone,national_id,age)
    values(auth.uid(),trim(p_full_name),lower(trim(p_email)),trim(p_phone),nullif(trim(p_national_id),''),p_age)
    returning id into v_patient_id;
  else
    update public.patients set
      full_name=trim(p_full_name),
      email=lower(trim(p_email)),
      auth_user_id=coalesce(auth_user_id,auth.uid()),
      national_id=coalesce(nullif(trim(p_national_id),''),national_id),
      age=p_age,
      updated_at=now()
    where id=v_patient_id;
  end if;

  insert into public.appointments(patient_id,full_name,email,phone,national_id,age,service)
  values(v_patient_id,trim(p_full_name),lower(trim(p_email)),trim(p_phone),
    nullif(trim(p_national_id),''),p_age,trim(p_service))
  returning id into v_appointment_id;

  insert into public.clinic_records(record_type,patient_id,payload,patient_visible)
  values('notification',v_patient_id,
    jsonb_build_object(
      'title','طلب موعد جديد',
      'text',trim(p_full_name)||' — '||trim(p_service),
      'email',lower(trim(p_email)),
      'appointment_id',v_appointment_id,
      'read',false
    ),false);

  return v_appointment_id;
end
$$;

alter table public.app_config enable row level security;
alter table public.profiles enable row level security;
alter table public.staff_permissions enable row level security;
alter table public.patients enable row level security;
alter table public.appointments enable row level security;
alter table public.clinic_records enable row level security;

drop policy if exists "config admin read" on public.app_config;
create policy "config admin read" on public.app_config
for select to authenticated using (public.is_admin());

drop policy if exists "profile self or admin" on public.profiles;
create policy "profile self or admin" on public.profiles
for select to authenticated using (id=auth.uid() or public.is_admin());

drop policy if exists "admin manages profiles" on public.profiles;
create policy "admin manages profiles" on public.profiles
for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "permissions self or admin" on public.staff_permissions;
create policy "permissions self or admin" on public.staff_permissions
for select to authenticated using (user_id=auth.uid() or public.is_admin());

drop policy if exists "admin manages permissions" on public.staff_permissions;
create policy "admin manages permissions" on public.staff_permissions
for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "patients read" on public.patients;
create policy "patients read" on public.patients
for select to authenticated using (
  public.allowed_section('patients') or auth_user_id=auth.uid()
);

drop policy if exists "staff manage patients" on public.patients;
create policy "staff manage patients" on public.patients
for all to authenticated using (public.allowed_section('patients'))
with check (public.allowed_section('patients'));

drop policy if exists "appointments access" on public.appointments;
create policy "appointments access" on public.appointments
for all to authenticated using (
  public.allowed_section('appointments') or patient_id in (
    select id from public.patients where auth_user_id=auth.uid()
  )
) with check (public.allowed_section('appointments'));

drop policy if exists "records read" on public.clinic_records;
create policy "records read" on public.clinic_records
for select to authenticated using (
  public.allowed_section(record_type) or (
    patient_visible and patient_id in (
      select id from public.patients where auth_user_id=auth.uid()
    )
  )
);

drop policy if exists "staff manage records" on public.clinic_records;
create policy "staff manage records" on public.clinic_records
for all to authenticated using (
  public.is_admin() or public.allowed_section(record_type)
) with check (
  public.is_admin() or public.allowed_section(record_type)
);

grant usage on schema public to anon,authenticated;
grant execute on function public.current_account_access() to authenticated;
grant execute on function public.create_appointment_request(text,text,text,text,integer,text)
  to anon,authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values(
  'clinic-imaging','clinic-imaging',false,52428800,
  array['image/jpeg','image/png','image/webp','application/pdf']
)
on conflict (id) do nothing;

drop policy if exists "staff upload clinic imaging" on storage.objects;
create policy "staff upload clinic imaging" on storage.objects
for insert to authenticated with check (
  bucket_id='clinic-imaging' and public.allowed_section('imaging')
);

drop policy if exists "authorized clinic imaging read" on storage.objects;
create policy "authorized clinic imaging read" on storage.objects
for select to authenticated using (
  bucket_id='clinic-imaging' and (
    public.allowed_section('imaging') or exists(
      select 1 from public.clinic_records r
      join public.patients p on p.id=r.patient_id
      where r.record_type='imaging'
        and r.patient_visible=true
        and p.auth_user_id=auth.uid()
        and r.payload->>'storage_path'=storage.objects.name
    )
  )
);

drop policy if exists "staff update clinic imaging" on storage.objects;
create policy "staff update clinic imaging" on storage.objects
for update to authenticated using (
  bucket_id='clinic-imaging' and public.allowed_section('imaging')
) with check (
  bucket_id='clinic-imaging' and public.allowed_section('imaging')
);

drop policy if exists "staff delete clinic imaging" on storage.objects;
create policy "staff delete clinic imaging" on storage.objects
for delete to authenticated using (
  bucket_id='clinic-imaging' and public.allowed_section('imaging')
);

commit;

select 'ORAVENA database is ready' as result,
       'amerihgg@gmail.com' as primary_admin;
