# Fresh rebuild summary

This is a ground-up implementation, not a patch of the previous React/TanStack Start source.

## New architecture

- Static HTML/CSS/JavaScript app (no SSR, no server runtime, no Node build command)
- Supabase browser client loaded as an ES module
- New consolidated Supabase schema and RLS policies in `supabase/schema.sql`
- Admin-only database operations use SECURITY DEFINER RPC functions with permission checks
- Static route fallback in `vercel.json` for direct URLs such as `/buy/<id>`, `/deal/<id>`, `/seller/<id>`, and `/admin`
- No service-role key is required or permitted in browser code

## Feature set carried forward

- Marketplace listings, search, sort, filters and listing image gallery
- Signup/login and seller profiles/storefronts
- Sell ID flow with up to six photos and linked Gmail credentials
- Admin listing approval/rejection and listing/credential review
- JazzCash/Easypaisa payment settings and buyer screenshot submission
- Admin screenshot verification, payment approval, automatic listing sold status and Gmail access release
- Buyer/seller orders, deal chat, admin chat, transfer checklist and deal reports
- Deal completion with 10% admin fee / 90% seller payout
- Buyer reviews, public seller ratings and verified-seller threshold (3 completed sales)
- Admin dashboard, permissions, team management, user list, payment settings and site appearance controls
- Hubby AI local rules helper and WhatsApp support contacts

## Reused reference assets only

The original logo/artwork and self-hosted font files are retained so the new app can keep the same visual identity. Application code and database setup have been newly authored.

## Validation performed

- `node --check public/app.js` — passed
- `node --check public/config.js` — passed
- `python -m json.tool vercel.json` — passed
- Python HTML parser on `public/index.html` — passed
- Live Supabase integration, SQL execution and Vercel deployment have not been run in this workspace; follow README and complete the checklist before accepting payments.
