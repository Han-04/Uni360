import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import 'worker_profile_repository.dart';

class WorkerProfileSection extends StatefulWidget {
  const WorkerProfileSection({
    super.key,
    required this.workerId,
    required this.load,
  });
  final String workerId;
  final WorkerProfileLoader load;

  @override
  State<WorkerProfileSection> createState() => _WorkerProfileSectionState();
}

class _WorkerProfileSectionState extends State<WorkerProfileSection> {
  late Future<WorkerProfile?> _profile = widget.load(widget.workerId);

  @override
  Widget build(BuildContext context) => FutureBuilder<WorkerProfile?>(
    future: _profile,
    builder: (context, snapshot) {
      final loading = snapshot.connectionState != ConnectionState.done;
      final profile = snapshot.data;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            'Work & skills',
            action: IconButton(
              tooltip: 'Refresh work profile',
              icon: const Icon(Icons.refresh),
              onPressed: loading
                  ? null
                  : () =>
                        setState(() => _profile = widget.load(widget.workerId)),
            ),
          ),
          const Text('Managed by your administrator'),
          const SizedBox(height: 12),
          if (loading)
            const LinearProgressIndicator()
          else if (snapshot.hasError)
            const Text(
              'Could not load your work profile. Tap refresh to try again.',
            )
          else if (profile == null)
            const Text('Your work profile has not been set up yet.')
          else ...[
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detail('Job role', profile.jobRole ?? 'Not assigned'),
                  _detail('Assigned zone', profile.zone ?? 'Not assigned'),
                  _detail('Employment status', profile.employmentStatus),
                  _detail('Standby', profile.standby ? 'Yes' : 'No'),
                  _detail('Current workload', '${profile.workload}'),
                ],
              ),
            ),
            const SectionHeading('Skills'),
            if (profile.skills.isEmpty) const Text('No skills assigned yet.'),
            for (final skill in profile.skills)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(child: Text(skill.name)),
              ),
            const SectionHeading('Certifications'),
            if (profile.certifications.isEmpty)
              const Text('No certifications added yet.'),
            for (final certificate in profile.certifications)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        certificate.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (certificate.number != null)
                        _detail('Certificate number', certificate.number!),
                      if (certificate.expiryDate != null)
                        _detail('Expiry date', certificate.expiryDate!),
                      _detail(
                        'Verification',
                        certificate.verified
                            ? 'Verified'
                            : 'Pending verification',
                      ),
                    ],
                  ),
                ),
              ),
            const SectionHeading('Date availability'),
            if (profile.shifts.isEmpty)
              const Text('No availability records yet.'),
            for (final shift in profile.shifts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shift.availability,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      _detail(
                        'Starts',
                        '${dateLabel(shift.start)} · ${timeLabel(shift.start)}',
                      ),
                      _detail(
                        'Ends',
                        '${dateLabel(shift.end)} · ${timeLabel(shift.end)}',
                      ),
                      _detail('Availability status', shift.status),
                      _detail('Leave status', shift.leaveStatus),
                    ],
                  ),
                ),
              ),
          ],
        ],
      );
    },
  );

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text('$label: $value'),
  );
}
