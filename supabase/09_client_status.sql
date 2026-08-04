-- ============================================================================
-- The Easy Cook — expose restaurant active/inactive so the app can gate a
-- deactivated (e.g. non-paying) client. Run after 08_cashier_alerts.sql.
-- Safe to re-run.
--
-- restaurants.active already exists (default true). Flip it to false to cut a
-- client off; the app shows a "cuenta desactivada" screen instead of loading.
-- Toggle it from the vendor admin panel (next step) or:
--   update public.restaurants set active=false where id='...';
-- ============================================================================

-- my_membership(): one call that resolves the caller's restaurant + role AND
-- whether that restaurant is active. Replaces the app's direct memberships
-- read (restaurants is RPC-only, so its `active` column isn't otherwise
-- reachable from the client).
create or replace function public.my_membership()
returns table (
  restaurant_id     uuid,
  role              text,
  restaurant_active boolean,
  restaurant_name   text
)
language sql
security definer
stable
set search_path = public
as $$
  select m.restaurant_id, m.role, r.active, r.name
  from public.memberships m
  join public.restaurants r on r.id = m.restaurant_id
  where m.user_id = auth.uid() and m.active
  order by (m.role = 'owner') desc
  limit 1;
$$;

revoke all     on function public.my_membership() from public, anon;
grant  execute on function public.my_membership() to   authenticated;

-- ============================================================================
-- Done.
-- ============================================================================
