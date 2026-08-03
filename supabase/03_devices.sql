-- ============================================================================
-- The Easy Cook — team-code device access + owner device controls
-- Run after schema.sql and 02_onboarding.sql. Safe to re-run (idempotent).
--
-- Goal: let employees use the app on their own phones WITHOUT the owner's
-- email ever landing on their device, and without employees creating emails.
--   • Owner  → email/password login, owns the restaurant.
--   • Device → signs in ANONYMOUSLY (no email/password, invisible to the user)
--              and joins the restaurant with a short TEAM CODE the owner shares.
--   • Inside the app, the existing PIN + role system still decides who's on the
--     till and what the UI allows.
-- Owner controls (for a lost/stolen phone or a problem employee): block one
-- device, cut ALL devices at once, and rotate the code so it can't be reused.
--
-- NOTE: also enable "Anonymous sign-ins" in Supabase → Authentication →
-- Sign In / Providers. An anonymous user with no membership can read/write
-- NOTHING (RLS denies every table), so the blast radius is contained.
-- ============================================================================


-- ── 0) Team-code generator ──────────────────────────────────────────────────
-- 6 chars from an unambiguous alphabet (no 0/O/1/I/L). ~10^9 combinations.
create or replace function public.gen_join_code()
returns text
language sql
volatile
set search_path = public
as $$
  with alpha as (select 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'::text a)
  select string_agg(substr(a, (floor(random()*length(a))::int)+1, 1), '')
  from alpha, generate_series(1, 6);
$$;


-- ── 1) Schema additions ─────────────────────────────────────────────────────

-- A short, shareable code per restaurant. Rotating it invalidates the old one.
alter table public.restaurants
  add column if not exists join_code text;

-- Give every existing restaurant a code, then default new ones automatically.
update public.restaurants set join_code = public.gen_join_code() where join_code is null;
alter table public.restaurants alter column join_code set default public.gen_join_code();

create unique index if not exists restaurants_join_code_key
  on public.restaurants(join_code) where join_code is not null;

-- Per-device bookkeeping on the membership row (owner rows keep active=true).
alter table public.memberships
  add column if not exists device_label text,
  add column if not exists active       boolean not null default true,
  add column if not exists last_seen_at  timestamptz;

-- Staff devices must not be able to read the code straight off the table and
-- re-share it. The owner reads it only through my_team_code() (definer, below).
-- The app never selects restaurants.join_code directly; the RPCs run as definer
-- so this revoke doesn't affect them.
revoke select (join_code) on public.restaurants from authenticated, anon;


-- ── 2) is_member now requires an ACTIVE membership ──────────────────────────
-- Flipping a device's membership to active=false instantly cuts ALL of its
-- table access (collections included) through every existing RLS policy.
create or replace function public.is_member(rid uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.memberships m
    where m.restaurant_id = rid
      and m.user_id = auth.uid()
      and m.active
  );
$$;


-- ── 3) Owner helpers ────────────────────────────────────────────────────────
-- The single restaurant the caller owns (null if they aren't an active owner).
create or replace function public.my_owner_restaurant()
returns uuid
language sql
security definer
stable
set search_path = public
as $$
  select m.restaurant_id
  from public.memberships m
  where m.user_id = auth.uid() and m.role = 'owner' and m.active
  limit 1;
$$;


-- ── 4) create_my_restaurant — now rejects anonymous callers ─────────────────
-- Owners must be real email accounts. Anonymous device sessions may only JOIN.
create or replace function public.create_my_restaurant(
  p_name text,
  p_ruc  text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Los dispositivos anónimos no pueden crear un restaurante';
  end if;

  insert into public.restaurants (name, ruc)
  values (coalesce(nullif(btrim(p_name), ''), 'Mi restaurante'), nullif(btrim(p_ruc), ''))
  returning id into v_id;

  insert into public.memberships (restaurant_id, user_id, role)
  values (v_id, auth.uid(), 'owner');

  return v_id;
end;
$$;

revoke all     on function public.create_my_restaurant(text, text) from public, anon;
grant  execute on function public.create_my_restaurant(text, text) to   authenticated;


-- ── 5) join_restaurant_with_code — a device joins with the team code ────────
-- Any authenticated caller (incl. anonymous device sessions). Re-joining a
-- previously blocked device reactivates it (owner can block again + rotate).
create or replace function public.join_restaurant_with_code(
  p_code  text,
  p_label text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select id into v_id
  from public.restaurants
  where join_code is not null
    and active
    and upper(btrim(p_code)) = upper(join_code)
  limit 1;

  if v_id is null then
    raise exception 'Código inválido';
  end if;

  insert into public.memberships (restaurant_id, user_id, role, device_label, active, last_seen_at)
  values (v_id, auth.uid(), 'staff', nullif(btrim(p_label), ''), true, now())
  on conflict (restaurant_id, user_id) do update
    set active       = true,
        device_label = coalesce(excluded.device_label, public.memberships.device_label),
        last_seen_at = now();

  return v_id;
end;
$$;

revoke all     on function public.join_restaurant_with_code(text, text) from public, anon;
grant  execute on function public.join_restaurant_with_code(text, text) to   authenticated;


-- ── 6) my_team_code — owner reads the current code (for display) ────────────
create or replace function public.my_team_code()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select r.join_code
  from public.restaurants r
  where r.id = public.my_owner_restaurant();
$$;

revoke all     on function public.my_team_code() from public, anon;
grant  execute on function public.my_team_code() to   authenticated;


-- ── 7) rotate_join_code — owner mints a new code, old one dies ──────────────
create or replace function public.rotate_join_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rid  uuid;
  v_code text;
begin
  v_rid := public.my_owner_restaurant();
  if v_rid is null then
    raise exception 'Solo el dueño puede cambiar el código';
  end if;

  loop
    v_code := public.gen_join_code();
    exit when not exists (select 1 from public.restaurants where join_code = v_code);
  end loop;

  update public.restaurants set join_code = v_code where id = v_rid;
  return v_code;
end;
$$;

revoke all     on function public.rotate_join_code() from public, anon;
grant  execute on function public.rotate_join_code() to   authenticated;


-- ── 8) revoke_membership — owner blocks ONE device ──────────────────────────
create or replace function public.revoke_membership(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rid uuid;
begin
  v_rid := public.my_owner_restaurant();
  if v_rid is null then
    raise exception 'Solo el dueño puede bloquear dispositivos';
  end if;

  update public.memberships
    set active = false
    where restaurant_id = v_rid
      and user_id = p_user
      and role <> 'owner';
end;
$$;

revoke all     on function public.revoke_membership(uuid) from public, anon;
grant  execute on function public.revoke_membership(uuid) to   authenticated;


-- ── 9) revoke_all_devices — owner cuts EVERY device (theft / reset) ─────────
create or replace function public.revoke_all_devices()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rid uuid;
  v_n   integer;
begin
  v_rid := public.my_owner_restaurant();
  if v_rid is null then
    raise exception 'Solo el dueño puede desconectar los dispositivos';
  end if;

  update public.memberships set active = false
    where restaurant_id = v_rid and role <> 'owner' and active;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all     on function public.revoke_all_devices() from public, anon;
grant  execute on function public.revoke_all_devices() to   authenticated;


-- ── 10) list_devices — owner sees joined devices ────────────────────────────
create or replace function public.list_devices()
returns table (
  user_id      uuid,
  device_label text,
  active       boolean,
  last_seen_at timestamptz,
  created_at   timestamptz
)
language sql
security definer
stable
set search_path = public
as $$
  select m.user_id, m.device_label, m.active, m.last_seen_at, m.created_at
  from public.memberships m
  where m.restaurant_id = public.my_owner_restaurant()
    and m.role <> 'owner'
  order by m.created_at desc;
$$;

revoke all     on function public.list_devices() from public, anon;
grant  execute on function public.list_devices() to   authenticated;


-- ── 11) touch_membership — caller stamps its own last_seen (called on load) ─
create or replace function public.touch_membership()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.memberships set last_seen_at = now()
    where user_id = auth.uid();
end;
$$;

revoke all     on function public.touch_membership() from public, anon;
grant  execute on function public.touch_membership() to   authenticated;

-- ============================================================================
-- Done. Enable Anonymous sign-ins in the Auth settings, then wire the app.
-- ============================================================================
