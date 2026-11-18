# Hubby Khan Dealing Hub — Existing Project Update

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
5. Confirm the new tables and RLS policies, then test with buyer, seller and admin accounts.

## Important security limitation

The original project stores the submitted Gmail password in `listing_credentials`. This update does not make that legacy credential flow safe or encrypted. Do not collect personal email passwords or launch account-credential delivery until a server-side encrypted vault and strict access controls have been implemented and reviewed. Never place Supabase service-role keys in browser code.

## Validation

Run `node --check public/app.js` and `node --check public/config.js`. A successful syntax check does not replace a live smoke test. Live Supabase and Vercel access is not available during this local package update, so verify the deployed app using the existing accounts and data before accepting transactions.
