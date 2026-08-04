-- ============================================================================
-- The Easy Cook — activation codes that gate NEW ACCOUNT creation
-- Run after 03_devices.sql. Safe to re-run (idempotent).
--
-- Problem: anyone with the app link could tap "Crear cuenta" and make a
-- restaurant. We want only people WE approve (a paying client) to be able to.
--
-- Solution: single-use ACTIVATION CODES that only the vendor can mint. Signup
-- requires one; it is claimed atomically and burned so it can't be reused.
--
--   Two different codes — don't confuse them:
--     • ACTIVATION code (here): vendor -> new owner, gates ACCOUNT creation. 1-use.
--     • TEAM code (03_devices): owner -> staff device, gates device JOIN. Rotatable.
--
-- Mint a code (run in the SQL editor, which is postgres/service_role):
--     select public.gen_signup_code('Cliente: Andiamo Café');
-- ============================================================================

-- ── 1) The codes table — locked down: no app user can read or write it ──────
create table if not exists public.signup_codes (
  code       text primary key,
  label      text,                                   -- who this code is for
  active     boolean not null default true,
  used_by    uuid references auth.users(id) on delete set null,
  used_at    timestamptz,
  created_at timestamptz not null default now()
);

alter table public.signup_codes enable row level security;
-- Intentionally NO policies → anon/authenticated get zero access. Only the
-- SECURITY DEFINER functions below and the SQL editor (postgres / service_role,
-- which bypass RLS) can ever touch this table.


-- ── 2) gen_signup_code() — VENDOR-ONLY: mint a fresh single-use code ─────────
create or replace function public.gen_signup_code(p_label text default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  loop
    v_code := public.gen_join_code();               -- reuse the 6-char generator
    exit when not exists (select 1 from public.signup_codes where code = v_code);
  end loop;
  insert into public.signup_codes (code, label) values (v_code, nullif(btrim(p_label), ''));
  return v_code;
end;
$$;

-- Only the SQL editor / service_role may mint codes — NOT app users (not even
-- authenticated owners). This is the vendor's private control.
revoke all on function public.gen_signup_code(text) from public, anon, authenticated;


-- ── 3) create_my_restaurant() — now REQUIRES a valid unused activation code ──
-- Drop the old 2-arg version so there's no ungated path left behind.
drop function if exists public.create_my_restaurant(text, text);

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

  -- Claim the code atomically: only succeeds if it exists, is active, unused.
  update public.signup_codes
     set used_by = auth.uid(), used_at = now(), active = false
   where code = v_code and active and used_by is null;
  if not found then
    raise exception 'Código de activación inválido o ya usado';
  end if;

  insert into public.restaurants (name, ruc)
  values (coalesce(nullif(btrim(p_name), ''), 'Mi restaurante'), nullif(btrim(p_ruc), ''))
  returning id into v_id;

  insert into public.memberships (restaurant_id, user_id, role)
  values (v_id, auth.uid(), 'owner');

  return v_id;
end;
$$;

revoke all     on function public.create_my_restaurant(text, text, text) from public, anon;
grant  execute on function public.create_my_restaurant(text, text, text) to   authenticated;

-- ============================================================================
-- Done. Mint codes with:  select public.gen_signup_code('label');
-- ============================================================================
