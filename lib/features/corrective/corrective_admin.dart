import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr/qr.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/account/account.dart';
import '../../shared/account/presentation/admin_portal_button.dart';
import 'corrective_analytics.dart';
import 'corrective_case_pdf.dart';
import 'corrective_categories_screen.dart';
import 'corrective_notifications.dart';
import 'corrective_repository.dart';
import 'corrective_widgets.dart';
import 'incident_report_screen.dart';

const correctiveAdminRoute = '/corrective';

class CorrectiveAdmin extends StatefulWidget {
  const CorrectiveAdmin({
    super.key,
    required this.repository,
    required this.account,
  });
  final CorrectiveRepository repository;
  final Account account;

  @override
  State<CorrectiveAdmin> createState() => _CorrectiveAdminState();
}

class _CorrectiveAdminState extends State<CorrectiveAdmin> {
  final _query = TextEditingController();
  late final RealtimeChannel _channel;
  late Future<List<CorrectiveIncident>> _list;
  String? _selected;
  String _filter = 'active';
  String? _urgency;
  String? _categoryFilter, _facilityFilter;
  DateTimeRange? _dateFilter;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _list = _request();
    _channel = widget.repository.watch('dispatch', () {
      _refreshTimer?.cancel();
      _refreshTimer = Timer(const Duration(milliseconds: 250), _refresh);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _query.dispose();
    unawaited(widget.repository.unwatch(_channel));
    super.dispose();
  }

  Future<List<CorrectiveIncident>> _request() =>
      widget.repository.list(widget.account.id, admin: true);

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _list = _request();
    });
  }

  Future<void> _selectDates() async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateFilter,
    );
    if (mounted && result != null) setState(() => _dateFilter = result);
  }

  Future<void> _report() async {
    final id = await Navigator.of(context).push(
      MaterialPageRoute<String>(
        builder: (_) =>
            IncidentReportScreen(widget.repository, administrator: true),
      ),
    );
    if (!mounted || id == null) return;
    _refresh();
    _open(id);
  }

  void _open(String id) {
    if (MediaQuery.sizeOf(context).width >= 1050) {
      setState(() => _selected = id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Review incident')),
          body: _AdminIncident(
            repository: widget.repository,
            id: id,
            onChange: _refresh,
          ),
        ),
      ),
    );
  }

  void _showNotifications() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Corrective updates'),
        content: SizedBox(
          width: 500,
          height: 400,
          child: CorrectiveNotifications(
            repository: widget.repository,
            scrollable: true,
            openIncident: (id) {
              Navigator.of(dialogContext).pop();
              if (mounted) _open(id);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Corrective Maintenance'),
      actions: [
        IconButton(
          tooltip: 'Manage maintenance categories',
          icon: const Icon(Icons.category_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CorrectiveCategoriesScreen(widget.repository),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Corrective updates',
          onPressed: _showNotifications,
          icon: const Icon(Icons.notifications_outlined),
        ),
        IconButton(
          tooltip: 'Facility check-in settings',
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => _SiteDialog(widget.repository),
          ),
          icon: const Icon(Icons.qr_code_2),
        ),
        IconButton(
          tooltip: 'Refresh incident queue',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 10),
      ],
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1050;
          final queue = FutureBuilder(
            future: _list,
            builder: (context, snapshot) {
              final rows = snapshot.data ?? <CorrectiveIncident>[];
              final search = _query.text.trim().toLowerCase();
              final visible =
                  rows.where((incident) {
                    if (incident.archived) {
                      if (_filter != 'archive') return false;
                    } else if (_filter == 'archive') {
                      return false;
                    }
                    final matches = switch (_filter) {
                      'archive' => true,
                      'active' => !closedCorrectiveStatuses.contains(
                        incident.status,
                      ),
                      'dispatch' => {
                        'approved',
                        'escalated',
                        'external',
                      }.contains(incident.status),
                      'intake' => {
                        'reported',
                        'needs_info',
                        'inspection',
                      }.contains(incident.status),
                      'overdue' => incident.overdue,
                      'work' => {
                        'assigned',
                        'acknowledged',
                        'checked_in',
                        'in_progress',
                        'rework',
                      }.contains(incident.status),
                      'closed' => closedCorrectiveStatuses.contains(
                        incident.status,
                      ),
                      _ => incident.status == _filter,
                    };
                    final malaysiaDate = incident.created.toUtc().add(
                      const Duration(hours: 8),
                    );
                    final day = DateTime(
                      malaysiaDate.year,
                      malaysiaDate.month,
                      malaysiaDate.day,
                    );
                    final dates = _dateFilter;
                    return matches &&
                        (_urgency == null || incident.urgency == _urgency) &&
                        (_categoryFilter == null ||
                            incident.category == _categoryFilter) &&
                        (_facilityFilter == null ||
                            incident.facility == _facilityFilter) &&
                        (dates == null ||
                            (!day.isBefore(dates.start) &&
                                !day.isAfter(dates.end))) &&
                        [
                          incident.reference,
                          incident.title,
                          incident.facility,
                          incident.worker ?? '',
                          incident.reporter,
                        ].join(' ').toLowerCase().contains(search);
                  }).toList()..sort((a, b) {
                    final priority = correctiveUrgencies
                        .indexOf(b.urgency)
                        .compareTo(correctiveUrgencies.indexOf(a.urgency));
                    return priority != 0
                        ? priority
                        : b.created.compareTo(a.created);
                  });
              final active = rows
                  .where((i) => !closedCorrectiveStatuses.contains(i.status))
                  .length;
              final pending = rows
                  .where(
                    (i) => {
                      'approved',
                      'escalated',
                      'external',
                    }.contains(i.status),
                  )
                  .length;
              final review = rows.where((i) => i.status == 'submitted').length;
              final inProgress = rows
                  .where((i) => i.status == 'in_progress')
                  .length;
              final today = DateTime.now().toUtc().add(
                const Duration(hours: 8),
              );
              final resolved = rows.where((i) {
                final at = i.resolved?.toUtc().add(const Duration(hours: 8));
                return at != null &&
                    at.year == today.year &&
                    at.month == today.month &&
                    at.day == today.day;
              }).length;
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  wide ? 24 : 16,
                  8,
                  wide ? 18 : 16,
                  24,
                ),
                children: [
                  const CorrectiveHero(
                    title: 'Incident command centre',
                    subtitle: 'Review campus faults, dispatch workers and verify completed repairs.',
                    icon: Icons.emergency_outlined,
                  ),
                  correctiveGap(14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Count('Active', active),
                      _Count(
                        'Overdue',
                        rows.where((row) => row.overdue).length,
                      ),
                      _Count('Needs dispatch', pending),
                      _Count('In progress', inProgress),
                      _Count('Awaiting evidence review', review),
                      _Count('Resolved today', resolved),
                    ],
                  ),
                  correctiveGap(16),
                  FilledButton.icon(
                    onPressed: _report,
                    icon: const Icon(Icons.add),
                    label: const Text('Report an incident'),
                  ),
                  if (kIsWeb && snapshot.hasData)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CorrectiveAnalyticsScreen(rows),
                        ),
                      ),
                      icon: const Icon(Icons.bar_chart),
                      label: const Text('Analytics and summary PDF'),
                    ),
                  if (kIsWeb)
                    TextButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pushNamed(adminPortalRoute),
                      icon: const Icon(Icons.manage_accounts_outlined),
                      label: const Text(
                        'Manage shared facilities and accounts',
                      ),
                    ),
                  correctiveGap(10),
                  DropdownButtonFormField<String>(
                    initialValue: _urgency ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Filter by priority',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('All priorities'),
                      ),
                      for (final urgency in correctiveUrgencies)
                        DropdownMenuItem(value: urgency, child: Text(urgency)),
                    ],
                    onChanged: (value) =>
                        setState(() => _urgency = value == '' ? null : value),
                  ),
                  correctiveGap(8),
                  ExpansionTile(
                    title: const Text('Category, facility and date'),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: [
                      _facet(
                        'Category',
                        _categoryFilter,
                        rows.map((row) => row.category),
                        (value) => setState(() => _categoryFilter = value),
                      ),
                      correctiveGap(8),
                      _facet(
                        'Facility',
                        _facilityFilter,
                        rows.map((row) => row.facility),
                        (value) => setState(() => _facilityFilter = value),
                      ),
                      correctiveGap(8),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _selectDates,
                            icon: const Icon(Icons.date_range),
                            label: Text(
                              _dateFilter == null
                                  ? 'Select report dates'
                                  : '${MaterialLocalizations.of(context).formatCompactDate(_dateFilter!.start)} – ${MaterialLocalizations.of(context).formatCompactDate(_dateFilter!.end)}',
                            ),
                          ),
                          if (_dateFilter != null)
                            TextButton(
                              onPressed: () =>
                                  setState(() => _dateFilter = null),
                              child: const Text('Clear dates'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  TextField(
                    controller: _query,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Find by reference, facility or person',
                    ),
                  ),
                  correctiveGap(10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 5,
                    children: [
                      for (final (key, label) in const [
                        ('active', 'Active'),
                        ('intake', 'Intake review'),
                        ('dispatch', 'Needs dispatch'),
                        ('work', 'Field work'),
                        ('submitted', 'Evidence review'),
                        ('overdue', 'Overdue'),
                        ('closed', 'Closed'),
                        ('archive', 'Archive'),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: _filter == key,
                          onSelected: (_) => setState(() => _filter = key),
                        ),
                    ],
                  ),
                  correctiveGap(),
                  if (snapshot.connectionState != ConnectionState.done)
                    const LinearProgressIndicator(),
                  if (snapshot.hasError)
                    CorrectiveMessage(
                      correctiveError(snapshot.error!),
                      onRetry: _refresh,
                    ),
                  if (snapshot.hasData && visible.isEmpty)
                    const CorrectiveMessage('No incidents match this view.'),
                  if (!snapshot.hasError)
                    for (final incident in visible)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: IncidentTile(
                          incident,
                          selected: wide && _selected == incident.id,
                          onOpen: () => _open(incident.id),
                        ),
                      ),
                ],
              );
            },
          );
          if (!wide) return queue;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 5, child: queue),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 6,
                child: _selected == null
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: CorrectiveMessage(
                            'Select an incident to review the report, assignment and evidence.',
                            icon: Icons.fact_check_outlined,
                          ),
                        ),
                      )
                    : _AdminIncident(
                        key: ValueKey(_selected),
                        repository: widget.repository,
                        id: _selected!,
                        onChange: _refresh,
                      ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

Widget _facet(
  String label,
  String? selected,
  Iterable<String> source,
  ValueChanged<String?> onChanged,
) {
  final values = {...source, ?selected}.toList()..sort();
  return DropdownButtonFormField<String>(
    initialValue: selected ?? '',
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      DropdownMenuItem(
        value: '',
        child: Text('All ${label.toLowerCase()} records'),
      ),
      for (final value in values)
        DropdownMenuItem(
          value: value,
          child: Text(value, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (value) => onChanged(value == '' ? null : value),
  );
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value);
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => CorrectivePanel(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$value  ',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          TextSpan(
            text: label,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _AdminIncident extends StatefulWidget {
  const _AdminIncident({
    super.key,
    required this.repository,
    required this.id,
    required this.onChange,
  });
  final CorrectiveRepository repository;
  final String id;
  final VoidCallback onChange;

  @override
  State<_AdminIncident> createState() => _AdminIncidentState();
}

class _AdminIncidentState extends State<_AdminIncident> {
  late final RealtimeChannel _channel;
  late Future<(CorrectiveDetail, CorrectiveRow?)> _details = _load();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _channel = widget.repository.watch('review', () {
      if (mounted && !_busy) _refresh();
    }, incidentId: widget.id);
  }

  @override
  void dispose() {
    unawaited(widget.repository.unwatch(_channel));
    super.dispose();
  }

  Future<(CorrectiveDetail, CorrectiveRow?)> _load() async {
    final detail = await widget.repository.detail(widget.id);
    try {
      return (detail, await widget.repository.adminOptions(widget.id));
    } on PostgrestException catch (error) {
      if (error.code != '42501') rethrow;
      return (detail, null);
    }
  }

  void _refresh() => setState(() {
    _details = _load();
  });

  Future<void> _act(String action, [CorrectiveRow data = const {}]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.action(
        widget.id,
        action,
        admin: true,
        payload: data,
      );
      widget.onChange();
      if (mounted) _refresh();
    } on Exception catch (error) {
      if (mounted) setState(() => _error = correctiveError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withNote(
    String action,
    String label, {
    CorrectiveRow data = const {},
  }) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(label),
    );
    if (mounted && note != null) await _act(action, {...data, 'note': note});
  }

  Future<void> _escalate(CorrectiveIncident incident) async {
    final details = await showDialog<CorrectiveRow>(
      context: context,
      builder: (_) => _EscalationDialog(incident.urgency),
    );
    if (mounted && details != null) await _act('escalate', details);
  }

  Future<void> _compare(
    CorrectiveIncident incident,
    CorrectiveRow match,
  ) async {
    final detail = widget.repository.detail(match['id'] as String);
    final merge = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Compare possible duplicates'),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: FutureBuilder(
              future: detail,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return CorrectiveMessage(correctiveError(snapshot.error!));
                }
                if (!snapshot.hasData) return const LinearProgressIndicator();
                return Column(
                  children: [
                    IncidentSummary(incident, widget.repository),
                    correctiveGap(12),
                    IncidentSummary(snapshot.data!.incident, widget.repository),
                  ],
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep separate'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Merge reports'),
          ),
        ],
      ),
    );
    if (mounted && merge == true) {
      await _withNote(
        'merge',
        'Link to this existing case',
        data: {'primary_id': match['id']},
      );
    }
  }

  Widget _review(
    CorrectiveIncident incident,
    CorrectiveRow options,
    bool disabled,
  ) {
    final triage = options['triage'] as CorrectiveRow? ?? const {};
    final matches = correctiveRows(options['duplicates']);
    final evidenceQuality = switch (triage['evidence_quality']) {
      'clear' => 'Photo passed exposure and contrast checks.',
      'dark' => 'The photo appears too dark.',
      'bright' => 'The photo appears overexposed.',
      'low_contrast' => 'The photo has low contrast.',
      'missing' => 'No report photo is attached.',
      _ => 'Photo quality requires a visual check.',
    };
    return CorrectivePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CorrectiveHeading('Report review'),
          correctiveGap(8),
          Text(
            'Suggested category · ${triage['category'] ?? incident.category}',
          ),
          Text(
            'Suggested priority · ${triage['priority'] ?? incident.urgency}',
          ),
          Text(
            triage['confidence'] == null
                ? 'Manual classification recommended'
                : 'Text model confidence · ${triage['confidence']}%',
          ),
          Text(evidenceQuality),
          if (triage['review_required'] == true)
            const Text(
              'Manual review required. Confirm the fault and supporting evidence.',
            ),
          correctiveGap(12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: disabled
                    ? null
                    : () async {
                        final decision = await showDialog<CorrectiveRow>(
                          context: context,
                          builder: (_) => _ReviewDialog(
                            widget.repository,
                            incident,
                            triage,
                          ),
                        );
                        if (mounted && decision != null) {
                          await _act('review_approve', decision);
                        }
                      },
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Review and approve'),
              ),
              OutlinedButton(
                onPressed: disabled
                    ? null
                    : () => _withNote(
                        'request_information',
                        'Request more information',
                      ),
                child: const Text('Request information'),
              ),
              OutlinedButton(
                onPressed: disabled
                    ? null
                    : () => _withNote('inspect', 'Request physical inspection'),
                child: const Text('Request inspection'),
              ),
              TextButton(
                onPressed: disabled
                    ? null
                    : () => _withNote('dismiss', 'Reject report'),
                child: const Text('Reject report'),
              ),
            ],
          ),
          if (matches.isNotEmpty) ...[
            correctiveGap(14),
            const CorrectiveHeading('Possible duplicates'),
            for (final match in matches)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(match['title'] as String),
                subtitle: Text(
                  [
                    'CM-${match['reference'].toString().padLeft(4, '0')} · ${correctiveStatuses[match['status']] ?? match['status']}',
                    '${match['text_similarity'] ?? match['similarity']}% text similarity',
                    if (match['photo_similarity'] case final num photo)
                      '${photo.toInt()}% photo similarity',
                  ].join('\n'),
                ),
                trailing: TextButton(
                  onPressed: disabled ? null : () => _compare(incident, match),
                  child: const Text('Compare'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _postpone(CorrectiveRow order) async {
    const malaysiaOffset = Duration(hours: 8);
    final earliest = DateTime.now().toUtc().add(
      malaysiaOffset + const Duration(hours: 1),
    );
    final current = DateTime.parse(order['start'] as String)
        .toUtc()
        .add(malaysiaOffset);
    final base = current.isAfter(earliest) ? current : earliest;
    final day = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: base,
      lastDate: base.add(const Duration(days: 30)),
    );
    if (!mounted || day == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (!mounted || time == null) return;
    final next = DateTime.utc(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    ).subtract(malaysiaOffset);
    await _withNote(
      'postpone',
      'Postpone preventive order',
      data: {'order_id': order['id'], 'new_start': next.toIso8601String()},
    );
  }

  Widget _dispatch(
    CorrectiveIncident incident,
    CorrectiveRow options,
    bool disabled,
  ) {
    final workers = correctiveRows(options['candidates']);
    final preventive = correctiveRows(options['preventive']);
    return CorrectivePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CorrectiveHeading('Assign approved work'),
          if (options['team'] case final String team)
            Text('Recommended team · $team'),
          correctiveGap(6),
          Text(
            'Required role · ${incident.data['required_role'] ?? 'Unspecified'}',
          ),
          if (incident.data['required_skill_id'] != null)
            const Text('A matching workforce skill is required.'),
          if ({'approved', 'escalated', 'external'}.contains(incident.status))
            TextButton.icon(
              onPressed: disabled
                  ? null
                  : () async {
                      final requirements = await showDialog<CorrectiveRow>(
                        context: context,
                        builder: (_) =>
                            _RequirementsDialog(widget.repository, incident),
                      );
                      if (mounted && requirements != null) {
                        await _act('requirements', requirements);
                      }
                    },
              icon: const Icon(Icons.tune),
              label: const Text('Edit assignment requirements'),
            ),
          if (workers.isEmpty)
            const CorrectiveMessage(
              'No eligible worker is available for the next hour. Check skills, on-duty shifts and conflicting work.',
              icon: Icons.person_search_outlined,
            ),
          for (final (index, worker) in workers.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(worker['worker_name'] as String),
              subtitle: Text(
                [
                  worker['job_role']?.toString() ?? 'Qualified by skill',
                  if (index == 0) 'Recommended',
                  if (worker['same_zone'] == true) 'Same zone',
                  if (worker['standby'] == true) 'Standby',
                  'Workload ${worker['workload']}',
                ].join(' · '),
              ),
              trailing: OutlinedButton(
                onPressed: disabled
                    ? null
                    : () => _withNote(
                        'assign',
                        'Verify and assign to ${worker['worker_name']}',
                        data: {'worker_id': worker['worker_id']},
                      ),
                child: const Text('Assign'),
              ),
            ),
          correctiveGap(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: disabled ? null : () => _act('dispatch'),
                icon: const Icon(Icons.bolt),
                label: Text(
                  workers.isEmpty
                      ? 'Retry dispatch'
                      : 'Assign recommended worker',
                ),
              ),
              OutlinedButton(
                onPressed: disabled ? null : () => _escalate(incident),
                child: const Text('Escalate'),
              ),
              OutlinedButton(
                onPressed: disabled
                    ? null
                    : () => _withNote('external', 'Record external assistance'),
                child: const Text('External assistance'),
              ),
              TextButton(
                onPressed: disabled
                    ? null
                    : () => _withNote('dismiss', 'Dismiss report'),
                child: const Text('Dismiss report'),
              ),
            ],
          ),
          if (preventive.isNotEmpty) ...[
            correctiveGap(14),
            const Divider(),
            const CorrectiveHeading('Conflicting preventive work'),
            correctiveGap(6),
            const Text(
              'Only unstarted orders marked as lower priority can be moved. The new slot must fit the worker’s shift.',
            ),
            for (final order in preventive)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(order['title'] as String),
                subtitle: Text(
                  '${order['worker']} · ${correctiveTime(DateTime.parse(order['start'] as String))}',
                ),
                trailing: TextButton(
                  onPressed: disabled
                      ? null
                      : () {
                          if (order['deferrable'] == true) {
                            _postpone(order);
                          } else {
                            _withNote(
                              'mark_deferrable',
                              'Mark this order as lower priority',
                              data: {'order_id': order['id']},
                            );
                          }
                        },
                  child: Text(
                    order['deferrable'] == true
                        ? 'Postpone'
                        : 'Mark lower priority',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _details,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Padding(
          padding: const EdgeInsets.all(18),
          child: CorrectiveMessage(
            correctiveError(snapshot.error!),
            onRetry: _refresh,
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final (detail, options) = snapshot.data!;
      final incident = detail.incident;
      final disabled =
          _busy || snapshot.connectionState != ConnectionState.done;
      final dispatchable = {
        'approved',
        'escalated',
        'assigned',
        'acknowledged',
        'checked_in',
        'external',
        'rework',
      }.contains(incident.status);
      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          IncidentSummary(incident, widget.repository),
          if (options != null &&
              const {
                'resolved',
                'rejected',
                'dismissed',
              }.contains(incident.status))
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: disabled
                    ? null
                    : () => _withNote(
                        incident.archived ? 'restore' : 'archive',
                        incident.archived
                            ? 'Restore ${incident.reference}'
                            : 'Archive ${incident.reference}',
                      ),
                icon: Icon(
                  incident.archived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                label: Text(
                  incident.archived ? 'Restore case' : 'Archive case',
                ),
              ),
            ),
          if (options != null &&
              (incident.data['prior_report_photos'] as List?)?.isNotEmpty ==
                  true)
            ExpansionTile(
              title: const Text('Previous report photographs'),
              children: [
                for (final path
                    in (incident.data['prior_report_photos'] as List)
                        .cast<String>())
                  CorrectivePhoto(
                    widget.repository,
                    path,
                    key: ValueKey(path),
                    label: 'Previous report photo',
                  ),
              ],
            ),
          if (kIsWeb && options != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: disabled
                    ? null
                    : () async {
                        try {
                          await exportCorrectiveCase(detail);
                        } on Exception {
                          if (mounted) {
                            setState(
                              () => _error =
                                  'The case PDF could not be generated.',
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Download case PDF'),
              ),
            ),
          correctiveGap(),
          if (disabled) const LinearProgressIndicator(),
          if (_error case final error?) ...[
            CorrectiveMessage(error),
            correctiveGap(),
          ],
          if (options != null &&
              {
                'reported',
                'needs_info',
                'inspection',
              }.contains(incident.status)) ...[
            _review(incident, options, disabled),
            correctiveGap(),
          ],
          if (options != null && dispatchable) ...[
            _dispatch(incident, options, disabled),
            correctiveGap(),
          ],
          CorrectiveVisits(detail, widget.repository),
          if (options != null && incident.status == 'submitted') ...[
            CorrectivePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CorrectiveHeading('Review completion evidence'),
                  correctiveGap(10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: disabled
                            ? null
                            : () => _withNote(
                                'approve',
                                'Approve and resolve incident',
                              ),
                        child: const Text('Approve and resolve'),
                      ),
                      OutlinedButton(
                        onPressed: disabled
                            ? null
                            : () => _withNote('rework', 'Request rework'),
                        child: const Text('Request rework'),
                      ),
                      OutlinedButton(
                        onPressed: disabled
                            ? null
                            : () => _withNote(
                                'reject',
                                'Reject submitted evidence',
                              ),
                        child: const Text('Reject evidence'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            correctiveGap(),
          ],
          CorrectiveHistory(detail.events),
          TextButton.icon(
            onPressed: disabled ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh details'),
          ),
        ],
      );
    },
  );
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog(this.repository, this.incident, this.suggestion);
  final CorrectiveRepository repository;
  final CorrectiveIncident incident;
  final CorrectiveRow suggestion;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late final _catalog = widget.repository.catalog();
  late String _priority =
      (widget.suggestion['priority'] as String?) ?? widget.incident.urgency;
  String? _category;
  String _note = '';

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _catalog,
    builder: (context, snapshot) {
      final categories = correctiveRows(snapshot.data?['categories'])
          .map((item) => item['name'] as String)
          .toList();
      final suggested = widget.suggestion['category'] as String?;
      final category =
          _category ??
          (categories.contains(suggested)
              ? suggested
              : categories.contains(widget.incident.category)
              ? widget.incident.category
              : null);
      return AlertDialog(
        title: const Text('Confirm classification and priority'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (snapshot.hasError)
                  CorrectiveMessage(correctiveError(snapshot.error!))
                else if (!snapshot.hasData)
                  const LinearProgressIndicator(),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  key: ValueKey(category),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Final category',
                  ),
                  items: [
                    for (final option in categories)
                      DropdownMenuItem(value: option, child: Text(option)),
                  ],
                  onChanged: (value) => setState(() => _category = value),
                ),
                correctiveGap(),
                DropdownButtonFormField<String>(
                  initialValue: correctiveUrgencies.contains(_priority)
                      ? _priority
                      : 'Medium',
                  decoration: const InputDecoration(
                    labelText: 'Final priority',
                  ),
                  items: [
                    for (final option in correctiveUrgencies)
                      DropdownMenuItem(value: option, child: Text(option)),
                  ],
                  onChanged: (value) =>
                      setState(() => _priority = value ?? 'Medium'),
                ),
                correctiveGap(),
                TextField(
                  maxLength: 2000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Review notes (optional)',
                  ),
                  onChanged: (value) => _note = value.trim(),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: category == null
                ? null
                : () => Navigator.pop(context, {
                    'category': category,
                    'urgency': _priority,
                    'note': _note,
                  }),
            child: const Text('Approve report'),
          ),
        ],
      );
    },
  );
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog(this.title);
  final String title;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _EscalationDialog extends StatefulWidget {
  const _EscalationDialog(this.initialUrgency);
  final String initialUrgency;

  @override
  State<_EscalationDialog> createState() => _EscalationDialogState();
}

class _EscalationDialogState extends State<_EscalationDialog> {
  late String _urgency = widget.initialUrgency;
  String _group = 'both';
  String _reason = 'No eligible worker is available';
  String _notes = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Escalate incident'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _reason,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Escalation reason'),
              items:
                  const [
                        'No eligible worker is available',
                        'Required qualification is unavailable',
                        'Conflicting work needs review',
                        'Further assessment is required',
                      ]
                      .map(
                        (reason) => DropdownMenuItem(
                          value: reason,
                          child: Text(reason, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
              onChanged: (value) => setState(() => _reason = value!),
            ),
            correctiveGap(),
            DropdownButtonFormField<String>(
              initialValue: _urgency,
              decoration: const InputDecoration(labelText: 'Urgency'),
              items: correctiveUrgencies
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _urgency = value!),
            ),
            correctiveGap(),
            DropdownButtonFormField<String>(
              initialValue: _group,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Notify in Uni360'),
              items: const [
                DropdownMenuItem(
                  value: 'both',
                  child: Text('Zone and super administrators'),
                ),
                DropdownMenuItem(
                  value: 'zone',
                  child: Text('Zone administrators'),
                ),
                DropdownMenuItem(
                  value: 'supervisors',
                  child: Text('Super administrators'),
                ),
              ],
              onChanged: (value) => setState(() => _group = value!),
            ),
            correctiveGap(),
            TextFormField(
              maxLength: 1900,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Additional notes',
                alignLabelWithHint: true,
              ),
              onChanged: (value) => _notes = value.trim(),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, {
          'note': [_reason, if (_notes.isNotEmpty) _notes].join(' · '),
          'notify_group': _group,
          'urgency': _urgency,
        }),
        child: const Text('Escalate and notify'),
      ),
    ],
  );
}

class _NoteDialogState extends State<_NoteDialog> {
  final _key = GlobalKey<FormState>();
  String _note = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 460,
      child: Form(
        key: _key,
        child: TextFormField(
          autofocus: true,
          maxLength: 2000,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Reason or review remarks',
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Enter remarks for the incident history.'
              : null,
          onChanged: (value) => _note = value.trim(),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_key.currentState!.validate()) Navigator.pop(context, _note);
        },
        child: const Text('Confirm'),
      ),
    ],
  );
}

class _RequirementsDialog extends StatefulWidget {
  const _RequirementsDialog(this.repository, this.incident);
  final CorrectiveRepository repository;
  final CorrectiveIncident incident;

  @override
  State<_RequirementsDialog> createState() => _RequirementsDialogState();
}

class _RequirementsDialogState extends State<_RequirementsDialog> {
  late final Future<CorrectiveRow> _catalog = widget.repository.catalog();
  late String _role = widget.incident.data['required_role'] as String? ?? '';
  late String _skill =
      widget.incident.data['required_skill_id'] as String? ?? '';
  late String _urgency = widget.incident.urgency;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Assignment requirements'),
    content: SizedBox(
      width: 450,
      child: FutureBuilder(
        future: _catalog,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text(correctiveError(snapshot.error!));
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final roles = {
            '',
            _role,
            ...(snapshot.data!['roles'] as List).cast<String>(),
          };
          final skills = correctiveRows(snapshot.data!['skills']);
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _urgency,
                  decoration: const InputDecoration(labelText: 'Urgency'),
                  items: correctiveUrgencies
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _urgency = value!),
                ),
                correctiveGap(),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Required role'),
                  items: roles
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.isEmpty ? 'Any role' : value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _role = value!),
                ),
                correctiveGap(),
                DropdownButtonFormField<String>(
                  initialValue: skills.any((row) => row['id'] == _skill)
                      ? _skill
                      : '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Required skill',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('No specific skill'),
                    ),
                    for (final skill in skills)
                      DropdownMenuItem(
                        value: skill['id'] as String,
                        child: Text(skill['label'] as String),
                      ),
                  ],
                  onChanged: (value) => setState(() => _skill = value!),
                ),
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, {
          'role': _role,
          'skill_id': _skill.isEmpty ? null : _skill,
          'urgency': _urgency,
        }),
        child: const Text('Save requirements'),
      ),
    ],
  );
}

class _SiteDialog extends StatefulWidget {
  const _SiteDialog(this.repository);
  final CorrectiveRepository repository;

  @override
  State<_SiteDialog> createState() => _SiteDialogState();
}

class _SiteDialogState extends State<_SiteDialog> {
  late final Future<CorrectiveRow> _catalog = widget.repository.catalog();
  final _form = GlobalKey<FormState>();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _radius = TextEditingController(text: '60');
  String? _facility, _error, _qr;
  bool _busy = false;
  bool _rotate = false;

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    _radius.dispose();
    super.dispose();
  }

  Future<void> _select(String? id) async {
    if (id == null) return;
    setState(() {
      _facility = id;
      _busy = true;
      _error = null;
      _qr = null;
      _rotate = false;
      _lat.clear();
      _lng.clear();
      _radius.text = '60';
    });
    try {
      final site = await widget.repository.site(id);
      if (mounted && site != null) _setSite(site);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = correctiveError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setSite(CorrectiveRow site) => setState(() {
    _lat.text = '${site['latitude']}';
    _lng.text = '${site['longitude']}';
    _radius.text = '${site['radius_m']}';
    _qr = 'uni360:${site['qr_token']}';
    _rotate = false;
  });

  Future<void> _save() async {
    if (_facility == null || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final site = await widget.repository.saveSite(_facility!, {
        'latitude': double.parse(_lat.text),
        'longitude': double.parse(_lng.text),
        'radius_m': int.parse(_radius.text),
        'rotate': _rotate,
      });
      if (mounted) _setSite(site);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = correctiveError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller,
    num minimum,
    num maximum, {
    bool integer = false,
  }) => TextFormField(
    controller: controller,
    enabled: !_busy,
    keyboardType: TextInputType.numberWithOptions(
      decimal: !integer,
      signed: minimum < 0,
    ),
    decoration: InputDecoration(labelText: label),
    validator: (value) {
      final parsed = integer
          ? int.tryParse(value ?? '')
          : double.tryParse(value ?? '');
      return parsed != null &&
              parsed.isFinite &&
              parsed >= minimum &&
              parsed <= maximum
          ? null
          : 'Enter a value from $minimum to $maximum.';
    },
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Facility check-in settings'),
    content: SizedBox(
      width: 490,
      child: FutureBuilder(
        future: _catalog,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text(correctiveError(snapshot.error!));
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final sites = correctiveRows(snapshot.data!['facilities'])
              .where((row) => row['can_manage'] == true);
          if (sites.isEmpty) {
            return const Text(
              'Assign this account to a facility zone before configuring check-in.',
            );
          }
          return SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _facility,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Facility'),
                    items: sites
                        .map(
                          (row) => DropdownMenuItem(
                            value: row['id'] as String,
                            child: Text(
                              row['label'] as String,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _busy ? null : _select,
                  ),
                  if (_facility != null) ...[
                    correctiveGap(),
                    _field('Latitude', _lat, -90, 90),
                    correctiveGap(),
                    _field('Longitude', _lng, -180, 180),
                    correctiveGap(),
                    _field(
                      'Geofence radius (metres)',
                      _radius,
                      15,
                      500,
                      integer: true,
                    ),
                  ],
                  if (_busy) const LinearProgressIndicator(),
                  if (_error case final error?) ...[
                    correctiveGap(),
                    Text(
                      error,
                      style: const TextStyle(color: correctiveAccent),
                    ),
                  ],
                  if (_qr case final qr?) ...[
                    correctiveGap(),
                    Center(
                      child: CustomPaint(
                        size: const Size.square(192),
                        painter: _QrPainter(qr),
                      ),
                    ),
                    const Text(
                      'Display this QR code at the selected facility.',
                    ),
                    CheckboxListTile(
                      value: _rotate,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Replace QR code when saving'),
                      subtitle: const Text(
                        'Print or display the new code after replacing the previous one.',
                      ),
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _rotate = value!),
                    ),
                  ],
                ],
              ),
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
      FilledButton(
        onPressed: _busy || _facility == null ? null : _save,
        child: const Text('Save site'),
      ),
    ],
  );
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.value);
  final String value;

  @override
  void paint(Canvas canvas, Size size) {
    final image = QrImage(
      QrCode.fromData(data: value, errorCorrectLevel: QrErrorCorrectLevel.M),
    );
    final module = size.width / (image.moduleCount + 8);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final paint = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var row = 0; row < image.moduleCount; row++) {
      for (var column = 0; column < image.moduleCount; column++) {
        if (image.isDark(row, column)) {
          canvas.drawRect(
            Rect.fromLTRB(
              ((column + 4) * module).roundToDouble(),
              ((row + 4) * module).roundToDouble(),
              ((column + 5) * module).roundToDouble(),
              ((row + 5) * module).roundToDouble(),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.value != value;
}
