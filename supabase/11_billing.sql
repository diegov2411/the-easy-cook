-- ============================================================================
-- The Easy Cook — vendor admin: billing & client lifecycle (Phase 1)
-- Run after 10_admin.sql. Safe to re-run.
--
-- Adds per-client billing METADATA (plan, price, status, next due date, notes)
-- and admin-only functions to edit it + "mark as paid". Still no access to any
-- client's operational data. All gated by is_superadmin().
-- ============================================================================

alter table public.restaurants
  add column if not exists plan           text,
  add column if not exists price          numeric,
  add column if not exists billing_status text default 'trial',   -- trial|active|overdue|canceled
  add column if not exists next_due_date  date,
  add column if not exists billing_notes  text;


-- ── Roster now includes billing (return type changed → drop first) ──────────
drop function if exists public.admin_list_restaurants();
create or replace function public.admin_list_restaurants()
returns table (
  id             uuid,
  name           text,
  ruc            text,
  active         boolean,
  created_at     timestamptz,
  devices        bigint,
  active_devices bigint,
  plan           text,
  price          numeric,
  billing_status text,
  next_due_date  date,
  billing_notes  text,
  days_until_due integer
)
language sql
security definer
stable
set search_path = public
as $$
  select r.id, r.name, r.ruc, r.active, r.created_at,
    (select count(*) from public.memberships m where m.restaurant_id = r.id and m.role <> 'owner'),
    (select count(*) from public.memberships m where m.restaurant_id = r.id and m.role <> 'owner' and m.active),
    r.plan, r.price, coalesce(r.billing_status, 'trial'), r.next_due_date, r.billing_notes,
    case when r.next_due_date is null then null else (r.next_due_date - current_date) end
  from public.restaurants r
  where public.is_superadmin()
  order by r.created_at desc;
$$;
revoke all     on function public.admin_list_restaurants() from public, anon;
grant  execute on function public.admin_list_restaurants() to   authenticated;


-- ── Edit a client's billing fields ──────────────────────────────────────────
create or replace function public.admin_set_billing(
  p_id      uuid,
  p_plan    text,
  p_price   numeric,
  p_status  text,
  p_next_due date,
  p_notes   text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_superadmin() then raise exception 'No autorizado'; end if;
  update public.restaurants set
    plan           = nullif(btrim(p_plan), ''),
    price          = p_price,
    billing_status = coalesce(nullif(btrim(p_status), ''), 'trial'),
    next_due_date  = p_next_due,
    billing_notes  = nullif(btrim(p_notes), '')
  where id = p_id;
end;
$$;
revoke all     on function public.admin_set_billing(uuid, text, numeric, text, date, text) from public, anon;
grant  execute on function public.admin_set_billing(uuid, text, numeric, text, date, text) to   authenticated;


-- ── Mark as paid → advance the due date one period, set active ──────────────
create or replace function public.admin_mark_paid(p_id uuid, p_period_days integer default 30)
returns date
language plpgsql
security definer
set search_path = public
as $$
declare
  v_base date;
  v_new  date;
begin
  if not public.is_superadmin() then raise exception 'No autorizado'; end if;
  -- advance from the current due date, or from today if it's null/overdue
  select case when next_due_date is null or next_due_date < current_date
              then current_date else next_due_date end
    into v_base
  from public.restaurants where id = p_id;
  v_new := v_base + coalesce(p_period_days, 30);
  update public.restaurants set next_due_date = v_new, billing_status = 'active' where id = p_id;
  return v_new;
end;
$$;
revoke all     on function public.admin_mark_paid(uuid, integer) from public, anon;
grant  execute on function public.admin_mark_paid(uuid, integer) to   authenticated;

-- ============================================================================
-- Done.
-- ============================================================================
