# Hubby Dealing Hub — Fresh Rebuild

A new, lightweight static web app rebuilt from the original Hubby Dealing Hub feature set. It uses plain JavaScript modules, Supabase Auth, Supabase Database, and Supabase Storage. There is no SSR server or Node build step, so deployment is simpler and the site does not depend on the old TanStack Start runtime.

## Features included

- Free Fire marketplace with listing search, filters, sorting, photos, seller names and prices
- Email/password signup and login
- Seller listing submission, up to six images, Gmail transfer details and admin approval queue
- Buyer checkout with JazzCash/Easypaisa selection and payment screenshot upload
- Buyer/seller order history and statuses
- Deal chat after admin payment approval, shared Gmail-transfer checklist, buyer Gmail delivery, reports and reviews
- Public seller storefront, profile photo, cover photo, bio, seller ratings and completed-sale stats
- Admin dashboard: sell requests, payments/orders, deal chats, payment settings, appearance, all listings/credentials, users and admin team permissions
- Offline rules-based Hubby AI helper and WhatsApp support links
- Dark/light appearance preference controlled from Admin → Appearance

## 1. Create a new Supabase project

1. Open [Supabase](https://supabase.com/dashboard) and create a **new project**.
2. Choose a strong database password and save it somewhere safe.
3. Wait until the project is ready.
4. Open **SQL Editor → New query**.
5. Open `supabase/schema.sql`, copy the complete contents, paste into SQL Editor, and click **Run**.
6. Open **Project Settings → API** (or API Keys) and copy the Project URL and the publishable/anon key.
7. After deploying, open **Authentication → URL Configuration** in Supabase. Set **Site URL** to your Vercel URL and add that URL (plus `http://localhost:8000` for local testing) to **Redirect URLs**.
8. Edit `public/config.js` and replace `YOUR-PROJECT-REF` and `YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY` with those values.

Only the Supabase publishable/anon key belongs in `public/config.js`. It is designed for browser use and protected by Row Level Security. **Never put the `service_role` key in `public/config.js`, HTML, JavaScript, or GitHub.** This project does not need a service-role key in the browser.

## 2. Create the first Super Admin

1. Deploy the website (or run it locally) and open `/auth`.
2. Sign up using the email address that should own the website.
3. If Supabase email confirmation is enabled, confirm the email and then log in.
4. In Supabase, open **SQL Editor** and run this query after replacing the email with your exact owner email:

```sql
insert into public.admin_members(user_id,email,role,permissions,is_active)
select id,email,'super_admin',array['*']::text[],true
from auth.users
where lower(email)=lower('YOUR_OWNER_EMAIL@example.com')
on conflict(user_id) do update
set role='super_admin',permissions=array['*']::text[],is_active=true;
```

5. Refresh the website and open `/admin`.
6. In Admin Team, another person must first register a normal account. Then add their email, role and permissions.

Admin changes are checked by SQL functions and Row Level Security, not just by hiding controls in the browser.

## 3. Deploy — easiest option: Vercel

1. Create a GitHub account if needed.
2. Create a new repository, for example `hubby-dealing-hub`.
3. Upload the contents of this folder to the repository root (not the parent folder).
4. Open [Vercel New Project](https://vercel.com/new), connect GitHub, and import the repository.
5. Framework preset: **Other**. Build command: leave empty. Output directory: `public`.
6. Deploy. `vercel.json` sends app routes back to `index.html` so direct links such as `/buy/id` and `/admin` load correctly.

No environment variables are needed in Vercel for this static build because the public Supabase URL and publishable/anon key are in `public/config.js`. If you prefer Vercel environment variables, a Vite build-based setup is required; do not paste a service-role key into this static app.

## 4. Local preview

Because this is a browser-module app, serve the folder over HTTP rather than opening `index.html` directly. For example, with Python installed:

```bash
cd public
python -m http.server 8000
```

Then open `http://localhost:8000`.

## Important security notes

- `public/config.js` contains only the public publishable/anon key. Row Level Security protects database operations.
- Payment account numbers and titles are initially blank. The Super Admin must configure them in Admin → Payment Settings before accepting payments.
- Gmail account credentials are sensitive. They are stored in Supabase and access is restricted to the seller, an eligible buyer after payment approval, and authorized admins. Use this feature only for accounts you are authorized to transfer. Buyers should change passwords and recovery methods immediately after transfer.
- Payment screenshot storage is private. Admins with payment permissions and the uploading buyer can access receipts.
- The Hubby AI helper is local rules-based help, not a generative AI model and not a website/code repair agent.
- The included WhatsApp contact numbers are carried over from the supplied project. Change them in `app.js` if the support numbers have changed.

## Testing note

This project was created as a static app to avoid the previous server-rendering deployment path. The source files are checked for JavaScript syntax before release, but a live Supabase project and Vercel deployment are not available from this workspace. Complete the new Supabase setup and test signup, listing submission, payment screenshot, admin approval, deal chat and credential delivery before accepting real payments.
