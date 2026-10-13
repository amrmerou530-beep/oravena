-- ORAVENA production foundation: run once in Supabase SQL Editor.
-- Do not place a service-role key in the website files.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  account_type text not null check (account_type in ('admin','doctor','employee','patient')),
  job_title text,
  phone text,
  status text not null default 'active' check (status in ('active','suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.staff_permissions (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  sections text[] not null default '{}',
  permission_templates text[] not null default '{}',
  updated_at timestamptz not null default now()
);

create table if not exists public.patients (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid references auth.users(id) on delete set null,
  file_number text unique not null,
  full_name text not null,
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

create sequence if not exists public.patient_file_seq start 1001;

create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid references public.patients(id) on delete cascade,
  full_name text not null,
  phone text not null,
  national_id text,
  age integer check (age between 0 and 120),
  service text not null,
  appointment_date date,
  appointment_time time,
  doctor_id uuid references public.profiles(id) on delete set null,
  status text not null default 'new_request',
  change_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.clinic_records (
  id uuid primary key default gen_random_uuid(),
  record_type text not null check (record_type in ('session','treatment_plan','prescription','imaging','tooth','finance','inventory','lab','message','notification','audit','setting')),
  patient_id uuid references public.patients(id) on delete cascade,
  owner_user_id uuid references auth.users(id) on delete set null,
  payload jsonb not null default '{}',
  patient_visible boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists appointments_patient_idx on public.appointments(patient_id);
create index if not exists clinic_records_type_idx on public.clinic_records(record_type);
create index if not exists clinic_records_patient_idx on public.clinic_records(patient_id);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles p where p.id=auth.uid() and p.account_type='admin' and p.status='active') $$;

create or replace function public.allowed_section(section_name text)
returns boolean language sql stable security definer set search_path=public
as $$ select public.is_admin() or exists(select 1 from public.staff_permissions sp join public.profiles p on p.id=sp.user_id where sp.user_id=auth.uid() and p.status='active' and section_name=any(sp.sections)) $$;

create or replace function public.current_account_access()
returns jsonb language sql stable security definer set search_path=public
as $$
  select jsonb_build_object(
    'user_id',p.id,
    'full_name',p.full_name,
    'account_type',p.account_type,
    'job_title',p.job_title,
    'status',p.status,
    'sections',coalesce(sp.sections,'{}'::text[]),
    'permission_templates',coalesce(sp.permission_templates,'{}'::text[])
  ) from public.profiles p left join public.staff_permissions sp on sp.user_id=p.id
  where p.id=auth.uid() and p.status='active';
$$;

create or replace function public.create_appointment_request(
  p_full_name text,p_phone text,p_national_id text,p_age integer,p_service text
) returns uuid language plpgsql security definer set search_path=public
as $$
declare v_patient_id uuid; v_appointment_id uuid;
begin
  if length(trim(p_full_name))<2 or length(trim(p_phone))<6 or length(trim(p_service))<2 then raise exception 'Invalid appointment data'; end if;
  select id into v_patient_id from public.patients where phone=trim(p_phone) order by created_at limit 1;
  if v_patient_id is null then
    insert into public.patients(file_number,full_name,phone,national_id,age)
    values('OR-'||nextval('public.patient_file_seq'),trim(p_full_name),trim(p_phone),nullif(trim(p_national_id),''),p_age)
    returning id into v_patient_id;
  else
    update public.patients set full_name=trim(p_full_name),national_id=coalesce(nullif(trim(p_national_id),''),national_id),age=p_age,updated_at=now() where id=v_patient_id;
  end if;
  insert into public.appointments(patient_id,full_name,phone,national_id,age,service)
  values(v_patient_id,trim(p_full_name),trim(p_phone),nullif(trim(p_national_id),''),p_age,trim(p_service)) returning id into v_appointment_id;
  insert into public.clinic_records(record_type,patient_id,payload)
  values('notification',v_patient_id,jsonb_build_object('title','طلب موعد جديد','appointment_id',v_appointment_id,'read',false));
  return v_appointment_id;
end $$;

alter table public.profiles enable row level security;
alter table public.staff_permissions enable row level security;
alter table public.patients enable row level security;
alter table public.appointments enable row level security;
alter table public.clinic_records enable row level security;

create policy "profile self or admin" on public.profiles for select to authenticated using (id=auth.uid() or public.is_admin());
create policy "permissions self or admin" on public.staff_permissions for select to authenticated using (user_id=auth.uid() or public.is_admin());
create policy "admin manages profiles" on public.profiles for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin manages permissions" on public.staff_permissions for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "staff read patients" on public.patients for select to authenticated using (public.allowed_section('patients') or auth_user_id=auth.uid());
create policy "staff manage patients" on public.patients for all to authenticated using (public.allowed_section('patients')) with check (public.allowed_section('patients'));
create policy "appointments by permission" on public.appointments for all to authenticated using (public.allowed_section('appointments') or patient_id in (select id from public.patients where auth_user_id=auth.uid())) with check (public.allowed_section('appointments'));
create policy "records by permission" on public.clinic_records for select to authenticated using (public.allowed_section(record_type) or (patient_visible and patient_id in (select id from public.patients where auth_user_id=auth.uid())));
create policy "staff manage records" on public.clinic_records for all to authenticated using (public.is_admin() or public.allowed_section(record_type)) with check (public.is_admin() or public.allowed_section(record_type));

grant execute on function public.current_account_access() to authenticated;
grant execute on function public.create_appointment_request(text,text,text,integer,text) to anon,authenticated;
