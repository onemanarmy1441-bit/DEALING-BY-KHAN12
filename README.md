# KHAN DEALING HUB — Existing Project Update

This repository update keeps the current static HTML/CSS/JavaScript application and adds a **Neon Noir** visual theme: deep black surfaces, electric violet highlights, ice-cyan accents, subtle card reveals, hover motion, a floating hero logo, and reduced-motion accessibility support. Existing marketplace behavior is retained.

## Important: update the existing deployment only

- Continue using the **same GitHub repository** and existing Vercel project.
- Continue using the **same Supabase project**, database, Auth users, Storage buckets, and policies.
- `public/config.js` is intentionally preserved. Do not replace the existing Supabase URL or publishable/anon key.
- Do **not** create a new Supabase project.
- Do **not** run `supabase/schema.sql` as a fresh setup. It is the project's schema reference, not an instruction to reset or recreate an already-running database.
- This feature update includes one additive migration at `supabase/migrations/20261119_marketplace_features.sql`. Apply it to the existing Supabase project only after taking a backup and reviewing the SQL. Do not run `supabase/schema.sql` as a fresh setup.

## Update the existing GitHub repository

1. Back up the current repository/production deployment first.
2. Replace the matching project files with the updated files from this folder, or commit the changes as a normal update to the existing branch.
3. Keep the existing `public/config.js` values and existing Vercel project settings.
4. Push to the same GitHub repository. The existing Vercel Git integration should deploy the commit automatically.
5. Check the deployed homepage, navigation, listing cards, login, seller flow, orders, deal pages, and admin pages.

## Supabase and keys

This visual update does not require Supabase setup, new API keys, new environment variables, SQL execution, or a database reset. Existing browser configuration is retained in `public/config.js`. Never expose a Supabase service-role/secret key in browser code or GitHub.

If a future feature needs a database change, create a narrowly scoped, additive migration only after checking the live schema and policies. Back up first; do not drop/recreate existing tables, policies, buckets, users, or data.

## Design notes

- Default palette: black / electric violet / ice cyan.
- Existing optional light mode remains available.
- Existing custom primary/accent colors saved in Admin → Appearance remain respected. The original default orange/gold colors are mapped to the new violet/cyan palette in the UI.
- Animations respect the operating system's `prefers-reduced-motion` setting.

## Added features in this update

- Buyer/seller dashboard with order and listing summaries.
- Wishlist save/remove and wishlist page.
- Order status notifications and notification center.
- Seller withdrawal requests and admin approval/rejection queue.
- Admin overview metrics.
- Listing category/rank fields and category filter.
- About, FAQ, privacy, terms, refund and safety information pages.
- Additive database foundations for seller follows, announcements and admin activity logs.
- Existing orders/reports remain the basis for purchase history and dispute reporting.

## Database migration

1. Back up the existing Supabase database.
2. Open Supabase SQL Editor for the SAME existing project.
3. Review and run `supabase/migrations/20261119_marketplace_features.sql` once.
4. Do not run `supabase/schema.sql`; it is the original schema reference, not a fresh-install step.
5. Run `20261121_remove_email_credentials_private_seller_area.sql` if it has not already been applied.
6. Run `20261122_seller_area_admin_only.sql` to restrict seller city/area to admins only.
7. Confirm the RLS policies, then test with buyer, seller and admin accounts.

## Important security limitation

The current listing flow does not collect Gmail addresses or passwords. The migration removes the legacy `listing_credentials` table. Never collect personal email passwords or OTPs, and never place Supabase service-role keys in browser code.

## Validation

Run `node --check public/app.js` and `node --check public/config.js`. A successful syntax check does not replace a live smoke test. Live Supabase and Vercel access is not available during this local package update, so verify the deployed app using the existing accounts and data before accepting transactions.


## Seller privacy and account handover update

The listing form does not collect a Free Fire-linked Gmail address or password. The seller city/area is stored separately and is visible only to authorized admins through row-level security; do not collect exact home addresses or live locations. Account handover should be coordinated in the approved deal chat. Never request personal email passwords or OTPs. Seller payout is an admin-managed process after deal completion; this project does not automatically transfer funds or issue refunds.

## Admin full website color control (latest update)

The Admin → Appearance tab now controls ten global palette colors: background, panels/header, cards, main text, secondary text, borders, primary buttons/glow, accent highlights, success states, and error/rejected states. Admin can also restore the default palette. Saved colors are stored in the existing `site_customization` row and shared across visitors.

Before using the new color controls, run this one additive migration in the EXISTING Supabase SQL Editor:

`supabase/migrations/20261123_admin_full_color_control.sql`

Do not create a new Supabase project and do not rerun `supabase/schema.sql` on an existing project. Existing data and email/password authentication are retained.


## DEALING BY KHAN12 feature update (19 Nov 2026)

This update is additive to the existing Supabase project. It adds seller verification applications, paid listing promotions, and seller/admin listing moderation with an audit trail.

### Important: apply the new migration to the EXISTING Supabase project

1. Open the existing Supabase project (do not create a new one).
2. Open **SQL Editor**.
3. Open and copy the complete contents of `supabase/migrations/20261125_verified_sellers_promotions_moderation.sql`.
4. Run it once in the existing project.
5. Deploy this project ZIP to the same GitHub repository / Vercel project.

Do **not** run `supabase/schema.sql` as a replacement/reset. Do not delete tables, buckets, users, or data. The new migration only adds columns, tables, functions, policies and a private receipt bucket.

### Seller verification

Default requirements are 3 completed sales, 7 days account age, completed profile (name and bio), phone number, and no open deal reports by default. Admins with `users` permission can change the deal, age and open-complaint thresholds, review applications, approve/reject, suspend, revoke or restore verification. Approved sellers receive a badge and new listings are auto-approved by a database trigger. Open deal reports are treated conservatively as complaints because the existing project does not have a separate complaint-severity field.

### Paid promotions

Default packages are 24 hours (Rs. 300), 3 days (Rs. 700), and 7 days (Rs. 1,400). Admins with `payments` permission can change prices, configure JazzCash, EasyPaisa and bank-transfer details, and manually approve/reject/cancel promotion requests. Sellers upload a receipt; payment is not automatic. A promotion starts only when an admin approves it. Expired promotions are excluded from the public featured section and are marked expired during site activity. Removing a listing cancels its promotion; refund decisions remain manual.

### Listing moderation

Sellers can hide, restore or remove their own listings from the public marketplace, hide or restore them from the dashboard. Admins with `listings` permission can hide, restore or remove any listing with a reason. Removal is archived (`hidden`) rather than physically deleting the database row, so existing order references and audit history are not destroyed. Actions are recorded in `listing_moderation_history`. Removing/hiding a promoted listing cancels the promotion; no automatic refund is promised.

### Profile phone number

Sellers can add or update their phone number under **My Profile**. It is used for verification eligibility and is not displayed as a public phone contact.

### Deployment note

Keep the existing `public/config.js` Supabase URL and anon/publishable key unchanged. Never put a Supabase service-role key in browser code.
