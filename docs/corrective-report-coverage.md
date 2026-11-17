# Corrective Maintenance report coverage

Reference: Ho Jun Jie, *Uni360 AI-Assisted Corrective Maintenance Management Module for University Facilities*, Chapters 1–4. This check uses the individual Corrective scope and the shared Uni360 integration.

| Report module | Requirements | Implementation and verification |
| --- | --- | --- |
| User and Access Management | FR-01 | The welcome page opens sign-in and Reporter registration. Supabase Auth and account policies gate Reporter, Administrator and Technician workspaces. Profile updates, password changes and recovery are available. Shared account administration follows the existing administrator hierarchy. |
| QR-Based Issue Reporting | FR-02–09 | The shared facility catalog provides location data. Administrators register facility QR codes in Corrective and maintain locations in the shared portal. Reporters scan a QR or select a location, attach a photo, enter or dictate a description, review the details and receive a case reference. Pending reports support editing and withdrawal. The SQL check covers valid QR resolution, required photos, case creation, edits and withdrawal. |
| AI-Assisted Triage and Validation | FR-10–12 | The text classifier suggests a category and confidence. The app checks photo exposure and contrast and supplies an image fingerprint. Duplicate review compares unresolved cases at the same facility by text and photo similarity. Manual review flags are advisory. The SQL check covers text ranking and photo similarity. |
| Administrative Review and Priority Management | FR-13–15 | The review screen supports approval, rejection, reclassification, priority override, more information, physical inspection, and duplicate comparison and merge. RLS and RPC checks scope administrators to their zones and keep the final decision with the administrator. |
| Smart Routing and Work Assignment | FR-16–18 | The system recommends teams and eligible technicians from the shared category, location, skill, shift and workload records. Administrators confirm or change assignments. The scheduling guard checks both modules for overlap. SQL fixtures cover dispatch, escalation, assignments and Preventive scheduling conflicts. |
| Maintenance Execution and Verification | FR-19–22 | Technician screens support acknowledgment, QR and GPS verification, start, progress notes and checklist, evidence capture and submission. Administrators approve, reject or return evidence for rework. The workflow check exercises geofence and QR rejection, evidence requirements and closure. |
| Notification and User Feedback | FR-23–24 | Reporter history, case details, in-app alerts and feedback connect the three roles. Linked reporters receive closure alerts and can flag a fault that still exists. The SQL checks cover assignment, linked-case notices and reopening. |
| Reporting and Audit | FR-25–29 | Administrators can search and filter the queue by status, priority, category, location and date. Historical cases have an audit timeline and archive/restore actions. The web workspace offers case PDFs, management summaries and charts for priorities, categories, frequently reported facilities and monthly submissions. |
| Shared integration | FR-30 | Corrective and Preventive reuse account, facility, zone, worker and scheduling records. The default public Table Editor shows nine core tables. Six additional physical tables in `uni360_data` hold shared records. Role-scoped `maintenance_api` views expose the relevant logical entities. |

## Design and structure

Chapter 4 groups the interfaces into Reporter mobile, Administrator mobile, Technician mobile and Administrator web. The Flutter workspace follows those role flows with a responsive Administrator queue and detail panel. Account, facility and workforce administration also use the existing shared desktop portal.

The ERD describes logical entities. The consolidated schema stores AI results and feedback with the incident, visits and evidence in shared execution and evidence storage, and audit events and notifications in shared activity storage. Supabase Auth, RLS, RPCs, Realtime and private Storage support the client workflows.

## Verification boundaries

- The report mockups guide the screen content and workflows. The implementation uses the shared Uni360 components, and visual matching to every mockup remains unverified.
- Category prediction uses text. Photo diagnostics provide evidence-quality and duplicate signals. Device notifications are in-app. Android provides voice input.
- Shared administrative access covers the existing hierarchy for Administrator and Technician accounts. Reporter registration and profile management are self-service.
- A signed-in phone walkthrough is needed to verify camera, physical QR scanning, microphone, GPS and password-recovery email delivery on the deployment configuration. Responsiveness and production-scale performance require separate measurements.

## Repeat the database checks

Run [verify_corrective_maintenance.sql](../supabase/verify_corrective_maintenance.sql) and [verify_maintenance_consolidation.sql](../supabase/verify_maintenance_consolidation.sql) after applying the [report requirements migration](../supabase/migrations/20261112030000_corrective_report_requirements.sql). Both scripts roll back their fixtures.
