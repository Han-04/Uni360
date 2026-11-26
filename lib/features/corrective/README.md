# Corrective Maintenance

Uni360 opens **Campus operations** after sign-in. A Reporter can submit faults and track their own reports. A Worker can complete corrective assignments and open the existing Preventive work orders. Administrators use the **Corrective Maintenance** section in the Uni360 Administration sidebar.

## Supabase and device setup

1. For a new database, apply the migrations in order and deploy `corrective-intake` to validate attachments. The Corrective app reads the `maintenance_api` views, the public incident table and RPCs, and the shared notification Realtime feed.
2. Sign in as a Super Administrator or as an Administrator assigned to the facility's campus zone. Use the existing Preventive portal to manage shared campus locations, workforce profiles and shifts.
3. Under **Corrective Maintenance**, select **Settings**, then open **Facility check-in settings**. Search for the facility and select **Use current location** while on site, or copy a map pin from Google Maps and paste it into the form. Set the allowed check-in distance and display the generated QR code at the site. Reporter QR scans and technician check-ins resolve to the same location.
4. For Reporter self-registration, enable email confirmation and use a TAR UMT campus address. For recovery, allow the app's exact redirect in Supabase Auth. On mobile the callback is `com.example.uni360://auth/callback?uni360_recovery=1`. On web it is the exact address of the running app with `?uni360_recovery=1` appended. Open a recovery link on the same device and browser or app that requested it.

## Supervisor walkthrough

1. From either mobile workspace, open **Profile** to see the same account. In Corrective, tap the center **+** button, pick the facility, describe a fault, and attach a photo or a video. Uni360 accepts one attachment up to 10 MB. MP4/MOV clips have a 30-second limit verified on the server.
2. Once the OpenRouter key is configured, attach a plain photo of a visible fault and submit. Uni360 automatically analyses the photo and shows its finding alongside the reporter's description on the incident report. Eligible routine cases at a configured check-in site are assigned using shared worker roles, qualifications, shift availability, workload and the Preventive schedule. If no worker qualifies, the case appears as escalated.
3. Submit a second report for an urgent or ambiguous fault. In **Review reports**, show the category, priority, possible duplicates and reason for review. Administrators can approve, request details or an inspection, reject or merge the report. **Assign work** offers recommended and manual assignment options after approval.
4. On the worker's phone, accept the assignment, verify GPS and the facility QR, start the timer and complete the checklist. Capture a completion photo, add notes and submit the repair.
5. In **Check completed work**, review the visit and close the case or request rework. Show the Reporter's notification and feedback, then download the case PDF from the desktop case view. The PDF includes the visit notes, evidence counts and audit history.

**All incidents** shows every status available to the signed-in account. Administrators handle their assigned zones, and Super Administrators have campus-wide access. On a demonstration project, run [seed_corrective_admin_demo.sql](../../../supabase/seed_corrective_admin_demo.sql) to populate the three queues and Analytics with labelled examples. The **Include demo reports** filter controls whether those examples are included in the Analytics screen and management PDF.

## Photo check and priority

To enable automatic photo analysis, create an API key in [OpenRouter](https://openrouter.ai/settings/keys) and add it as `Uni360_OPENROUTER` in **Supabase Dashboard → Edge Functions → Secrets**. The Edge Function uses `nvidia/nemotron-3.5-super-vl:free` with zero-price routing.

When an attached photo is submitted, the Edge Function sends it to OpenRouter and its model provider. The photo remains attached to the report in private Supabase Storage for staff review. Use photos free of personal, confidential or sensitive information for external analysis.

| Photo finding | Suggested priority |
| --- | --- |
| Visible litter or overflowing rubbish | Low |
| Possible sink leak, blocked sink, damaged furniture or surface | Medium |
| Possible widespread standing water or damaged electrical fitting | High |
| Normal-looking facility or inconclusive photo | Administrator reviews submitted reports |

Supabase combines the finding with the text assessment and hazard rules. A description of an immediate hazard can raise the report to Critical. Automatic dispatch for a photo-detected fault requires supporting text. A normal-looking photo can miss a hidden leak or intermittent fault. Reporters can still submit one.

When photo analysis is skipped, unavailable or rate-limited, Uni360 uses the description. Videos are checked for duration and kept in Uni360 storage for staff review. Android voice input uses the device's system speech recognizer. Notifications are delivered in-app.

## Verify

Run [verify_corrective_maintenance.sql](../../../supabase/verify_corrective_maintenance.sql) in Supabase SQL Editor after deployment. It checks QR lookup, required evidence, pending edits and withdrawals, triage, role-based access, intake approval, dispatch, check-in, closure, archive and linked-case feedback. Test fixtures are rolled back.

Run [verify_corrective_smart_intake.sql](../../../supabase/verify_corrective_smart_intake.sql) for automatic dispatch, critical review, duplicate detection and attachment verification. Its photo classification is supplied by test fixtures. Run `node --test supabase/functions/corrective-intake/*_test.ts` to check video validation and the OpenRouter request and fallback using mocked responses.

See the [Chapter 3 and Chapter 4 coverage](../../../docs/corrective-report-coverage.md) for requirement mapping and verification boundaries.

Use `flutter test` to exercise app navigation and approval flows. Test email delivery, deep links, microphone, GPS, scanning and camera uploads on a real device before the demo.
