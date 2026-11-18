import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/curved_back_button.dart';
import '../../core/widgets/worker_bottom_navigation.dart';
import '../../shared/account/account.dart';
import 'corrective_facility_scanner.dart';
import 'corrective_notifications.dart';
import 'corrective_repository.dart';
import 'corrective_widgets.dart';
import 'incident_report_screen.dart';

enum CorrectiveMobileTab {
  assigned(WorkerDestination('Assigned', Icons.assignment_outlined)),
  reports(WorkerDestination('My reports', Icons.description_outlined)),
  updates(WorkerDestination('Updates', Icons.notifications_outlined));

  const CorrectiveMobileTab(this.destination);
  final WorkerDestination destination;
}

class CorrectiveMobile extends StatefulWidget {
  const CorrectiveMobile({
    super.key,
    required this.repository,
    required this.account,
    this.initialTab = CorrectiveMobileTab.assigned,
  });
  final CorrectiveRepository repository;
  final Account account;
  final CorrectiveMobileTab initialTab;

  @override
  State<CorrectiveMobile> createState() => _CorrectiveMobileState();
}

class _CorrectiveMobileState extends State<CorrectiveMobile>
    with WidgetsBindingObserver {
  late final _tabs = [
    if (widget.account.role == AccountRole.worker) CorrectiveMobileTab.assigned,
    CorrectiveMobileTab.reports,
    CorrectiveMobileTab.updates,
  ];
  late CorrectiveMobileTab _tab = _tabs.contains(widget.initialTab)
      ? widget.initialTab
      : _tabs.first;
  late final RealtimeChannel _channel;
  List<CorrectiveIncident>? _items;
  String? _error;
  int _request = 0;
  bool _loading = true;
  String? _priority, _status;
  int _updatesRefresh = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel = widget.repository.watch('mobile', _load);
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.repository.unwatch(_channel));
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.repository.list(widget.account.id);
      if (mounted && request == _request) setState(() => _items = rows);
    } on Exception catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _error = correctiveError(error);
          if (error is PostgrestException) _items = null;
        });
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _open(String id) async {
    await Navigator.of(context).push(
      correctivePage<void>(
        context,
        builder: (_) => CorrectiveJobScreen(
          repository: widget.repository,
          account: widget.account,
          id: id,
        ),
      ),
    );
    if (mounted) unawaited(_load());
  }

  Future<void> _report() async {
    final result = await Navigator.of(context).push(
      correctivePage<IncidentReportResult>(
        context,
        builder: (_) => IncidentReportScreen(widget.repository),
      ),
    );
    if (!mounted || result == null) return;
    _selectTab(CorrectiveMobileTab.reports);
    unawaited(_load());
    if (result.openDetails) await _open(result.id);
  }

  void _selectTab(CorrectiveMobileTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _priority = null;
      _status = null;
    });
  }

  Future<void> _refreshCurrentTab() async {
    if (_tab == CorrectiveMobileTab.updates) {
      setState(() => _updatesRefresh++);
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final showingUpdates = _tab == CorrectiveMobileTab.updates;
    final compact = MediaQuery.sizeOf(context).width < 375;
    final title = showingUpdates
        ? (compact ? 'Updates' : 'Corrective updates')
        : (compact ? 'Corrective' : 'Corrective Maintenance');
    return Scaffold(
      appBar: AppBar(
        leading: CurvedBackButton.forRoute(context),
        title: Text(title),
        actions: [
          if (showingUpdates)
            IconButton(
              tooltip: 'Report an incident',
              onPressed: _report,
              icon: const Icon(Icons.add),
            ),
          IconButton(
            tooltip: showingUpdates ? 'Refresh updates' : 'Refresh incidents',
            onPressed: _refreshCurrentTab,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refreshCurrentTab,
          child: ListView(
            key: ValueKey(_tab),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            children: showingUpdates
                ? [
                    CorrectiveNotifications(
                      key: ValueKey(_updatesRefresh),
                      repository: widget.repository,
                      openIncident: _open,
                      emptyState: const EmptyState(
                        title: 'No updates yet',
                        message:
                            'Incident and assignment updates will appear here.',
                        illustration: Image(
                          image: AssetImage(
                            'assets/notifications/empty-mailbox.png',
                          ),
                          width: 104,
                          height: 120,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                  ]
                : _incidentList(),
          ),
        ),
      ),
      bottomNavigationBar: WorkerBottomNavigation(
        key: const ValueKey('corrective-footer'),
        destinations: [for (final tab in _tabs) tab.destination],
        selectedIndex: _tabs.indexOf(_tab),
        onDestinationSelected: (index) => _selectTab(_tabs[index]),
      ),
    );
  }

  List<Widget> _incidentList() {
    final assigned = _tab == CorrectiveMobileTab.assigned;
    final actor = widget.account.id;
    final all = (_items ?? []).where((incident) {
      return assigned
          ? incident.workerId == actor
          : incident.reporterId == actor;
    }).toList();
    final items = all.where((incident) {
      final status = incident.data['withdrawn_at'] == null
          ? incident.status
          : 'withdrawn';
      return (_priority == null || incident.urgency == _priority) &&
          (_status == null || status == _status);
    }).toList();
    if (assigned) {
      items.sort((a, b) {
        final priority = correctiveUrgencies
            .indexOf(b.urgency)
            .compareTo(correctiveUrgencies.indexOf(a.urgency));
        return priority == 0 ? b.created.compareTo(a.created) : priority;
      });
    }
    final open = all
        .where(
          (incident) => !closedCorrectiveStatuses.contains(incident.status),
        )
        .length;
    final resolved = all
        .where((incident) => incident.status == 'resolved')
        .length;

    return [
      _IncidentOverview(
        title: assigned ? 'Incident response' : 'Reports overview',
        icon: assigned ? Icons.handyman_outlined : Icons.description_outlined,
        summary: _items == null ? null : '$open open · $resolved resolved',
      ),
      correctiveGap(),
      FilledButton.icon(
        onPressed: _report,
        icon: const Icon(Icons.add),
        label: const Text('Report an incident'),
      ),
      SectionHeading(assigned ? 'Assigned incidents' : 'Report history'),
      if (_loading && _items == null) const LinearProgressIndicator(),
      if (_error != null) ...[
        CorrectiveMessage(
          _items == null
              ? _error!
              : 'Showing the last loaded incidents. $_error',
          onRetry: _load,
        ),
        correctiveGap(),
      ],
      if (all.isNotEmpty) ...[_filters(), correctiveGap(10)],
      if (!_loading && _error == null && items.isEmpty)
        if (all.isNotEmpty)
          const CorrectiveMessage('No incidents match these filters.')
        else
          EmptyState(
            icon: assigned
                ? Icons.assignment_outlined
                : Icons.description_outlined,
            title: assigned ? 'No assignments yet' : 'No reports yet',
            message: assigned
                ? 'New corrective assignments will appear here.'
                : 'Your incident reports will appear here.',
          ),
      for (final incident in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: IncidentTile(incident, onOpen: () => _open(incident.id)),
        ),
    ];
  }

  Widget _filters() => SurfaceCard(
    padding: EdgeInsets.zero,
    child: ExpansionTile(
      key: ValueKey(_tab),
      shape: const Border(),
      collapsedShape: const Border(),
      leading: const Icon(Icons.tune_outlined),
      title: Text(
        _priority == null && _status == null ? 'Filters' : 'Filters applied',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(('priority', _priority)),
          initialValue: _priority ?? '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Priority'),
          items: [
            const DropdownMenuItem(value: '', child: Text('All priorities')),
            for (final value in correctiveUrgencies)
              DropdownMenuItem(value: value, child: Text(value)),
          ],
          onChanged: (value) =>
              setState(() => _priority = value == '' ? null : value),
        ),
        correctiveGap(),
        DropdownButtonFormField<String>(
          key: ValueKey(('status', _status)),
          initialValue: _status ?? '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Status'),
          items: [
            const DropdownMenuItem(value: '', child: Text('All statuses')),
            for (final entry in correctiveStatuses.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text(entry.value, overflow: TextOverflow.ellipsis),
              ),
            const DropdownMenuItem(
              value: 'withdrawn',
              child: Text('Withdrawn'),
            ),
          ],
          onChanged: (value) =>
              setState(() => _status = value == '' ? null : value),
        ),
        if (_priority != null || _status != null)
          TextButton(
            onPressed: () => setState(() {
              _priority = null;
              _status = null;
            }),
            child: const Text('Clear filters'),
          ),
      ],
    ),
  );
}

class _IncidentOverview extends StatelessWidget {
  const _IncidentOverview({
    required this.title,
    required this.icon,
    this.summary,
  });

  final String title;
  final IconData icon;
  final String? summary;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [WorkerColors.blue, WorkerColors.deepBlue],
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 25),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (summary case final value?)
                  Text(value, style: const TextStyle(color: Color(0xFFE5EDFF))),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class CorrectiveJobScreen extends StatefulWidget {
  const CorrectiveJobScreen({
    super.key,
    required this.repository,
    required this.account,
    required this.id,
  });
  final CorrectiveRepository repository;
  final Account account;
  final String id;

  @override
  State<CorrectiveJobScreen> createState() => _CorrectiveJobScreenState();
}

class _CorrectiveJobScreenState extends State<CorrectiveJobScreen> {
  final _notes = TextEditingController();
  late final RealtimeChannel _channel;
  late Future<CorrectiveDetail> _details = widget.repository.detail(widget.id);
  String? _error;
  bool _busy = false;
  bool _confirmed = false;
  int? _draftAttempt;

  bool get _nativeMobile =>
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
      }.contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    _channel = widget.repository.watch('job', () {
      if (mounted && !_busy) _reload();
    }, incidentId: widget.id);
  }

  @override
  void dispose() {
    unawaited(widget.repository.unwatch(_channel));
    _notes.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
    _details = widget.repository.detail(widget.id);
  });

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
      if (mounted) _reload();
    } on Exception catch (error) {
      if (mounted) setState(() => _error = correctiveError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkIn(CorrectiveIncident incident) => _run(() async {
    if (!_nativeMobile) {
      throw const CorrectiveException(
        'Open Uni360 on Android or iOS for GPS and camera check-in.',
      );
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const CorrectiveException(
        'Turn on location services before checking in.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw const CorrectiveException(
        'Allow precise location in device settings and try again.',
      );
    }
    var position = await _readPosition();
    final location = await widget.repository.verifyLocation(
      widget.id,
      _positionPayload(position),
    );
    if (!mounted) return;
    final scan = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Inside the facility geofence'),
        content: Text(
          '${incident.facility}\n'
          '${(location['distance_m'] as num).round()} m from the check-in point · '
          'GPS accuracy ${(location['accuracy_m'] as num).round()} m',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Scan facility QR'),
          ),
        ],
      ),
    );
    if (!mounted || scan != true) return;
    final qr = await Navigator.of(context).push(
      correctivePage<String>(
        context,
        builder: (_) => const CorrectiveFacilityScanner(),
      ),
    );
    if (!mounted || qr == null) return;
    if (DateTime.now().difference(position.timestamp).inSeconds > 15) {
      position = await _readPosition();
    }
    await widget.repository.action(
      widget.id,
      'check_in',
      payload: {..._positionPayload(position), 'qr': qr},
    );
  });

  CorrectiveRow _positionPayload(Position position) => {
    'latitude': position.latitude,
    'longitude': position.longitude,
    'accuracy': position.accuracy,
  };

  Future<Position> _readPosition() async {
    final Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } on TimeoutException {
      throw const CorrectiveException(
        'Could not get a GPS fix. Move to an open area and try again.',
      );
    }
    if (position.isMocked) {
      throw const CorrectiveException(
        'Turn off mock locations and use the device GPS to check in.',
      );
    }
    return position;
  }

  Future<void> _askDispatch() async {
    var message = '';
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contact dispatch'),
        content: TextField(
          maxLength: 2000,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'How can the administrator help?',
          ),
          onChanged: (value) => message = value.trim(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, message),
            child: const Text('Send in Uni360'),
          ),
        ],
      ),
    );
    if (!mounted || note == null) return;
    await _run(
      () => widget.repository.action(
        widget.id,
        'request_help',
        payload: {'notes': note},
      ),
    );
  }

  Future<void> _reporterResponse({required bool feedback}) async {
    var note = '';
    var rating = 5;
    var unresolved = false;
    final answer = await showDialog<CorrectiveRow>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            feedback ? 'Rate the repair' : 'Send requested information',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (feedback) ...[
                  DropdownButtonFormField<int>(
                    initialValue: rating,
                    decoration: const InputDecoration(
                      labelText: 'Satisfaction',
                    ),
                    items: [
                      for (final value in [5, 4, 3, 2, 1])
                        DropdownMenuItem(
                          value: value,
                          child: Text('$value out of 5'),
                        ),
                    ],
                    onChanged: (value) => update(() => rating = value ?? 5),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: unresolved,
                    title: const Text('The fault is still present'),
                    onChanged: (value) =>
                        update(() => unresolved = value ?? false),
                  ),
                ],
                TextField(
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: feedback
                        ? 'Comment (optional)'
                        : 'Additional details',
                  ),
                  onChanged: (value) => note = value.trim(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'note': note,
                if (feedback) 'rating': rating,
                if (feedback) 'unresolved': unresolved,
              }),
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || answer == null) return;
    await _run(
      () => widget.repository.reporterAction(
        widget.id,
        feedback ? 'feedback' : 'reply',
        answer,
      ),
    );
  }

  Future<void> _editPending(CorrectiveIncident incident) async {
    final updated = await Navigator.of(context).push<IncidentReportResult>(
      correctivePage<IncidentReportResult>(
        context,
        builder: (_) =>
            IncidentReportScreen(widget.repository, pending: incident),
      ),
    );
    if (mounted && updated != null) _reload();
  }

  Future<void> _withdraw(CorrectiveIncident incident) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(dialog).colorScheme.error,
        ),
        title: const Text('Withdraw this report?'),
        content: Text(
          '${incident.reference} will leave the review queue. You can still see it in your history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: _withdrawStyle(dialog),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _run(
      () => widget.repository.reporterAction(widget.id, 'withdraw', const {}),
    );
  }

  ButtonStyle _withdrawStyle(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FilledButton.styleFrom(
      backgroundColor: colors.error,
      foregroundColor: colors.onError,
    );
  }

  Future<void> _capture() => _run(() async {
    final XFile? photo;
    try {
      photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 82,
      );
    } on Exception {
      throw const CorrectiveException(
        'The camera could not open. Check the camera permission and try again.',
      );
    }
    if (photo == null) return;
    final path = await widget.repository.upload(
      widget.id,
      await photo.readAsBytes(),
      report: false,
    );
    try {
      await widget.repository.action(
        widget.id,
        'photo',
        payload: {'photo': path},
      );
    } on Exception {
      await widget.repository.discardDraft(path);
      rethrow;
    }
  });

  Widget _work(CorrectiveDetail detail, {required bool disabled}) {
    final incident = detail.incident;
    final visit = detail.visit;
    if (_draftAttempt != incident.attempt) {
      _draftAttempt = incident.attempt;
      _notes.text = visit?['notes'] as String? ?? '';
      _confirmed = false;
    }
    final checked = (visit?['checklist_checked'] as List? ?? const [])
        .cast<int>()
        .toSet();
    final photos = detail.photos
        .where((photo) => photo['attempt'] == incident.attempt)
        .toList();
    return CorrectivePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CorrectiveHeading('Complete the site visit'),
          if (visit?['started_at'] case final String started) ...[
            correctiveGap(6),
            _WorkTimer(DateTime.parse(started)),
          ],
          correctiveGap(8),
          for (final (index, label) in incident.checklist.indexed)
            CheckboxListTile(
              value: checked.contains(index),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(label),
              onChanged: disabled
                  ? null
                  : (value) {
                      final next = {...checked};
                      if (value == true) {
                        next.add(index);
                      } else {
                        next.remove(index);
                      }
                      _run(
                        () => widget.repository.action(
                          widget.id,
                          'checklist',
                          payload: {'checked': next.toList()},
                        ),
                      );
                    },
            ),
          correctiveGap(),
          Text('Completion photographs · ${photos.length}/5'),
          if (photos.isNotEmpty) ...[
            correctiveGap(8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (index, photo) in photos.indexed)
                  CorrectivePhoto(
                    key: ValueKey(photo['path']),
                    widget.repository,
                    photo['path'] as String,
                    label: 'View photograph ${index + 1}',
                    thumbnail: true,
                  ),
              ],
            ),
          ],
          correctiveGap(),
          if (_nativeMobile)
            OutlinedButton.icon(
              onPressed: disabled || photos.length >= 5 ? null : _capture,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Capture completion photo'),
            )
          else
            const Text(
              'Use the Android or iOS app to capture completion evidence.',
            ),
          correctiveGap(),
          TextField(
            controller: _notes,
            enabled: !disabled,
            maxLength: 2000,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Completion notes',
              alignLabelWithHint: true,
            ),
          ),
          OutlinedButton.icon(
            onPressed: disabled
                ? null
                : () => _run(
                    () => widget.repository.action(
                      widget.id,
                      'draft',
                      payload: {'notes': _notes.text.trim()},
                    ),
                  ),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save draft'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _confirmed,
            title: const Text(
              'I confirm all checklist items were completed correctly.',
            ),
            onChanged: disabled
                ? null
                : (value) => setState(() => _confirmed = value ?? false),
          ),
          FilledButton.icon(
            onPressed:
                disabled ||
                    !_confirmed ||
                    checked.length != incident.checklist.length ||
                    photos.isEmpty
                ? null
                : () {
                    _run(
                      () => widget.repository.action(
                        widget.id,
                        'submit',
                        payload: {
                          'notes': _notes.text.trim(),
                          'confirmed': _confirmed,
                        },
                      ),
                    );
                  },
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Submit for review'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: CurvedBackButton.forRoute(context),
      title: const Text('Incident details'),
      actions: [
        IconButton(
          tooltip: 'Refresh incident',
          onPressed: _busy ? null : _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: FutureBuilder(
        future: _details,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(18),
              child: CorrectiveMessage(
                correctiveError(snapshot.error!),
                onRetry: _reload,
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final detail = snapshot.data!;
          final incident = detail.incident;
          final assignedToMe = incident.workerId == widget.account.id;
          final updating =
              _busy || snapshot.connectionState != ConnectionState.done;
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            children: [
              IncidentSummary(incident, widget.repository),
              correctiveGap(),
              if (updating) const LinearProgressIndicator(),
              if (_error case final error?) ...[
                CorrectiveMessage(error),
                correctiveGap(),
              ],
              if (incident.reporterId == widget.account.id &&
                  incident.canEditReport) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: updating ? null : () => _editPending(incident),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit pending report'),
                    ),
                    FilledButton.icon(
                      style: _withdrawStyle(context),
                      onPressed: updating ? null : () => _withdraw(incident),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Withdraw report'),
                    ),
                  ],
                ),
                correctiveGap(),
              ],
              if (incident.reporterId == widget.account.id &&
                  incident.status == 'needs_info') ...[
                FilledButton.icon(
                  onPressed: updating
                      ? null
                      : () => _reporterResponse(feedback: false),
                  icon: const Icon(Icons.reply),
                  label: const Text('Send requested information'),
                ),
                correctiveGap(),
              ],
              if (incident.reporterId == widget.account.id &&
                  (incident.status == 'resolved' ||
                      incident.data['linked_status'] == 'resolved') &&
                  incident.data['feedback_rating'] == null) ...[
                OutlinedButton.icon(
                  onPressed: updating
                      ? null
                      : () => _reporterResponse(feedback: true),
                  icon: const Icon(Icons.star_outline),
                  label: const Text('Rate the repair'),
                ),
                correctiveGap(),
              ],
              if (assignedToMe) ...[
                if (incident.status == 'rework') ...[
                  for (final event
                      in detail.events
                          .where(
                            (event) => event['event'] == 'Rework requested',
                          )
                          .take(1))
                    CorrectiveMessage(event['note'] as String),
                  correctiveGap(8),
                  TextField(
                    controller: _notes,
                    enabled: !updating,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Rework response (optional)',
                    ),
                  ),
                ],
                if (incident.status == 'assigned' ||
                    incident.status == 'rework') ...[
                  FilledButton.icon(
                    onPressed: updating
                        ? null
                        : () => _run(
                            () => widget.repository.action(
                              widget.id,
                              'acknowledge',
                              payload: incident.status == 'rework'
                                  ? {'notes': _notes.text.trim()}
                                  : const {},
                            ),
                          ),
                    icon: const Icon(Icons.check),
                    label: Text(
                      incident.status == 'rework'
                          ? 'Acknowledge rework'
                          : 'Acknowledge assignment',
                    ),
                  ),
                  correctiveGap(),
                ],
                if (incident.status == 'acknowledged') ...[
                  FilledButton.icon(
                    onPressed: updating ? null : () => _checkIn(incident),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan facility QR and check in'),
                  ),
                  correctiveGap(),
                ],
                if (incident.status == 'checked_in') ...[
                  CorrectivePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const CorrectiveHeading('Check-in verified'),
                        correctiveGap(8),
                        for (final item in incident.checklist)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text('• $item'),
                          ),
                        correctiveGap(10),
                        FilledButton.icon(
                          onPressed: updating
                              ? null
                              : () => _run(
                                  () => widget.repository.action(
                                    widget.id,
                                    'start',
                                  ),
                                ),
                          icon: const Icon(Icons.timer_outlined),
                          label: const Text('Start work timer'),
                        ),
                      ],
                    ),
                  ),
                  correctiveGap(),
                ],
                if (incident.status == 'in_progress') ...[
                  _work(detail, disabled: updating),
                  correctiveGap(),
                ],
                if (incident.status != 'in_progress' ||
                    detail.visits.length > 1)
                  CorrectiveVisits(detail, widget.repository),
                if (!closedCorrectiveStatuses.contains(incident.status)) ...[
                  OutlinedButton.icon(
                    onPressed: updating ? null : _askDispatch,
                    icon: const Icon(Icons.support_agent),
                    label: const Text('Contact dispatch'),
                  ),
                  correctiveGap(),
                ],
              ],
              CorrectiveHistory(detail.events),
            ],
          );
        },
      ),
    ),
  );
}

class _WorkTimer extends StatefulWidget {
  const _WorkTimer(this.started);
  final DateTime started;

  @override
  State<_WorkTimer> createState() => _WorkTimerState();
}

class _WorkTimerState extends State<_WorkTimer> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    'Elapsed time · ${correctiveDuration(DateTime.now().difference(widget.started))}',
  );
}
