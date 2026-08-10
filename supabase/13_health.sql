-- ============================================================================
-- The Easy Cook — vendor admin: health & churn monitoring (Phase 3)
-- Run after 12_codes.sql. Safe to re-run.
--
-- Adds a "last active" signal per restaurant so the admin can spot clients going
-- quiet before they churn. Derived from TIMESTAMPS only (when a device was last
-- seen, and when data was last written) — never the content of a client's data.
-- ============================================================================

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
  days_until_due integer,
  last_active    timestamptz,
  days_inactive  integer
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
    case when r.next_due_date is null then null else (r.next_due_date - current_date) end,
    la.last_active,
    case when la.last_active is null then null else (current_date - la.last_active::date) end
  from public.restaurants r
  left join lateral (
    select greatest(
      (select max(m.last_seen_at) from public.memberships m where m.restaurant_id = r.id),
      (select max(c.updated_at)   from public.collections c where c.restaurant_id = r.id)
    ) as last_active
  ) la on true
  where public.is_superadmin()
  order by r.created_at desc;
$$;
revoke all     on function public.admin_list_restaurants() from public, anon;
grant  execute on function public.admin_list_restaurants() to   authenticated;

-- ============================================================================
-- Done.
-- ============================================================================
