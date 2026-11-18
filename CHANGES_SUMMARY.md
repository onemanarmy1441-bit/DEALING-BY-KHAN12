# Feature update — Neon Noir Marketplace

## Frontend features added
- Buyer/seller dashboard with listing, order, sale and rating summaries.
- Wishlist save/remove and saved-listings page.
- Notification center with mark-all-read.
- Seller withdrawal request form/history.
- Admin analytics overview and withdrawal review queue.
- Listing category and rank fields plus category filtering.
- About, FAQ, privacy, terms, refund and safety pages.
- Existing dark Neon Noir theme and motion styling retained.

## Additive Supabase migration
`supabase/migrations/20261119_marketplace_features.sql` adds wishlist, notifications, withdrawal requests, seller follows, announcements, admin activity logs, listing metadata and account-status support, with RLS policies and order-status notification triggers. It does not drop/recreate existing business tables.

## Preserved
- `public/config.js` remains unchanged (same existing Supabase URL/key).
- Existing `supabase/schema.sql` remains unchanged.
- Existing GitHub/Vercel project structure retained.
- No new Supabase project or API key required.

## Not fully implemented / requires separate secure backend
- Automated JazzCash/Easypaisa gateway verification (manual admin review remains).
- Real escrow/refund automation and seller payout transfer (withdrawals are requests for manual admin processing).
- Announcement publishing UI and seller-follow UI (database foundations are included).
- Full edit workflow for approved listings and advanced fraud analytics.
- Credential encryption vault. The legacy Gmail password collection/storage is not safe for production and must be replaced before accepting real credentials.

## Validation
- `node --check public/app.js` passed.
- `node --check public/config.js` passed.
- Live Supabase migration, RLS behavior and Vercel deployment were not executed here.
