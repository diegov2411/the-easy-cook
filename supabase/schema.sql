-- ============================================================================
-- The Easy Cook — multi-tenant foundation (Supabase / Postgres)
-- Run this once in Supabase → SQL Editor → New query → paste → Run.
-- Safe to re-run: every statement is idempotent (IF NOT EXISTS / OR REPLACE).
-- ============================================================================

-- 1) RESTAURANTS — one row per customer (the "tenant"). Settings live here too.
create table if not exists public.restaurants (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null,
  ruc                 text,
  igv_mode            text    not null default 'incluido',
  service_charge      boolean not null default false,
  service_charge_pct  numeric not null default 0,
  food_cost_target    numeric not null default 30,
  active              boolean not null default true,        -- flip to false to disable a client
  created_at          timestamptz not null default now()
);

-- 2) MEMBERSHIPS — links a Supabase Auth login to a restaurant. This is the
--    table RLS checks to decide who may see a given restaurant's data.
create table if not exists public.memberships (
  restaurant_id  uuid not null references public.restaurants(id) on delete cascade,
  user_id        uuid not null references auth.users(id)        on delete cascade,
  role           text not null default 'owner',
  created_at     timestamptz not null default now(),
  primary key (restaurant_id, user_id)
);

-- 3) COLLECTIONS — the app's data, one JSON document per collection per
--    restaurant (products, recipes, orders, ...). Flexible + lossless, and
--    writes touch only the section that changed.
create table if not exists public.collections (
  restaurant_id  uuid not null references public.restaurants(id) on delete cascade,
  name           text not null,                              -- e.g. 'products', 'orders'
  data           jsonb not null default '[]'::jsonb,
  updated_at     timestamptz not null default now(),
  primary key (restaurant_id, name)
);

-- ---------------------------------------------------------------------------
-- Helper: is the current logged-in user a member of restaurant :rid ?
-- SECURITY DEFINER so it can read memberships without tripping RLS recursion.
-- ---------------------------------------------------------------------------
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
  );
$$;

-- ---------------------------------------------------------------------------
-- Row-Level Security: the wall between one restaurant and another.
-- ---------------------------------------------------------------------------
alter table public.restaurants enable row level security;
alter table public.memberships enable row level security;
alter table public.collections enable row level security;

-- restaurants: a member can read and update their own restaurant.
drop policy if exists "member reads restaurant"   on public.restaurants;
create policy "member reads restaurant" on public.restaurants
  for select using (public.is_member(id));

drop policy if exists "member updates restaurant" on public.restaurants;
create policy "member updates restaurant" on public.restaurants
  for update using (public.is_member(id)) with check (public.is_member(id));

-- memberships: you can see your own membership rows.
drop policy if exists "see own memberships" on public.memberships;
create policy "see own memberships" on public.memberships
  for select using (user_id = auth.uid());

-- collections: full read/write limited to members of that restaurant.
drop policy if exists "member reads collections"   on public.collections;
create policy "member reads collections" on public.collections
  for select using (public.is_member(restaurant_id));

drop policy if exists "member inserts collections" on public.collections;
create policy "member inserts collections" on public.collections
  for insert with check (public.is_member(restaurant_id));

drop policy if exists "member updates collections" on public.collections;
create policy "member updates collections" on public.collections
  for update using (public.is_member(restaurant_id)) with check (public.is_member(restaurant_id));

drop policy if exists "member deletes collections" on public.collections;
create policy "member deletes collections" on public.collections
  for delete using (public.is_member(restaurant_id));

-- Keep collections.updated_at fresh (used later for conflict detection).
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists collections_touch on public.collections;
create trigger collections_touch
  before update on public.collections
  for each row execute function public.touch_updated_at();

-- ============================================================================
-- Done. Next step (separate task): a small signup function that creates a
-- restaurant + owner membership for a new user, then wiring the app's
-- loadData/setData to read/write these collections instead of localStorage.
-- ============================================================================
