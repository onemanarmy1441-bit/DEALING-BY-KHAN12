-- Safe additive order integrity and manual refund tracking.
-- Admin must send the money through the original payment method before marking refunded.

alter table public.orders add column if not exists refunded_at timestamptz;
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check
  check (status in ('payment_pending','screenshot_verified','payment_approved','completed','rejected','refunded'));

-- Derive the true amount and seller from the approved listing; do not trust browser values.
create or replace function public.set_order_values_from_listing()
returns trigger language plpgsql security definer set search_path=public as $$
declare listing_row public.listings%rowtype;
begin
  select * into listing_row from public.listings where id=new.listing_id for update;
  if not found then raise exception 'Listing not found'; end if;
  if listing_row.status <> 'approved' then raise exception 'This listing is not available'; end if;
  if listing_row.seller_id = new.buyer_id then raise exception 'You cannot buy your own listing'; end if;
  new.seller_id := listing_row.seller_id;
  new.amount := listing_row.price;
  new.status := 'payment_pending';
  new.refunded_at := null;
  return new;
end;
$$;
drop trigger if exists orders_set_listing_values on public.orders;
create trigger orders_set_listing_values before insert on public.orders
for each row execute function public.set_order_values_from_listing();

create or replace function public.admin_update_order(_order_id uuid,_status text,_fee int default null)
returns void language plpgsql security definer set search_path=public as $$
declare amt int; listing uuid; current_status text; admin_fee_value int; payout_value int;
begin
  if not public.is_active_admin('payments') and not public.is_active_admin('deals') then raise exception 'Not authorized'; end if;
  select amount,listing_id,status into amt,listing,current_status from public.orders where id=_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if _status='screenshot_verified' and current_status<>'payment_pending' then raise exception 'Order is not waiting for screenshot verification';
  elsif _status='payment_approved' and current_status<>'screenshot_verified' then raise exception 'Verify the screenshot first';
  elsif _status='rejected' and current_status not in ('payment_pending','screenshot_verified') then raise exception 'Only unapproved orders can be rejected';
  elsif _status='completed' and current_status<>'payment_approved' then raise exception 'Only approved deals can be marked done';
  elsif _status='refunded' and current_status<>'rejected' then raise exception 'Only rejected orders can be marked refunded';
  elsif _status not in ('screenshot_verified','payment_approved','completed','rejected','refunded') then raise exception 'Invalid status'; end if;
  admin_fee_value:=case when _fee is not null then greatest(0,least(_fee,amt)) else round(amt*0.10)::int end;
  payout_value:=amt-admin_fee_value;
  update public.orders set status=_status,
    verified_at=case when _status='screenshot_verified' then now() else verified_at end,
    approved_at=case when _status='payment_approved' then now() else approved_at end,
    completed_at=case when _status='completed' then now() else completed_at end,
    refunded_at=case when _status='refunded' then now() else refunded_at end,
    admin_fee=case when _status='completed' then admin_fee_value else admin_fee end,
    seller_payout=case when _status='completed' then payout_value else seller_payout end,
    delivered_at=case when _status='payment_approved' then now() else delivered_at end
  where id=_order_id;
  if _status='payment_approved' then
    update public.listings set status='sold',reviewed_at=coalesce(reviewed_at,now()) where id=listing;
    insert into public.deal_messages(order_id,sender_id,sender_role,body) values(_order_id,null,'admin','Payment approved by admin. Deal chat is now open. Complete the handover checklist. Never share personal email passwords or OTPs.');
  elsif _status='completed' then
    insert into public.deal_messages(order_id,sender_id,sender_role,body) values(_order_id,null,'admin',format('Deal marked complete. Admin fee 10%%: Rs %s; seller payout 90%%: Rs %s. Buyer, please rate the seller.',admin_fee_value,payout_value));
  elsif _status='refunded' then
    insert into public.deal_messages(order_id,sender_id,sender_role,body) values(_order_id,null,'admin','Admin has marked the refund as sent. Check the original payment account. If it has not arrived, contact support with your order ID.');
  end if;
end;
$$;
revoke all on function public.admin_update_order(uuid,text,int) from public,anon;
grant execute on function public.admin_update_order(uuid,text,int) to authenticated;

-- Private seller verification image storage. Only upload owner and authorized Admins can access it.
alter table public.seller_private_details
  add column if not exists verification_image_path text;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('seller-verification','seller-verification',false,4194304,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false,file_size_limit=4194304,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists seller_verification_owner_upload on storage.objects;
create policy seller_verification_owner_upload on storage.objects
for insert to authenticated
with check (bucket_id='seller-verification' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists seller_verification_admin_read on storage.objects;
create policy seller_verification_admin_read on storage.objects
for select to authenticated
using (bucket_id='seller-verification' and (public.is_active_admin('users') or public.is_active_admin('listings')));
