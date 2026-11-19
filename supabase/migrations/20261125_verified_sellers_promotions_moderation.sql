
-- DEALING BY KHAN12: additive seller verification, promotions and listing moderation.
-- Safe to apply to the existing project; no existing tables or rows are dropped.
begin;

-- Keep phone/contact data out of the publicly readable profiles table.
create table if not exists public.seller_verification_contacts (
 seller_id uuid primary key references public.profiles(id) on delete cascade,
 phone_number text not null default '',
 updated_at timestamptz not null default now()
);
alter table public.profiles add column if not exists is_verified_seller boolean not null default false;
alter table public.profiles add column if not exists verification_status text not null default 'not_applied'
  check (verification_status in ('not_applied','pending','approved','rejected','suspended','revoked'));

alter table public.listings drop constraint if exists listings_status_check;
alter table public.listings add constraint listings_status_check
  check(status in ('pending','approved','rejected','sold','hidden'));

create table if not exists public.seller_verification_settings (
 id boolean primary key default true check(id),
 min_successful_deals integer not null default 3 check(min_successful_deals>=0),
 min_account_age_days integer not null default 7 check(min_account_age_days>=0),
 require_profile boolean not null default true,
 require_phone boolean not null default true,
 max_open_serious_complaints integer not null default 0 check(max_open_serious_complaints>=0),
 updated_at timestamptz not null default now()
);
insert into public.seller_verification_settings(id) values(true) on conflict(id) do nothing;

create table if not exists public.seller_verification_applications (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null references public.profiles(id) on delete cascade,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 seller_note text not null default '',
 admin_note text not null default '',
 reviewed_by uuid references auth.users(id) on delete set null,
 reviewed_at timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists seller_verification_applications_seller_idx on public.seller_verification_applications(seller_id,created_at desc);

create table if not exists public.promotion_packages (
 code text primary key check(code in ('24h','3d','7d')),
 label text not null,
 duration_hours integer not null check(duration_hours in (24,72,168)),
 price_pkr integer not null default 0 check(price_pkr>=0),
 is_enabled boolean not null default true
);
insert into public.promotion_packages(code,label,duration_hours,price_pkr) values
 ('24h','24 Hours',24,300),('3d','3 Days',72,700),('7d','7 Days',168,1400)
on conflict(code) do nothing;

create table if not exists public.promotion_payment_methods (
 code text primary key check(code in ('jazzcash','easypaisa','bank_transfer')),
 label text not null,
 account_title text not null default '',
 account_number text not null default '',
 instructions text not null default '',
 is_enabled boolean not null default true
);
insert into public.promotion_payment_methods(code,label) values
 ('jazzcash','JazzCash'),('easypaisa','EasyPaisa'),('bank_transfer','Bank Transfer')
on conflict(code) do nothing;

create table if not exists public.listing_promotions (
 id uuid primary key default gen_random_uuid(),
 listing_id uuid not null references public.listings(id) on delete cascade,
 seller_id uuid not null references public.profiles(id) on delete cascade,
 package_code text not null references public.promotion_packages(code),
 amount_pkr integer not null check(amount_pkr>=0),
 payment_method text not null check(payment_method in ('jazzcash','easypaisa','bank_transfer')),
 receipt_path text not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled','expired')),
 starts_at timestamptz,
 expires_at timestamptz,
 admin_note text not null default '',
 reviewed_by uuid references auth.users(id) on delete set null,
 reviewed_at timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists listing_promotions_active_idx on public.listing_promotions(status,expires_at desc);

create table if not exists public.listing_moderation_history (
 id uuid primary key default gen_random_uuid(),
 listing_id uuid,
 seller_id uuid,
 actor_id uuid references auth.users(id) on delete set null,
 action text not null check(action in ('seller_hide','seller_restore','seller_delete','admin_hide','admin_restore','admin_delete')),
 reason text not null default '',
 snapshot jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);

create or replace function public.is_verified_seller(_seller uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select coalesce((select is_verified_seller from public.profiles where id=_seller),false) $$;

create or replace function public.auto_approve_verified_listing()
returns trigger language plpgsql security definer set search_path=public
as $$ begin
 if public.is_verified_seller(new.seller_id) then new.status := 'approved'; end if;
 return new;
end $$;
drop trigger if exists trg_auto_approve_verified_listing on public.listings;
create trigger trg_auto_approve_verified_listing before insert on public.listings
for each row execute function public.auto_approve_verified_listing();

create or replace function public.apply_seller_verification(_note text default '')
returns jsonb language plpgsql security definer set search_path=public
as $$
declare uid uuid:=auth.uid(); p public.profiles%rowtype; cfg public.seller_verification_settings%rowtype;
 deals integer; age_days integer; complaints integer; existing_id uuid;
begin
 if uid is null then raise exception 'Please login first'; end if;
 select * into p from public.profiles where id=uid;
 if not found then raise exception 'Profile not found'; end if;
 select * into cfg from public.seller_verification_settings where id=true;
 select count(*) into deals from public.orders where seller_id=uid and status='completed';
 select greatest(0,floor(extract(epoch from now()-(select created_at from auth.users where id=uid))/86400)::int) into age_days;
 select count(*) into complaints from public.deal_reports r join public.orders o on o.id=r.order_id
 where o.seller_id=uid and r.resolved=false;
 if cfg.require_profile and (length(trim(p.display_name))<2 or length(trim(p.bio))=0) then raise exception 'Complete your profile name and bio first'; end if;
 if cfg.require_phone and length(regexp_replace(coalesce((select phone_number from public.seller_verification_contacts where seller_id=uid),''),'\s','','g'))<7 then raise exception 'Add your phone number in Edit Profile first'; end if;
 if deals<cfg.min_successful_deals then raise exception 'You need at least % successful deals',cfg.min_successful_deals; end if;
 if age_days<cfg.min_account_age_days then raise exception 'Your account must be at least % days old',cfg.min_account_age_days; end if;
 if complaints>cfg.max_open_serious_complaints then raise exception 'Open complaints prevent verification. Contact admin.'; end if;
 if exists(select 1 from public.seller_verification_applications where seller_id=uid and status='pending') then raise exception 'Application already pending'; end if;
 insert into public.seller_verification_applications(seller_id,seller_note) values(uid,left(coalesce(_note,''),1000)) returning id into existing_id;
 update public.profiles set verification_status='pending' where id=uid;
 return jsonb_build_object('application_id',existing_id,'successful_deals',deals,'account_age_days',age_days);
end $$;

create or replace function public.admin_review_seller_verification(_application uuid,_decision text,_note text default '')
returns void language plpgsql security definer set search_path=public
as $$
declare app public.seller_verification_applications%rowtype;
begin
 if not public.is_active_admin('users') then raise exception 'Admin access required'; end if;
 if _decision not in ('approved','rejected') then raise exception 'Invalid decision'; end if;
 select * into app from public.seller_verification_applications where id=_application for update;
 if not found or app.status<>'pending' then raise exception 'Pending application not found'; end if;
 update public.seller_verification_applications set status=_decision,admin_note=left(coalesce(_note,''),1000),reviewed_by=auth.uid(),reviewed_at=now() where id=_application;
 update public.profiles set is_verified_seller=(_decision='approved'),verification_status=_decision where id=app.seller_id;
end $$;

create or replace function public.admin_set_seller_verification(_seller uuid,_status text)
returns void language plpgsql security definer set search_path=public
as $$ begin
 if not public.is_active_admin('users') then raise exception 'Admin access required'; end if;
 if _status not in ('approved','suspended','revoked') then raise exception 'Invalid status'; end if;
 update public.profiles set is_verified_seller=(_status='approved'),verification_status=_status where id=_seller;
end $$;

create or replace function public.seller_remove_listing(_listing uuid,_action text,_reason text default '')
returns void language plpgsql security definer set search_path=public
as $$
declare l public.listings%rowtype;
begin
 if auth.uid() is null then raise exception 'Login required'; end if;
 if _action not in ('hide','restore','delete') then raise exception 'Invalid action'; end if;
 select * into l from public.listings where id=_listing and seller_id=auth.uid() for update;
 if not found then raise exception 'You can only manage your own listings'; end if;
 insert into public.listing_moderation_history(listing_id,seller_id,actor_id,action,reason,snapshot)
 values(l.id,l.seller_id,auth.uid(),case _action when 'hide' then 'seller_hide' when 'restore' then 'seller_restore' else 'seller_delete' end,left(coalesce(_reason,''),500),to_jsonb(l));
 if _action='delete' then
   update public.listing_promotions set status='cancelled',admin_note='Listing deleted by seller' where listing_id=l.id and status in ('pending','approved');
   update public.listings set status='hidden' where id=l.id;
 elsif _action='hide' then
   update public.listings set status='hidden' where id=l.id;
 else
   update public.listings set status='approved' where id=l.id and status='hidden';
 end if;
end $$;

create or replace function public.admin_moderate_listing(_listing uuid,_action text,_reason text default '')
returns void language plpgsql security definer set search_path=public
as $$
declare l public.listings%rowtype;
begin
 if not public.is_active_admin('listings') then raise exception 'Admin listing permission required'; end if;
 if _action not in ('hide','restore','delete') then raise exception 'Invalid action'; end if;
 select * into l from public.listings where id=_listing for update;
 if not found then raise exception 'Listing not found'; end if;
 insert into public.listing_moderation_history(listing_id,seller_id,actor_id,action,reason,snapshot)
 values(l.id,l.seller_id,auth.uid(),case _action when 'hide' then 'admin_hide' when 'restore' then 'admin_restore' else 'admin_delete' end,left(coalesce(_reason,''),500),to_jsonb(l));
 if _action='delete' then
   update public.listing_promotions set status='cancelled',admin_note='Listing removed by admin; refund decision is manual' where listing_id=l.id and status in ('pending','approved');
   update public.listings set status='hidden' where id=l.id;
 elsif _action='hide' then
   update public.listing_promotions set status='cancelled',admin_note='Listing hidden by admin; refund decision is manual' where listing_id=l.id and status='approved';
   update public.listings set status='hidden' where id=l.id;
 else update public.listings set status='approved' where id=l.id and status='hidden';
 end if;
end $$;

alter table public.seller_verification_settings enable row level security;
alter table public.seller_verification_applications enable row level security;
alter table public.promotion_packages enable row level security;
alter table public.promotion_payment_methods enable row level security;
alter table public.listing_promotions enable row level security;
alter table public.listing_moderation_history enable row level security;
drop policy if exists verification_settings_read on public.seller_verification_settings;
create policy verification_settings_read on public.seller_verification_settings for select to authenticated using(true);
drop policy if exists verification_apps_read on public.seller_verification_applications;
create policy verification_apps_read on public.seller_verification_applications for select to authenticated using(seller_id=auth.uid() or public.is_active_admin('users'));
drop policy if exists promo_packages_read on public.promotion_packages;
create policy promo_packages_read on public.promotion_packages for select to anon,authenticated using(true);
drop policy if exists promo_methods_read on public.promotion_payment_methods;
create policy promo_methods_read on public.promotion_payment_methods for select to anon,authenticated using(true);
drop policy if exists promotions_read on public.listing_promotions;
create policy promotions_read on public.listing_promotions for select to authenticated using(seller_id=auth.uid() or public.is_active_admin('listings') or public.is_active_admin('payments'));
drop policy if exists moderation_history_read on public.listing_moderation_history;
create policy moderation_history_read on public.listing_moderation_history for select to authenticated using(seller_id=auth.uid() or public.is_active_admin('listings'));

grant select on public.seller_verification_settings,public.seller_verification_applications,public.promotion_packages,public.promotion_payment_methods,public.listing_promotions,public.listing_moderation_history to authenticated;
grant select on public.promotion_packages,public.promotion_payment_methods to anon;
grant execute on function public.apply_seller_verification(text) to authenticated;
grant execute on function public.admin_review_seller_verification(uuid,text,text) to authenticated;
grant execute on function public.admin_set_seller_verification(uuid,text) to authenticated;
grant execute on function public.seller_remove_listing(uuid,text,text) to authenticated;
grant execute on function public.admin_moderate_listing(uuid,text,text) to authenticated;

commit;


drop policy if exists listings_insert_own on public.listings;
create policy listings_insert_own on public.listings for insert to authenticated
with check(seller_id=auth.uid() and (status='pending' or (status='approved' and public.is_verified_seller(auth.uid()))));
drop policy if exists verification_settings_admin_update on public.seller_verification_settings;
create policy verification_settings_admin_update on public.seller_verification_settings for update to authenticated using(public.is_active_admin('users')) with check(public.is_active_admin('users'));
drop policy if exists verification_apps_admin_update on public.seller_verification_applications;
create policy verification_apps_admin_update on public.seller_verification_applications for update to authenticated using(public.is_active_admin('users')) with check(public.is_active_admin('users'));
drop policy if exists promotions_seller_insert on public.listing_promotions;
create policy promotions_seller_insert on public.listing_promotions for insert to authenticated with check(
 seller_id=auth.uid() and status='pending' and starts_at is null and expires_at is null
 and exists(select 1 from public.listings l where l.id=listing_id and l.seller_id=auth.uid() and l.status='approved')
 and exists(select 1 from public.promotion_packages p where p.code=package_code and p.is_enabled and p.price_pkr=amount_pkr)
);
drop policy if exists promotions_admin_update on public.listing_promotions;
create policy promotions_admin_update on public.listing_promotions for update to authenticated using(public.is_active_admin('payments')) with check(public.is_active_admin('payments'));
drop policy if exists promo_packages_admin_update on public.promotion_packages;
create policy promo_packages_admin_update on public.promotion_packages for update to authenticated using(public.is_active_admin('payments')) with check(public.is_active_admin('payments'));
drop policy if exists promo_methods_admin_update on public.promotion_payment_methods;
create policy promo_methods_admin_update on public.promotion_payment_methods for update to authenticated using(public.is_active_admin('payment_settings') or public.is_active_admin('payments')) with check(public.is_active_admin('payment_settings') or public.is_active_admin('payments'));

create or replace function public.admin_set_promotion_status(_promotion uuid,_status text,_note text default '')
returns void language plpgsql security definer set search_path=public
as $$
declare pr public.listing_promotions%rowtype; pkg public.promotion_packages%rowtype;
begin
 if not public.is_active_admin('payments') then raise exception 'Admin payment permission required'; end if;
 if _status not in ('approved','rejected','cancelled') then raise exception 'Invalid status'; end if;
 select * into pr from public.listing_promotions where id=_promotion for update;
 if not found then raise exception 'Promotion not found'; end if;
 if _status='approved' then
  select * into pkg from public.promotion_packages where code=pr.package_code;
  update public.listing_promotions set status='approved',starts_at=now(),expires_at=now()+make_interval(hours=>pkg.duration_hours),
   reviewed_by=auth.uid(),reviewed_at=now(),admin_note=left(coalesce(_note,''),1000) where id=_promotion;
 else
  update public.listing_promotions set status=_status,reviewed_by=auth.uid(),reviewed_at=now(),admin_note=left(coalesce(_note,''),1000) where id=_promotion;
 end if;
end $$;
grant execute on function public.admin_set_promotion_status(uuid,text,text) to authenticated;

create or replace function public.expire_listing_promotions()
returns integer language plpgsql security definer set search_path=public
as $$ declare n integer; begin
 update public.listing_promotions set status='expired' where status='approved' and expires_at<=now();
 get diagnostics n=row_count; return n;
end $$;


-- Private promotion receipts bucket; receipts remain private and admin-only.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('promotion-receipts','promotion-receipts',false,6291456,array['image/jpeg','image/png','image/webp'])
on conflict(id) do nothing;
drop policy if exists promotion_receipt_upload_own on storage.objects;
create policy promotion_receipt_upload_own on storage.objects for insert to authenticated
with check(bucket_id='promotion-receipts' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists promotion_receipt_read_allowed on storage.objects;
create policy promotion_receipt_read_allowed on storage.objects for select to authenticated
using(bucket_id='promotion-receipts' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_active_admin('payments')));


create or replace view public.active_listing_promotions as
 select listing_id,expires_at from public.listing_promotions
 where status='approved' and expires_at>now();
grant select on public.active_listing_promotions to anon,authenticated;
grant insert on public.listing_promotions to authenticated;
grant update on public.seller_verification_settings,public.seller_verification_applications,public.promotion_packages,public.promotion_payment_methods,public.listing_promotions to authenticated;

alter table public.seller_verification_contacts enable row level security;
drop policy if exists verification_contact_owner_read on public.seller_verification_contacts;
create policy verification_contact_owner_read on public.seller_verification_contacts for select to authenticated
using(seller_id=auth.uid() or public.is_active_admin('users'));
drop policy if exists verification_contact_owner_insert on public.seller_verification_contacts;
create policy verification_contact_owner_insert on public.seller_verification_contacts for insert to authenticated
with check(seller_id=auth.uid());
drop policy if exists verification_contact_owner_update on public.seller_verification_contacts;
create policy verification_contact_owner_update on public.seller_verification_contacts for update to authenticated
using(seller_id=auth.uid()) with check(seller_id=auth.uid());
grant select,insert,update on public.seller_verification_contacts to authenticated;


create or replace function public.admin_seller_verification_history()
returns table(seller_id uuid,successful_deals bigint,total_deals bigint,open_complaints bigint)
language plpgsql stable security definer set search_path=public
as $$
begin
 if not public.is_active_admin('users') then raise exception 'Admin users permission required'; end if;
 return query
 select p.id,
  (select count(*) from public.orders o where o.seller_id=p.id and o.status='completed'),
  (select count(*) from public.orders o where o.seller_id=p.id),
  (select count(*) from public.deal_reports r join public.orders o on o.id=r.order_id where o.seller_id=p.id and r.resolved=false)
 from public.profiles p
 where exists(select 1 from public.seller_verification_applications a where a.seller_id=p.id);
end $$;
grant execute on function public.admin_seller_verification_history() to authenticated;

-- Tighten promotion submissions: payment method must be enabled and receipt path must belong to seller.
drop policy if exists promotions_seller_insert on public.listing_promotions;
create policy promotions_seller_insert on public.listing_promotions for insert to authenticated with check(
 seller_id=auth.uid() and status='pending' and starts_at is null and expires_at is null
 and (storage.foldername(receipt_path))[1]=auth.uid()::text
 and exists(select 1 from public.listings l where l.id=listing_id and l.seller_id=auth.uid() and l.status='approved')
 and exists(select 1 from public.promotion_packages p where p.code=package_code and p.is_enabled and p.price_pkr=amount_pkr)
 and exists(select 1 from public.promotion_payment_methods m where m.code=payment_method and m.is_enabled)
);

revoke all on function public.expire_listing_promotions() from public;
grant execute on function public.expire_listing_promotions() to authenticated;
