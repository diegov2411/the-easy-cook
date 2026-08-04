-- ============================================================================
-- The Easy Cook — table privileges for the authenticated role
-- Run after 06_events.sql. Safe to re-run (grants are idempotent).
--
-- RLS decides WHICH rows a user sees, but PostgREST/supabase-js still needs a
-- table-level GRANT to touch a table at all. This project's tables were created
-- without those grants, so the app's direct reads (memberships, collections)
-- and the realtime subscriptions (collections, events) would hit
-- "permission denied for table ...". These grants fix that.
--
-- Only SELECT is granted: every WRITE in the app goes through a SECURITY DEFINER
-- RPC (create_my_restaurant, join_*, save_collection, log_event, revoke_*),
-- which runs with the function owner's rights and bypasses these grants. RLS
-- policies (member-only reads, owner-only events) still apply on top.
--
-- "authenticated" covers both email owners and anonymous device sessions (both
-- authenticate with the authenticated Postgres role). restaurants is left
-- RPC-only on purpose (nothing reads it directly, and its join_code stays
-- unreadable to clients).
-- ============================================================================

grant select on public.memberships to authenticated;
grant select on public.collections to authenticated;
grant select on public.events      to authenticated;

-- ============================================================================
-- Done.
-- ============================================================================
