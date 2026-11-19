-- Permission repair for the existing Supabase project. Safe to run more than once.
-- Run after 20261119_marketplace_features.sql if that migration has not yet been applied.
-- No tables, users, keys, or existing records are dropped or reset.

grant select, insert, delete on public.wishlists to authenticated;
grant select, update on public.notifications to authenticated;
