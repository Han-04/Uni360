import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'corrective_repository.dart';

const correctiveAccent = Color(0xFFC3472E);
const correctiveTint = Color(0xFFFFEDE7);

String correctiveTime(DateTime value) {
  final date = value.toUtc().add(const Duration(hours: 8));
  final month = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][date.month - 1];
  return '${date.day} $month · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} MYT';
}

Widget correctiveGap([double height = 12]) => SizedBox(height: height);

String correctiveDuration(Duration duration) {
  final elapsed = duration.isNegative ? Duration.zero : duration;
  return [
    elapsed.inHours,
    elapsed.inMinutes % 60,
    elapsed.inSeconds % 60,
  ].map((value) => value.toString().padLeft(2, '0')).join(':');
}

class CorrectiveHero extends StatelessWidget {
  const CorrectiveHero({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.handyman_outlined,
    this.gradientColors = const [Color(0xFF10243D), Color(0xFF154D59)],
  });
  final String title, subtitle;
  final IconData icon;
  final List<Color> gradientColors;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: gradientColors),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Stack(
      children: [
        Positioned(
          right: -18,
          bottom: -34,
          child: Icon(
            icon,
            size: 175,
            color: Colors.white.withValues(alpha: .09),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: const Color(0xFF87E3D1), size: 28),
              correctiveGap(16),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              correctiveGap(8),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFFE0EEF3),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class CorrectivePanel extends StatelessWidget {
  const CorrectivePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: Color(0xFFE0E6EE)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class CorrectiveBadge extends StatelessWidget {
  const CorrectiveBadge(this.label, {super.key, this.alert = false});
  final String label;
  final bool alert;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: alert ? correctiveTint : const Color(0xFFE7F3F1),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        label,
        style: TextStyle(
          color: alert ? const Color(0xFF9D3320) : const Color(0xFF11665C),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class IncidentTile extends StatelessWidget {
  const IncidentTile(
    this.incident, {
    super.key,
    required this.onOpen,
    this.selected = false,
  });
  final CorrectiveIncident incident;
  final VoidCallback onOpen;
  final bool selected;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFFE5F3F1) : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: selected ? AppColors.teal : const Color(0xFFE0E6EE),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        incident.reference,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      CorrectiveBadge(
                        incident.urgency,
                        alert: correctiveHighPriority(incident.urgency),
                      ),
                      CorrectiveBadge(
                        incident.statusLabel,
                        alert: {
                          'escalated',
                          'rework',
                          'rejected',
                        }.contains(incident.status),
                      ),
                    ],
                  ),
                  correctiveGap(8),
                  Text(
                    incident.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  correctiveGap(4),
                  Text(
                    incident.facility,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  if (incident.worker != null)
                    Text(
                      'Assigned to ${incident.worker}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );
}

class CorrectiveHeading extends StatelessWidget {
  const CorrectiveHeading(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
  );
}

class CorrectiveMessage extends StatelessWidget {
  const CorrectiveMessage(
    this.message, {
    super.key,
    this.onRetry,
    this.icon = Icons.info_outline,
  });
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) => CorrectivePanel(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.teal),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

class CorrectiveHistory extends StatelessWidget {
  const CorrectiveHistory(this.events, {super.key});
  final List<CorrectiveRow> events;

  @override
  Widget build(BuildContext context) => CorrectivePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CorrectiveHeading('Incident history'),
        for (final event in events)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 5, right: 10),
                  child: Icon(Icons.circle, size: 9, color: AppColors.teal),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event['event'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${event['actor_name']} · ${correctiveTime(DateTime.parse(event['occurred_at'] as String))}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      if ((event['note'] as String).isNotEmpty)
                        Text(event['note'] as String),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class CorrectivePhoto extends StatefulWidget {
  const CorrectivePhoto(
    this.repository,
    this.path, {
    super.key,
    required this.label,
    this.thumbnail = false,
  });
  final CorrectiveRepository repository;
  final String path, label;
  final bool thumbnail;

  @override
  State<CorrectivePhoto> createState() => _CorrectivePhotoState();
}

class _CorrectivePhotoState extends State<CorrectivePhoto> {
  late final _thumbnail = widget.repository.photoUrl(widget.path);

  void _open() {
    final photo = widget.repository.photoUrl(widget.path);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.label),
        content: SizedBox(
          width: 540,
          child: FutureBuilder(
            future: photo,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(correctiveError(snapshot.error!));
              }
              if (!snapshot.hasData) {
                return const Center(
                  heightFactor: 2,
                  child: CircularProgressIndicator(),
                );
              }
              return InteractiveViewer(
                child: Image.network(
                  snapshot.data!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Text('The photograph could not be displayed.'),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.thumbnail) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.photo_outlined),
        label: Text(widget.label),
        onPressed: _open,
      );
    }
    return Tooltip(
      message: widget.label,
      child: Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(10),
        color: AppColors.background,
        child: InkWell(
          onTap: _open,
          child: SizedBox.square(
            dimension: 70,
            child: FutureBuilder(
              future: _thumbnail,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Icon(Icons.photo_outlined);
                return Image.network(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(Icons.photo_outlined),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class IncidentSummary extends StatelessWidget {
  const IncidentSummary(this.incident, this.repository, {super.key});
  final CorrectiveIncident incident;
  final CorrectiveRepository repository;

  @override
  Widget build(BuildContext context) => CorrectivePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 7,
          children: [
            CorrectiveBadge(incident.reference),
            CorrectiveBadge(
              incident.urgency,
              alert: correctiveHighPriority(incident.urgency),
            ),
            CorrectiveBadge(incident.statusLabel),
          ],
        ),
        correctiveGap(),
        Text(
          incident.title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        correctiveGap(),
        Text(
          '${incident.category} · ${incident.facility}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(incident.location),
        if (incident.data['location_method'] == 'qr')
          const Text('Facility identified by QR'),
        if (incident.data['linked_reference'] case final int reference)
          Text(
            'Linked case CM-${reference.toString().padLeft(4, '0')} · ${correctiveStatuses[incident.data['linked_status']] ?? 'Awaiting review'}',
          ),
        if (incident.data['feedback_rating'] case final int rating)
          Text('Reporter feedback $rating/5'),
        correctiveGap(),
        Text(incident.description),
        correctiveGap(),
        Text(
          'Reported by ${incident.reporter} · ${correctiveTime(incident.created)}',
          style: const TextStyle(color: AppColors.muted),
        ),
        if (incident.worker != null) Text('Assigned to ${incident.worker}'),
        if (incident.due case final due?)
          Text('Response window ends ${correctiveTime(due)}'),
        if (incident.reportPhoto case final photo?) ...[
          correctiveGap(),
          CorrectivePhoto(repository, photo, label: 'Report photograph'),
        ],
      ],
    ),
  );
}

class CorrectiveVisits extends StatelessWidget {
  const CorrectiveVisits(this.detail, this.repository, {super.key});
  final CorrectiveDetail detail;
  final CorrectiveRepository repository;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final visit in detail.visits)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: CorrectivePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CorrectiveHeading('Site visit ${visit['attempt']}'),
                correctiveGap(8),
                Text(
                  'Geofence and facility QR verified · ${correctiveTime(DateTime.parse(visit['check_in_at'] as String))}',
                ),
                Text(
                  '${(visit['distance_m'] as num).round()} m from site centre · GPS accuracy ${(visit['accuracy_m'] as num).round()} m',
                ),
                if (visit['latitude'] case final num latitude)
                  Text(
                    'Recorded coordinates ${latitude.toStringAsFixed(5)}, ${(visit['longitude'] as num).toStringAsFixed(5)}',
                  ),
                if (visit['started_at'] case final String started)
                  Text(
                    'Work started ${correctiveTime(DateTime.parse(started))}',
                  ),
                if (visit['submitted_at'] case final String submitted) ...[
                  Text(
                    'Submitted ${correctiveTime(DateTime.parse(submitted))}',
                  ),
                  if (visit['started_at'] case final String started)
                    Text(
                      'Time spent · ${correctiveDuration(DateTime.parse(submitted).difference(DateTime.parse(started)))}',
                    ),
                  correctiveGap(),
                  for (final (index, label)
                      in detail.incident.checklist.indexed)
                    Text(
                      '${(visit['checklist_checked'] as List).contains(index) ? '✓' : '○'}  $label',
                    ),
                ],
                if (visit['notes'] case final String notes) ...[
                  correctiveGap(8),
                  Text(notes),
                ],
                for (final (index, photo)
                    in detail.photos
                        .where((photo) => photo['attempt'] == visit['attempt'])
                        .indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: CorrectivePhoto(
                      repository,
                      photo['path'] as String,
                      label: 'Completion photo ${index + 1}',
                    ),
                  ),
              ],
            ),
          ),
        ),
    ],
  );
}
