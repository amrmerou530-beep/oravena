-- ORAVENA V21
-- Repairs odontogram persistence, patient appointment visibility and booking services.
-- Safe to run once after V20. Existing business data is preserved.

begin;

-- Link one patient file to every registered account by its verified email.
with candidates as (
  select distinct on (u.id) p.id as patient_id,u.id as user_id
  from auth.users u
  join public.patients p on lower(trim(coalesce(p.email,'')))=lower(trim(coalesce(u.email,'')))
  where p.auth_user_id is null
  order by u.id,p.updated_at desc,p.created_at desc,p.id desc
)
update public.patients p
set auth_user_id=c.user_id,updated_at=now()
from candidates c
where p.id=c.patient_id;

-- If an old installation linked more than one file to the same account, move
-- all patient-visible relations to the newest file, then unlink the duplicate.
with ranked as (
  select id,auth_user_id,
         first_value(id) over(partition by auth_user_id order by updated_at desc,created_at desc,id desc) as canonical_id,
         row_number() over(partition by auth_user_id order by updated_at desc,created_at desc,id desc) as rn
  from public.patients
  where auth_user_id is not null
)
update public.appointments a
set patient_id=r.canonical_id,updated_at=now()
from ranked r
where r.rn>1 and a.patient_id=r.id;

with ranked as (
  select id,auth_user_id,
         first_value(id) over(partition by auth_user_id order by updated_at desc,created_at desc,id desc) as canonical_id,
         row_number() over(partition by auth_user_id order by updated_at desc,created_at desc,id desc) as rn
  from public.patients
  where auth_user_id is not null
)
update public.clinic_records r
set patient_id=x.canonical_id,updated_at=now()
from ranked x
where x.rn>1 and r.patient_id=x.id;

with ranked as (
  select id,row_number() over(partition by auth_user_id order by updated_at desc,created_at desc,id desc) as rn
  from public.patients
  where auth_user_id is not null
)
update public.patients p
set auth_user_id=null,updated_at=now()
from ranked r
where p.id=r.id and r.rn>1;

-- Relink appointment requests created before account linking by exact email.
with canonical as (
  select distinct on (lower(trim(email))) id,lower(trim(email)) as email_key
  from public.patients
  where auth_user_id is not null and nullif(trim(email),'') is not null
  order by lower(trim(email)),updated_at desc,created_at desc,id desc
)
update public.appointments a
set patient_id=c.id,updated_at=now()
from canonical c
where lower(trim(coalesce(a.email,'')))=c.email_key
  and a.patient_id is distinct from c.id;

-- Keep only the newest odontogram for each patient. Older duplicates caused
-- the browser to display stale tooth states after a successful save.
with ranked as (
  select id,row_number() over(
    partition by patient_id
    order by updated_at desc,created_at desc,id desc
  ) as rn
  from public.clinic_records
  where record_type='tooth' and patient_id is not null
)
delete from public.clinic_records r
using ranked x
where r.id=x.id and x.rn>1;

create unique index if not exists clinic_records_one_tooth_map_per_patient
on public.clinic_records(patient_id)
where record_type='tooth' and patient_id is not null;

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

  if p_record_type='tooth' and p_patient_id is null then
    raise exception 'PATIENT_REQUIRED';
  end if;

  if p_id is null and p_record_type='tooth' then
    update public.clinic_records
    set payload=coalesce(p_payload,'{}'::jsonb),
        patient_visible=true,
        owner_user_id=coalesce(owner_user_id,auth.uid()),
        updated_at=now()
    where record_type='tooth' and patient_id=p_patient_id
    returning * into v_row;

    if v_row.id is null then
      insert into public.clinic_records(record_type,patient_id,owner_user_id,payload,patient_visible)
      values('tooth',p_patient_id,auth.uid(),coalesce(p_payload,'{}'::jsonb),true)
      returning * into v_row;
    end if;
  elsif p_id is null then
    insert into public.clinic_records(record_type,patient_id,owner_user_id,payload,patient_visible)
    values(p_record_type,p_patient_id,auth.uid(),coalesce(p_payload,'{}'::jsonb),coalesce(p_patient_visible,false))
    returning * into v_row;
  else
    update public.clinic_records
    set patient_id=p_patient_id,
        payload=coalesce(p_payload,'{}'::jsonb),
        patient_visible=case when p_record_type='tooth' then true else coalesce(p_patient_visible,false) end,
        updated_at=now()
    where id=p_id
    returning * into v_row;
  end if;

  if v_row.id is null then raise exception 'RECORD_NOT_FOUND'; end if;
  return to_jsonb(v_row);
end
$$;

create or replace function public.create_appointment_request(
  p_full_name text,p_email text,p_phone text,p_national_id text,p_age integer,p_service text
) returns uuid
language plpgsql
security definer
set search_path=public,auth
as $$
declare
  v_patient_id uuid;
  v_appointment_id uuid;
  v_user_id uuid;
  v_service text:=trim(coalesce(p_service,''));
begin
  if length(trim(coalesce(p_full_name,'')))<2
     or position('@' in trim(coalesce(p_email,'')))<2
     or length(trim(coalesce(p_phone,'')))<6
     or p_age not between 0 and 120 then
    raise exception 'INVALID_APPOINTMENT_DATA';
  end if;

  if v_service<>'غير محدد' and not exists(
    select 1 from public.clinic_services s
    where s.active=true and s.name_ar=v_service
  ) then
    raise exception 'SERVICE_NOT_AVAILABLE';
  end if;

  v_user_id:=auth.uid();
  if v_user_id is null then
    select id into v_user_id from auth.users
    where lower(email)=lower(trim(p_email)) limit 1;
  end if;

  if v_user_id is not null then
    select id into v_patient_id from public.patients
    where auth_user_id=v_user_id
    order by updated_at desc,created_at desc limit 1;
  end if;

  if v_patient_id is null then
    select id into v_patient_id from public.patients
    where lower(trim(coalesce(email,'')))=lower(trim(p_email))
    order by updated_at desc,created_at desc limit 1;
  end if;

  if v_patient_id is null then
    select id into v_patient_id from public.patients
    where phone=trim(p_phone)
    order by updated_at desc,created_at desc limit 1;
  end if;

  if v_patient_id is null then
    insert into public.patients(auth_user_id,full_name,email,phone,national_id,age)
    values(v_user_id,trim(p_full_name),lower(trim(p_email)),trim(p_phone),nullif(trim(p_national_id),''),p_age)
    returning id into v_patient_id;
  else
    update public.patients set
      auth_user_id=coalesce(auth_user_id,v_user_id),
      full_name=trim(p_full_name),email=lower(trim(p_email)),phone=trim(p_phone),
      national_id=coalesce(nullif(trim(p_national_id),''),national_id),
      age=p_age,updated_at=now()
    where id=v_patient_id;
  end if;

  insert into public.appointments(patient_id,full_name,email,phone,national_id,age,service)
  values(v_patient_id,trim(p_full_name),lower(trim(p_email)),trim(p_phone),nullif(trim(p_national_id),''),p_age,v_service)
  returning id into v_appointment_id;

  insert into public.clinic_records(record_type,patient_id,payload,patient_visible)
  values('notification',v_patient_id,jsonb_build_object(
    'title','طلب موعد جديد','text',trim(p_full_name)||' — '||v_service,
    'email',lower(trim(p_email)),'appointment_id',v_appointment_id,'read',false
  ),false);

  return v_appointment_id;
exception
  when unique_violation then raise exception 'PHONE_OR_EMAIL_ALREADY_LINKED';
end
$$;

create or replace function public.oravena_persistence_health()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select case when auth.uid() is null then
    jsonb_build_object('ok',false,'version',21,'reason','AUTH_REQUIRED')
  else
    jsonb_build_object('ok',true,'version',21,'user_id',auth.uid(),'server_time',now())
  end
$$;

grant execute on function public.oravena_save_record(uuid,text,uuid,jsonb,boolean) to authenticated;
grant execute on function public.create_appointment_request(text,text,text,text,integer,text) to anon,authenticated;
grant execute on function public.oravena_persistence_health() to authenticated;

commit;

notify pgrst, 'reload schema';
select 'ORAVENA tooth, appointments and services v21 is ready' as result;
