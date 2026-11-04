-- ORAVENA V30 — client-requested registration, doctor access, and session pricing fixes
-- Run once in Supabase SQL Editor after V28. Existing data is preserved.
begin;

-- A doctor account automatically gets the clinical workflow needed for daily work.
-- There is no separate "price permission". Other staff still use assigned sections.
create or replace function public.allowed_section(section_name text)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select public.is_admin()
    or exists(
      select 1 from public.profiles p
      where p.id=auth.uid()
        and p.status='active'
        and p.account_type='doctor'
        and section_name=any(array[
          'dashboard','services','appointments','patients','sessions',
          'odontogram','plans','accounts','reports'
        ]::text[])
    )
    or exists(
      select 1
      from public.staff_permissions sp
      join public.profiles p on p.id=sp.user_id
      where sp.user_id=auth.uid()
        and p.status='active'
        and section_name=any(sp.sections)
    )
$$;

-- Keep the UI and database rules aligned: phone is optional when staff creates a
-- patient file, but if supplied it must contain at least six characters.
create or replace function public.oravena_save_patient(p_id uuid,p_data jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_row public.patients%rowtype;
  v_phone text:=trim(coalesce(p_data->>'phone',''));
begin
  if not public.allowed_section('patients') then raise exception 'PERMISSION_DENIED'; end if;
  if length(trim(coalesce(p_data->>'full_name','')))<2
     or (v_phone<>'' and length(v_phone)<6) then
    raise exception 'INVALID_PATIENT_DATA';
  end if;

  if p_id is null then
    insert into public.patients(
      file_number,full_name,email,phone,national_id,age,birth_date,blood_type,
      allergy,chronic_conditions,current_medications,doctor_notes,emergency_contact,balance
    ) values(
      coalesce(nullif(trim(p_data->>'file_number'),''),'OR-'||nextval('public.patient_file_seq')),
      trim(p_data->>'full_name'),nullif(lower(trim(p_data->>'email')),''),v_phone,
      nullif(trim(p_data->>'national_id'),''),nullif(p_data->>'age','')::integer,
      nullif(p_data->>'birth_date','')::date,nullif(trim(p_data->>'blood_type'),''),
      nullif(trim(p_data->>'allergy'),''),nullif(trim(p_data->>'chronic_conditions'),''),
      nullif(trim(p_data->>'current_medications'),''),nullif(trim(p_data->>'doctor_notes'),''),
      nullif(trim(p_data->>'emergency_contact'),''),coalesce(nullif(p_data->>'balance','')::numeric,0)
    ) returning * into v_row;
  else
    update public.patients set
      file_number=coalesce(nullif(trim(p_data->>'file_number'),''),file_number),
      full_name=trim(p_data->>'full_name'),
      email=nullif(lower(trim(p_data->>'email')),''),
      phone=v_phone,
      national_id=nullif(trim(p_data->>'national_id'),''),
      age=nullif(p_data->>'age','')::integer,
      birth_date=nullif(p_data->>'birth_date','')::date,
      blood_type=nullif(trim(p_data->>'blood_type'),''),
      allergy=nullif(trim(p_data->>'allergy'),''),
      chronic_conditions=nullif(trim(p_data->>'chronic_conditions'),''),
      current_medications=nullif(trim(p_data->>'current_medications'),''),
      doctor_notes=nullif(trim(p_data->>'doctor_notes'),''),
      emergency_contact=nullif(trim(p_data->>'emergency_contact'),''),
      balance=coalesce(nullif(p_data->>'balance','')::numeric,0),
      updated_at=now()
    where id=p_id returning * into v_row;
  end if;

  if v_row.id is null then raise exception 'PATIENT_NOT_FOUND'; end if;
  return to_jsonb(v_row)||jsonb_build_object('_confirmed',true);
end
$$;

create or replace function public.oravena_persistence_health()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select case when auth.uid() is null
    then jsonb_build_object('ok',false,'version',30,'reason','AUTH_REQUIRED')
    else jsonb_build_object('ok',true,'version',30,'user_id',auth.uid(),'server_time',now())
  end
$$;

grant execute on function public.oravena_save_patient(uuid,jsonb) to authenticated;
grant execute on function public.oravena_save_service(uuid,jsonb) to authenticated;
grant execute on function public.oravena_save_session_with_tooth(uuid,uuid,jsonb,boolean) to authenticated;
grant execute on function public.oravena_persistence_health() to authenticated;

commit;
notify pgrst,'reload schema';
select 'ORAVENA V30 client fixes are ready' as result;
