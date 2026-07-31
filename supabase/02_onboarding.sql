-- ============================================================================
-- The Easy Cook — onboarding RPC
-- Run after schema.sql. Safe to re-run (create or replace).
--
-- create_my_restaurant(): the logged-in user creates their restaurant and is
-- made its owner, in one atomic call. SECURITY DEFINER so it can insert into
-- restaurants + memberships regardless of RLS, but it only ever acts for the
-- caller (auth.uid()) — a user can never create a membership for someone else.
-- The app calls this once, during first-run onboarding.
-- ============================================================================

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

  insert into public.restaurants (name, ruc)
  values (coalesce(nullif(btrim(p_name), ''), 'Mi restaurante'), nullif(btrim(p_ruc), ''))
  returning id into v_id;

  insert into public.memberships (restaurant_id, user_id, role)
  values (v_id, auth.uid(), 'owner');

  return v_id;
end;
$$;

-- Only logged-in users may call it (never the anonymous public role).
revoke all     on function public.create_my_restaurant(text, text) from public, anon;
grant  execute on function public.create_my_restaurant(text, text) to   authenticated;
