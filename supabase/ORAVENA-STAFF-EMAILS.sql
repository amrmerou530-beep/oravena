-- ORAVENA — staff email invitations and permissions
-- Run once after ORAVENA-SUPABASE-SETUP.sql

begin;

create table if not exists public.staff_invitations (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  full_name text not null,
  account_type text not null check (account_type in ('doctor','employee')),
  job_title text,
  phone text,
  sections text[] not null default '{}',
  permission_templates text[] not null default '{}',
  status text not null default 'pending'
    check (status in ('pending','activated','suspended')),
  invited_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  activated_at timestamptz,
  updated_at timestamptz not null default now()
);

create unique index if not exists staff_invitations_email_unique
  on public.staff_invitations(lower(email));

alter table public.staff_invitations enable row level security;

drop policy if exists "admin manages staff invitations" on public.staff_invitations;
create policy "admin manages staff invitations" on public.staff_invitations
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create or replace function public.upsert_staff_invitation(
  p_email text,
  p_full_name text,
  p_account_type text,
  p_job_title text,
  p_phone text,
  p_sections text[],
  p_permission_templates text[]
) returns uuid
language plpgsql security definer set search_path=public
as $$
declare
  v_invitation_id uuid;
  v_user_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  if p_account_type not in ('doctor','employee') then
    raise exception 'Invalid staff account type';
  end if;
  if position('@' in trim(p_email))<2 or length(trim(p_full_name))<2 then
    raise exception 'Invalid staff data';
  end if;

  insert into public.staff_invitations(
    email,full_name,account_type,job_title,phone,sections,
    permission_templates,status,invited_by
  ) values (
    lower(trim(p_email)),trim(p_full_name),p_account_type,
    nullif(trim(p_job_title),''),nullif(trim(p_phone),''),
    coalesce(p_sections,'{}'),coalesce(p_permission_templates,'{}'),
    'pending',auth.uid()
  )
  on conflict (lower(email)) do update set
    full_name=excluded.full_name,
    account_type=excluded.account_type,
    job_title=excluded.job_title,
    phone=excluded.phone,
    sections=excluded.sections,
    permission_templates=excluded.permission_templates,
    status=case when public.staff_invitations.status='activated'
      then 'activated' else 'pending' end,
    updated_at=now()
  returning id into v_invitation_id;

  select id into v_user_id from public.profiles
  where lower(email)=lower(trim(p_email)) limit 1;

  if v_user_id is not null then
    update public.profiles set
      full_name=trim(p_full_name),account_type=p_account_type,
      job_title=nullif(trim(p_job_title),''),phone=nullif(trim(p_phone),''),
      status='active',updated_at=now()
    where id=v_user_id;

    insert into public.staff_permissions(
      user_id,sections,permission_templates,updated_at
    ) values (
      v_user_id,coalesce(p_sections,'{}'),
      coalesce(p_permission_templates,'{}'),now()
    ) on conflict (user_id) do update set
      sections=excluded.sections,
      permission_templates=excluded.permission_templates,
      updated_at=now();

    update public.staff_invitations set
      status='activated',activated_at=coalesce(activated_at,now()),updated_at=now()
    where id=v_invitation_id;
  end if;

  return v_invitation_id;
end
$$;

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
    v_invitation.job_title,coalesce(v_invitation.phone,nullif(new.raw_user_meta_data->>'phone','')),'active'
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

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert or update of email on auth.users
for each row execute function public.handle_new_user();

grant select on public.staff_invitations to authenticated;
grant execute on function public.upsert_staff_invitation(
  text,text,text,text,text,text[],text[]
) to authenticated;

commit;

select 'Staff email permissions are ready' as result;
