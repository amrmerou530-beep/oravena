-- ORAVENA V18 — unified, durable data API
-- Run this entire file once in Supabase SQL Editor.
-- Safe to rerun. It does not delete accounts or operational data.

begin;

alter table public.appointments add column if not exists doctor_name text;

create table if not exists public.clinic_services (
  id uuid primary key default gen_random_uuid(),
  name_ar text not null,
  name_tr text,
  name_en text,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists clinic_services_name_ar_unique
  on public.clinic_services(lower(name_ar));

create table if not exists public.staff_invitations (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  full_name text not null,
  account_type text not null check (account_type in ('doctor','employee')),
  job_title text,
  phone text,
  sections text[] not null default '{}',
  permission_templates text[] not null default '{}',
  status text not null default 'pending',
  invited_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  activated_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.clinic_services enable row level security;
grant select on public.clinic_services to anon,authenticated;
grant insert,update,delete on public.clinic_services to authenticated;

drop policy if exists "public reads active services" on public.clinic_services;
create policy "public reads active services" on public.clinic_services
for select to anon,authenticated using (active=true);

drop policy if exists "authorized staff reads all services" on public.clinic_services;
create policy "authorized staff reads all services" on public.clinic_services
for select to authenticated using (public.allowed_section('services'));

drop policy if exists "authorized staff manages services" on public.clinic_services;
create policy "authorized staff manages services" on public.clinic_services
for all to authenticated using (public.allowed_section('services'))
with check (public.allowed_section('services'));

insert into public.clinic_services(name_ar,name_tr,name_en,active,sort_order)
values
  ('الفحص والتشخيص','Muayene ve teşhis','Examination & diagnosis',true,10),
  ('العلاج والترميم','Tedavi ve restorasyon','Treatment & restoration',true,20),
  ('التقويم والابتسامة','Ortodonti ve gülüş','Orthodontics & smile',true,30),
  ('الزراعة والجراحة','İmplant ve cerrahi','Implants & surgery',true,40)
on conflict do nothing;

create or replace function public.clinic_record_section(record_kind text)
returns text language sql immutable set search_path=public
as $$
  select case record_kind
    when 'session' then 'sessions'
    when 'treatment_plan' then 'plans'
    when 'prescription' then 'prescriptions'
    when 'imaging' then 'imaging'
    when 'tooth' then 'odontogram'
    when 'finance' then 'finance'
    when 'inventory' then 'inventory'
    when 'lab' then 'labs'
    when 'message' then 'messages'
    when 'notification' then 'dashboard'
    when 'audit' then 'audit'
    when 'setting' then 'settings'
    else record_kind
  end
$$;

create or replace function public.oravena_core_data()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;

  return jsonb_build_object(
    'patients',coalesce((
      select jsonb_agg(to_jsonb(p) order by p.created_at desc)
      from public.patients p
      where public.allowed_section('patients') or p.auth_user_id=auth.uid()
    ),'[]'::jsonb),
    'appointments',coalesce((
      select jsonb_agg(to_jsonb(a) order by a.created_at desc)
      from public.appointments a
      where public.allowed_section('appointments') or exists(
        select 1 from public.patients p
        where p.id=a.patient_id and p.auth_user_id=auth.uid()
      )
    ),'[]'::jsonb),
    'records',coalesce((
      select jsonb_agg(to_jsonb(r) order by r.created_at desc)
      from public.clinic_records r
      where public.allowed_section(public.clinic_record_section(r.record_type))
         or (r.patient_visible and exists(
           select 1 from public.patients p
           where p.id=r.patient_id and p.auth_user_id=auth.uid()
         ))
    ),'[]'::jsonb),
    'staff',case when public.is_admin() then coalesce((
      select jsonb_agg(to_jsonb(s) order by s.created_at desc)
      from public.staff_invitations s
    ),'[]'::jsonb) else '[]'::jsonb end,
    'services',coalesce((
      select jsonb_agg(to_jsonb(s) order by s.sort_order,s.name_ar)
      from public.clinic_services s
      where s.active or public.allowed_section('services')
    ),'[]'::jsonb)
  );
end
$$;

create or replace function public.oravena_save_patient(p_id uuid,p_data jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_row public.patients%rowtype;
begin
  if not public.allowed_section('patients') then raise exception 'PERMISSION_DENIED'; end if;
  if length(trim(coalesce(p_data->>'full_name','')))<2 or length(trim(coalesce(p_data->>'phone','')))<6 then
    raise exception 'INVALID_PATIENT_DATA';
  end if;

  if p_id is null then
    if nullif(trim(p_data->>'file_number'),'') is null then
      insert into public.patients(full_name,email,phone,national_id,age,birth_date,blood_type,allergy,chronic_conditions,current_medications,doctor_notes,emergency_contact,balance)
      values(trim(p_data->>'full_name'),nullif(lower(trim(p_data->>'email')),''),trim(p_data->>'phone'),nullif(trim(p_data->>'national_id'),''),nullif(p_data->>'age','')::integer,nullif(p_data->>'birth_date','')::date,nullif(p_data->>'blood_type',''),nullif(p_data->>'allergy',''),nullif(p_data->>'chronic_conditions',''),nullif(p_data->>'current_medications',''),nullif(p_data->>'doctor_notes',''),nullif(p_data->>'emergency_contact',''),coalesce(nullif(p_data->>'balance','')::numeric,0))
      returning * into v_row;
    else
      insert into public.patients(file_number,full_name,email,phone,national_id,age,birth_date,blood_type,allergy,chronic_conditions,current_medications,doctor_notes,emergency_contact,balance)
      values(trim(p_data->>'file_number'),trim(p_data->>'full_name'),nullif(lower(trim(p_data->>'email')),''),trim(p_data->>'phone'),nullif(trim(p_data->>'national_id'),''),nullif(p_data->>'age','')::integer,nullif(p_data->>'birth_date','')::date,nullif(p_data->>'blood_type',''),nullif(p_data->>'allergy',''),nullif(p_data->>'chronic_conditions',''),nullif(p_data->>'current_medications',''),nullif(p_data->>'doctor_notes',''),nullif(p_data->>'emergency_contact',''),coalesce(nullif(p_data->>'balance','')::numeric,0))
      returning * into v_row;
    end if;
  else
    update public.patients set
      file_number=coalesce(nullif(trim(p_data->>'file_number'),''),file_number),
      full_name=trim(p_data->>'full_name'),email=nullif(lower(trim(p_data->>'email')),''),phone=trim(p_data->>'phone'),
      national_id=nullif(trim(p_data->>'national_id'),''),age=nullif(p_data->>'age','')::integer,birth_date=nullif(p_data->>'birth_date','')::date,
      blood_type=nullif(p_data->>'blood_type',''),allergy=nullif(p_data->>'allergy',''),chronic_conditions=nullif(p_data->>'chronic_conditions',''),
      current_medications=nullif(p_data->>'current_medications',''),doctor_notes=nullif(p_data->>'doctor_notes',''),emergency_contact=nullif(p_data->>'emergency_contact',''),
      balance=coalesce(nullif(p_data->>'balance','')::numeric,0),updated_at=now()
    where id=p_id returning * into v_row;
  end if;
  if v_row.id is null then raise exception 'PATIENT_NOT_FOUND'; end if;
  return to_jsonb(v_row);
end
$$;

create or replace function public.oravena_save_appointment(p_id uuid,p_data jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_row public.appointments%rowtype;
begin
  if not public.allowed_section('appointments') then raise exception 'PERMISSION_DENIED'; end if;
  if p_id is null then
    insert into public.appointments(patient_id,full_name,email,phone,national_id,age,service,appointment_date,appointment_time,doctor_name,status,change_reason)
    values((p_data->>'patient_id')::uuid,p_data->>'full_name',nullif(p_data->>'email',''),p_data->>'phone',nullif(p_data->>'national_id',''),nullif(p_data->>'age','')::integer,p_data->>'service',nullif(p_data->>'appointment_date','')::date,nullif(p_data->>'appointment_time','')::time,nullif(p_data->>'doctor_name',''),p_data->>'status',nullif(p_data->>'change_reason',''))
    returning * into v_row;
  else
    update public.appointments set patient_id=(p_data->>'patient_id')::uuid,full_name=p_data->>'full_name',email=nullif(p_data->>'email',''),phone=p_data->>'phone',national_id=nullif(p_data->>'national_id',''),age=nullif(p_data->>'age','')::integer,service=p_data->>'service',appointment_date=nullif(p_data->>'appointment_date','')::date,appointment_time=nullif(p_data->>'appointment_time','')::time,doctor_name=nullif(p_data->>'doctor_name',''),status=p_data->>'status',change_reason=nullif(p_data->>'change_reason',''),updated_at=now()
    where id=p_id returning * into v_row;
  end if;
  if v_row.id is null then raise exception 'APPOINTMENT_NOT_FOUND'; end if;
  return to_jsonb(v_row);
end
$$;

create or replace function public.oravena_save_record(p_id uuid,p_record_type text,p_patient_id uuid,p_payload jsonb,p_patient_visible boolean)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_row public.clinic_records%rowtype;
begin
  if not public.allowed_section(public.clinic_record_section(p_record_type)) then raise exception 'PERMISSION_DENIED'; end if;
  if p_id is null then
    insert into public.clinic_records(record_type,patient_id,owner_user_id,payload,patient_visible)
    values(p_record_type,p_patient_id,auth.uid(),coalesce(p_payload,'{}'::jsonb),coalesce(p_patient_visible,false)) returning * into v_row;
  else
    update public.clinic_records set patient_id=p_patient_id,payload=coalesce(p_payload,'{}'::jsonb),patient_visible=coalesce(p_patient_visible,false),updated_at=now()
    where id=p_id returning * into v_row;
  end if;
  if v_row.id is null then raise exception 'RECORD_NOT_FOUND'; end if;
  return to_jsonb(v_row);
end
$$;

create or replace function public.oravena_save_service(p_id uuid,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare v_row public.clinic_services%rowtype;
begin
  if not public.allowed_section('services') then raise exception 'PERMISSION_DENIED'; end if;
  if p_id is null then
    insert into public.clinic_services(name_ar,name_tr,name_en,active,sort_order)
    values(trim(p_data->>'name_ar'),nullif(trim(p_data->>'name_tr'),''),nullif(trim(p_data->>'name_en'),''),coalesce((p_data->>'active')::boolean,false),coalesce((p_data->>'sort_order')::integer,0)) returning * into v_row;
  else
    update public.clinic_services set name_ar=trim(p_data->>'name_ar'),name_tr=nullif(trim(p_data->>'name_tr'),''),name_en=nullif(trim(p_data->>'name_en'),''),active=coalesce((p_data->>'active')::boolean,false),sort_order=coalesce((p_data->>'sort_order')::integer,0),updated_at=now()
    where id=p_id returning * into v_row;
  end if;
  return to_jsonb(v_row);
end
$$;

create or replace function public.oravena_delete_entity(p_entity text,p_id uuid)
returns boolean language plpgsql security definer set search_path=public
as $$
declare v_type text;
begin
  case p_entity
    when 'patient' then
      if not public.allowed_section('patients') then raise exception 'PERMISSION_DENIED'; end if;
      delete from public.patients where id=p_id;
    when 'appointment' then
      if not public.allowed_section('appointments') then raise exception 'PERMISSION_DENIED'; end if;
      delete from public.appointments where id=p_id;
    when 'service' then
      if not public.allowed_section('services') then raise exception 'PERMISSION_DENIED'; end if;
      delete from public.clinic_services where id=p_id;
    when 'record' then
      select record_type into v_type from public.clinic_records where id=p_id;
      if not public.allowed_section(public.clinic_record_section(v_type)) then raise exception 'PERMISSION_DENIED'; end if;
      delete from public.clinic_records where id=p_id;
    else raise exception 'INVALID_ENTITY';
  end case;
  return found;
end
$$;

create or replace function public.mark_my_notifications_read()
returns integer language plpgsql security definer set search_path=public
as $$
declare changed_count integer;
begin
  update public.clinic_records r
  set payload=jsonb_set(r.payload,'{read}','true'::jsonb,true),updated_at=now()
  where r.record_type='notification' and r.patient_visible=true
    and r.patient_id in (select p.id from public.patients p where p.auth_user_id=auth.uid())
    and coalesce((r.payload->>'read')::boolean,false)=false;
  get diagnostics changed_count=row_count;
  return changed_count;
end
$$;

create or replace function public.link_patient_auth_account()
returns trigger language plpgsql security definer set search_path=public,auth
as $$
begin
  if new.auth_user_id is null and nullif(trim(new.email),'') is not null then
    select u.id into new.auth_user_id from auth.users u
    where lower(u.email)=lower(trim(new.email)) limit 1;
  end if;
  new.updated_at=now();
  return new;
end
$$;

drop trigger if exists link_patient_auth_account_trigger on public.patients;
create trigger link_patient_auth_account_trigger
before insert or update of email on public.patients
for each row execute function public.link_patient_auth_account();

update public.patients p set auth_user_id=u.id,updated_at=now()
from auth.users u
where p.auth_user_id is null and p.email is not null and lower(p.email)=lower(u.email);

drop policy if exists "records read" on public.clinic_records;
create policy "records read" on public.clinic_records for select to authenticated using (
  public.allowed_section(public.clinic_record_section(record_type)) or
  (patient_visible and patient_id in (select id from public.patients where auth_user_id=auth.uid()))
);

drop policy if exists "staff manage records" on public.clinic_records;
create policy "staff manage records" on public.clinic_records for all to authenticated
using (public.allowed_section(public.clinic_record_section(record_type)))
with check (public.allowed_section(public.clinic_record_section(record_type)));

grant execute on function public.oravena_core_data() to authenticated;
grant execute on function public.oravena_save_patient(uuid,jsonb) to authenticated;
grant execute on function public.oravena_save_appointment(uuid,jsonb) to authenticated;
grant execute on function public.oravena_save_record(uuid,text,uuid,jsonb,boolean) to authenticated;
grant execute on function public.oravena_save_service(uuid,jsonb) to authenticated;
grant execute on function public.oravena_delete_entity(text,uuid) to authenticated;
grant execute on function public.mark_my_notifications_read() to authenticated;

grant select,insert,update,delete on public.patients,public.appointments,public.clinic_records,public.clinic_services to authenticated;
grant select on public.staff_invitations to authenticated;
grant usage,select on sequence public.patient_file_seq to authenticated;

commit;

notify pgrst, 'reload schema';
select 'ORAVENA unified data fix v18 is ready' as result;
