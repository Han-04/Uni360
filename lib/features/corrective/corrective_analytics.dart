import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../preventive/admin/admin_widgets.dart';
import 'corrective_pdf_download_stub.dart'
    if (dart.library.js_interop) 'corrective_pdf_download_web.dart';
import 'corrective_repository.dart';
import 'corrective_widgets.dart';

class CorrectiveAnalyticsScreen extends StatefulWidget {
  const CorrectiveAnalyticsScreen(
    this.incidents, {
    super.key,
    required this.onRefresh,
  });

  final List<CorrectiveIncident> incidents;
  final VoidCallback onRefresh;

  @override
  State<CorrectiveAnalyticsScreen> createState() => _CorrectiveAnalyticsState();
}

class _CorrectiveAnalyticsState extends State<CorrectiveAnalyticsScreen> {
  int? _period;
  bool _exporting = false;
  bool _includeDemo = true;

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
            if (analytics.demoCount > 0) pw.Text(analytics.demoSummary),
            pw.Text('Generated ${correctiveTime(DateTime.now())}'),
            pw.SizedBox(height: 12),
            for (final metric in analytics.metrics)
              pw.Text('${metric.label}  ${metric.value}'),
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
    final now = DateTime.now();
    final cutoff = _period == null
        ? null
        : now.subtract(Duration(days: _period!));
    final periodRows = widget.incidents.where(
      (incident) => cutoff == null || !incident.created.isBefore(cutoff),
    );
    final analytics = _Analytics(
      periodRows.where((incident) => _includeDemo || !incident.isDemo).toList(),
      since: cutoff,
      now: now,
    );
    final period = _period == null ? 'All time' : 'Last $_period days';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AdminHeading(
              'Corrective analytics',
              subtitle: 'Track incident volumes and resolution times.',
              actions: [
                if (kIsWeb)
                  FilledButton.icon(
                    onPressed: _exporting || analytics.incidents.isEmpty
                        ? null
                        : () => _export(analytics, period),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Download management summary'),
                  ),
                IconButton(
                  onPressed: widget.onRefresh,
                  tooltip: 'Refresh analytics',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Wrap(
              spacing: 14,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 230,
                  child: DropdownButtonFormField<int>(
                    initialValue: _period ?? 0,
                    isExpanded: true,
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
                ),
                if (periodRows.any((incident) => incident.isDemo))
                  FilterChip(
                    label: const Text('Include demo reports'),
                    selected: _includeDemo,
                    onSelected: (value) => setState(() => _includeDemo = value),
                  ),
                if (analytics.demoCount > 0) Text(analytics.demoSummary),
              ],
            ),
            correctiveGap(),
            if (analytics.incidents.isEmpty)
              const CorrectiveMessage(
                'No reports are available for the selected period and filters.',
              )
            else ...[
              _MetricCards(analytics.metrics),
              correctiveGap(16),
              _ChartPair(
                left: _MonthlyChart(analytics.months),
                right: _PriorityChart(
                  analytics.priorities,
                  analytics.incidents.length,
                ),
                leftFlex: 3,
                rightFlex: 2,
              ),
              correctiveGap(16),
              _ChartPair(
                left: _RankedChart(
                  'Current status',
                  analytics.statuses,
                  color: _statusColor,
                ),
                right: _RankedChart(
                  'Incidents by category',
                  analytics.categories,
                ),
              ),
              correctiveGap(16),
              _RankedChart('Most reported facilities', analytics.facilities),
            ],
          ],
        ),
      ),
    );
  }
}

const _teal = Color(0xFF007F79);
const _navy = Color(0xFF162A45);
const _blue = Color(0xFF305CA5);
const _green = Color(0xFF23744D);
const _orange = Color(0xFFBD570C);
const _red = Color(0xFFBE3934);
const _track = Color(0xFFE8EEF4);

const _priorityColors = {
  'Low': _teal,
  'Medium': _orange,
  'High': _red,
  'Critical': Color(0xFF823C76),
};

Color _statusColor(String status) => switch (status) {
  'Resolved' => _green,
  'Awaiting review' ||
  'More information needed' ||
  'Inspection requested' => _orange,
  'Evidence submitted' => _blue,
  'Escalated' || 'Withdrawn' || 'Rejected' => _red,
  _ => _teal,
};

typedef _Metric = ({String label, String value, IconData icon, Color color});
typedef _MonthCount = ({DateTime month, int reports});

class _MetricCards extends StatelessWidget {
  const _MetricCards(this.metrics);

  final List<_Metric> metrics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      const gap = 12.0;
      final columns = size.maxWidth >= 1050
          ? 6
          : (size.maxWidth >= 550 ? 3 : 2);
      final text = Theme.of(context).textTheme;
      return Column(
        children: [
          for (var start = 0; start < metrics.length; start += columns) ...[
            if (start != 0) const SizedBox(height: gap),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, metric)
                      in metrics.skip(start).take(columns).indexed) ...[
                    if (index != 0) const SizedBox(width: gap),
                    Expanded(
                      child: CorrectivePanel(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: metric.color.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(7),
                                child: Icon(
                                  metric.icon,
                                  color: metric.color,
                                  size: 17,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              metric.value,
                              style: text.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: _navy,
                              ),
                            ),
                            Text(metric.label, style: text.bodySmall),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _ChartPair extends StatelessWidget {
  const _ChartPair({
    required this.left,
    required this.right,
    this.leftFlex = 1,
    this.rightFlex = 1,
  });

  final Widget left, right;
  final int leftFlex, rightFlex;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) => size.maxWidth >= 820
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: leftFlex, child: left),
              const SizedBox(width: 16),
              Expanded(flex: rightFlex, child: right),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 16), right],
          ),
  );
}

class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart(this.months);

  final List<_MonthCount> months;
  static const _shortMonths = [
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
  ];

  @override
  Widget build(BuildContext context) {
    const plotHeight = 166.0;
    const steps = 4;
    final peak = months.fold(1, (max, month) => math.max(max, month.reports));
    final step = (peak / steps).ceil();
    final ceiling = step * steps;
    final localizations = MaterialLocalizations.of(context);
    final start = localizations.formatMonthYear(months.first.month);
    final end = localizations.formatMonthYear(months.last.month);
    final labelStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: const Color(0xFF52647B));
    return CorrectivePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CorrectiveHeading('Reports by month'),
          const SizedBox(height: 3),
          Text(start == end ? start : '$start – $end', style: labelStyle),
          const SizedBox(height: 16),
          SizedBox(
            height: plotHeight + 24,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var tick = 0; tick <= steps; tick++)
                  Positioned(
                    bottom: plotHeight * tick / steps - 8,
                    left: 0,
                    right: 0,
                    height: 16,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 33,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('${step * tick}', style: labelStyle),
                          ),
                        ),
                        const Expanded(
                          child: Divider(height: 1, color: _track),
                        ),
                      ],
                    ),
                  ),
                Positioned.fill(
                  left: 33,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final month in months)
                        Expanded(
                          child: Tooltip(
                            message:
                                '${localizations.formatMonthYear(month.month)}: ${month.reports} ${month.reports == 1 ? 'report' : 'reports'}',
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (month.reports > 0) ...[
                                  Text('${month.reports}', style: labelStyle),
                                  const SizedBox(height: 3),
                                  FractionallySizedBox(
                                    widthFactor: .56,
                                    child: Container(
                                      height:
                                          plotHeight * month.reports / ceiling,
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(5),
                                            ),
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            _teal,
                                            _teal.withValues(alpha: .75),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 33),
            child: LayoutBuilder(
              builder: (context, size) => Row(
                children: [
                  for (final (index, item) in months.indexed)
                    Expanded(
                      child: Text(
                        size.maxWidth / months.length >= 27 || index.isEven
                            ? _shortMonths[item.month.month - 1]
                            : '',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        textAlign: TextAlign.center,
                        style: labelStyle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriorityChart extends StatelessWidget {
  const _PriorityChart(this.entries, this.total);

  final List<MapEntry<String, int>> entries;
  final int total;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ring = SizedBox.square(
      dimension: 144,
      child: CustomPaint(
        painter: _PriorityRing(entries.map((entry) => entry.value).toList()),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$total',
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _navy,
                ),
              ),
              Text('Reports', style: text.labelSmall),
            ],
          ),
        ),
      ),
    );
    final legend = Column(
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Tooltip(
              message: '${(100 * entry.value / total).round()}% of reports',
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _priorityColors[entry.key],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(entry.key)),
                  Text(
                    '${entry.value}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    return CorrectivePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CorrectiveHeading('Priority breakdown'),
          const SizedBox(height: 3),
          Text('Reports by risk level', style: text.labelSmall),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, size) => size.maxWidth >= 275
                ? ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 216),
                    child: Row(
                      children: [
                        ring,
                        const SizedBox(width: 18),
                        Expanded(child: legend),
                      ],
                    ),
                  )
                : Column(children: [ring, const SizedBox(height: 12), legend]),
          ),
        ],
      ),
    );
  }
}

class _PriorityRing extends CustomPainter {
  const _PriorityRing(this.counts);

  final List<int> counts;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 17.0;
    final arc = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - strokeWidth) / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(arc.center, arc.width / 2, paint..color = _track);
    final total = counts.fold<int>(0, (sum, count) => sum + count);
    final hasMultiple = counts.where((count) => count > 0).length > 1;
    var start = -math.pi / 2;
    for (final (index, count) in counts.indexed) {
      if (count == 0) continue;
      final sweep = 2 * math.pi * count / total;
      final gap = hasMultiple ? math.min(.04, sweep / 3) : 0.0;
      canvas.drawArc(
        arc,
        start + gap / 2,
        sweep - gap,
        false,
        paint..color = _priorityColors[correctiveUrgencies[index]]!,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_PriorityRing oldDelegate) =>
      !listEquals(counts, oldDelegate.counts);
}

class _RankedChart extends StatelessWidget {
  const _RankedChart(this.label, this.entries, {this.color});

  final String label;
  final List<MapEntry<String, int>> entries;
  final Color Function(String)? color;

  @override
  Widget build(BuildContext context) => CorrectivePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CorrectiveHeading(label),
        for (final entry in entries) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.key,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${entry.value}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: ColoredBox(
              color: _track,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: entry.value / entries.first.value,
                child: SizedBox(
                  height: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color?.call(entry.key) ?? _teal,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _Analytics {
  _Analytics(this.incidents, {required this.since, required this.now});

  final List<CorrectiveIncident> incidents;
  final DateTime? since;
  final DateTime now;

  int get demoCount => incidents.where((incident) => incident.isDemo).length;
  String get demoSummary {
    final count = demoCount;
    return '$count demo ${count == 1 ? 'report' : 'reports'} included';
  }

  List<_Metric> get metrics {
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
        .where((incident) => !incident.closed && !incident.archived)
        .length;
    return [
      (
        label: 'Reports',
        value: '${incidents.length}',
        icon: Icons.list_alt_outlined,
        color: _navy,
      ),
      (
        label: 'Open',
        value: '$open',
        icon: Icons.folder_open_outlined,
        color: _blue,
      ),
      (
        label: 'Resolved',
        value: '${resolved.length}',
        icon: Icons.check_circle_outline,
        color: _green,
      ),
      (
        label: 'Overdue',
        value: '${incidents.where((incident) => incident.overdue).length}',
        icon: Icons.warning_amber_outlined,
        color: _red,
      ),
      (
        label: 'Resolution rate',
        value: incidents.isEmpty
            ? '—'
            : '${(resolved.length * 100 / incidents.length).round()}%',
        icon: Icons.donut_small_outlined,
        color: _teal,
      ),
      (
        label: 'Mean resolution time',
        value: timed.isEmpty
            ? '—'
            : '${(minutes / timed.length / 60).toStringAsFixed(1)} h',
        icon: Icons.schedule_outlined,
        color: _orange,
      ),
    ];
  }

  late final statuses = _counts((incident) => incident.statusLabel);
  late final categories = _counts((incident) => incident.category);
  late final facilities = _counts((incident) => incident.facility)
      .take(8)
      .toList();
  late final priorities = [
    for (final urgency in correctiveUrgencies)
      MapEntry(
        urgency,
        incidents.where((incident) => incident.urgency == urgency).length,
      ),
  ];

  late final List<_MonthCount> months = _monthlyCounts();

  List<_MonthCount> _monthlyCounts() {
    DateTime monthOf(DateTime timestamp) {
      final local = timestamp.toUtc().add(const Duration(hours: 8));
      return DateTime.utc(local.year, local.month);
    }

    final counts = <DateTime, int>{};
    for (final incident in incidents) {
      counts.update(
        monthOf(incident.created),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final reportedMonths = counts.keys.toList()..sort();
    final cutoff = since;
    final last = cutoff != null || reportedMonths.isEmpty
        ? monthOf(now)
        : reportedMonths.last;
    final DateTime first;
    if (cutoff != null || reportedMonths.isEmpty) {
      first = monthOf(cutoff ?? now);
    } else {
      final earliest = reportedMonths.first;
      final span =
          (last.year - earliest.year) * 12 + last.month - earliest.month + 1;
      first = DateTime.utc(last.year, last.month - span.clamp(6, 12) + 1);
    }
    return [
      for (
        var month = first;
        !month.isAfter(last);
        month = DateTime.utc(month.year, month.month + 1)
      )
        (month: month, reports: counts[month] ?? 0),
    ];
  }

  List<(String, List<MapEntry<String, int>>)> get groups => [
    ('Status', statuses),
    ('Priority', priorities),
    ('Categories', categories),
    ('Most reported facilities', facilities),
    (
      'Recent monthly submissions',
      [
        for (final item in months)
          MapEntry(
            '${item.month.year}-${item.month.month.toString().padLeft(2, '0')}',
            item.reports,
          ),
      ],
    ),
  ];

  List<MapEntry<String, int>> _counts(
    String Function(CorrectiveIncident) field,
  ) {
    final counts = <String, int>{};
    for (final incident in incidents) {
      counts.update(field(incident), (count) => count + 1, ifAbsent: () => 1);
    }
    return counts.entries.toList()..sort((a, b) {
      final difference = b.value.compareTo(a.value);
      return difference == 0 ? a.key.compareTo(b.key) : difference;
    });
  }
}
