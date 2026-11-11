# Uni360 · Preventive maintenance mobile

Flutter worker app based on the proposal’s mobile designs (Figures 4.19–4.27), with a separate desktop portal for account management. See the [desktop portal guide](docs/admin-portal.md).

## Run

Developed with Flutter 3.47.5 / Dart 3.13.4. Set up the Supabase account table, test users and project configuration using the [account setup guide](docs/supabase-accounts.md).

```sh
flutter pub get
flutter devices
flutter run -d <android-device-id> --dart-define-from-file=config/supabase.json
```

The worker app is designed for **portrait Android/iOS phones**. On Windows, run `./tool/run_worker_android.ps1` to launch the available Pixel 3a emulator and open the native Android app. Alternatively, connect a phone with USB debugging, select it in Android Studio and run `lib/main.dart`. iOS builds require macOS and Xcode.

Phone screens use their available device size. On a larger display, the entire app—including navigation, dialogs and task screens—stays inside a portrait phone viewport up to 430 × 932 logical pixels.

Sign in with a confirmed Supabase Auth email and password. The account's role determines which workspace opens.

## Try the workflow

1. Open **Air-conditioning service** from Home or My tasks.
2. Select **Verify location & check in**, verify the demo location, simulate a matching QR scan, then start the work timer.
3. Complete the checklist. Open **Capture evidence** and add at least two sample captures.
4. Add notes, confirm the work, then **Submit for review**. Status becomes **Under review** until administrator approval.
5. Open the water pump task to try rework. Acknowledge it, check in again, complete the checklist and capture new evidence before resubmitting.

The verification screen includes outside-geofence and wrong-QR failure scenarios. Sample tasks demonstrate approval, rejection and review feedback. Alerts open the related task. Profile and password changes are saved in Supabase. Sessions expire after 15 minutes of inactivity.

## Folder structure

```text
lib/
  app/                         App setup, dependencies and session lifecycle
  core/
    theme/                     Shared colours and theme
    utils/                     Date/time formatting
    widgets/                   Cards, banners and empty states
  shared/account/              Supabase authentication, roles and profile screens
  features/
    preventive/
      domain/                  Models, repository and device-service contracts
      data/                    Dummy data and simulated device services
      application/             State and workflow rules
      presentation/
        screens/               Worker screens
        widgets/               Work-order cards and status indicators
    corrective/                Reserved boundary (README only)
test/                          Workflow and mobile widget tests
docs/                          Architecture and integration notes
supabase/                      Account migration and test account seed
```

## Demo boundaries

Accounts and worker scheduling profiles use Supabase. Profile → Work & skills shows saved workforce records. Use the Supabase Table Editor with project access to populate the four workforce tables, or use the Data API with an active Administrator or Super Administrator account. Preventive tasks, GPS, QR and photographic capture are simulated. Evidence is represented by metadata. Sample task changes and drafts reset on a full app restart.

There is no administrator approval button in the worker app. Approved/rejected/rework outcomes are seeded examples. Scheduling and workforce management belong to the later administrator app.

## Checks

```sh
flutter analyze
flutter test
flutter build apk --debug --dart-define-from-file=config/supabase.json
```

See [architecture and integration notes](docs/architecture.md) for database boundaries, proposal coverage and next steps.

The automated tests cover phone layouts, account routing and the complete check-in → checklist → evidence → review submission flow. Tests use a local account fixture. Build with the project configuration to test live sign-in.
