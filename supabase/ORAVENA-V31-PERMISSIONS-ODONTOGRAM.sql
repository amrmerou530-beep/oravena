-- ORAVENA V31 — reliable admin recognition and clinical access repair
-- Run once in the SAME Supabase project used by the website.
-- Existing patients, appointments, sessions, services and tooth data are preserved.
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

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select public.is_primary_admin()
    or exists(
      select 1 from public.profiles p
      where p.id=auth.uid()
        and p.status='active'
        and p.account_type='admin'
    )
$$;

update public.profiles
set account_type='admin',status='active',updated_at=now()
where lower(email)=lower(public.primary_admin_email());

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

create or replace function public.oravena_persistence_health()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select case when auth.uid() is null
    then jsonb_build_object('ok',false,'version',31,'reason','AUTH_REQUIRED')
    else jsonb_build_object(
      'ok',true,'version',31,'user_id',auth.uid(),
      'is_admin',public.is_admin(),'server_time',now()
    )
  end
$$;

grant execute on function public.is_primary_admin() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.allowed_section(text) to authenticated;
grant execute on function public.oravena_persistence_health() to authenticated;

commit;
notify pgrst,'reload schema';
select 'ORAVENA V31 permissions and odontogram repair is ready' as result;
