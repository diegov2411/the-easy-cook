-- ============================================================================
-- The Easy Cook — vendor admin: ops & safety (Phase 4)
-- Run after 13_health.sql. Safe to re-run.
--
-- Adds: manage super-admins from the panel (add/remove/list) + an audit log of
-- admin actions. Existing admin mutations now record an audit entry. Still all
-- gated by is_superadmin(); no client data involved.
-- ============================================================================

create table if not exists public.admin_audit (
  id          bigint generated always as identity primary key,
  actor_user  uuid,
  actor_email text,
  action      text not null,
  detail      text,
  created_at  timestamptz not null default now()
);
alter table public.admin_audit enable row level security;
-- No policies: only the SECURITY DEFINER functions below touch it.
create index if not exists admin_audit_created on public.admin_audit(created_at desc);


-- ── audit helper (internal — called from other definer functions) ──────────
create or replace function public._admin_audit(p_action text, p_detail text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.admin_audit (actor_user, actor_email, action, detail)
  values (auth.uid(), (select email from auth.users where id = auth.uid()),
          p_action, nullif(btrim(p_detail), ''));
end;
$$;
revoke all on function public._admin_audit(text, text) from public, anon, authenticated;


-- ── read the audit log ──────────────────────────────────────────────────────
create or replace function public.admin_list_audit(p_limit integer default 100)
returns table (actor_email text, action text, detail text, created_at timestamptz)
language sql security definer stable set search_path = public as $$
  select a.actor_email, a.action, a.detail, a.created_at
  from public.admin_audit a
  where public.is_superadmin()
  order by a.created_at desc
  limit coalesce(p_limit, 100);
$$;
revoke all     on function public.admin_list_audit(integer) from public, anon;
grant  execute on function public.admin_list_audit(integer) to   authenticated;


-- ── manage super-admins ─────────────────────────────────────────────────────
create or replace function public.admin_list_admins()
returns table (user_id uuid, email text, created_at timestamptz)
language sql security definer stable set search_path = public as $$
  select s.user_id, u.email, s.created_at
  from public.superadmins s join auth.users u on u.id = s.user_id
  where public.is_superadmin()
  order by s.created_at;
$$;
revoke all     on function public.admin_list_admins() from public, anon;
grant  execute on function public.admin_list_admins() to   authenticated;

create or replace function public.admin_add_admin(p_email text)
returns void language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_superadmin() then raise exception 'No autorizado'; end if;
  select id into v_id from auth.users where lower(email) = lower(btrim(p_email));
  if v_id is null then
    raise exception 'No existe una cuenta con ese correo. Pídele que cree su cuenta primero.';
  end if;
  insert into public.superadmins (user_id) values (v_id) on conflict do nothing;
  perform public._admin_audit('Agregó admin', p_email);
end; $$;
revoke all     on function public.admin_add_admin(text) from public, anon;
grant  execute on function public.admin_add_admin(text) to   authenticated;

create or replace function public.admin_remove_admin(p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_superadmin() then raise exception 'No autorizado'; end if;
  if p_user = auth.uid() then raise exception 'No puedes quitarte a ti mismo'; end if;
  delete from public.superadmins where user_id = p_user;
  perform public._admin_audit('Quitó admin', p_user::text);
end; $$;
revoke all     on function public.admin_remove_admin(uuid) from public, anon;
grant  execute on function public.admin_remove_admin(uuid) to   authenticated;


-- ── existing mutations, now with audit entries ──────────────────────────────
create or replace function public.admin_set_active(p_id uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_name text;
begin
  if not public.is_superadmin() then raise exception 'No autorizado'; end if;
  update public.restaurants set active = coalesce(p_active, true) where id = p_id
    returning name into v_name;
  perform public._admin_audit(case when p_active then 'Activó restaurante' else 'Pausó restaurante' end, v_name);
end; $$;
revoke all     on function public.admin_set_active(uuid, boolean) from public, anon;
grant  execute on function public.admin_set_active(uuid, boolean) to   authenticated;

create or replace function public.admin_set_billing(
  p_id uuid, p_plan text, p_price numeric, p_status text, p_next_due date, p_notes text
) returns void language plpgsql security definer set search_path = public as $$
declare v_name text;
begin
  if not public.is_superadmin() then raise exception 'No autorizado'; end if;
  update public.restaurants set
    plan = nullif(btrim(p_plan), ''), price = p_price,
    billing_status = coalesce(nullif(btrim(p_status), ''), 'trial'),
    next_due_date = p_next_due, billing_notes = nullif(btrim(p_notes), '')
  where id = p_id returning name into v_name;
  perform public._admin_audit('Editó facturación', v_name);
end; $$;
revoke all     on function public.admin_set_billing(uuid, text, numeric, text, date, text) from public, anon;
grant  execute on function public.admin_set_billing(uuid, text, numeric, text, date, text) to   authenticated;

create or replace function public.admin_mark_paid(p_id uuid, p_period_days integer default 30)
returns date language plpgsql security definer set search_path = public as $$
declare v_base date; v_new date; v_name text;
begin
  if not public.is_superadmin() then raise exception 'No autorizado'; end if;
  select case when next_due_date is null or next_due_date < current_date
              then current_date else next_due_date end, name
    into v_base, v_name
  from public.restaurants where id = p_id;
  v_new := v_base + coalesce(p_period_days, 30);
  update public.restaurants set next_due_date = v_new, billing_status = 'active' where id = p_id;
  perform public._admin_audit('Marcó pagado', v_name || ' → ' || v_new::text);
  return v_new;
end; $$;
revoke all     on function public.admin_mark_paid(uuid, integer) from public, anon;
grant  execute on function public.admin_mark_paid(uuid, integer) to   authenticated;

create or replace function public.admin_gen_code(p_label text default null, p_expires_days integer default null)
returns text language plpgsql security definer set search_path = public as $$
declare v_code text;
begin
  if not public.is_superadmin() then raise exception 'No autorizado'; end if;
  loop
    v_code := public.gen_join_code();
    exit when not exists (select 1 from public.signup_codes where code = v_code);
  end loop;
  insert into public.signup_codes (code, label, expires_at)
  values (v_code, nullif(btrim(p_label), ''),
          case when p_expires_days is null then null else now() + (p_expires_days || ' days')::interval end);
  perform public._admin_audit('Generó código', coalesce(nullif(btrim(p_label), ''), v_code));
  return v_code;
end; $$;
revoke all     on function public.admin_gen_code(text, integer) from public, anon;
grant  execute on function public.admin_gen_code(text, integer) to   authenticated;

create or replace function public.admin_revoke_code(p_code text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_superadmin() then raise exception 'No autorizado'; end if;
  update public.signup_codes set active = false
    where upper(code) = upper(btrim(p_code)) and used_by is null;
  perform public._admin_audit('Anuló código', upper(btrim(p_code)));
end; $$;
revoke all     on function public.admin_revoke_code(text) from public, anon;
grant  execute on function public.admin_revoke_code(text) to   authenticated;

-- ============================================================================
-- Done.
-- ============================================================================
