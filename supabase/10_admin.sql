-- ============================================================================
-- The Easy Cook — vendor admin (manage clients WITHOUT seeing their data)
-- Run after 09_client_status.sql. Safe to re-run.
--
-- PRIVACY BY DESIGN: a superadmin account owns no restaurant, so normal RLS
-- (is_member) already denies it EVERY client's collections/events. The admin
-- functions below only ever return account METADATA (name, RUC, active flag,
-- counts) and never a client's recipes, sales, or financials. There is
-- deliberately NO function that reads a restaurant's collections.
--
-- Bootstrap (one time): create a bare admin login in the Supabase dashboard
-- (Authentication → Add user), then promote it:
--   insert into public.superadmins (user_id)
--   select id from auth.users where email = 'admin@example.com';
-- ============================================================================

create table if not exists public.superadmins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.superadmins enable row level security;
-- No policies → not readable/writable by app users; only the definer functions
-- below and the SQL editor (postgres/service_role) can touch it.

create or replace function public.is_superadmin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (select 1 from public.superadmins where user_id = auth.uid());
$$;
revoke all     on function public.is_superadmin() from public, anon;
grant  execute on function public.is_superadmin() to   authenticated;


-- ── Client roster — METADATA ONLY (no access to collections) ────────────────
create or replace function public.admin_list_restaurants()
returns table (
  id             uuid,
  name           text,
  ruc            text,
  active         boolean,
  created_at     timestamptz,
  devices        bigint,
  active_devices bigint
)
language sql
security definer
stable
set search_path = public
as $$
  select r.id, r.name, r.ruc, r.active, r.created_at,
    (select count(*) from public.memberships m where m.restaurant_id = r.id and m.role <> 'owner'),
    (select count(*) from public.memberships m where m.restaurant_id = r.id and m.role <> 'owner' and m.active)
  from public.restaurants r
  where public.is_superadmin()          -- non-admins get zero rows
  order by r.created_at desc;
$$;
revoke all     on function public.admin_list_restaurants() from public, anon;
grant  execute on function public.admin_list_restaurants() to   authenticated;


-- ── Activate / deactivate a client ──────────────────────────────────────────
create or replace function public.admin_set_active(p_id uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_superadmin() then raise exception 'No autorizado'; end if;
  update public.restaurants set active = coalesce(p_active, true) where id = p_id;
end;
$$;
revoke all     on function public.admin_set_active(uuid, boolean) from public, anon;
grant  execute on function public.admin_set_active(uuid, boolean) to   authenticated;


-- ── Generate a new single-use activation code ───────────────────────────────
create or replace function public.admin_gen_code(p_label text default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if not public.is_superadmin() then raise exception 'No autorizado'; end if;
  loop
    v_code := public.gen_join_code();
    exit when not exists (select 1 from public.signup_codes where code = v_code);
  end loop;
  insert into public.signup_codes (code, label) values (v_code, nullif(btrim(p_label), ''));
  return v_code;
end;
$$;
revoke all     on function public.admin_gen_code(text) from public, anon;
grant  execute on function public.admin_gen_code(text) to   authenticated;


-- ── List activation codes (used / unused) ───────────────────────────────────
create or replace function public.admin_list_codes()
returns table (code text, label text, used boolean, created_at timestamptz)
language sql
security definer
stable
set search_path = public
as $$
  select c.code, c.label, (c.used_by is not null), c.created_at
  from public.signup_codes c
  where public.is_superadmin()
  order by c.created_at desc;
$$;
revoke all     on function public.admin_list_codes() from public, anon;
grant  execute on function public.admin_list_codes() to   authenticated;

-- ============================================================================
-- Done. Create the admin login in the dashboard, then insert into superadmins.
-- ============================================================================
