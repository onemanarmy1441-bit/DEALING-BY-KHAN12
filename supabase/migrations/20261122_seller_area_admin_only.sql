-- Restrict seller city/area details to authorized admins only.
-- Sellers may submit their own area with a listing, but cannot read it back through the API.
-- Public/anonymous users have no SELECT policy or table grant.

alter table public.seller_private_details enable row level security;

drop policy if exists seller_private_details_owner_read on public.seller_private_details;
drop policy if exists seller_private_details_admin_read on public.seller_private_details;
create policy seller_private_details_admin_read
  on public.seller_private_details for select to authenticated
  using (public.is_active_admin('users') or public.is_active_admin('listings'));

drop policy if exists seller_private_details_owner_insert on public.seller_private_details;
create policy seller_private_details_owner_insert
  on public.seller_private_details for insert to authenticated
  with check (
    seller_id = auth.uid()
    and exists (
      select 1 from public.listings l
      where l.id = listing_id and l.seller_id = auth.uid()
    )
  );

revoke all on public.seller_private_details from anon;
revoke select on public.seller_private_details from authenticated;
grant insert on public.seller_private_details to authenticated;
grant select on public.seller_private_details to authenticated;

-- The older Gmail/password credential table is not used by the current flow.
drop table if exists public.listing_credentials;
