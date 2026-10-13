-- ORAVENA v11 — persistent clinical records + automatic treatment invoices
-- Run once in Supabase SQL Editor after ORAVENA-SUPABASE-SETUP.sql.

begin;

-- Match database record types to the dashboard permission names.
drop policy if exists "records read" on public.clinic_records;
create policy "records read" on public.clinic_records
for select to authenticated using (
  public.is_admin() or public.allowed_section(
    case record_type
      when 'session' then 'sessions'
      when 'treatment_plan' then 'plans'
      when 'prescription' then 'prescriptions'
      when 'lab' then 'labs'
      when 'message' then 'messages'
      when 'notification' then 'messages'
      else record_type
    end
  ) or (
    patient_visible and patient_id in (
      select id from public.patients where auth_user_id=auth.uid()
    )
  )
);

drop policy if exists "staff manage records" on public.clinic_records;
create policy "staff manage records" on public.clinic_records
for all to authenticated using (
  public.is_admin() or public.allowed_section(
    case record_type
      when 'session' then 'sessions'
      when 'treatment_plan' then 'plans'
      when 'prescription' then 'prescriptions'
      when 'lab' then 'labs'
      when 'message' then 'messages'
      when 'notification' then 'messages'
      else record_type
    end
  )
) with check (
  public.is_admin() or public.allowed_section(
    case record_type
      when 'session' then 'sessions'
      when 'treatment_plan' then 'plans'
      when 'prescription' then 'prescriptions'
      when 'lab' then 'labs'
      when 'message' then 'messages'
      when 'notification' then 'messages'
      else record_type
    end
  )
);

create or replace function public.oravena_sync_plan_finance()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  plan_row public.clinic_records;
  plan_key text;
  plan_status text;
  plan_cost numeric := 0;
  plan_paid numeric := 0;
  patient_name text := '';
begin
  if tg_op='DELETE' then plan_row := old; else plan_row := new; end if;
  if plan_row.record_type <> 'treatment_plan' then
    return case when tg_op='DELETE' then old else new end;
  end if;

  plan_key := plan_row.id::text;

  -- Rebuild only the automatically generated movements for this plan.
  delete from public.clinic_records
  where record_type='finance'
    and payload->>'sourcePlanId'=plan_key
    and payload->>'automatic'='true';

  if tg_op='DELETE' then return old; end if;

  plan_status := coalesce(new.payload->>'status','');
  if plan_status <> 'مكتملة' then return new; end if;

  if coalesce(new.payload->>'cost','') ~ '^[0-9]+([.][0-9]+)?$' then
    plan_cost := (new.payload->>'cost')::numeric;
  end if;
  if coalesce(new.payload->>'paid','') ~ '^[0-9]+([.][0-9]+)?$' then
    plan_paid := (new.payload->>'paid')::numeric;
  end if;
  select coalesce(full_name,'') into patient_name from public.patients where id=new.patient_id;

  if plan_cost > 0 then
    insert into public.clinic_records(record_type,patient_id,owner_user_id,patient_visible,payload)
    values('finance',new.patient_id,auth.uid(),true,jsonb_build_object(
      'person',patient_name,
      'treatment',coalesce(new.payload->>'title','علاج أسنان'),
      'type','فاتورة علاج',
      'amount',plan_cost::text,
      'date',current_date::text,
      'method','غير مطبق',
      'status','معتمدة',
      'sourcePlanId',plan_key,
      'automatic',true
    ));
  end if;

  if plan_paid > 0 and plan_cost > 0 then
    insert into public.clinic_records(record_type,patient_id,owner_user_id,patient_visible,payload)
    values('finance',new.patient_id,auth.uid(),true,jsonb_build_object(
      'person',patient_name,
      'treatment',coalesce(new.payload->>'title','دفعة علاج'),
      'type','دفعة',
      'amount',least(plan_paid,plan_cost)::text,
      'date',current_date::text,
      'method','غير مطبق',
      'status','معتمدة',
      'sourcePlanId',plan_key,
      'automatic',true
    ));
  end if;
  return new;
end;
$$;

drop trigger if exists oravena_plan_finance_trigger on public.clinic_records;
create trigger oravena_plan_finance_trigger
after insert or update or delete on public.clinic_records
for each row execute function public.oravena_sync_plan_finance();

commit;

select 'ORAVENA finance linkage v11 is ready' as result;
