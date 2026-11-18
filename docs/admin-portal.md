# Uni360 desktop administration

Open the Uni360 project root in Android Studio. Choose **Uni360 Web**, select **Chrome** in the device dropdown, and click **Run**. On the Uni360 welcome screen, select **Admin login** to open the desktop sign-in at `/#/admin`. Choose **Corrective Maintenance** in the administration sidebar to review reports. The back arrow on the sign-in page returns to the mobile login.

The configuration loads `config/supabase.json` automatically. The dashboard is a Flutter Web route. Its source is in `lib/features/preventive/admin`, and Android Studio runs it alongside the rest of Uni360.

Sign in with an existing Uni360 Administrator or Super Administrator account.

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

After editing the portal source, regenerate the embedded web assets with `npm.cmd ci --prefix admin_portal` and `npm.cmd run build:flutter --prefix admin_portal`, or use `flutter build web --dart-define-from-file=config/supabase.json`. The portal receives the Supabase project URL and publishable key from Flutter at runtime. Use the same Flutter run configuration after editing the dashboard. Corrective Maintenance uses the same desktop session as the administration portal.

The `manage-accounts` Edge Function is deployed in Uni360 Supabase. Its source is in `supabase/functions/manage-accounts/index.ts`. It checks each Auth token and the caller's current role and active status. Creation uses the server's Auth admin credential, inserts the linked account, and compensates for a failed insert by removing the newly created Auth user. New Worker records provision their workforce profile through the existing database trigger. The browser only uses the publishable key and the signed-in user's token.
