-- ============================================================================
-- The Easy Cook — owner change-notifications (live "someone did X" feed)
-- Run after 05_realtime_sync.sql. Safe to re-run (idempotent).
--
-- A small, OWNER-ONLY event feed. Staff devices (and the owner's own devices)
-- write events when notable things happen — a recipe/price change, a deletion,
-- a dish marked out-of-stock, a new device joining. The owner's app subscribes
-- via realtime and shows a small toast (skipping the owner's own actions).
-- High-frequency routine sales are NOT events here — those stay a live counter.
-- ============================================================================

-- ── 1) The feed ─────────────────────────────────────────────────────────────
create table if not exists public.events (
  id            bigint generated always as identity primary key,
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  actor_user    uuid,                       -- who did it (to skip the owner's own)
  actor_name    text,                       -- display name (PIN user)
  kind          text not null,              -- recipe_change|price_change|delete|out_of_stock|device_join
  message       text not null,
  created_at    timestamptz not null default now()
);

create index if not exists events_restaurant_created
  on public.events(restaurant_id, created_at desc);

alter table public.events enable row level security;

-- Only the OWNER of the restaurant can read the feed → notifications are
-- owner-only (a user owns at most one restaurant; non-owners match nothing).
drop policy if exists "owner reads events" on public.events;
create policy "owner reads events" on public.events
  for select using (restaurant_id = public.my_owner_restaurant());

-- Any member (owner or staff device) may add an event for their restaurant.
drop policy if exists "member inserts events" on public.events;
create policy "member inserts events" on public.events
  for insert with check (public.is_member(restaurant_id));


-- ── 2) log_event() — the app calls this to record a notable change ──────────
create or replace function public.log_event(
  p_kind       text,
  p_message    text,
  p_actor_name text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rid uuid;
begin
  v_rid := public.my_restaurant();
  if v_rid is null then return; end if;      -- not a member → silently ignore
  insert into public.events (restaurant_id, actor_user, actor_name, kind, message)
  values (v_rid, auth.uid(), nullif(btrim(p_actor_name), ''), p_kind, left(p_message, 300));
end;
$$;

revoke all     on function public.log_event(text, text, text) from public, anon;
grant  execute on function public.log_event(text, text, text) to   authenticated;


-- ── 3) Device joins log themselves (trigger — no app code needed) ───────────
-- Fires on a NEW staff membership, or when a blocked device is re-activated.
-- Deliberately NOT on last_seen touches (active stays true → no fire).
create or replace function public.on_membership_join()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.role <> 'owner' and NEW.active
     and (TG_OP = 'INSERT' or OLD.active is distinct from true) then
    insert into public.events (restaurant_id, actor_user, actor_name, kind, message)
    values (NEW.restaurant_id, NEW.user_id, NEW.device_label, 'device_join',
            'Nuevo dispositivo del equipo: ' || coalesce(nullif(btrim(NEW.device_label), ''), 'sin nombre'));
  end if;
  return NEW;
end;
$$;

drop trigger if exists membership_join_event on public.memberships;
create trigger membership_join_event
  after insert or update on public.memberships
  for each row execute function public.on_membership_join();


-- ── 4) Realtime ─────────────────────────────────────────────────────────────
alter table public.events replica identity full;
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'events'
  ) then
    alter publication supabase_realtime add table public.events;
  end if;
end
$$;

-- ============================================================================
-- Done. Wire the app: log_event() at notable change sites + an owner-only
-- realtime subscription that toasts incoming events.
-- ============================================================================
