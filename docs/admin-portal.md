# Uni360 desktop administration

Open the Uni360 project root in Android Studio. Choose **Uni360 Web**, select **Chrome** in the device dropdown, and click **Run**. On the Uni360 login page, select **Admin login**. The admin page opens at `/#/admin` on the current localhost port. The back arrow returns to the worker login.

The configuration loads `config/supabase.json` automatically. The dashboard is a Flutter Web route. Its source is in `lib/features/preventive/admin`, and Android Studio runs it alongside the rest of Uni360.

Sign in with an existing Uni360 account. Test credentials are in `config/supabase.test-accounts.local.json`.

| Role | Account records it can manage |
| --- | --- |
| Super Administrator | Administrators |
| Administrator | Workers |

Search by name or employee ID. Create accounts with a login email and temporary password. Edit the full name, employee ID and phone. Deactivation retains the profile and blocks its access to Uni360. The login email and role are assigned at creation.

## Workforce management

Administrators and Super Administrators can select **Workforce management**, search by worker name or employee ID, and open a worker profile. Use **Edit profile** for scheduling details, **Add Skill** to record a skill, and **Add Certifications** or **Edit certification** to manage certificates and their documents. Use **Date availability** to manage shifts and leave or see tasks for the selected day. Availability is shown in Malaysia time.

Apply `supabase/migrations/20261111000000_workforce_directory.sql` after the account and workforce migrations when setting up a new Supabase project. Workers can read their own workforce details in the mobile app.

For Android, choose **Uni360 Worker Android** with your phone or emulator selected. The Android admin page directs administrators to Uni360 on their computer.

## Run from a terminal

From the project root, run:

```powershell
flutter run -d chrome --dart-define-from-file=config/supabase.json
```

Use the same Flutter run configuration after editing the dashboard. To produce the web build, run `flutter build web --dart-define-from-file=config/supabase.json`.

The `manage-accounts` Edge Function is deployed in Uni360 Supabase. Its source is in `supabase/functions/manage-accounts/index.ts`. It checks each Auth token and the caller's current role and active status. Creation uses the server's Auth admin credential, inserts the linked account, and compensates for a failed insert by removing the newly created Auth user. New Worker records provision their workforce profile through the existing database trigger. The browser only uses the publishable key and the signed-in user's token.
