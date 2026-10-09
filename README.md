Swaralay Music Academy website
Static public website (`index.html`) plus a separate administrator login/dashboard (`admin.html`). No build step is required for Vercel.
Deploy on Vercel
Keep `index.html`, `admin.html`, `vercel.json`, and `schema.sql` in the repository root.
Push/commit the files to the connected GitHub branch (`main`). Vercel should deploy the new commit automatically.
Open the public site at `/` and the separate admin sign-in at `/admin` (or `/admin.html`).
Configure secure admin sign-in (required)
Create/open your Supabase project.
In Supabase Project Settings > API, copy the Project URL and the anon/publishable key. Put these into `SUPABASE_URL` and `SUPABASE_ANON_KEY` near the bottom of `admin.html`.
Never place the Supabase `service_role` key or database password in HTML, GitHub, or any browser code.
In Supabase SQL Editor, run the complete `schema.sql` file once (if its tables/policies have not already been created).
Create the administrator account in Supabase Authentication > Users (or use the supported sign-up flow). Then run this SQL with the administrator's actual email:
```sql
   update public.profiles
   set role = 'admin'
   where id = (select id from auth.users where email = 'YOUR_ADMIN_EMAIL');
   ```
Verify that exactly the intended account has the `admin` role. New accounts default to `student` in the schema. Do not make students admins.
Test `/admin`: an ordinary student account must be denied; the authorised admin account should be allowed. Supabase Row Level Security must remain enabled. The dashboard queries use the logged-in user's session and the database policies, not a password hard-coded in the page.
Important security and functionality notes
The admin route is separate from the public site and is marked `noindex`; this is not a substitute for authentication. The actual gate is Supabase Auth plus the `profiles.role = 'admin'` check and RLS policies.
The public website still contains demo-only student portal and registration interactions; they do not securely create accounts, store payment screenshots, or save records. Do not treat those demo interactions as production registration/payment processing until they are connected to Supabase with the appropriate validation and RLS policies.
The admin dashboard currently reads real records only. It does not yet perform editing, payment verification, messaging, or uploads. Those actions should be implemented with authenticated Supabase operations and server/database-side permission checks.
Static site code cannot keep credentials secret. Use only the Supabase anon/publishable key in browser code; never use the service-role key.
