-- ============================================================================
-- The Easy Cook — let cashiers get out-of-stock alerts
-- Run after 07_grants.sql. Safe to re-run (idempotent).
--
-- The events feed is owner-only by default. This adds a SECOND select policy so
-- any member (a staff device) may read ONLY 'out_of_stock' events — enough for a
-- cashier's app to pop a "dish is now unavailable, stop selling it" alert live.
-- Postgres combines multiple SELECT policies with OR, so:
--   • owner  → every event (existing "owner reads events" policy)
--   • member → out_of_stock events only (this policy)
-- The client further limits the popup to the cashier PIN role.
-- ============================================================================

drop policy if exists "member reads out_of_stock" on public.events;
create policy "member reads out_of_stock" on public.events
  for select using (public.is_member(restaurant_id) and kind = 'out_of_stock');

-- ============================================================================
-- Done.
-- ============================================================================
