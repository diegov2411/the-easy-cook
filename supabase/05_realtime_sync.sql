-- ============================================================================
-- The Easy Cook — multi-device live sync (per-collection, conflict-safe)
-- Run after 04_signup_codes.sql. Safe to re-run (idempotent).
--
-- Goal: several devices in the same restaurant can add/edit at once, see each
-- other's changes live, and never silently overwrite one another.
--
-- Pieces:
--   • save_collection(): writes ONE collection with optimistic concurrency —
--     if the server copy changed since the client last saw it, it returns a
--     'conflict' + the current data so the client merges (by record id) and
--     retries, instead of blindly clobbering.
--   • Realtime: the collections table is published so clients get live updates.
-- ============================================================================


-- ── 1) my_restaurant() — the caller's active restaurant (owner OR staff) ────
create or replace function public.my_restaurant()
returns uuid
language sql
security definer
stable
set search_path = public
as $$
  select m.restaurant_id
  from public.memberships m
  where m.user_id = auth.uid() and m.active
  order by (m.role = 'owner') desc         -- prefer an owner membership if any
  limit 1;
$$;

revoke all     on function public.my_restaurant() from public, anon;
grant  execute on function public.my_restaurant() to   authenticated;


-- ── 2) save_collection() — optimistic-concurrency write of one collection ───
-- p_base = the updated_at the client last saw for this collection (null if it
-- has never synced this one). Returns:
--   { status:'ok',       version:<new updated_at> }
--   { status:'conflict', version:<current updated_at>, data:<current data> }
create or replace function public.save_collection(
  p_name text,
  p_data jsonb,
  p_base timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rid  uuid;
  v_cur  timestamptz;
  v_data jsonb;
  v_new  timestamptz;
begin
  v_rid := public.my_restaurant();
  if v_rid is null then
    raise exception 'No autorizado';
  end if;

  select updated_at, data into v_cur, v_data
  from public.collections
  where restaurant_id = v_rid and name = p_name
  for update;

  if not found then
    insert into public.collections (restaurant_id, name, data)
    values (v_rid, p_name, p_data)
    returning updated_at into v_new;
    return jsonb_build_object('status', 'ok', 'version', v_new);
  end if;

  -- Someone else wrote since the client loaded this collection (or the client
  -- has no base yet but a row already exists) → let the client merge + retry.
  if v_cur is distinct from p_base then
    return jsonb_build_object('status', 'conflict', 'version', v_cur, 'data', v_data);
  end if;

  update public.collections set data = p_data
  where restaurant_id = v_rid and name = p_name
  returning updated_at into v_new;
  return jsonb_build_object('status', 'ok', 'version', v_new);
end;
$$;

revoke all     on function public.save_collection(text, jsonb, timestamptz) from public, anon;
grant  execute on function public.save_collection(text, jsonb, timestamptz) to   authenticated;


-- ── 3) Enable Realtime on collections ───────────────────────────────────────
-- Full row in the change payload (so clients get the whole `data` + updated_at).
alter table public.collections replica identity full;

-- Add the table to Supabase's realtime publication (guarded so re-runs are safe).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'collections'
  ) then
    alter publication supabase_realtime add table public.collections;
  end if;
end
$$;

-- Realtime "postgres_changes" honors RLS: the existing "member reads
-- collections" SELECT policy already limits each client to its own restaurant.

-- ============================================================================
-- Done. Wire the app: per-collection saves via save_collection + a realtime
-- subscription that merges incoming changes.
-- ============================================================================
