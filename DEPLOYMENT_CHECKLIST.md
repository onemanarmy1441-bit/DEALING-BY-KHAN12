# Deployment checklist

- [ ] Create a new Supabase project.
- [ ] Run all of `supabase/schema.sql` once in SQL Editor.
- [ ] Copy the project URL and publishable/anon key into `public/config.js`.
- [ ] Upload the whole project to GitHub, keeping `public/` and `supabase/` folders.
- [ ] Import the repository into Vercel (Framework: Other, Build command: empty, Output directory: `public`).
- [ ] In Supabase Authentication → URL Configuration, set Site URL and Redirect URLs to the deployed Vercel URL.
- [ ] Sign up the owner account and confirm email if required.
- [ ] Promote owner account to `super_admin` using the SQL in README.
- [ ] Configure JazzCash and Easypaisa details in Admin → Payment Settings.
- [ ] Confirm homepage appearance and support contact numbers.
- [ ] Test signup/login, listing upload, admin approval, buyer checkout, receipt access, payment approval, deal chat, Gmail transfer and review.
- [ ] Do not accept real payments until all tests pass.
