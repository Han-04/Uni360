# Supabase account setup

The Uni360 project is configured in this workspace. The account migration and all three test accounts have been applied. Use `config/supabase.test-accounts.local.json` for the temporary test credentials. The setup steps below are for a new environment.

Use a development Supabase project for the three test accounts. Each person has one row in `public.account`, keyed by the corresponding `auth.users.id`. Supabase Auth owns email addresses and passwords. `public.account` stores the employee ID, full name, phone, role, active flag and creation timestamp.

## Create the table

Open **SQL Editor → New query** in the Uni360 project. Paste and run [the account migration](../supabase/migrations/20261110000000_create_account.sql). The migration creates the `super_administrator`, `administrator` and `worker` roles and enables row level security. An active signed-in user can read their own row and update their name and phone. Role, employee ID and active status are managed by a trusted operator. Deactivate an account by setting `is_active` to `false`.

## Create test users

In **Authentication → Users → Add user → Create new user**, add one user per row below. Set a unique temporary password for each and enable **Auto Confirm User**. Supabase Auth stores the passwords.

| Test email | Employee ID | Role |
| --- | --- | --- |
| `super-admin@uni360.example` | `SA-2026-001` | Super Administrator |
| `admin@uni360.example` | `ADM-2026-001` | Administrator |
| `worker@uni360.example` | `EMP-2026-001` | Worker |

Run [the test account seed](../supabase/seed_test_accounts.sql) in SQL Editor. It associates those confirmed Auth users with their three roles in `public.account`. If you chose different emails, edit the seed first. The seed can be rerun and leaves existing account details and roles in place. It rolls back if any user is missing or has a conflicting role, employee ID or active status.

## Connect the Android app

1. Copy `config/supabase.example.json` to `config/supabase.json`.
2. From the project’s **Connect** panel, copy the project URL and the **publishable** key (`sb_publishable_…`) into that file. Use the client key here. Keep secret and service-role keys on trusted servers.
3. Run `./tool/run_worker_android.ps1` in PowerShell, or run the following on a connected Android phone or emulator.

```sh
flutter pub get
flutter devices
flutter run -d <android-device-id> --dart-define-from-file=config/supabase.json
```

In Android Studio, add `--dart-define-from-file=config/supabase.json` to the Flutter run configuration's additional run arguments. A rebuilt APK also needs the same `--dart-define-from-file` flag.

Workers sign in on mobile to open the preventive task workspace. Administrators and Super Administrators sign in to the [desktop portal](admin-portal.md). Worker contact and password changes go to Supabase. The mobile app signs out after 15 minutes of inactivity and requires fresh sign-in after a restart.
