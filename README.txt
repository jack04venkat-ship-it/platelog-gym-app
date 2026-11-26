PlateLog - Supabase setup

1. Create a Supabase project.
2. In the Supabase SQL Editor, run the full contents of supabase-setup.sql.
3. In Project Settings > API, copy the Project URL and publishable key.
   The older anon/public key also works. Never use the service_role key here.
4. The current project URL and publishable key are already configured near
   the top of index.html. If you connect a different project later, replace
   those two values there.
5. In Supabase Authentication > URL Configuration, set the Site URL to this
   app URL and add it to the Redirect URLs list:
   https://jack04venkat-ship-it.github.io/platelog-gym-app/
6. Publish the updated files to GitHub Pages.

Users sign up as a trainer, then add a client and share the invite code.
Clients create an account with that invite code. Workout, food, and progress
data is then shared through Supabase with row-level security enabled.

Existing browser-only demo data is not automatically imported into Supabase.
