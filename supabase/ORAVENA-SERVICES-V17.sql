-- ORAVENA V17 — managed clinic services and controlled booking choices
-- Run this entire file once in Supabase SQL Editor after V16.

begin;

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

create or replace function public.validate_appointment_service()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if tg_op='UPDATE' and new.service is not distinct from old.service then
    return new;
  end if;

  if trim(coalesce(new.service,''))='غير محدد' then
    return new;
  end if;

  if not exists (
    select 1 from public.clinic_services s
    where s.active=true and s.name_ar=trim(new.service)
  ) then
    raise exception 'SERVICE_NOT_AVAILABLE';
  end if;

  new.service=trim(new.service);
  return new;
end
$$;

drop trigger if exists validate_appointment_service_trigger on public.appointments;
create trigger validate_appointment_service_trigger
before insert or update of service on public.appointments
for each row execute function public.validate_appointment_service();

commit;

notify pgrst, 'reload schema';

select 'ORAVENA services v17 is ready' as result;
