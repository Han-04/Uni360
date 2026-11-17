import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/account/account.dart';
import 'corrective_facility_scanner.dart';
import 'corrective_notifications.dart';
import 'corrective_repository.dart';
import 'corrective_widgets.dart';
import 'incident_report_screen.dart';

class CorrectiveMobile extends StatefulWidget {
  const CorrectiveMobile({
    super.key,
    required this.repository,
    required this.account,
    this.initialTab = 0,
  });
  final CorrectiveRepository repository;
  final Account account;
  final int initialTab;

  @override
  State<CorrectiveMobile> createState() => _CorrectiveMobileState();
}

class _CorrectiveMobileState extends State<CorrectiveMobile>
    with WidgetsBindingObserver {
  late int _tab =
      widget.initialTab == 0 && widget.account.role == AccountRole.reporter
      ? 1
      : widget.initialTab;
  late final RealtimeChannel _channel;
  List<CorrectiveIncident>? _items;
  String? _error;
  int _request = 0;
  bool _loading = true;
  String? _priority, _status;

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
      MaterialPageRoute<void>(
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
    final id = await Navigator.of(context).push(
      MaterialPageRoute<String>(
        builder: (_) => IncidentReportScreen(widget.repository),
      ),
    );
    if (!mounted) return;
    if (id == null) {
      unawaited(_load());
      return;
    }
    setState(() => _tab = 1);
    await _open(id);
  }

  @override
  Widget build(BuildContext context) {
    final actor = widget.account.id;
    final all = (_items ?? [])
        .where(
          (incident) => switch (_tab) {
            0 => incident.workerId == actor,
            1 => incident.reporterId == actor,
            _ => false,
          },
        )
        .toList();
    final items = all
        .where(
          (incident) =>
              (_priority == null || incident.urgency == _priority) &&
              (_status == null || incident.status == _status),
        )
        .toList();
    if (_tab == 0) {
      items.sort((a, b) {
        final priority = correctiveUrgencies
            .indexOf(b.urgency)
            .compareTo(correctiveUrgencies.indexOf(a.urgency));
        return priority == 0 ? b.created.compareTo(a.created) : priority;
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Corrective Maintenance'),
        actions: [
          IconButton(
            tooltip: 'Refresh incidents',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            children: [
              const CorrectiveHero(
                title: 'Incident response',
                subtitle: 'Report facility faults, track dispatch and complete repairs.',
              ),
              correctiveGap(16),
              FilledButton.icon(
                onPressed: _report,
                icon: const Icon(Icons.add),
                label: const Text('Report an incident'),
              ),
              correctiveGap(),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  if (widget.account.role == AccountRole.worker)
                    const ButtonSegment(value: 0, label: Text('Assigned')),
                  const ButtonSegment(value: 1, label: Text('My reports')),
                  const ButtonSegment(value: 2, label: Text('Updates')),
                ],
                selected: {_tab},
                onSelectionChanged: (value) => setState(() {
                  _tab = value.first;
                  _priority = null;
                  _status = null;
                }),
              ),
              correctiveGap(16),
              if (_tab == 2)
                CorrectiveNotifications(
                  repository: widget.repository,
                  openIncident: _open,
                ),
              if (_tab < 2 && _loading && _items == null)
                const LinearProgressIndicator(),
              if (_tab < 2 && _error != null) ...[
                CorrectiveMessage(
                  _items == null
                      ? _error!
                      : 'Showing the last loaded incidents. $_error',
                  onRetry: _load,
                ),
                correctiveGap(),
              ],
              if (_tab < 2 && all.isNotEmpty) ...[
                Text(
                  '${all.where((incident) => !closedCorrectiveStatuses.contains(incident.status)).length} open · '
                  '${all.where((incident) => incident.status == 'resolved').length} resolved',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                ExpansionTile(
                  title: const Text('Filter by priority and status'),
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey('priority-$_tab'),
                      initialValue: _priority ?? '',
                      decoration: const InputDecoration(labelText: 'Priority'),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('All priorities'),
                        ),
                        for (final value in correctiveUrgencies)
                          DropdownMenuItem(value: value, child: Text(value)),
                      ],
                      onChanged: (value) => setState(
                        () => _priority = value == '' ? null : value,
                      ),
                    ),
                    correctiveGap(8),
                    DropdownButtonFormField<String>(
                      key: ValueKey('status-$_tab'),
                      initialValue: _status ?? '',
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('All statuses'),
                        ),
                        for (final entry in correctiveStatuses.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _status = value == '' ? null : value),
                    ),
                    correctiveGap(),
                  ],
                ),
              ],
              if (_tab < 2 && !_loading && _error == null && items.isEmpty)
                CorrectiveMessage(
                  all.isNotEmpty
                      ? 'No incidents match these filters.'
                      : _tab == 0
                      ? 'New corrective assignments will appear here.'
                      : 'Your incident reports will appear here.',
                ),
              for (final incident in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: IncidentTile(
                    incident,
                    onOpen: () => _open(incident.id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
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
      MaterialPageRoute<String>(
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
    final updated = await Navigator.of(context).push<String>(
      MaterialPageRoute(
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
                    TextButton(
                      onPressed: updating ? null : () => _withdraw(incident),
                      child: const Text('Withdraw report'),
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
