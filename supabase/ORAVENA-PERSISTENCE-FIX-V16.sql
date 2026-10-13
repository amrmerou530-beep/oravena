-- ORAVENA V16 — durable data persistence
-- Run this entire file once in Supabase SQL Editor.
-- It keeps all existing accounts and data.

begin;

alter table public.appointments
  add column if not exists doctor_name text;

grant usage on schema public to authenticated;
grant select,insert,update,delete on public.patients to authenticated;
grant select,insert,update,delete on public.appointments to authenticated;
grant select,insert,update,delete on public.clinic_records to authenticated;
grant usage,select on sequence public.patient_file_seq to authenticated;

-- UI section names are plural while database record types are singular.
-- This mapper makes doctor/employee permissions work for every saved record.
create or replace function public.clinic_record_section(record_kind text)
returns text
language sql
immutable
set search_path=public
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

drop policy if exists "records read" on public.clinic_records;
create policy "records read" on public.clinic_records
for select to authenticated using (
  public.allowed_section(public.clinic_record_section(record_type)) or (
    patient_visible and patient_id in (
      select id from public.patients where auth_user_id=auth.uid()
    )
  )
);

drop policy if exists "staff manage records" on public.clinic_records;
create policy "staff manage records" on public.clinic_records
for all to authenticated using (
  public.is_admin() or
  public.allowed_section(public.clinic_record_section(record_type))
) with check (
  public.is_admin() or
  public.allowed_section(public.clinic_record_section(record_type))
);

drop policy if exists "patients mark notifications read" on public.clinic_records;

create or replace function public.mark_my_notifications_read()
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  changed_count integer;
begin
  update public.clinic_records r
  set payload=jsonb_set(r.payload,'{read}','true'::jsonb,true),updated_at=now()
  where r.record_type='notification'
    and r.patient_visible=true
    and r.patient_id in (
      select p.id from public.patients p where p.auth_user_id=auth.uid()
    )
    and coalesce((r.payload->>'read')::boolean,false)=false;
  get diagnostics changed_count=row_count;
  return changed_count;
end
$$;

grant execute on function public.mark_my_notifications_read() to authenticated;

-- Automatically connect a patient file to the matching login account.
create or replace function public.link_patient_auth_account()
returns trigger
language plpgsql
security definer
set search_path=public,auth
as $$
begin
  if new.auth_user_id is null and nullif(trim(new.email),'') is not null then
    select u.id into new.auth_user_id
    from auth.users u
    where lower(u.email)=lower(trim(new.email))
    limit 1;
  end if;
  new.updated_at=now();
  return new;
end
$$;

drop trigger if exists link_patient_auth_account_trigger on public.patients;
create trigger link_patient_auth_account_trigger
before insert or update of email on public.patients
for each row execute function public.link_patient_auth_account();

update public.patients p
set auth_user_id=u.id,updated_at=now()
from auth.users u
where p.auth_user_id is null
  and p.email is not null
  and lower(p.email)=lower(u.email);

commit;

notify pgrst, 'reload schema';

select 'ORAVENA persistence fix v16 is ready' as result;
