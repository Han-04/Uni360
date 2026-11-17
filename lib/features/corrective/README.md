# Corrective Maintenance

Uni360 opens **Campus operations** after sign-in. A Reporter can submit faults and track their own reports. A Worker can complete corrective assignments and open the existing Preventive work orders. Administrators can open the Corrective command centre or the existing Preventive desktop portal.

## Supabase and device setup

1. For a new database, apply the migrations in order through the [report requirements migration](../../../supabase/migrations/20261112030000_corrective_report_requirements.sql). The Corrective app reads the `maintenance_api` views, the public incident table and RPCs, and the shared notification Realtime feed.
2. Sign in as a Super Administrator or as an Administrator assigned to the facility's campus zone. Use the existing Preventive portal to manage shared campus locations, workforce profiles and shifts.
3. In **Corrective Maintenance**, open **Facility check-in settings**. Select the exact facility, save its GPS coordinates and radius, and display its generated QR code at the site. Reporter QR scans and technician check-ins resolve to the same location. Reporters can also select a location manually.
4. For Reporter self-registration, enable email confirmation and use a TAR UMT campus address. For recovery, allow the app's exact redirect in Supabase Auth. On mobile the callback is `com.example.uni360://auth/callback?uni360_recovery=1`. On web it is the exact address of the running app with `?uni360_recovery=1` appended. Open a recovery link on the same device and browser or app that requested it.

## Supervisor walkthrough

1. In **Campus operations**, show the Corrective and Preventive workspaces. On mobile, sign in as a Reporter, scan the registered facility QR or select its location, describe a burst pipe, attach a photo and review the submission.
2. In the desktop Corrective command centre, open **Intake review**. Inspect the submitted details and photo, suggested category, model confidence, suggested priority and potential duplicates. Confirm the category and one of **Low**, **Medium**, **High** or **Critical**, then approve the report. The administrator can also ask for information, request an inspection, reject the intake or merge a duplicate.
3. Open **Needs dispatch** and assign the recommended eligible worker or select another candidate. Routing uses the shared role, skills, active shift, zone and workload, and checks Preventive schedule conflicts. If the selected facility has no eligible worker, dispatch escalates the case.
4. On the worker's phone, accept the assignment, verify GPS and the facility QR, start the timer and complete the checklist. Capture a completion photo, add notes and submit the repair.
5. In **Evidence review**, review the visit and close the case or request rework. Show the Reporter's notification and feedback, then download the case PDF from the desktop case view. The PDF includes the visit notes, evidence counts and audit history.

Supabase stores the case, audit history, notifications and private evidence. The triage model compares report text with labelled example descriptions. Its confidence represents the relative weight of matching examples. Photo exposure and contrast checks and visual similarity help administrators review evidence and possible duplicates. Android voice input uses the device's system speech recognizer. Notifications are delivered in-app.

## Verify

Run [verify_corrective_maintenance.sql](../../../supabase/verify_corrective_maintenance.sql) in Supabase SQL Editor after deployment. It checks QR lookup, required evidence, pending edits and withdrawals, triage, role-based access, intake approval, dispatch, check-in, closure, archive and linked-case feedback. Test fixtures are rolled back.

See the [Chapter 3 and Chapter 4 coverage](../../../docs/corrective-report-coverage.md) for requirement mapping and verification boundaries.

Use `flutter test` to exercise app navigation and approval flows. Test email delivery, deep links, microphone, GPS, scanning and camera uploads on a real device before the demo.
