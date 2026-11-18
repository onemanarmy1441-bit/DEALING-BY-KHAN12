-- Safe additive privacy update for the existing project.
-- Seller area is stored separately from public listings and protected by RLS.

create table if not exists public.seller_private_details (
  listing_id uuid primary key references public.listings(id) on delete cascade,
  seller_id uuid not null references auth.users(id) on delete cascade,
  city_area text not null check (char_length(city_area) between 2 and 100),
  created_at timestamptz not null default now()
);

alter table public.seller_private_details enable row level security;
drop policy if exists seller_private_details_owner_read on public.seller_private_details;
create policy seller_private_details_owner_read
  on public.seller_private_details for select to authenticated
  using (seller_id = auth.uid());
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

grant select, insert on public.seller_private_details to authenticated;

-- Remove the old Gmail/password storage table after replacing the order RPC below.
create or replace function public.admin_update_order(_order_id uuid,_status text,_fee int default null)
returns void language plpgsql security definer set search_path=public as $$
declare amt int; listing uuid; current_status text; admin_fee_value int; payout_value int;
begin
 if not public.is_active_admin('payments') and not public.is_active_admin('deals') then raise exception 'Not authorized'; end if;
 select amount,listing_id,status into amt,listing,current_status from public.orders where id=_order_id for update;
 if not found then raise exception 'Order not found'; end if;
 if _status='screenshot_verified' and current_status<>'payment_pending' then raise exception 'Order is not waiting for screenshot verification'; end if;
 if _status='payment_approved' and current_status<>'screenshot_verified' then raise exception 'Verify the screenshot first'; end if;
 if _status='rejected' and current_status not in ('payment_pending','screenshot_verified') then raise exception 'Only unapproved orders can be rejected'; end if;
 if _status='completed' and current_status<>'payment_approved' then raise exception 'Only approved deals can be marked done'; end if;
 if _status not in ('screenshot_verified','payment_approved','completed','rejected') then raise exception 'Invalid status'; end if;
 admin_fee_value:=case when _fee is not null then greatest(0,least(_fee,amt)) else round(amt*0.10)::int end;
 payout_value:=amt-admin_fee_value;
 update public.orders set status=_status,
  verified_at=case when _status='screenshot_verified' then now() else verified_at end,
  approved_at=case when _status='payment_approved' then now() else approved_at end,
  completed_at=case when _status='completed' then now() else completed_at end,
  admin_fee=case when _status='completed' then admin_fee_value else admin_fee end,
  seller_payout=case when _status='completed' then payout_value else seller_payout end,
  delivered_at=case when _status='payment_approved' then now() else delivered_at end
 where id=_order_id;
 if _status='payment_approved' then
   update public.listings set status='sold',reviewed_at=coalesce(reviewed_at,now()) where id=listing;
   insert into public.deal_messages(order_id,sender_id,sender_role,body)
   values(_order_id,null,'admin','Payment approved by admin. Deal chat is now open. Buyer and seller, complete the account handover using the checklist. Never share personal email passwords.');
 elsif _status='completed' then
   insert into public.deal_messages(order_id,sender_id,sender_role,body)
   values(_order_id,null,'admin',format('Deal Done. Admin fee 10%%: Rs %s. Seller payout 90%%: Rs %s. Buyer, please rate the seller.',admin_fee_value,payout_value));
 end if;
end; $$;

-- Existing stored Gmail credentials are no longer part of the marketplace.
drop table if exists public.listing_credentials;
