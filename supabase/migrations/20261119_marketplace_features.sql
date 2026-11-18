-- ADDITIVE migration for the existing Hubby Dealing Hub Supabase project.
-- Do NOT run schema.sql as a fresh setup. Back up the database first.
-- This migration only adds tables/columns/policies/functions; it does not drop existing data.

create extension if not exists pgcrypto;

alter table public.listings add column if not exists category text not null default 'Other';
alter table public.listings add column if not exists rank_label text not null default '';
alter table public.profiles add column if not exists account_status text not null default 'active';

create table if not exists public.wishlists (
  user_id uuid not null references public.profiles(id) on delete cascade,
  listing_id uuid not null references public.listings(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_id, listing_id)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null default '',
  related_order_id uuid references public.orders(id) on delete set null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_created_idx on public.notifications(user_id, created_at desc);

create table if not exists public.withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount integer not null check(amount >= 100 and amount <= 10000000),
  method text not null check(method in ('jazzcash','easypaisa')),
  account_title text not null check(char_length(account_title) between 2 and 100),
  account_number text not null check(char_length(account_number) between 5 and 40),
  status text not null default 'pending' check(status in ('pending','approved','rejected','paid')),
  admin_note text not null default '',
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists withdrawal_requests_user_idx on public.withdrawal_requests(user_id, created_at desc);

create table if not exists public.seller_follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(follower_id,seller_id),
  check(follower_id <> seller_id)
);

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check(char_length(title) between 2 and 120),
  body text not null default '' check(char_length(body) <= 1000),
  is_active boolean not null default true,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.admin_activity_logs (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_type text not null default '',
  target_id text not null default '',
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists admin_activity_logs_created_idx on public.admin_activity_logs(created_at desc);

alter table public.wishlists enable row level security;
alter table public.notifications enable row level security;
alter table public.withdrawal_requests enable row level security;
alter table public.seller_follows enable row level security;
alter table public.announcements enable row level security;
alter table public.admin_activity_logs enable row level security;

-- Idempotent policies for newly added tables.
drop policy if exists wishlist_owner_all on public.wishlists;
create policy wishlist_owner_all on public.wishlists for all to authenticated
using(user_id = auth.uid()) with check(user_id = auth.uid());

drop policy if exists notifications_owner_read on public.notifications;
create policy notifications_owner_read on public.notifications for select to authenticated using(user_id = auth.uid());
drop policy if exists notifications_owner_update on public.notifications;
create policy notifications_owner_update on public.notifications for update to authenticated using(user_id = auth.uid()) with check(user_id = auth.uid());
drop policy if exists notifications_admin_insert on public.notifications;
create policy notifications_admin_insert on public.notifications for insert to authenticated with check(public.is_active_admin('users') or public.is_active_admin('payments') or public.is_active_admin('deals'));

drop policy if exists withdrawals_owner_read on public.withdrawal_requests;
create policy withdrawals_owner_read on public.withdrawal_requests for select to authenticated using(user_id = auth.uid() or public.is_active_admin('payments'));
drop policy if exists withdrawals_owner_insert on public.withdrawal_requests;
create policy withdrawals_owner_insert on public.withdrawal_requests for insert to authenticated with check(user_id = auth.uid() and status = 'pending');
drop policy if exists withdrawals_admin_update on public.withdrawal_requests;
create policy withdrawals_admin_update on public.withdrawal_requests for update to authenticated using(public.is_active_admin('payments')) with check(public.is_active_admin('payments'));

drop policy if exists seller_follows_owner_all on public.seller_follows;
create policy seller_follows_owner_all on public.seller_follows for all to authenticated using(follower_id = auth.uid()) with check(follower_id = auth.uid());

drop policy if exists announcements_public_read on public.announcements;
create policy announcements_public_read on public.announcements for select to anon,authenticated using(is_active = true and starts_at <= now() and (ends_at is null or ends_at > now()));
drop policy if exists announcements_admin_manage on public.announcements;
create policy announcements_admin_manage on public.announcements for all to authenticated using(public.is_active_admin('appearance')) with check(public.is_active_admin('appearance'));

drop policy if exists activity_logs_admin_read on public.admin_activity_logs;
create policy activity_logs_admin_read on public.admin_activity_logs for select to authenticated using(public.is_active_admin('users'));
drop policy if exists activity_logs_admin_insert on public.admin_activity_logs;
create policy activity_logs_admin_insert on public.admin_activity_logs for insert to authenticated with check(public.is_active_admin('users'));

-- Notify buyer and seller when an order is created or its status changes.
create or replace function public.notify_order_parties()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  _title text;
  _body text;
begin
  if tg_op = 'INSERT' then
    _title := 'Order received';
    _body := 'Your order has been created and is awaiting payment review.';
  elsif new.status is distinct from old.status then
    _title := 'Order status updated';
    _body := 'Your order status is now: ' || replace(new.status, '_', ' ');
  else
    return new;
  end if;
  insert into public.notifications(user_id,title,body,related_order_id)
  values(new.buyer_id,_title,_body,new.id);
  if new.seller_id is distinct from new.buyer_id then
    insert into public.notifications(user_id,title,body,related_order_id)
    values(new.seller_id,_title,_body,new.id);
  end if;
  return new;
end; $$;
drop trigger if exists orders_notify_parties on public.orders;
create trigger orders_notify_parties after insert or update of status on public.orders
for each row execute function public.notify_order_parties();

-- Stop suspended accounts from creating new orders/listings through normal app flows.
create or replace function public.block_suspended_marketplace_actions()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if exists(select 1 from public.profiles p where p.id = auth.uid() and p.account_status <> 'active') then
    raise exception 'This account is currently restricted. Contact support.';
  end if;
  return new;
end; $$;
drop trigger if exists listings_block_suspended on public.listings;
create trigger listings_block_suspended before insert on public.listings for each row execute function public.block_suspended_marketplace_actions();
drop trigger if exists orders_block_suspended on public.orders;
create trigger orders_block_suspended before insert on public.orders for each row execute function public.block_suspended_marketplace_actions();

-- Seller may remove only their own still-pending listing. Approved/sold records remain auditable.
drop policy if exists listings_delete_own_pending on public.listings;
create policy listings_delete_own_pending on public.listings for delete to authenticated
using(seller_id = auth.uid() and status in ('pending','rejected'));

-- Admin-only account status change; does not delete the user or their history.
create or replace function public.admin_set_user_status(_user_id uuid, _status text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_active_admin('users') then raise exception 'Not authorized'; end if;
  if _status not in ('active','suspended') then raise exception 'Invalid account status'; end if;
  update public.profiles set account_status=_status where id=_user_id;
  insert into public.admin_activity_logs(admin_id,action,target_type,target_id,details)
  values(auth.uid(),'user_status_changed','profile',_user_id::text,jsonb_build_object('status',_status));
end; $$;
revoke all on function public.admin_set_user_status(uuid,text) from public;
grant execute on function public.admin_set_user_status(uuid,text) to authenticated;

-- Manual migration review checklist: confirm existing policies and bucket names before launch.

-- Prevent a normal user from changing their own suspension flag through the existing
-- profiles_update_own policy. Only an admin action may alter account_status.
create or replace function public.protect_profile_account_status()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.account_status is distinct from old.account_status
     and not public.is_active_admin('users') then
    raise exception 'Only an authorized admin can change account status';
  end if;
  return new;
end; $$;
drop trigger if exists profiles_protect_account_status on public.profiles;
create trigger profiles_protect_account_status before update of account_status on public.profiles
for each row execute function public.protect_profile_account_status();
