# Website update summary

This package keeps the existing Supabase project configuration and existing website email/password authentication.

## Included in this update
- Buyer/seller profile editing: display name, bio, profile photo, and cover photo.
- Existing marketplace, wishlist, notifications, admin dashboard, seller/buyer deal chat, handover checklist, and deal-report/complaint workflow retained.
- Admin appearance panel now includes global color controls for website background, panels/header, cards, main text, secondary text, borders, primary buttons/glow, accent highlights, success states, and error/rejected states.
- Admin can choose Dark/Light mode, update brand name and homepage text, and update logo/banner.
- Admin can restore the default color palette.
- Existing Free Fire linked Gmail/password fields are not part of the seller listing form; the deal chat is for coordination, and the site warns users never to share personal email passwords or OTPs.
- Seller city/area and an optional private game-account proof image are stored separately from public listings; RLS and a private storage bucket restrict proof access to authorized Admins. The form discourages entering an exact home address or uploading face photos, identity documents, personal Gmail details, or OTPs.

## Required database step for full color control
Run only `supabase/migrations/20261123_admin_full_color_control.sql` in the existing Supabase SQL Editor. This is an additive migration and does not create a new Supabase project or replace existing data. Do not rerun `supabase/schema.sql` on the existing project.

The global palette is saved through an admin-only database function and is visible to all site visitors after refresh.

## Validation
- JavaScript syntax check passed with Node.js.
- Supabase live integration and real user/admin permissions have not been tested from this package; test on a preview deployment before production use.
- Added manual refund tracking: Admin can mark a rejected order as refunded only after sending the money through the original payment method. Refunds are not automatic.
- Added a database-side order integrity trigger so the actual listing price and seller ID are taken from the approved listing, not trusted from browser form values.
- Profile photo upload now exposes separate Gallery and Camera choices.
- Added manual refund tracking: Admin can mark a rejected order as refunded only after sending the money through the original payment method. Refunds are not automatic.
- Added a database-side order integrity trigger so the actual listing price and seller ID are taken from the approved listing, not trusted from browser form values.
- Profile photo upload now has separate Gallery and Camera choices.


## 19 Nov 2026 feature additions
- Seller verification application flow with configurable deal, account-age and complaint thresholds.
- Database trigger automatically approves new listings for verified sellers.
- Paid promotion packages (24h / 3d / 7d), private receipt upload, manual admin approval and expiry.
- Configurable JazzCash, EasyPaisa and bank-transfer instructions for promotions.
- Seller-owned hide/restore/delete actions and admin moderation with reasons and audit history.
- Existing tables and data preserved; apply the new additive migration to the existing Supabase project.
