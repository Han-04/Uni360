# Preventive mobile architecture

## Scope and proposal mapping

This phase follows the attached proposal, especially account requirements 1.1–1.3, 1.13–1.14, task-verification requirements 5.1–5.12 and mobile Figures 4.19–4.27. The mobile actor there is Worker. General campus-user incident reporting belongs to the corrective subsystem.

| Area | Implemented | Deferred integration |
| --- | --- | --- |
| Account | Supabase email sign-in, three roles, active account check, sign-out, session expiry, profile edits and password changes | In-app recovery and management of other users |
| Work orders | Worker-owned lists, search, date/status filters, details, schedules and instructions | Administrator scheduling/assignments, API errors and durable offline cache |
| Verification | Haversine distance, facility radius, GPS accuracy check, matching facility/asset QR, timestamps | Device permissions, real scanner, configurable accuracy tolerance, signed/expiring QR and server validation |
| Execution | Timer, checklist, notes, session drafts, evidence metadata and submission validation | Camera-only photographs, uploads and durable persistence |
| Review | Read-only submitted work, seeded approval/rejection/rework, timeline and linked alerts | Administrator review service and push notifications |
| Rework | Retain previous capture metadata and feedback, reset checklist, require new check-in and evidence | Durable revisions and targeted rework checklist |
| Profile | Edit name/phone; protected employee ID, email, skills, zone and shift | Profile photo upload |

**Check in & start work timer** records both verified check-in and work commencement, combining the proposal’s verification and start-work screens into one explicit action. Worker submission never approves work.

## Structure and dependencies

The worker interface targets portrait phones. `PhoneViewport` wraps the entire navigator, limiting large-screen previews to 430 × 932 logical pixels while retaining the available screen space on smaller phones. `main.dart` requests portrait orientation. Use the Android launcher in `tool/run_worker_android.ps1` or select a physical Android device in the IDE.

`main.dart` initializes Supabase from the project configuration. `Uni360App` manages `AccountController` and routes workers into a workspace backed by `MockPreventiveRepository` and `MockVerificationService`. Account screens and repositories live under `shared/account`. The account setup guide describes the `public.account` migration, role policies and test accounts.

The repository is a synchronous in-memory cache interface for this phase. For a database, either implement a locally hydrated cache behind it or evolve its methods to `Future` operations with loading/error states in the controller. Keep network calls out of widgets. The asynchronous device-service contract already provides a replacement point for GPS, QR scanning and camera capture.

## Status transitions

```text
Assigned -> [valid GPS + facility QR] -> In progress
In progress -> [all checks + required captures + confirmation] -> Under review
Under review -> Completed / Rework required / Rejected       (administrator only)
Rework required -> [acknowledge] -> Assigned -> verify again -> In progress
```

Pending is represented for future scheduling but has no worker mutation. Rejected/completed tasks are read-only. Rework retains the timeline and earlier evidence metadata, clears the active checklist/evidence, and keeps administrator remarks. Resubmission adds another timeline event. These are session-only prototype records.

## Suggested database entities

Use stable IDs and UTC timestamps in storage, displaying dates in the worker’s local timezone.

- `account`: implemented. Stores role, account status, name, contact and employee ID. References `auth.users`, which owns credentials and email.
- `worker_profile`, `skill`, `worker_skill` and `worker_availability`: implemented in Supabase. Each worker profile uses its account UUID, and the employee number comes from `account.employee_id`. Assignments store certification number, expiry and verification. Availability stores shift start/end with timezone, availability and leave status. Workers can read their own data, and active Administrator and Super Administrator accounts can manage it through the Data API. Worker profile edits in the app cover personal contact details. Workforce fields appear as read-only in the worker app.
- `facilities` / `assets`: labels, coordinates, radius, accuracy tolerance and QR identity.
- `recurring_templates`: facility, frequency, skill, duration, priority, checklist and evidence requirements; administrator-owned.
- `work_orders`: template ID, worker, schedule, due time, status, revision, check-in/start/submission timestamps and notes.
- `work_order_checklist`: template snapshot, completion state, revision and timestamp.
- `check_ins`: worker, task, coordinates, accuracy, distance, QR identity and verification timestamp.
- `evidence`: task, worker, revision, private storage key, capture timestamp, coordinates and device metadata.
- `work_order_events` / `reviews`: append-only transitions, actor, decision, remarks and timestamps.
- `notifications`: recipient, linked task, type, message and read timestamp.

## Integration sequence

1. Apply the account migration and configure Supabase. Add server-side operations for the Super Administrator to manage administrators and for administrators to manage workers.
2. Implement the repository with loading/error/retry and offline/conflict handling. Enforce ownership, roles and status transitions on the backend.
3. Replace the mock device service with location/scanner/camera adapters. Handle permission denial, inaccurate/stale GPS, cancellation and unavailable hardware. Keep completion gallery import unavailable.
4. Add real evidence image references and private uploads. Validate evidence count and status transitions on the server. Never accept `isSimulated` evidence in production.
5. Persist drafts, notes, checklists and evidence revisions. The controller’s `previousEvidence` map is a temporary session archive.
6. Connect administrator review outcomes and notifications. Workers must never approve their own submissions.
7. Implement administrator scheduling, then connect corrective incidents through an explicit contract. The mobile worker app consumes assignments.

## Validation

Tests cover ownership, authentication, geofence/QR failures, verification invalidation, submission rules, immutable submissions, drafts, rework evidence retention, protected profile fields, passwords, read alerts and session expiry. Widget tests exercise navigation at 320, 390 and 600 logical pixels and the complete check-in, checklist, capture and review-submission flow.
