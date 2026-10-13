-- ORAVENA — booking email and automatic patient-account linking
-- Run once in Supabase SQL Editor after the previous ORAVENA setup files.

begin;

alter table public.patients add column if not exists email text;
alter table public.appointments add column if not exists email text;

create index if not exists patients_email_idx
  on public.patients(lower(email)) where email is not null;

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
    insert into public.patients(
      auth_user_id,full_name,email,phone,national_id,age
    ) values (
      auth.uid(),trim(p_full_name),lower(trim(p_email)),trim(p_phone),
      nullif(trim(p_national_id),''),p_age
    ) returning id into v_patient_id;
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

  insert into public.appointments(
    patient_id,full_name,email,phone,national_id,age,service
  ) values (
    v_patient_id,trim(p_full_name),lower(trim(p_email)),trim(p_phone),
    nullif(trim(p_national_id),''),p_age,trim(p_service)
  ) returning id into v_appointment_id;

  insert into public.clinic_records(
    record_type,patient_id,payload,patient_visible
  ) values (
    'notification',v_patient_id,
    jsonb_build_object(
      'title','طلب موعد جديد',
      'text',trim(p_full_name)||' — '||trim(p_service),
      'email',lower(trim(p_email)),
      'appointment_id',v_appointment_id,
      'read',false
    ),false
  );

  return v_appointment_id;
end
$$;

grant execute on function public.create_appointment_request(
  text,text,text,text,integer,text
) to anon,authenticated;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
declare
  v_invitation public.staff_invitations%rowtype;
  v_account_type text := 'patient';
  v_full_name text;
begin
  select * into v_invitation
  from public.staff_invitations
  where lower(email)=lower(coalesce(new.email,''))
    and status in ('pending','activated')
  limit 1;

  if lower(coalesce(new.email,''))=public.primary_admin_email() then
    v_account_type := 'admin';
  elsif v_invitation.id is not null then
    v_account_type := v_invitation.account_type;
  end if;

  v_full_name := coalesce(
    nullif(v_invitation.full_name,''),
    nullif(new.raw_user_meta_data->>'full_name',''),
    ''
  );

  insert into public.profiles(
    id,email,full_name,account_type,job_title,phone,status
  ) values (
    new.id,lower(new.email),v_full_name,v_account_type,
    v_invitation.job_title,
    coalesce(v_invitation.phone,nullif(new.raw_user_meta_data->>'phone','')),
    'active'
  ) on conflict (id) do update set
    email=excluded.email,
    full_name=case when excluded.full_name<>''
      then excluded.full_name else public.profiles.full_name end,
    account_type=case
      when excluded.email=public.primary_admin_email() then 'admin'
      when v_invitation.id is not null then excluded.account_type
      else public.profiles.account_type end,
    job_title=coalesce(excluded.job_title,public.profiles.job_title),
    phone=coalesce(excluded.phone,public.profiles.phone),
    status=case when excluded.email=public.primary_admin_email()
      then 'active' else public.profiles.status end,
    updated_at=now();

  if v_invitation.id is not null then
    insert into public.staff_permissions(
      user_id,sections,permission_templates,updated_at
    ) values (
      new.id,v_invitation.sections,v_invitation.permission_templates,now()
    ) on conflict (user_id) do update set
      sections=excluded.sections,
      permission_templates=excluded.permission_templates,
      updated_at=now();

    update public.staff_invitations set
      status='activated',activated_at=coalesce(activated_at,now()),updated_at=now()
    where id=v_invitation.id;
  elsif v_account_type='patient' then
    update public.patients set auth_user_id=new.id,updated_at=now()
    where auth_user_id is null and lower(email)=lower(coalesce(new.email,''));
  end if;

  return new;
end
$$;

commit;

select 'ORAVENA booking email and account linking are ready' as result;
