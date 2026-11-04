-- ORAVENA V32 — no per-section permissions for clinic staff
-- Run once in the SAME Supabase project used by the website.
-- Existing patients, appointments, sessions, services, accounts and tooth data are preserved.
begin;

insert into public.app_config(key,value)
values('primary_admin_email','amerihgg@gmail.com')
on conflict(key) do update set value=excluded.value;

create or replace function public.is_primary_admin()
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select lower(coalesce(auth.jwt()->>'email',''))=lower(coalesce(public.primary_admin_email(),''))
$$;

create or replace function public.is_clinic_staff()
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists(
    select 1 from public.profiles p
    where p.id=auth.uid()
      and p.status='active'
      and p.account_type in ('admin','doctor','employee')
  )
$$;

-- Compatibility: old database functions and policies call is_admin().
-- In V32 it means an active clinic-team account, while destructive reset still
-- uses is_primary_admin() and remains restricted to the main administrator.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path=public
as $$ select public.is_clinic_staff() $$;

create or replace function public.allowed_section(section_name text)
returns boolean
language sql
stable
security definer
set search_path=public
as $$ select public.is_clinic_staff() $$;

-- Do not allow direct REST calls to promote/demote accounts. The existing
-- upsert_staff_invitation security-definer function remains the safe UI path
-- and only accepts doctor or employee account types.
drop policy if exists "admin manages profiles" on public.profiles;
drop policy if exists "primary admin manages profiles" on public.profiles;
create policy "primary admin manages profiles" on public.profiles
for all to authenticated
using(public.is_primary_admin())
with check(public.is_primary_admin());

drop policy if exists "admin manages permissions" on public.staff_permissions;
drop policy if exists "primary admin manages permissions" on public.staff_permissions;
create policy "primary admin manages permissions" on public.staff_permissions
for all to authenticated
using(public.is_primary_admin())
with check(public.is_primary_admin());

create or replace function public.oravena_persistence_health()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select case when auth.uid() is null
    then jsonb_build_object('ok',false,'version',32,'reason','AUTH_REQUIRED')
    else jsonb_build_object(
      'ok',true,'version',32,'user_id',auth.uid(),
      'is_clinic_staff',public.is_clinic_staff(),
      'is_primary_admin',public.is_primary_admin(),
      'server_time',now()
    )
  end
$$;

grant execute on function public.is_primary_admin() to authenticated;
grant execute on function public.is_clinic_staff() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.allowed_section(text) to authenticated;
grant execute on function public.oravena_persistence_health() to authenticated;

commit;
notify pgrst,'reload schema';
select 'ORAVENA V32 open staff workflow is ready' as result;
