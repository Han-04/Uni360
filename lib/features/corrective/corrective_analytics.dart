import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/widgets/curved_back_button.dart';
import 'corrective_pdf_download_stub.dart'
    if (dart.library.js_interop) 'corrective_pdf_download_web.dart';
import 'corrective_repository.dart';
import 'corrective_widgets.dart';

class CorrectiveAnalyticsScreen extends StatefulWidget {
  const CorrectiveAnalyticsScreen(this.incidents, {super.key});

  final List<CorrectiveIncident> incidents;

  @override
  State<CorrectiveAnalyticsScreen> createState() => _CorrectiveAnalyticsState();
}

class _CorrectiveAnalyticsState extends State<CorrectiveAnalyticsScreen> {
  int? _period;
  bool _exporting = false;

  Future<void> _export(_Analytics analytics, String period) async {
    setState(() => _exporting = true);
    try {
      final pdf = pw.Document(title: 'Uni360 corrective maintenance summary');
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (_) => [
            pw.Header(level: 0, text: 'Uni360 corrective maintenance summary'),
            pw.Text('Reports submitted: $period'),
            pw.Text('Generated ${correctiveTime(DateTime.now())}'),
            pw.SizedBox(height: 12),
            for (final (label, value) in analytics.metrics)
              pw.Text('$label  $value'),
            for (final (label, counts) in analytics.groups) ...[
              pw.Header(level: 1, text: label),
              if (counts.isEmpty) pw.Text('No reports in this period.'),
              for (final entry in counts)
                pw.Text('${entry.key}  ${entry.value}'),
            ],
          ],
        ),
      );
      downloadCorrectivePdf('Uni360-corrective-summary.pdf', await pdf.save());
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The summary PDF could not be generated.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cutoff = _period == null
        ? null
        : DateTime.now().subtract(Duration(days: _period!));
    final analytics = _Analytics(
      widget.incidents
          .where(
            (incident) => cutoff == null || !incident.created.isBefore(cutoff),
          )
          .toList(),
    );
    final period = _period == null ? 'All time' : 'Last $_period days';
    return Scaffold(
      appBar: AppBar(
        leading: CurvedBackButton.forRoute(context),
        title: const Text('Corrective analytics'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              DropdownButtonFormField<int>(
                initialValue: _period ?? 0,
                decoration: const InputDecoration(
                  labelText: 'Report submission period',
                ),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('All time')),
                  DropdownMenuItem(value: 30, child: Text('Last 30 days')),
                  DropdownMenuItem(value: 90, child: Text('Last 90 days')),
                ],
                onChanged: (value) =>
                    setState(() => _period = value == 0 ? null : value),
              ),
              correctiveGap(),
              CorrectivePanel(
                child: Wrap(
                  spacing: 24,
                  runSpacing: 10,
                  children: [
                    for (final (label, value) in analytics.metrics)
                      SizedBox(
                        width: 156,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              value,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            Text(label),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (kIsWeb) ...[
                correctiveGap(),
                FilledButton.icon(
                  onPressed: _exporting
                      ? null
                      : () => _export(analytics, period),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Download management summary'),
                ),
              ],
              for (final (label, entries) in analytics.groups) ...[
                correctiveGap(),
                CorrectivePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CorrectiveHeading(label),
                      if (entries.isEmpty)
                        const Text('No reports in this period.'),
                      for (final entry in entries) ...[
                        correctiveGap(10),
                        Row(
                          children: [
                            Expanded(child: Text(entry.key)),
                            Text('${entry.value}'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: entry.value / analytics.incidents.length,
                          semanticsLabel: entry.key,
                          semanticsValue: '${entry.value} reports',
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Analytics {
  _Analytics(this.incidents);

  final List<CorrectiveIncident> incidents;

  List<(String, String)> get metrics {
    final resolved = incidents
        .where((incident) => incident.status == 'resolved')
        .toList();
    final timed = resolved
        .where((incident) => incident.resolved != null)
        .toList();
    final minutes = timed.fold<int>(
      0,
      (sum, incident) =>
          sum + incident.resolved!.difference(incident.created).inMinutes,
    );
    final open = incidents
        .where(
          (incident) => !closedCorrectiveStatuses.contains(incident.status),
        )
        .length;
    return [
      ('Reports', '${incidents.length}'),
      ('Open', '$open'),
      ('Resolved', '${resolved.length}'),
      ('Overdue', '${incidents.where((incident) => incident.overdue).length}'),
      (
        'Resolution rate',
        incidents.isEmpty
            ? '—'
            : '${(resolved.length * 100 / incidents.length).round()}%',
      ),
      (
        'Mean resolution time',
        timed.isEmpty
            ? '—'
            : '${(minutes / timed.length / 60).toStringAsFixed(1)} h',
      ),
    ];
  }

  List<(String, List<MapEntry<String, int>>)> get groups => [
    ('Priority', _counts((incident) => incident.urgency)),
    ('Categories', _counts((incident) => incident.category)),
    (
      'Most reported facilities',
      _counts((incident) => incident.facility).take(8).toList(),
    ),
    (
      'Recent monthly submissions',
      _counts((incident) {
        final local = incident.created.toUtc().add(const Duration(hours: 8));
        return '${local.year}-${local.month.toString().padLeft(2, '0')}';
      }, chronological: true).take(12).toList(),
    ),
  ];

  List<MapEntry<String, int>> _counts(
    String Function(CorrectiveIncident) field, {
    bool chronological = false,
  }) {
    final counts = <String, int>{};
    for (final incident in incidents) {
      counts.update(field(incident), (count) => count + 1, ifAbsent: () => 1);
    }
    return counts.entries.toList()..sort((a, b) {
      if (chronological) return b.key.compareTo(a.key);
      final difference = b.value.compareTo(a.value);
      return difference == 0 ? a.key.compareTo(b.key) : difference;
    });
  }
}
