-- Hubby Dealing Hub - fresh Supabase schema
-- Run this entire file once in Supabase SQL Editor on a NEW project.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 60),
  bio text not null default '' check (char_length(bio) <= 1000),
  avatar_url text not null default '',
  cover_url text not null default '',
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, display_name)
  values (new.id, coalesce(nullif(left(trim(new.raw_user_meta_data->>'display_name'),60),''), 'Seller '||left(new.id::text,6)))
  on conflict (id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create table if not exists public.payment_settings (
  id int primary key default 1 check (id=1),
  jazzcash_number text not null default '', jazzcash_title text not null default '',
  easypaisa_number text not null default '', easypaisa_title text not null default '',
  updated_at timestamptz not null default now()
);
insert into public.payment_settings(id) values(1) on conflict(id) do nothing;

create table if not exists public.site_customization (
  id int primary key default 1 check (id=1),
  brand_name text not null default 'Hubby Khan Dealing Hub',
  hero_title text not null default 'FREE FIRE IDs MARKET',
  hero_subtitle text not null default 'Har ID admin se verify. Safe deal, JazzCash / Easypaisa payment.',
  logo_url text not null default '', hero_image_url text not null default '',
  theme_mode text not null default 'dark' check(theme_mode in ('dark','light')),
  primary_color text not null default '#f97316', accent_color text not null default '#facc15',
  updated_at timestamptz not null default now()
);
insert into public.site_customization(id) values(1) on conflict(id) do nothing;

create table if not exists public.listings (
  id uuid primary key default gen_random_uuid(), seller_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check(char_length(title) between 3 and 100), level int check(level is null or level between 1 and 100),
  price int not null check(price > 0 and price <= 10000000), description text not null default '' check(char_length(description)<=2000),
  images text[] not null default '{}', status text not null default 'pending' check(status in ('pending','approved','rejected','sold')),
  created_at timestamptz not null default now(), reviewed_at timestamptz
);
create index if not exists listings_status_idx on public.listings(status,created_at desc);
create index if not exists listings_seller_idx on public.listings(seller_id);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(), listing_id uuid not null references public.listings(id) on delete cascade,
  buyer_id uuid not null references public.profiles(id) on delete cascade, seller_id uuid not null references public.profiles(id) on delete cascade,
  amount int not null check(amount>0), payment_method text not null check(payment_method in ('jazzcash','easypaisa')),
  payment_account_number text not null default '', payment_account_title text not null default '', screenshot_path text not null,
  status text not null default 'payment_pending' check(status in ('payment_pending','screenshot_verified','payment_approved','completed','rejected')),
  checklist jsonb not null default '{}'::jsonb, admin_fee int, seller_payout int,
  verified_at timestamptz, approved_at timestamptz, delivered_at timestamptz, completed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists orders_buyer_idx on public.orders(buyer_id);
create index if not exists orders_seller_idx on public.orders(seller_id);
create index if not exists orders_status_idx on public.orders(status,created_at desc);

create table if not exists public.deal_messages (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id) on delete cascade,
  sender_id uuid references public.profiles(id) on delete set null,
  sender_role text not null default 'buyer' check(sender_role in ('buyer','seller','admin')),
  body text not null check(char_length(body) between 1 and 2000), created_at timestamptz not null default now()
);
create index if not exists deal_messages_order_idx on public.deal_messages(order_id,created_at);

create table if not exists public.deal_reports (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check(char_length(reason) between 3 and 1000), resolved boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(), order_id uuid not null unique references public.orders(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  rating int not null check(rating between 1 and 5), comment text not null default '' check(char_length(comment)<=1000),
  created_at timestamptz not null default now()
);
create index if not exists reviews_seller_idx on public.reviews(seller_id,created_at desc);

create table if not exists public.admin_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique, role text not null default 'admin' check(role in ('super_admin','admin','moderator','support')),
  permissions text[] not null default '{}', is_active boolean not null default true,
  invited_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now()
);

-- RLS helpers
create or replace function public.is_active_admin(_permission text default null)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.admin_members a where a.user_id=auth.uid() and a.is_active=true
    and (a.role='super_admin' or (_permission is not null and _permission=any(a.permissions))))
$$;
create or replace function public.is_deal_participant(_order_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.orders o where o.id=_order_id and (o.buyer_id=auth.uid() or o.seller_id=auth.uid()) and o.status in ('payment_approved','completed'))
$$;

-- Order values are derived from the listing/payment settings, never trusted from the browser.
create or replace function public.prepare_order()
returns trigger language plpgsql security definer set search_path=public as $$
declare l public.listings%rowtype; p public.payment_settings%rowtype;
begin
  select * into l from public.listings where id=new.listing_id for update;
  if not found or l.status<>'approved' then raise exception 'This ID is not available for sale'; end if;
  if l.seller_id=new.buyer_id then raise exception 'You cannot buy your own ID'; end if;
  if new.buyer_id<>auth.uid() then raise exception 'Invalid buyer'; end if;
  if new.screenshot_path not like new.buyer_id::text||'/%' then raise exception 'Invalid screenshot path'; end if;
  select * into p from public.payment_settings where id=1;
  new.seller_id:=l.seller_id; new.amount:=l.price; new.status:='payment_pending'; new.checklist:='{}'::jsonb;
  new.admin_fee:=null; new.seller_payout:=null; new.verified_at:=null; new.approved_at:=null; new.delivered_at:=null; new.completed_at:=null;
  if new.payment_method='jazzcash' then new.payment_account_number:=p.jazzcash_number; new.payment_account_title:=p.jazzcash_title;
  else new.payment_account_number:=p.easypaisa_number; new.payment_account_title:=p.easypaisa_title; end if;
  return new;
end; $$;
drop trigger if exists orders_prepare on public.orders;
create trigger orders_prepare before insert on public.orders for each row execute function public.prepare_order();

create or replace function public.set_message_role()
returns trigger language plpgsql security definer set search_path=public as $$
declare o public.orders%rowtype;
begin
  if new.sender_id is null then new.sender_role:='admin'; return new; end if;
  select * into o from public.orders where id=new.order_id;
  if o.buyer_id=new.sender_id then new.sender_role:='buyer'; elsif o.seller_id=new.sender_id then new.sender_role:='seller'; else raise exception 'Not part of this deal'; end if;
  return new;
end; $$;
drop trigger if exists deal_messages_role on public.deal_messages;
create trigger deal_messages_role before insert on public.deal_messages for each row execute function public.set_message_role();

create or replace function public.moderate_deal_message()
returns trigger language plpgsql as $$
begin
 if new.body ~* '(^|[^a-z0-9])(fuck|fucking|motherfucker|bitch|bastard|asshole|shit|bullshit|chutiya|madarchod|behenchod|gaand|harami)([^a-z0-9]|$)' then
  raise exception 'Please use respectful language. Hubby AI has blocked this message.';
 end if; return new;
end; $$;
drop trigger if exists deal_messages_moderation_guard on public.deal_messages;
create trigger deal_messages_moderation_guard before insert on public.deal_messages for each row execute function public.moderate_deal_message();

create or replace function public.set_checklist_item(_order_id uuid,_key text,_value boolean)
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
 if not public.is_deal_participant(_order_id) then raise exception 'Not allowed'; end if;
 if _key !~ '^[a-z_]{1,40}$' then raise exception 'Invalid checklist item'; end if;
 update public.orders set checklist=checklist||jsonb_build_object(_key,_value) where id=_order_id returning checklist into result;
 return result;
end; $$;

create or replace function public.submit_seller_review(_order_id uuid,_rating int,_comment text default '')
returns jsonb language plpgsql security definer set search_path=public as $$
declare o public.orders%rowtype; r public.reviews%rowtype;
begin
 if auth.uid() is null then raise exception 'Please sign in'; end if;
 if _rating not between 1 and 5 then raise exception 'Rating must be 1 to 5'; end if;
 if char_length(coalesce(_comment,''))>1000 then raise exception 'Review is too long'; end if;
 select * into o from public.orders where id=_order_id;
 if not found or o.buyer_id<>auth.uid() or o.status<>'completed' then raise exception 'Only the buyer of a completed deal can review'; end if;
 insert into public.reviews(order_id,seller_id,buyer_id,rating,comment) values(_order_id,o.seller_id,auth.uid(),_rating,coalesce(_comment,'')) returning * into r;
 return jsonb_build_object('id',r.id,'rating',r.rating,'comment',r.comment,'created_at',r.created_at);
exception when unique_violation then raise exception 'You have already reviewed this deal';
end; $$;

create or replace function public.seller_stats(_seller_id uuid)
returns table(total_sold bigint,avg_rating numeric,review_count bigint) language sql stable security definer set search_path=public as $$
 select (select count(*) from public.orders where seller_id=_seller_id and status='completed'),
 (select round(avg(rating)::numeric,1) from public.reviews where seller_id=_seller_id),
 (select count(*) from public.reviews where seller_id=_seller_id)
$$;

-- Admin RPCs: all writes are checked inside Postgres, not just in the interface.
create or replace function public.admin_update_listing(_listing_id uuid,_status text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_active_admin('listings') then raise exception 'Not authorized'; end if;
 if _status not in ('approved','rejected','sold') then raise exception 'Invalid status'; end if;
 update public.listings set status=_status,reviewed_at=now() where id=_listing_id;
end; $$;
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
   values(_order_id,null,'admin','Payment approved by admin. Deal chat is now open. Buyer and seller, coordinate the Free Fire account handover here. Never share personal email passwords or OTPs.');
 elsif _status='completed' then
   insert into public.deal_messages(order_id,sender_id,sender_role,body)
   values(_order_id,null,'admin',format('Deal Done. Admin fee 10%%: Rs %s. Seller payout 90%%: Rs %s. Buyer, please rate the seller.',admin_fee_value,payout_value));
 end if;
end; $$;
create or replace function public.admin_save_payment_settings(_jnum text,_jtitle text,_enum text,_etitle text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_active_admin('payment_settings') then raise exception 'Not authorized'; end if;
 update public.payment_settings set jazzcash_number=_jnum,jazzcash_title=_jtitle,easypaisa_number=_enum,easypaisa_title=_etitle,updated_at=now() where id=1;
end; $$;
create or replace function public.admin_save_site(_brand text,_title text,_subtitle text,_logo text,_banner text,_theme text,_primary text,_accent text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_active_admin('appearance') then raise exception 'Not authorized'; end if;
 update public.site_customization set brand_name=_brand,hero_title=_title,hero_subtitle=_subtitle,logo_url=_logo,hero_image_url=_banner,theme_mode=_theme,primary_color=_primary,accent_color=_accent,updated_at=now() where id=1;
end; $$;
create or replace function public.admin_upsert_member(_email text,_role text,_permissions text[])
returns void language plpgsql security definer set search_path=public as $$
declare target uuid;
begin
 if not public.is_active_admin('admins') then raise exception 'Only super admin can manage admins'; end if;
 select id into target from auth.users where lower(email)=lower(_email);
 if target is null then raise exception 'User must register first'; end if;
 insert into public.admin_members(user_id,email,role,permissions,is_active,invited_by)
 values(target,lower(_email),_role,_permissions,true,auth.uid())
 on conflict(user_id) do update set role=excluded.role,permissions=excluded.permissions,is_active=true,email=excluded.email;
end; $$;
create or replace function public.admin_set_member_active(_user_id uuid,_active boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_active_admin('admins') then raise exception 'Only super admin can manage admins'; end if;
 if _user_id=auth.uid() then raise exception 'You cannot change your own access'; end if;
 update public.admin_members set is_active=_active where user_id=_user_id;
end; $$;
create or replace function public.admin_remove_member(_user_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_active_admin('admins') then raise exception 'Only super admin can manage admins'; end if;
 if _user_id=auth.uid() then raise exception 'You cannot remove yourself'; end if;
 delete from public.admin_members where user_id=_user_id;
end; $$;

-- Grants and row security
alter table public.profiles enable row level security;
alter table public.payment_settings enable row level security;
alter table public.site_customization enable row level security;
alter table public.listings enable row level security;
alter table public.orders enable row level security;
alter table public.deal_messages enable row level security;
alter table public.deal_reports enable row level security;
alter table public.reviews enable row level security;
alter table public.admin_members enable row level security;

drop policy if exists profiles_public_read on public.profiles;
create policy profiles_public_read on public.profiles for select to anon,authenticated using(true);
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
drop policy if exists payment_settings_read on public.payment_settings;
create policy payment_settings_read on public.payment_settings for select to anon,authenticated using(true);
drop policy if exists site_customization_read on public.site_customization;
create policy site_customization_read on public.site_customization for select to anon,authenticated using(true);
drop policy if exists listings_public_read on public.listings;
create policy listings_public_read on public.listings for select to anon,authenticated using(status in ('approved','sold') or seller_id=auth.uid() or public.is_active_admin('listings') or public.is_active_admin('credentials'));
drop policy if exists listings_insert_own on public.listings;
create policy listings_insert_own on public.listings for insert to authenticated with check(seller_id=auth.uid() and status='pending');
drop policy if exists listings_update_own_pending on public.listings;
create policy listings_update_own_pending on public.listings for update to authenticated using(seller_id=auth.uid() and status='pending') with check(seller_id=auth.uid() and status='pending');
drop policy if exists orders_read_participants on public.orders;
create policy orders_read_participants on public.orders for select to authenticated using(buyer_id=auth.uid() or seller_id=auth.uid() or public.is_active_admin('payments') or public.is_active_admin('deals'));
drop policy if exists orders_insert_buyer on public.orders;
create policy orders_insert_buyer on public.orders for insert to authenticated with check(buyer_id=auth.uid() and status='payment_pending');
drop policy if exists messages_read_participant on public.deal_messages;
create policy messages_read_participant on public.deal_messages for select to authenticated using(public.is_deal_participant(order_id) or public.is_active_admin('deals'));
drop policy if exists messages_insert_participant on public.deal_messages;
create policy messages_insert_participant on public.deal_messages for insert to authenticated with check(sender_id=auth.uid() and (public.is_deal_participant(order_id) or public.is_active_admin('deals')));
drop policy if exists reports_read_allowed on public.deal_reports;
create policy reports_read_allowed on public.deal_reports for select to authenticated using(reporter_id=auth.uid() or public.is_active_admin('deals'));
drop policy if exists reports_insert_participant on public.deal_reports;
create policy reports_insert_participant on public.deal_reports for insert to authenticated with check(reporter_id=auth.uid() and resolved=false and public.is_deal_participant(order_id));
drop policy if exists reviews_public_read on public.reviews;
create policy reviews_public_read on public.reviews for select to anon,authenticated using(true);
drop policy if exists reviews_insert_buyer on public.reviews;
create policy reviews_insert_buyer on public.reviews for insert to authenticated with check(buyer_id=auth.uid() and exists(select 1 from public.orders o where o.id=order_id and o.buyer_id=auth.uid() and o.status='completed'));
-- Admin membership is deliberately not directly readable/writable by browser roles.
revoke all on public.admin_members from anon,authenticated;
grant all on public.admin_members to service_role;
grant select on public.profiles,public.payment_settings,public.site_customization,public.listings,public.reviews to anon,authenticated;
grant select,update on public.profiles to authenticated;
grant insert,select,update on public.listings to authenticated;
grant select,insert on public.orders,public.deal_messages,public.deal_reports to authenticated;
grant select on public.reviews to anon,authenticated;
revoke insert on public.reviews from authenticated;
grant execute on function public.is_active_admin(text) to anon,authenticated;
grant execute on function public.is_deal_participant(uuid) to authenticated;
grant execute on function public.set_checklist_item(uuid,text,boolean) to authenticated;
grant execute on function public.submit_seller_review(uuid,int,text) to authenticated;
grant execute on function public.seller_stats(uuid) to anon,authenticated;
grant execute on function public.admin_update_listing(uuid,text) to authenticated;
grant execute on function public.admin_update_order(uuid,text,int) to authenticated;
grant execute on function public.admin_save_payment_settings(text,text,text,text) to authenticated;
grant execute on function public.admin_save_site(text,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.admin_upsert_member(text,text,text[]) to authenticated;
grant execute on function public.admin_set_member_active(uuid,boolean) to authenticated;
grant execute on function public.admin_remove_member(uuid) to authenticated;

-- Storage buckets: listing images and seller profile media public; payment receipts private.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('listing-images','listing-images',true,6291456,array['image/jpeg','image/png','image/webp']),
 ('seller-media','seller-media',true,4194304,array['image/jpeg','image/png','image/webp']),
 ('payment-screenshots','payment-screenshots',false,6291456,array['image/jpeg','image/png','image/webp'])
on conflict(id) do nothing;
create policy "Public listing image read" on storage.objects for select to anon,authenticated using(bucket_id in ('listing-images','seller-media'));
create policy "User uploads own listing images" on storage.objects for insert to authenticated with check(bucket_id='listing-images' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "User uploads own seller media" on storage.objects for insert to authenticated with check(bucket_id='seller-media' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "User updates own seller media" on storage.objects for update to authenticated using(bucket_id='seller-media' and (storage.foldername(name))[1]=auth.uid()::text) with check(bucket_id='seller-media' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "Buyer uploads own payment screenshot" on storage.objects for insert to authenticated with check(bucket_id='payment-screenshots' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "Buyer and admin read payment screenshot" on storage.objects for select to authenticated using(bucket_id='payment-screenshots' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_active_admin('payments')));

-- Read-only admin dashboard RPCs.
create or replace function public.get_my_admin_status()
returns jsonb language sql stable security definer set search_path=public as $$
 select coalesce((select jsonb_build_object('user_id',user_id,'email',email,'role',role,'permissions',permissions,'is_active',is_active)
 from public.admin_members where user_id=auth.uid() and is_active=true),'{}'::jsonb)
$$;
create or replace function public.admin_list_members()
returns table(user_id uuid,email text,role text,permissions text[],is_active boolean,created_at timestamptz)
language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_active_admin('admins') then raise exception 'Not authorized'; end if;
 return query select a.user_id,a.email,a.role,a.permissions,a.is_active,a.created_at from public.admin_members a order by a.created_at;
end; $$;
create or replace function public.admin_list_users()
returns table(user_id uuid,email text,display_name text,created_at timestamptz,listings bigint,buys bigint,sales bigint,confirmed boolean)
language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_active_admin('users') then raise exception 'Not authorized'; end if;
 return query select u.id,u.email,coalesce(p.display_name,''),u.created_at,
  (select count(*) from public.listings l where l.seller_id=u.id),
  (select count(*) from public.orders o where o.buyer_id=u.id),
  (select count(*) from public.orders o where o.seller_id=u.id and o.status='completed'),
  (u.email_confirmed_at is not null)
 from auth.users u left join public.profiles p on p.id=u.id order by u.created_at desc limit 500;
end; $$;
create or replace function public.admin_list_reports()
returns table(id uuid,order_id uuid,reporter_id uuid,reason text,resolved boolean,created_at timestamptz)
language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_active_admin('deals') then raise exception 'Not authorized'; end if;
 return query select r.id,r.order_id,r.reporter_id,r.reason,r.resolved,r.created_at from public.deal_reports r order by r.created_at desc;
end; $$;
create or replace function public.admin_resolve_report(_report_id uuid,_resolved boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_active_admin('deals') then raise exception 'Not authorized'; end if;
 update public.deal_reports set resolved=_resolved where id=_report_id;
end; $$;
grant execute on function public.get_my_admin_status() to authenticated;
grant execute on function public.admin_list_members() to authenticated;
grant execute on function public.admin_list_users() to authenticated;
grant execute on function public.admin_list_reports() to authenticated;
grant execute on function public.admin_resolve_report(uuid,boolean) to authenticated;

create or replace function public.admin_send_deal_message(_order_id uuid,_body text)
returns uuid language plpgsql security definer set search_path=public as $$
declare new_id uuid;
begin
 if not public.is_active_admin('deals') then raise exception 'Not authorized'; end if;
 if char_length(trim(_body)) not between 1 and 2000 then raise exception 'Message must be 1 to 2000 characters'; end if;
 insert into public.deal_messages(order_id,sender_id,sender_role,body) values(_order_id,null,'admin',trim(_body)) returning id into new_id;
 return new_id;
end; $$;
grant execute on function public.admin_send_deal_message(uuid,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('site-assets','site-assets',true,4194304,array['image/jpeg','image/png','image/webp'])
on conflict(id) do nothing;
create policy "Public site brand assets read" on storage.objects for select to anon,authenticated using(bucket_id='site-assets');
create policy "Active admins upload site assets" on storage.objects for insert to authenticated with check(bucket_id='site-assets' and public.is_active_admin('appearance'));
create policy "Active admins update site assets" on storage.objects for update to authenticated using(bucket_id='site-assets' and public.is_active_admin('appearance')) with check(bucket_id='site-assets' and public.is_active_admin('appearance'));
create policy "Active admins delete site assets" on storage.objects for delete to authenticated using(bucket_id='site-assets' and public.is_active_admin('appearance'));
