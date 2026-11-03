-- ORAVENA V28 — hierarchical services, doctor agenda, session/tooth sync
-- Run once in Supabase SQL Editor after V22. Existing data is preserved.
begin;
alter table public.clinic_services
  add column if not exists price numeric(12,2) not null default 0,
  add column if not exists service_type text not null default 'main',
  add column if not exists parent_service_id uuid references public.clinic_services(id) on delete restrict;
alter table public.clinic_services drop constraint if exists clinic_services_service_type_check;
alter table public.clinic_services add constraint clinic_services_service_type_check check(service_type in ('main','sub'));
alter table public.clinic_services drop constraint if exists clinic_services_parent_shape_check;
alter table public.clinic_services add constraint clinic_services_parent_shape_check check((service_type='main' and parent_service_id is null) or(service_type='sub' and parent_service_id is not null));
create index if not exists clinic_services_parent_idx on public.clinic_services(parent_service_id);
do $$
begin
 update public.clinic_services s set price=coalesce((
   select nullif(r.payload->'servicePrices'->>s.id::text,'')::numeric
   from public.clinic_records r where r.record_type='setting'
   order by r.updated_at desc limit 1
 ),s.price) where s.price=0;
exception when others then
 raise notice 'Legacy service prices were kept in settings; resave them from Services if needed.';
end $$;

create or replace function public.allowed_section(section_name text) returns boolean language sql stable security definer set search_path=public as $$
 select public.is_admin() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.status='active' and p.account_type='doctor' and section_name=any(array['dashboard','services','appointments','patients','sessions','odontogram','plans','reports']::text[])) or exists(select 1 from public.staff_permissions sp join public.profiles p on p.id=sp.user_id where sp.user_id=auth.uid() and p.status='active' and section_name=any(sp.sections))
$$;

create or replace function public.oravena_save_service(p_id uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_row public.clinic_services%rowtype;v_type text:=coalesce(nullif(p_data->>'service_type',''),'main');v_parent uuid:=nullif(p_data->>'parent_service_id','')::uuid;
begin
 if not public.allowed_section('services') then raise exception 'PERMISSION_DENIED'; end if;
 if length(trim(coalesce(p_data->>'name_ar','')))<2 or length(trim(coalesce(p_data->>'name_en','')))<2 then raise exception 'SERVICE_NAMES_REQUIRED'; end if;
 if v_type not in ('main','sub') then raise exception 'INVALID_SERVICE_TYPE'; end if;
 if v_type='main' then v_parent:=null; end if;
 if v_type='sub' and not exists(select 1 from public.clinic_services where id=v_parent and service_type='main') then raise exception 'PARENT_SERVICE_REQUIRED'; end if;
 if p_id is null then
  insert into public.clinic_services(name_ar,name_tr,name_en,price,service_type,parent_service_id,active,sort_order) values(trim(p_data->>'name_ar'),nullif(trim(p_data->>'name_tr'),''),trim(p_data->>'name_en'),greatest(coalesce(nullif(p_data->>'price','')::numeric,0),0),v_type,v_parent,coalesce((p_data->>'active')::boolean,true),coalesce((p_data->>'sort_order')::integer,0)) returning * into v_row;
 else
  if v_parent=p_id then raise exception 'SERVICE_CANNOT_PARENT_ITSELF'; end if;
  update public.clinic_services set name_ar=trim(p_data->>'name_ar'),name_tr=nullif(trim(p_data->>'name_tr'),''),name_en=trim(p_data->>'name_en'),price=greatest(coalesce(nullif(p_data->>'price','')::numeric,0),0),service_type=v_type,parent_service_id=v_parent,active=coalesce((p_data->>'active')::boolean,true),sort_order=coalesce((p_data->>'sort_order')::integer,0),updated_at=now() where id=p_id returning * into v_row;
 end if;
 if v_row.id is null then raise exception 'SERVICE_NOT_FOUND'; end if;return to_jsonb(v_row)||jsonb_build_object('_confirmed',true);
end $$;

create table if not exists public.doctor_schedule(id uuid primary key default gen_random_uuid(),doctor_user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),patient_id uuid references public.patients(id) on delete set null,patient_name text not null,service_id uuid references public.clinic_services(id) on delete set null,service_name text,schedule_date date not null,schedule_time time not null,important boolean not null default false,status text not null default 'scheduled' check(status in ('scheduled','completed','cancelled')),notes text,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create index if not exists doctor_schedule_day_idx on public.doctor_schedule(doctor_user_id,schedule_date,schedule_time);
alter table public.doctor_schedule enable row level security;grant select on public.doctor_schedule to authenticated;revoke insert,update,delete on public.doctor_schedule from anon,authenticated;
drop policy if exists "oravena doctor schedule select" on public.doctor_schedule;
create policy "oravena doctor schedule select" on public.doctor_schedule for select to authenticated using(public.is_admin() or doctor_user_id=auth.uid());

create or replace function public.oravena_save_schedule(p_id uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role text;v_row public.doctor_schedule%rowtype;v_patient uuid:=nullif(p_data->>'patient_id','')::uuid;
begin
 select account_type into v_role from public.profiles where id=auth.uid() and status='active';if v_role not in('admin','doctor') then raise exception 'PERMISSION_DENIED'; end if;
 if nullif(p_data->>'schedule_date','') is null or nullif(p_data->>'schedule_time','') is null then raise exception 'SCHEDULE_DATE_TIME_REQUIRED'; end if;
 if p_id is null then insert into public.doctor_schedule(doctor_user_id,patient_id,patient_name,service_id,service_name,schedule_date,schedule_time,important,status,notes) values(auth.uid(),v_patient,trim(p_data->>'patient_name'),nullif(p_data->>'service_id','')::uuid,nullif(trim(p_data->>'service_name'),''),(p_data->>'schedule_date')::date,(p_data->>'schedule_time')::time,coalesce((p_data->>'important')::boolean,false),coalesce(nullif(p_data->>'status',''),'scheduled'),nullif(trim(p_data->>'notes'),'')) returning * into v_row;
 else update public.doctor_schedule set patient_id=v_patient,patient_name=trim(p_data->>'patient_name'),service_id=nullif(p_data->>'service_id','')::uuid,service_name=nullif(trim(p_data->>'service_name'),''),schedule_date=(p_data->>'schedule_date')::date,schedule_time=(p_data->>'schedule_time')::time,important=coalesce((p_data->>'important')::boolean,false),status=coalesce(nullif(p_data->>'status',''),'scheduled'),notes=nullif(trim(p_data->>'notes'),''),updated_at=now() where id=p_id and(public.is_admin() or doctor_user_id=auth.uid()) returning * into v_row;end if;
 if v_row.id is null then raise exception 'SCHEDULE_NOT_FOUND'; end if;return to_jsonb(v_row)||jsonb_build_object('_confirmed',true);
end $$;
create or replace function public.oravena_delete_schedule(p_id uuid) returns boolean language plpgsql security definer set search_path=public as $$ declare v_count integer;begin delete from public.doctor_schedule where id=p_id and(public.is_admin() or doctor_user_id=auth.uid());get diagnostics v_count=row_count;return v_count=1;end $$;

create or replace function public.oravena_save_session_with_tooth(p_id uuid,p_patient_id uuid,p_payload jsonb,p_patient_visible boolean) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_session public.clinic_records%rowtype;v_tooth_record public.clinic_records%rowtype;v_number text:=nullif(p_payload->>'toothNumber','');v_teeth jsonb;v_old jsonb;v_history jsonb;v_new jsonb;
begin
 if not public.allowed_section('sessions') or not public.allowed_section('odontogram') then raise exception 'PERMISSION_DENIED'; end if;if not exists(select 1 from public.patients where id=p_patient_id) then raise exception 'PATIENT_NOT_FOUND'; end if;
 if p_id is null then insert into public.clinic_records(record_type,patient_id,owner_user_id,payload,patient_visible) values('session',p_patient_id,auth.uid(),coalesce(p_payload,'{}'::jsonb),coalesce(p_patient_visible,true)) returning * into v_session;else update public.clinic_records set patient_id=p_patient_id,payload=coalesce(p_payload,'{}'::jsonb),patient_visible=coalesce(p_patient_visible,true),updated_at=now() where id=p_id and record_type='session' returning * into v_session;end if;
 if v_session.id is null then raise exception 'SESSION_NOT_FOUND'; end if;
 if v_number is not null then
  select * into v_tooth_record from public.clinic_records where record_type='tooth' and patient_id=p_patient_id for update;v_teeth:=coalesce(v_tooth_record.payload->'teeth',v_tooth_record.payload,'{}'::jsonb);v_old:=coalesce(v_teeth->v_number,'{}'::jsonb);v_history:=coalesce(v_old->'history','[]'::jsonb);
  if coalesce(v_old->>'status','')<>'' then v_history:=v_history||jsonb_build_array(jsonb_build_object('date',now(),'status',v_old->>'status','stage',v_old->>'stage','needs',v_old->>'needs','note',v_old->>'note','sessionId',v_session.id));end if;
  v_new:=jsonb_build_object('status',coalesce(nullif(p_payload->>'toothStatus',''),'unknown'),'stage',coalesce(p_payload->>'toothStage',''),'needs',coalesce(p_payload->>'toothNeeds',''),'note',coalesce(p_payload->>'toothNote',p_payload->>'visible',''),'history',v_history,'lastSessionId',v_session.id,'updatedAt',now());v_teeth:=jsonb_set(v_teeth,array[v_number],v_new,true);
  insert into public.clinic_records(record_type,patient_id,owner_user_id,payload,patient_visible) values('tooth',p_patient_id,auth.uid(),jsonb_build_object('patientId',p_patient_id,'teeth',v_teeth),true) on conflict(patient_id) where record_type='tooth' and patient_id is not null do update set payload=excluded.payload,patient_visible=true,updated_at=now();
 end if;return to_jsonb(v_session)||jsonb_build_object('_confirmed',true);
end $$;
create or replace function public.create_appointment_request(p_full_name text,p_email text,p_phone text,p_national_id text,p_age integer,p_service text) returns uuid language plpgsql security definer set search_path=public as $$
declare v_patient_id uuid;v_appointment_id uuid;v_patient_user_id uuid;v_service text:=trim(coalesce(p_service,''));
begin
 if length(trim(coalesce(p_full_name,'')))<2 or position('@' in trim(coalesce(p_email,'')))<2 or length(trim(coalesce(p_phone,'')))<6 or p_age not between 0 and 120 then raise exception 'INVALID_APPOINTMENT_DATA';end if;
 if v_service<>'غير محدد' and not exists(select 1 from public.clinic_services s where s.active and s.name_ar=v_service) then raise exception 'SERVICE_NOT_AVAILABLE';end if;
 select id into v_patient_user_id from public.profiles where id=auth.uid() and account_type='patient' and status='active';
 if v_patient_user_id is not null then select id into v_patient_id from public.patients where auth_user_id=v_patient_user_id limit 1;end if;
 if v_patient_id is null then select id into v_patient_id from public.patients where lower(trim(coalesce(email,'')))=lower(trim(p_email)) and phone=trim(p_phone) order by updated_at desc,created_at desc limit 1;end if;
 if v_patient_id is null then select id into v_patient_id from public.patients where phone=trim(p_phone) order by updated_at desc,created_at desc limit 1;end if;
 if v_patient_id is null then insert into public.patients(auth_user_id,full_name,email,phone,national_id,age) values(v_patient_user_id,trim(p_full_name),lower(trim(p_email)),trim(p_phone),nullif(trim(p_national_id),''),p_age) returning id into v_patient_id;
 elsif v_patient_user_id is not null or exists(select 1 from public.patients where id=v_patient_id and auth_user_id is null) then update public.patients set auth_user_id=coalesce(auth_user_id,v_patient_user_id),full_name=trim(p_full_name),email=lower(trim(p_email)),phone=trim(p_phone),national_id=coalesce(nullif(trim(p_national_id),''),national_id),age=p_age,updated_at=now() where id=v_patient_id;end if;
 insert into public.appointments(patient_id,full_name,email,phone,national_id,age,service,status) values(v_patient_id,trim(p_full_name),lower(trim(p_email)),trim(p_phone),nullif(trim(p_national_id),''),p_age,v_service,'new_request') returning id into v_appointment_id;
 insert into public.clinic_records(record_type,patient_id,payload,patient_visible) values('notification',v_patient_id,jsonb_build_object('title','كشف جديد','text',trim(p_full_name)||' — '||v_service,'email',lower(trim(p_email)),'appointment_id',v_appointment_id,'read',false),false);
 return v_appointment_id;
end $$;
create or replace function public.reset_oravena_operational_data(p_confirmation text) returns jsonb language plpgsql security definer set search_path=public as $$
declare patient_count integer;appointment_count integer;record_count integer;schedule_count integer;
begin
 if not public.is_primary_admin() then raise exception 'PRIMARY_ADMIN_ONLY';end if;if coalesce(trim(p_confirmation),'')<>'تصفير' then raise exception 'INVALID_CONFIRMATION';end if;
 select count(*) into patient_count from public.patients;select count(*) into appointment_count from public.appointments;select count(*) into record_count from public.clinic_records where record_type<>'setting';select count(*) into schedule_count from public.doctor_schedule;
 delete from public.doctor_schedule where id is not null;delete from public.clinic_records where record_type<>'setting';delete from public.appointments where id is not null;delete from public.patients where id is not null;
 return jsonb_build_object('ok',true,'patients_deleted',patient_count,'appointments_deleted',appointment_count,'records_deleted',record_count,'schedule_deleted',schedule_count);
end $$;
create or replace function public.oravena_persistence_health() returns jsonb language sql stable security definer set search_path=public as $$ select case when auth.uid() is null then jsonb_build_object('ok',false,'version',28,'reason','AUTH_REQUIRED') else jsonb_build_object('ok',true,'version',28,'user_id',auth.uid(),'server_time',now()) end $$;
grant execute on function public.create_appointment_request(text,text,text,text,integer,text) to anon,authenticated;grant execute on function public.oravena_save_service(uuid,jsonb) to authenticated;grant execute on function public.oravena_save_schedule(uuid,jsonb) to authenticated;grant execute on function public.oravena_delete_schedule(uuid) to authenticated;grant execute on function public.oravena_save_session_with_tooth(uuid,uuid,jsonb,boolean) to authenticated;grant execute on function public.oravena_persistence_health() to authenticated;
commit;notify pgrst,'reload schema';select 'ORAVENA V28 clinical workflow is ready' as result;
