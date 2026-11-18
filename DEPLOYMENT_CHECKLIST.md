# Existing deployment update checklist

- [ ] Back up the existing GitHub repository and production Supabase database.
- [ ] Keep the same GitHub repository and Vercel project.
- [ ] Keep `public/config.js` and existing Supabase keys unchanged.
- [ ] Review `supabase/migrations/20261119_marketplace_features.sql`.
- [ ] Run that additive migration once on the SAME Supabase project only.
- [ ] Do NOT run `supabase/schema.sql` as a fresh setup.
- [ ] Verify RLS for wishlist, notifications and withdrawal requests.
- [ ] Test buyer, seller, admin and suspended-account flows with test users.
- [ ] Confirm manual withdrawal review and payment status notifications.
- [ ] Do not launch Gmail password collection until credential storage is redesigned securely.
- [ ] Run `node --check public/app.js` and `node --check public/config.js`.
- [ ] Deploy to the existing Vercel project and smoke-test all routes.


### Marketplace / Wishlist / Notifications repair
- Keep the existing `public/config.js` and existing Supabase project unchanged.
- If `20261119_marketplace_features.sql` has not been run, run it first in the existing project's Supabase SQL Editor.
- Then run `20261120_marketplace_wishlist_notifications_grants.sql`. This grants the signed-in API role the minimum table operations used by Wishlist and Notifications; RLS policies still enforce per-user access.
- Do not run `supabase/schema.sql` as a fresh setup and do not rotate or replace existing keys for this repair.

## Latest update: Admin full color control
- [ ] Deploy the updated project files to the existing GitHub repository.
- [ ] In the existing Supabase SQL Editor, run only `supabase/migrations/20261123_admin_full_color_control.sql`.
- [ ] Do not rerun `supabase/schema.sql` on the existing project.
- [ ] Sign in with an Admin account that has the `appearance` permission.
- [ ] Open Admin → Appearance, choose colors, and press Save All Colors & Appearance.
- [ ] Refresh the public website and confirm the selected palette is applied.

## Additional order/refund update
Run `supabase/migrations/20261124_order_integrity_refunds.sql` in the existing Supabase SQL Editor after the earlier additive migrations. This adds a server-side price/seller integrity check and manual refund status. Refund money must still be transferred manually by an authorized Admin; the website does not move money automatically.

## Additional order/refund update
Run `supabase/migrations/20261124_order_integrity_refunds.sql` in the existing Supabase SQL Editor after the earlier additive migrations. This adds a server-side price/seller integrity check and manual refund status. Refund money must still be transferred manually by an authorized Admin; the website does not move money automatically.
