import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qr/qr.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../preventive/admin/admin_widgets.dart';
import 'corrective_analytics.dart';
import 'corrective_case_pdf.dart';
import 'corrective_categories_screen.dart';
import 'corrective_notifications.dart';
import 'corrective_repository.dart';
import 'corrective_widgets.dart';
import 'incident_report_screen.dart';

enum CorrectiveAdminPage {
  incidents('All incidents', Icons.list_alt_outlined),
  intake('Review reports', Icons.fact_check_outlined),
  dispatch('Assign work', Icons.assignment_ind_outlined),
  evidence('Check completed work', Icons.verified_outlined),
  analytics('Analytics', Icons.bar_chart_outlined),
  settings('Settings', Icons.tune_outlined);

  const CorrectiveAdminPage(this.label, this.icon);
  final String label;
  final IconData icon;
}

class CorrectiveAdmin extends StatefulWidget {
  const CorrectiveAdmin({
    super.key,
    required this.repository,
    required this.administratorId,
    this.page = CorrectiveAdminPage.incidents,
  });
  final CorrectiveRepository repository;
  final String administratorId;
  final CorrectiveAdminPage page;

  @override
  State<CorrectiveAdmin> createState() => _CorrectiveAdminState();
}

class _CorrectiveAdminState extends State<CorrectiveAdmin> {
  final _query = TextEditingController();
  late final RealtimeChannel _channel;
  late Future<List<CorrectiveIncident>> _list;
  String? _selected;
  CorrectiveIncident? _editing;
  bool _reportOpen = false;
  bool _filtersOpen = false;
  String _scope = 'all';
  String? _urgency, _categoryFilter, _facilityFilter;
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
  void didUpdateWidget(covariant CorrectiveAdmin oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page == widget.page) return;
    _selected = null;
    _editing = null;
    _reportOpen = false;
    _filtersOpen = false;
    _query.clear();
    _scope = 'all';
    _urgency = _categoryFilter = _facilityFilter = null;
    _dateFilter = null;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _query.dispose();
    unawaited(widget.repository.unwatch(_channel));
    super.dispose();
  }

  Future<List<CorrectiveIncident>> _request() =>
      widget.repository.list(widget.administratorId, admin: true);

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _list = _request();
    });
  }

  Future<void> _selectDates() async {
    final page = widget.page;
    final result = await showDialog<DateTimeRange>(
      context: context,
      builder: (context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 488, maxHeight: 580),
            child: LayoutBuilder(
              builder: (context, size) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(size: Size(size.maxWidth, size.maxHeight)),
                child: DatePickerTheme(
                  data: DatePickerTheme.of(context).copyWith(
                    rangePickerShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: DateRangePickerDialog(
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    initialDateRange: _dateFilter,
                    initialEntryMode: DatePickerEntryMode.calendarOnly,
                    helpText: 'Report dates',
                    saveText: 'Apply dates',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted && widget.page == page && result != null) {
      setState(() => _dateFilter = result);
    }
  }

  void _clearExtraFilters() => setState(() {
    _urgency = _categoryFilter = _facilityFilter = null;
    _dateFilter = null;
  });

  void _report([CorrectiveIncident? incident]) => setState(() {
    _editing = incident;
    _reportOpen = true;
  });

  void _closeReport(IncidentReportResult? result) => setState(() {
    _editing = null;
    _reportOpen = false;
    if (result != null) {
      _list = _request();
      if (result.openDetails) _selected = result.id;
    }
  });

  void _open(String id) => setState(() => _selected = id);

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

  List<CorrectiveIncident> _visible(List<CorrectiveIncident> rows) {
    final search = _query.text.trim().toLowerCase();
    return rows.where((incident) {
      final status = incident.status;
      final matches = switch (widget.page) {
        CorrectiveAdminPage.intake =>
          !incident.archived &&
              !incident.closed &&
              {'reported', 'needs_info', 'inspection'}.contains(status),
        CorrectiveAdminPage.dispatch =>
          !incident.archived &&
              !incident.closed &&
              {'approved', 'escalated', 'external'}.contains(status),
        CorrectiveAdminPage.evidence =>
          !incident.archived && !incident.closed && status == 'submitted',
        _ when _scope == 'all' => true,
        _ when _scope == 'archive' => incident.archived,
        _ when _scope == 'withdrawn' => incident.withdrawn,
        _ when incident.archived => false,
        _ => switch (_scope) {
          'field' =>
            !incident.closed &&
                {
                  'assigned',
                  'acknowledged',
                  'checked_in',
                  'in_progress',
                  'rework',
                }.contains(status),
          'overdue' => incident.overdue,
          'closed' => incident.closed,
          _ => !incident.closed,
        },
      };
      if (!matches ||
          (_urgency != null && incident.urgency != _urgency) ||
          (_categoryFilter != null && incident.category != _categoryFilter) ||
          (_facilityFilter != null && incident.facility != _facilityFilter)) {
        return false;
      }
      if (_dateFilter case final dates?) {
        final malaysiaDate = incident.created.toUtc().add(
          const Duration(hours: 8),
        );
        final day = DateTime(
          malaysiaDate.year,
          malaysiaDate.month,
          malaysiaDate.day,
        );
        if (day.isBefore(dates.start) || day.isAfter(dates.end)) return false;
      }
      return [
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
      return priority != 0 ? priority : b.created.compareTo(a.created);
    });
  }

  Widget _queue(List<CorrectiveIncident> rows, bool loading) {
    final visible = _visible(rows);
    final page = widget.page;
    final (subtitle, empty) = switch (page) {
      CorrectiveAdminPage.intake => (
        'Confirm the fault and priority, request more information, or approve it for repair.',
        'No reports are waiting for review. Reports that need your decision will appear here.',
      ),
      CorrectiveAdminPage.dispatch => (
        'Assign approved repairs to a worker or arrange help for escalated cases.',
        'No repairs need assignment. Approved reports and escalated cases will appear here.',
      ),
      CorrectiveAdminPage.evidence => (
        'Check the worker’s submitted notes and evidence, then resolve the incident or request rework.',
        'No completed repairs are waiting for a check. Worker submissions will appear here.',
      ),
      _ => (
        'Search all reports you can access, including closed, withdrawn and archived cases.',
        'No corrective incident reports are available to this account.',
      ),
    };
    final filterCount = [
      _urgency,
      _categoryFilter,
      _facilityFilter,
      _dateFilter,
    ].nonNulls.length;
    final hasFilters =
        _query.text.trim().isNotEmpty || _scope != 'all' || filterCount > 0;
    final search = TextField(
      controller: _query,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        labelText: 'Search by reference, title, facility or person',
      ),
    );
    final scope = page == CorrectiveAdminPage.incidents
        ? DropdownButtonFormField<String>(
            initialValue: _scope,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Show incidents'),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All statuses')),
              DropdownMenuItem(
                value: 'active',
                child: Text('Active incidents'),
              ),
              DropdownMenuItem(value: 'field', child: Text('Field work')),
              DropdownMenuItem(value: 'overdue', child: Text('Overdue')),
              DropdownMenuItem(value: 'closed', child: Text('Closed')),
              DropdownMenuItem(value: 'withdrawn', child: Text('Withdrawn')),
              DropdownMenuItem(value: 'archive', child: Text('Archive')),
            ],
            onChanged: (value) => setState(() => _scope = value ?? 'all'),
          )
        : null;
    final filters = FilledButton.icon(
      onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
      icon: Icon(_filtersOpen ? Icons.expand_less : Icons.filter_list),
      label: Text(filterCount == 0 ? 'Filters' : 'Filters ($filterCount)'),
    );
    return LayoutBuilder(
      builder: (context, size) => ListView(
        key: ValueKey(page),
        padding: EdgeInsets.all(size.maxWidth >= 820 ? 28 : 16),
        children: [
          AdminHeading(
            page.label,
            subtitle: subtitle,
            actions: [
              if (page == CorrectiveAdminPage.incidents)
                FilledButton.icon(
                  onPressed: () => _report(),
                  icon: const Icon(Icons.add),
                  label: const Text('Report an incident'),
                ),
              IconButton(
                onPressed: _showNotifications,
                tooltip: 'Corrective updates',
                icon: const Icon(Icons.notifications_outlined),
              ),
              IconButton(
                onPressed: _refresh,
                tooltip: 'Refresh incident queue',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          CorrectivePanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (size.maxWidth >= 700)
                  Row(
                    children: [
                      Expanded(child: search),
                      if (scope != null) ...[
                        const SizedBox(width: 12),
                        SizedBox(width: 200, child: scope),
                      ],
                      const SizedBox(width: 12),
                      filters,
                    ],
                  )
                else ...[
                  search,
                  if (scope != null) ...[correctiveGap(12), scope],
                  correctiveGap(12),
                  Align(alignment: Alignment.centerLeft, child: filters),
                ],
                if (_filtersOpen) _filterFields(rows, filterCount),
              ],
            ),
          ),
          correctiveGap(),
          if (loading) const LinearProgressIndicator(),
          if (!loading && visible.isNotEmpty) ...[
            Text(
              '${visible.length} ${visible.length == 1 ? 'incident' : 'incidents'}',
            ),
            correctiveGap(8),
          ],
          if (!loading && visible.isEmpty)
            CorrectiveMessage(
              hasFilters
                  ? 'No incidents match your search and filters.'
                  : empty,
            ),
          if (visible.isNotEmpty && size.maxWidth >= 960)
            AdminTable(
              const [
                'Incident',
                'Facility',
                'Priority',
                'Status',
                'Assigned to',
              ],
              [
                for (final incident in visible)
                  [
                    SizedBox(
                      width: 220,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            incident.reference,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            incident.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 125,
                      child: Text(
                        incident.facility,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    CorrectiveBadge.priority(incident.urgency),
                    CorrectiveBadge.status(incident),
                    SizedBox(
                      width: 100,
                      child: Text(
                        incident.worker ?? 'Unassigned',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
              ],
              empty: 'No incidents match this view.',
              onRowTap: (index) => _open(visible[index].id),
            )
          else
            for (final incident in visible)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IncidentTile(incident, onOpen: () => _open(incident.id)),
              ),
        ],
      ),
    );
  }

  Widget _filterFields(List<CorrectiveIncident> rows, int count) {
    final dates = _dateFilter;
    final localizations = MaterialLocalizations.of(context);
    final dateLabel = dates == null
        ? 'Select report dates'
        : '${localizations.formatShortDate(dates.start)} – ${localizations.formatShortDate(dates.end)}';
    final fields = [
      _facet(
        'Priority',
        'All priorities',
        _urgency,
        correctiveUrgencies,
        (value) => setState(() => _urgency = value),
      ),
      _facet(
        'Category',
        'All categories',
        _categoryFilter,
        rows.map((row) => row.category).toSet().toList()..sort(),
        (value) => setState(() => _categoryFilter = value),
      ),
      _facet(
        'Facility',
        'All facilities',
        _facilityFilter,
        rows.map((row) => row.facility).toSet().toList()..sort(),
        (value) => setState(() => _facilityFilter = value),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, size) {
            const gap = 12.0;
            final columns = size.maxWidth >= 640 ? 3 : 1;
            final width = (size.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final field in fields)
                  SizedBox(width: width, child: field),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _selectDates,
              icon: const Icon(Icons.date_range),
              label: Text(dateLabel),
            ),
            if (count > 0)
              TextButton(
                onPressed: _clearExtraFilters,
                child: const Text('Clear filters'),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _list,
    builder: (context, snapshot) {
      if (_reportOpen) {
        return IncidentReportScreen(
          widget.repository,
          pending: _editing,
          administrator: true,
          onExit: _closeReport,
        );
      }
      if (_selected case final id?) {
        return _AdminIncident(
          key: ValueKey(id),
          repository: widget.repository,
          id: id,
          onChange: _refresh,
          onBack: () => setState(() => _selected = null),
          onEdit: _report,
        );
      }
      if (widget.page == CorrectiveAdminPage.settings) {
        return CorrectiveCategoriesScreen(
          widget.repository,
          onConfigureSite: () => showDialog<void>(
            context: context,
            builder: (_) => _SiteDialog(widget.repository),
          ),
        );
      }
      if (snapshot.hasError) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.topLeft,
            child: CorrectiveMessage(
              correctiveError(snapshot.error!),
              onRetry: _refresh,
            ),
          ),
        );
      }
      final rows = snapshot.data ?? <CorrectiveIncident>[];
      if (widget.page == CorrectiveAdminPage.analytics) {
        return snapshot.hasData
            ? CorrectiveAnalyticsScreen(rows, onRefresh: _refresh)
            : const Center(child: CircularProgressIndicator());
      }
      return _queue(rows, snapshot.connectionState != ConnectionState.done);
    },
  );
}

Widget _facet(
  String label,
  String allLabel,
  String? selected,
  Iterable<String> source,
  ValueChanged<String?> onChanged,
) {
  final values = {...source, ?selected};
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        initialValue: selected ?? '',
        isExpanded: true,
        menuMaxHeight: 320,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        items: [
          DropdownMenuItem(value: '', child: Text(allLabel)),
          for (final value in values)
            DropdownMenuItem(
              value: value,
              child: Text(value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) => onChanged(value == '' ? null : value),
      ),
    ],
  );
}

class _AdminIncident extends StatefulWidget {
  const _AdminIncident({
    super.key,
    required this.repository,
    required this.id,
    required this.onChange,
    required this.onBack,
    required this.onEdit,
  });
  final CorrectiveRepository repository;
  final String id;
  final VoidCallback onChange;
  final VoidCallback onBack;
  final ValueChanged<CorrectiveIncident> onEdit;

  @override
  State<_AdminIncident> createState() => _AdminIncidentState();
}

enum _IncidentPanel { report, evidence, history }

class _AdminIncidentState extends State<_AdminIncident> {
  late final RealtimeChannel _channel;
  late Future<(CorrectiveDetail, CorrectiveRow?)> _details = _load();
  bool _busy = false;
  String? _error;
  _IncidentPanel? _panel;

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
    final evidenceQuality = triage['media_kind'] == 'video'
        ? 'Video duration verified.'
        : switch (triage['evidence_quality']) {
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
          if (triage['confidence'] != null)
            Text('Text model confidence · ${triage['confidence']}%'),
          if (triage['routing_reason'] case final String reason) Text(reason),
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
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1120),
      child: FutureBuilder(
        future: _details,
        builder: (context, snapshot) {
          final data = snapshot.data;
          final detail = data?.$1;
          final options = data?.$2;
          final incident = detail?.incident;
          final panel =
              _panel ??
              (incident?.status == 'submitted'
                  ? _IncidentPanel.evidence
                  : _IncidentPanel.report);
          final disabled =
              _busy || snapshot.connectionState != ConnectionState.done;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to incidents'),
                ),
              ),
              if (snapshot.hasError)
                CorrectiveMessage(
                  correctiveError(snapshot.error!),
                  onRetry: _refresh,
                )
              else if (incident == null || detail == null)
                const LinearProgressIndicator()
              else ...[
                AdminHeading(
                  incident.reference,
                  subtitle: incident.title,
                  actions: [
                    CorrectiveBadge.status(incident),
                    if (kIsWeb && options != null)
                      OutlinedButton.icon(
                        onPressed: disabled ? null : () => _download(detail),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Download case PDF'),
                      ),
                    IconButton(
                      onPressed: disabled ? null : _refresh,
                      tooltip: 'Refresh details',
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final (item, label) in const [
                      (_IncidentPanel.report, 'Report'),
                      (_IncidentPanel.evidence, 'Work & evidence'),
                      (_IncidentPanel.history, 'History'),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: panel == item,
                        onSelected: (_) => setState(() => _panel = item),
                      ),
                  ],
                ),
                correctiveGap(),
                if (disabled) const LinearProgressIndicator(),
                if (_error case final error?) ...[
                  CorrectiveMessage(error),
                  correctiveGap(),
                ],
                if (panel == _IncidentPanel.report) ...[
                  IncidentSummary(
                    incident,
                    widget.repository,
                    showHeading: false,
                  ),
                  correctiveGap(),
                  if (incident.canEditReport(widget.repository.actorId))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: disabled
                            ? null
                            : () => widget.onEdit(incident),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit pending report'),
                      ),
                    ),
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
                  if (options != null && incident.priorReportPhotos.isNotEmpty)
                    CorrectiveAttachmentHistory(incident, widget.repository),
                  if (options != null &&
                      const {
                        'reported',
                        'needs_info',
                        'inspection',
                      }.contains(incident.status))
                    _review(incident, options, disabled),
                  if (options != null &&
                      const {
                        'approved',
                        'escalated',
                        'assigned',
                        'acknowledged',
                        'checked_in',
                        'external',
                        'rework',
                      }.contains(incident.status))
                    _dispatch(incident, options, disabled),
                ],
                if (panel == _IncidentPanel.evidence) ...[
                  if (detail.visits.isEmpty)
                    const CorrectiveMessage(
                      'No site visits have been recorded.',
                    )
                  else
                    CorrectiveVisits(detail, widget.repository),
                  if (options != null && incident.status == 'submitted') ...[
                    correctiveGap(),
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
                                    : () =>
                                          _withNote('rework', 'Request rework'),
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
                  ],
                ],
                if (panel == _IncidentPanel.history)
                  CorrectiveHistory(detail.events),
              ],
            ],
          );
        },
      ),
    ),
  );

  Future<void> _download(CorrectiveDetail detail) async {
    try {
      await exportCorrectiveCase(detail);
    } on Exception {
      if (mounted) {
        setState(() => _error = 'The case PDF could not be generated.');
      }
    }
  }
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

typedef _CheckInFacility = ({String id, String label, String searchText});

class _SiteDialogState extends State<_SiteDialog> {
  late final Future<List<_CheckInFacility>> _facilities = widget.repository
      .catalog()
      .then(
        (catalog) => [
          for (final row in correctiveRows(catalog['facilities']))
            if (row['can_manage'] == true)
              (
                id: row['id'] as String,
                label: row['label'] as String,
                searchText: (row['label'] as String).toLowerCase(),
              ),
        ],
      );
  final _form = GlobalKey<FormState>();
  final _mapPin = TextEditingController();
  final _radius = TextEditingController(text: '60');
  _CheckInFacility? _facility;
  String? _error, _qr, _locationSource;
  ({double latitude, double longitude})? _point;
  bool _busy = false;
  bool _rotate = false;

  @override
  void dispose() {
    _mapPin.dispose();
    _radius.dispose();
    super.dispose();
  }

  Future<void> _select(_CheckInFacility facility) async {
    if (_busy || _facility?.id == facility.id) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _facility = facility;
      _busy = true;
      _error = null;
      _qr = null;
      _rotate = false;
      _mapPin.clear();
      _point = null;
      _locationSource = null;
      _radius.text = '60';
    });
    try {
      final site = await widget.repository.site(facility.id);
      if (mounted && site != null) _setSite(site);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = correctiveError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setSite(CorrectiveRow site) => setState(() {
    _point = (
      latitude: (site['latitude'] as num).toDouble(),
      longitude: (site['longitude'] as num).toDouble(),
    );
    _mapPin.clear();
    _locationSource = 'Saved check-in location';
    _radius.text = '${site['radius_m']}';
    _qr = 'uni360:${site['qr_token']}';
    _rotate = false;
  });

  Future<void> _useCurrentLocation() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      if (position.isMocked || position.accuracy > 100) {
        throw const FormatException(
          'This location reading is too imprecise. Try outdoors or use a map pin.',
        );
      }
      setState(() {
        _point = (latitude: position.latitude, longitude: position.longitude);
        _mapPin.clear();
        _locationSource =
            'Current location captured (accuracy ±${position.accuracy.round()} m)';
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(
          () => _error = 'Location is unavailable. Allow location access in your browser, or use a map pin.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMap(String facilityName) async {
    final url = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': 'TAR UMT $facilityName',
    });
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
        mounted) {
      setState(
        () => _error = 'Open Google Maps and find the selected facility.',
      );
    }
  }

  Future<void> _save() async {
    if (_facility == null || !(_form.currentState?.validate() ?? false)) return;
    final input = _mapPin.text.trim();
    final point = input.isEmpty ? _point : _parseMapPin(input);
    if (point == null) {
      setState(
        () => _error =
            'Use your current location or paste a map pin to continue.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final site = await widget.repository.saveSite(_facility!.id, {
        'latitude': point.latitude,
        'longitude': point.longitude,
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

  Widget _radiusField() => TextFormField(
    controller: _radius,
    enabled: !_busy,
    keyboardType: TextInputType.number,
    decoration: const InputDecoration(
      labelText: 'Allowed check-in distance (metres)',
      helperText: 'How far a worker can be from the pin. Start with 60 m.',
    ),
    validator: (value) {
      final parsed = int.tryParse(value ?? '');
      return parsed != null && parsed >= 15 && parsed <= 500
          ? null
          : 'Enter a distance from 15 to 500 metres.';
    },
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Facility check-in settings'),
    content: SizedBox(
      width: 490,
      child: FutureBuilder(
        future: _facilities,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text(correctiveError(snapshot.error!));
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final sites = snapshot.data!;
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
                  Autocomplete<_CheckInFacility>(
                    displayStringForOption: (facility) => facility.label,
                    optionsMaxHeight: 240,
                    optionsViewOpenDirection:
                        OptionsViewOpenDirection.mostSpace,
                    optionsBuilder: (input) {
                      final query = input.text.trim().toLowerCase();
                      if (query.isEmpty) return const [];
                      final terms = query.split(RegExp(r'[\s/]+'));
                      return sites
                          .where(
                            (site) => terms.every(site.searchText.contains),
                          )
                          .take(20)
                          .toList();
                    },
                    fieldViewBuilder: (context, controller, focus, submit) =>
                        TextField(
                          controller: controller,
                          focusNode: focus,
                          enabled: !_busy,
                          onSubmitted: (_) => submit(),
                          decoration: const InputDecoration(
                            labelText: 'Search for a facility',
                            prefixIcon: Icon(Icons.search),
                            helperText: 'Type a building, room, or asset name.',
                          ),
                        ),
                    onSelected: _select,
                  ),
                  if (_facility case final facility?) ...[
                    correctiveGap(),
                    Text('Selected facility: ${facility.label}'),
                    correctiveGap(8),
                    const Text(
                      'Set the check-in point from the facility or drop a pin on the map.',
                    ),
                    correctiveGap(8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _useCurrentLocation,
                          icon: const Icon(Icons.my_location),
                          label: const Text('Use current location'),
                        ),
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _openMap(facility.label),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open Google Maps'),
                        ),
                      ],
                    ),
                    if (_locationSource case final source?) ...[
                      correctiveGap(8),
                      Text(source),
                    ],
                    correctiveGap(),
                    TextFormField(
                      controller: _mapPin,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Paste a map pin',
                        helperText: 'In Google Maps, right-click the check-in spot, click the coordinate pair to copy it, then paste here.',
                        helperMaxLines: 3,
                      ),
                      validator: (value) {
                        final pin = value?.trim() ?? '';
                        return pin.isEmpty || _parseMapPin(pin) != null
                            ? null
                            : 'Paste the coordinate pair copied from the map.';
                      },
                    ),
                    correctiveGap(),
                    _radiusField(),
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

({double latitude, double longitude})? _parseMapPin(String text) {
  final match = RegExp(r'^([+-]?\d+(?:\.\d+)?),\s*([+-]?\d+(?:\.\d+)?)$')
      .firstMatch(text);
  if (match == null) return null;
  final latitude = double.parse(match[1]!);
  final longitude = double.parse(match[2]!);
  if (latitude.abs() > 90 || longitude.abs() > 180) return null;
  return (latitude: latitude, longitude: longitude);
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
