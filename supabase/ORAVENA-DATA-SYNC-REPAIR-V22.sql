-- ORAVENA V22 — authoritative data sync and permission repair
-- Run once after the existing ORAVENA setup. No operational data is reset.

begin;

alter table public.patients add column if not exists email text;
alter table public.appointments add column if not exists email text;
alter table public.appointments add column if not exists doctor_name text;

-- Temporarily remove the odontogram uniqueness rule while old duplicate
-- patient accounts are consolidated into one canonical account.
drop index if exists public.clinic_records_one_tooth_map_per_patient;

-- Choose exactly one canonical patient file for every authenticated account.
-- All appointments and medical records move to that file; no clinical record
-- is discarded here.
with ranked as (
  select id,auth_user_id,
         first_value(id) over(
           partition by auth_user_id
           order by (phone not like 'ACCOUNT-%') desc,updated_at desc,created_at desc,id desc
         ) canonical_id,
         row_number() over(
           partition by auth_user_id
           order by (phone not like 'ACCOUNT-%') desc,updated_at desc,created_at desc,id desc
         ) rn
  from public.patients where auth_user_id is not null
)
update public.appointments a
set patient_id=r.canonical_id,updated_at=now()
from ranked r
where r.rn>1 and a.patient_id=r.id;

with ranked as (
  select id,auth_user_id,
         first_value(id) over(
           partition by auth_user_id
           order by (phone not like 'ACCOUNT-%') desc,updated_at desc,created_at desc,id desc
         ) canonical_id,
         row_number() over(
           partition by auth_user_id
           order by (phone not like 'ACCOUNT-%') desc,updated_at desc,created_at desc,id desc
         ) rn
  from public.patients where auth_user_id is not null
)
update public.clinic_records c
set patient_id=r.canonical_id,updated_at=now()
from ranked r
where r.rn>1 and c.patient_id=r.id;

with ranked as (
  select id,row_number() over(
    partition by auth_user_id
    order by (phone not like 'ACCOUNT-%') desc,updated_at desc,created_at desc,id desc
  ) rn
  from public.patients where auth_user_id is not null
)
update public.patients p
set auth_user_id=null,updated_at=now()
from ranked r
where p.id=r.id and r.rn>1;

create unique index if not exists patients_one_file_per_auth_user
on public.patients(auth_user_id) where auth_user_id is not null;

-- Keep the most recently updated odontogram as the active map after
-- consolidation. Older duplicates are preserved as history; nothing is
-- deleted by this migration.
with ranked as (
  select id,row_number() over(
    partition by patient_id order by updated_at desc,created_at desc,id desc
  ) rn
  from public.clinic_records
  where record_type='tooth' and patient_id is not null
)
update public.clinic_records c
set record_type='tooth_history',
    payload=coalesce(c.payload,'{}'::jsonb)||jsonb_build_object(
      'archived_by_migration',22,
      'archived_at',now()
    ),
    patient_visible=false,
    updated_at=now()
from ranked r
where c.id=r.id and r.rn>1;

create unique index clinic_records_one_tooth_map_per_patient
on public.clinic_records(patient_id)
where record_type='tooth' and patient_id is not null;

create or replace function public.current_account_access()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select jsonb_build_object(
    'user_id',p.id,'email',p.email,'full_name',p.full_name,
    'account_type',p.account_type,'job_title',p.job_title,'status',p.status,
    'sections',case when public.is_admin() then
      array['dashboard','services','appointments','patients','sessions','odontogram',
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

create or replace function public.oravena_core_data()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_account_type text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select account_type into v_account_type
  from public.profiles where id=auth.uid() and status='active';
  if v_account_type is null then raise exception 'ACCOUNT_NOT_ACTIVE'; end if;

  return jsonb_build_object(
    'patients',coalesce((
      select jsonb_agg(to_jsonb(p) order by p.updated_at desc,p.created_at desc)
      from public.patients p
      where public.allowed_section('patients') or p.auth_user_id=auth.uid()
    ),'[]'::jsonb),
    'appointments',coalesce((
      select jsonb_agg(to_jsonb(a) order by a.updated_at desc,a.created_at desc)
      from public.appointments a
      where public.allowed_section('appointments') or exists(
        select 1 from public.patients p
        where p.id=a.patient_id and p.auth_user_id=auth.uid()
      )
    ),'[]'::jsonb),
    'records',coalesce((
      select jsonb_agg(
        case when v_account_type='patient' then
          to_jsonb(r)||jsonb_build_object(
            'payload',case when r.record_type='session' then r.payload-'internal' else r.payload end
          )
        else to_jsonb(r) end
        order by r.updated_at desc,r.created_at desc
      )
      from public.clinic_records r
      where public.allowed_section(public.clinic_record_section(r.record_type))
         or (r.patient_visible and exists(
           select 1 from public.patients p
           where p.id=r.patient_id and p.auth_user_id=auth.uid()
         ))
    ),'[]'::jsonb),
    'staff',case when public.is_admin() then coalesce((
      select jsonb_agg(to_jsonb(s) order by s.updated_at desc,s.created_at desc)
      from public.staff_invitations s
    ),'[]'::jsonb) else '[]'::jsonb end,
    'services',coalesce((
      select jsonb_agg(to_jsonb(s) order by s.sort_order,s.name_ar)
      from public.clinic_services s
      where s.active or public.allowed_section('services')
    ),'[]'::jsonb),
    'meta',jsonb_build_object('version',22,'user_id',auth.uid(),'server_time',now())
  );
end
$$;

create or replace function public.create_appointment_request(
  p_full_name text,p_email text,p_phone text,p_national_id text,p_age integer,p_service text
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_patient_id uuid;
  v_appointment_id uuid;
  v_patient_user_id uuid;
  v_service text:=trim(coalesce(p_service,''));
begin
  if length(trim(coalesce(p_full_name,'')))<2
     or position('@' in trim(coalesce(p_email,'')))<2
     or length(trim(coalesce(p_phone,'')))<6
     or p_age not between 0 and 120 then
    raise exception 'INVALID_APPOINTMENT_DATA';
  end if;
  if v_service<>'غير محدد' and not exists(
    select 1 from public.clinic_services s where s.active and s.name_ar=v_service
  ) then raise exception 'SERVICE_NOT_AVAILABLE'; end if;

  select id into v_patient_user_id from public.profiles
  where id=auth.uid() and account_type='patient' and status='active';

  if v_patient_user_id is not null then
    select id into v_patient_id from public.patients
    where auth_user_id=v_patient_user_id limit 1;
  end if;

  if v_patient_id is null then
    select id into v_patient_id from public.patients
    where lower(trim(coalesce(email,'')))=lower(trim(p_email))
      and phone=trim(p_phone)
    order by updated_at desc,created_at desc limit 1;
  end if;

  if v_patient_id is null then
    select id into v_patient_id from public.patients
    where phone=trim(p_phone)
    order by updated_at desc,created_at desc limit 1;
  end if;

  if v_patient_id is null then
    insert into public.patients(auth_user_id,full_name,email,phone,national_id,age)
    values(v_patient_user_id,trim(p_full_name),lower(trim(p_email)),trim(p_phone),
      nullif(trim(p_national_id),''),p_age)
    returning id into v_patient_id;
  elsif v_patient_user_id is not null or exists(
    select 1 from public.patients where id=v_patient_id and auth_user_id is null
  ) then
    update public.patients set
      auth_user_id=coalesce(auth_user_id,v_patient_user_id),full_name=trim(p_full_name),
      email=lower(trim(p_email)),phone=trim(p_phone),
      national_id=coalesce(nullif(trim(p_national_id),''),national_id),
      age=p_age,updated_at=now()
    where id=v_patient_id;
  end if;

  insert into public.appointments(
    patient_id,full_name,email,phone,national_id,age,service,status
  ) values(
    v_patient_id,trim(p_full_name),lower(trim(p_email)),trim(p_phone),
    nullif(trim(p_national_id),''),p_age,v_service,'new_request'
  ) returning id into v_appointment_id;

  insert into public.clinic_records(record_type,patient_id,payload,patient_visible)
  values('notification',v_patient_id,jsonb_build_object(
    'title','طلب موعد جديد','text',trim(p_full_name)||' — '||v_service,
    'email',lower(trim(p_email)),'appointment_id',v_appointment_id,'read',false
  ),false);
  return v_appointment_id;
end
$$;

create or replace function public.oravena_save_appointment(p_id uuid,p_data jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_old public.appointments%rowtype;
  v_row public.appointments%rowtype;
  v_patient_id uuid:=nullif(p_data->>'patient_id','')::uuid;
  v_status text:=coalesce(nullif(p_data->>'status',''),'new_request');
  v_date date:=nullif(p_data->>'appointment_date','')::date;
  v_time time:=nullif(p_data->>'appointment_time','')::time;
  v_changed boolean:=false;
begin
  if not public.allowed_section('appointments') then raise exception 'PERMISSION_DENIED'; end if;
  if v_patient_id is null or not exists(select 1 from public.patients where id=v_patient_id) then
    raise exception 'PATIENT_NOT_FOUND';
  end if;
  if v_status not in ('new_request','confirmed','changed','cancelled','completed') then
    raise exception 'INVALID_APPOINTMENT_STATUS';
  end if;

  if p_id is null then
    insert into public.appointments(
      patient_id,full_name,email,phone,national_id,age,service,
      appointment_date,appointment_time,doctor_name,status,change_reason
    ) values(
      v_patient_id,trim(p_data->>'full_name'),nullif(lower(trim(p_data->>'email')),''),
      trim(p_data->>'phone'),nullif(trim(p_data->>'national_id'),''),
      nullif(p_data->>'age','')::integer,trim(p_data->>'service'),v_date,v_time,
      nullif(trim(p_data->>'doctor_name'),''),v_status,nullif(trim(p_data->>'change_reason'),'')
    ) returning * into v_row;
    v_changed:=true;
  else
    select * into v_old from public.appointments where id=p_id for update;
    if v_old.id is null then raise exception 'APPOINTMENT_NOT_FOUND'; end if;
    update public.appointments set
      patient_id=v_patient_id,full_name=trim(p_data->>'full_name'),
      email=nullif(lower(trim(p_data->>'email')),''),phone=trim(p_data->>'phone'),
      national_id=nullif(trim(p_data->>'national_id'),''),
      age=nullif(p_data->>'age','')::integer,service=trim(p_data->>'service'),
      appointment_date=v_date,appointment_time=v_time,
      doctor_name=nullif(trim(p_data->>'doctor_name'),''),status=v_status,
      change_reason=nullif(trim(p_data->>'change_reason'),''),updated_at=now()
    where id=p_id returning * into v_row;
    v_changed:=v_old.patient_id is distinct from v_row.patient_id
      or v_old.status is distinct from v_row.status
      or v_old.appointment_date is distinct from v_row.appointment_date
      or v_old.appointment_time is distinct from v_row.appointment_time
      or v_old.service is distinct from v_row.service
      or v_old.doctor_name is distinct from v_row.doctor_name;
  end if;

  if v_changed then
    insert into public.clinic_records(record_type,patient_id,owner_user_id,payload,patient_visible)
    values('notification',v_row.patient_id,auth.uid(),jsonb_build_object(
      'title',case when p_id is null then 'تم تسجيل موعد' else 'تم تحديث الموعد' end,
      'text',concat_ws(' · ',v_row.service,coalesce(v_row.appointment_date::text,'موعد غير محدد'),
        coalesce(to_char(v_row.appointment_time,'HH24:MI'),''),'الحالة: '||v_status),
      'appointment_id',v_row.id,'status',v_status,'date',v_row.appointment_date,
      'time',v_row.appointment_time,'reason',v_row.change_reason,'read',false
    ),true);
  end if;
  return to_jsonb(v_row)||jsonb_build_object('_confirmed',true);
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
  if length(trim(coalesce(p_data->>'full_name','')))<2
     or length(trim(coalesce(p_data->>'phone','')))<6 then
    raise exception 'INVALID_PATIENT_DATA';
  end if;
  if p_id is null then
    insert into public.patients(
      file_number,full_name,email,phone,national_id,age,birth_date,blood_type,
      allergy,chronic_conditions,current_medications,doctor_notes,emergency_contact,balance
    ) values(
      coalesce(nullif(trim(p_data->>'file_number'),''),'OR-'||nextval('public.patient_file_seq')),
      trim(p_data->>'full_name'),nullif(lower(trim(p_data->>'email')),''),trim(p_data->>'phone'),
      nullif(trim(p_data->>'national_id'),''),nullif(p_data->>'age','')::integer,
      nullif(p_data->>'birth_date','')::date,nullif(trim(p_data->>'blood_type'),''),
      nullif(trim(p_data->>'allergy'),''),nullif(trim(p_data->>'chronic_conditions'),''),
      nullif(trim(p_data->>'current_medications'),''),nullif(trim(p_data->>'doctor_notes'),''),
      nullif(trim(p_data->>'emergency_contact'),''),coalesce(nullif(p_data->>'balance','')::numeric,0)
    ) returning * into v_row;
  else
    update public.patients set
      file_number=coalesce(nullif(trim(p_data->>'file_number'),''),file_number),
      full_name=trim(p_data->>'full_name'),email=nullif(lower(trim(p_data->>'email')),''),
      phone=trim(p_data->>'phone'),national_id=nullif(trim(p_data->>'national_id'),''),
      age=nullif(p_data->>'age','')::integer,birth_date=nullif(p_data->>'birth_date','')::date,
      blood_type=nullif(trim(p_data->>'blood_type'),''),allergy=nullif(trim(p_data->>'allergy'),''),
      chronic_conditions=nullif(trim(p_data->>'chronic_conditions'),''),
      current_medications=nullif(trim(p_data->>'current_medications'),''),
      doctor_notes=nullif(trim(p_data->>'doctor_notes'),''),
      emergency_contact=nullif(trim(p_data->>'emergency_contact'),''),
      balance=coalesce(nullif(p_data->>'balance','')::numeric,0),updated_at=now()
    where id=p_id returning * into v_row;
  end if;
  if v_row.id is null then raise exception 'PATIENT_NOT_FOUND'; end if;
  return to_jsonb(v_row)||jsonb_build_object('_confirmed',true);
end
$$;

create or replace function public.oravena_save_record(
  p_id uuid,p_record_type text,p_patient_id uuid,p_payload jsonb,p_patient_visible boolean
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_row public.clinic_records%rowtype;
begin
  if not public.allowed_section(public.clinic_record_section(p_record_type)) then
    raise exception 'PERMISSION_DENIED';
  end if;
  if p_patient_id is not null and not exists(select 1 from public.patients where id=p_patient_id) then
    raise exception 'PATIENT_NOT_FOUND';
  end if;
  if p_record_type='tooth' then
    if p_patient_id is null then raise exception 'PATIENT_REQUIRED'; end if;
    insert into public.clinic_records(record_type,patient_id,owner_user_id,payload,patient_visible)
    values('tooth',p_patient_id,auth.uid(),coalesce(p_payload,'{}'::jsonb),true)
    on conflict (patient_id) where record_type='tooth' and patient_id is not null
    do update set payload=excluded.payload,patient_visible=true,
      owner_user_id=coalesce(public.clinic_records.owner_user_id,auth.uid()),updated_at=now()
    returning * into v_row;
  elsif p_id is null then
    insert into public.clinic_records(record_type,patient_id,owner_user_id,payload,patient_visible)
    values(p_record_type,p_patient_id,auth.uid(),coalesce(p_payload,'{}'::jsonb),coalesce(p_patient_visible,false))
    returning * into v_row;
  else
    update public.clinic_records set
      patient_id=p_patient_id,payload=coalesce(p_payload,'{}'::jsonb),
      patient_visible=coalesce(p_patient_visible,false),updated_at=now()
    where id=p_id and record_type=p_record_type returning * into v_row;
  end if;
  if v_row.id is null then raise exception 'RECORD_NOT_FOUND'; end if;
  return to_jsonb(v_row)||jsonb_build_object('_confirmed',true);
end
$$;

-- Replace permissive legacy policies with explicit read/manage boundaries.
drop policy if exists "staff read patients" on public.patients;
drop policy if exists "staff manage patients" on public.patients;
drop policy if exists "appointments by permission" on public.appointments;
drop policy if exists "records by permission" on public.clinic_records;
drop policy if exists "records read" on public.clinic_records;
drop policy if exists "staff manage records" on public.clinic_records;
drop policy if exists "oravena patients select" on public.patients;
drop policy if exists "oravena patients manage" on public.patients;
drop policy if exists "oravena appointments select" on public.appointments;
drop policy if exists "oravena appointments manage" on public.appointments;
drop policy if exists "oravena records select" on public.clinic_records;
drop policy if exists "oravena records manage" on public.clinic_records;

create policy "oravena patients select" on public.patients
for select to authenticated using(
  public.allowed_section('patients') or auth_user_id=auth.uid()
);
create policy "oravena patients manage" on public.patients
for all to authenticated using(public.allowed_section('patients'))
with check(public.allowed_section('patients'));

create policy "oravena appointments select" on public.appointments
for select to authenticated using(
  public.allowed_section('appointments') or exists(
    select 1 from public.patients p
    where p.id=public.appointments.patient_id and p.auth_user_id=auth.uid()
  )
);
create policy "oravena appointments manage" on public.appointments
for all to authenticated using(public.allowed_section('appointments'))
with check(public.allowed_section('appointments'));

create policy "oravena records select" on public.clinic_records
for select to authenticated using(
  public.allowed_section(public.clinic_record_section(record_type)) or
  (patient_visible and exists(
    select 1 from public.patients p
    where p.id=public.clinic_records.patient_id and p.auth_user_id=auth.uid()
  ))
);
create policy "oravena records manage" on public.clinic_records
for all to authenticated using(
  public.allowed_section(public.clinic_record_section(record_type))
) with check(
  public.allowed_section(public.clinic_record_section(record_type))
);

revoke insert,update,delete on public.patients,public.appointments,public.clinic_records from anon,authenticated;
grant select on public.patients,public.appointments,public.clinic_records to authenticated;

create or replace function public.oravena_persistence_health()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select case when auth.uid() is null then
    jsonb_build_object('ok',false,'version',22,'reason','AUTH_REQUIRED')
  else jsonb_build_object('ok',true,'version',22,'user_id',auth.uid(),'server_time',now()) end
$$;

grant execute on function public.current_account_access() to authenticated;
grant execute on function public.oravena_core_data() to authenticated;
grant execute on function public.create_appointment_request(text,text,text,text,integer,text) to anon,authenticated;
grant execute on function public.oravena_save_appointment(uuid,jsonb) to authenticated;
grant execute on function public.oravena_save_patient(uuid,jsonb) to authenticated;
grant execute on function public.oravena_save_record(uuid,text,uuid,jsonb,boolean) to authenticated;
grant execute on function public.oravena_persistence_health() to authenticated;

commit;
notify pgrst, 'reload schema';
select 'ORAVENA data sync repair v22 is ready' as result;
