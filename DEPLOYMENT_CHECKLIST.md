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
