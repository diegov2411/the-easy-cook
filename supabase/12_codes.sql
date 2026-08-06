-- ============================================================================
-- The Easy Cook — vendor admin: activation-code polish (Phase 2)
-- Run after 11_billing.sql. Safe to re-run.
--
-- Adds: optional expiry on codes, revoke-unused, and a link from a used code to
-- the restaurant it created (so the admin sees who redeemed what). Still all
-- gated by is_superadmin(); no client data involved.
-- ============================================================================

alter table public.signup_codes
  add column if not exists expires_at      timestamptz,
  add column if not exists used_restaurant uuid references public.restaurants(id) on delete set null;


-- ── create_my_restaurant: reject EXPIRED codes + record which restaurant used it
create or replace function public.create_my_restaurant(
  p_name text,
  p_ruc  text default null,
  p_code text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id   uuid;
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Los dispositivos anónimos no pueden crear un restaurante';
  end if;

  v_code := upper(btrim(coalesce(p_code, '')));

  update public.signup_codes
     set used_by = auth.uid(), used_at = now(), active = false
   where code = v_code and active and used_by is null
     and (expires_at is null or expires_at > now());
  if not found then
    raise exception 'Código de activación inválido, vencido o ya usado';
  end if;

  insert into public.restaurants (name, ruc)
  values (coalesce(nullif(btrim(p_name), ''), 'Mi restaurante'), nullif(btrim(p_ruc), ''))
  returning id into v_id;

  insert into public.memberships (restaurant_id, user_id, role)
  values (v_id, auth.uid(), 'owner');

  update public.signup_codes set used_restaurant = v_id where code = v_code;
  return v_id;
end;
$$;

revoke all     on function public.create_my_restaurant(text, text, text) from public, anon;
grant  execute on function public.create_my_restaurant(text, text, text) to   authenticated;


-- ── admin_gen_code: now takes an optional expiry (days) ─────────────────────
drop function if exists public.admin_gen_code(text);
create or replace function public.admin_gen_code(p_label text default null, p_expires_days integer default null)
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
  insert into public.signup_codes (code, label, expires_at)
  values (v_code, nullif(btrim(p_label), ''),
          case when p_expires_days is null then null else now() + (p_expires_days || ' days')::interval end);
  return v_code;
end;
$$;
revoke all     on function public.admin_gen_code(text, integer) from public, anon;
grant  execute on function public.admin_gen_code(text, integer) to   authenticated;


-- ── admin_revoke_code: cancel an UNUSED code ────────────────────────────────
create or replace function public.admin_revoke_code(p_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_superadmin() then raise exception 'No autorizado'; end if;
  update public.signup_codes set active = false
    where upper(code) = upper(btrim(p_code)) and used_by is null;
end;
$$;
revoke all     on function public.admin_revoke_code(text) from public, anon;
grant  execute on function public.admin_revoke_code(text) to   authenticated;


-- ── admin_list_codes: status + expiry + which restaurant redeemed it ────────
drop function if exists public.admin_list_codes();
create or replace function public.admin_list_codes()
returns table (
  code       text,
  label      text,
  status     text,       -- available | used | expired | revoked
  restaurant text,
  created_at timestamptz,
  expires_at timestamptz
)
language sql
security definer
stable
set search_path = public
as $$
  select c.code, c.label,
    case when c.used_by is not null then 'used'
         when not c.active           then 'revoked'
         when c.expires_at is not null and c.expires_at < now() then 'expired'
         else 'available' end,
    r.name, c.created_at, c.expires_at
  from public.signup_codes c
  left join public.restaurants r on r.id = c.used_restaurant
  where public.is_superadmin()
  order by c.created_at desc;
$$;
revoke all     on function public.admin_list_codes() from public, anon;
grant  execute on function public.admin_list_codes() to   authenticated;

-- ============================================================================
-- Done.
-- ============================================================================
