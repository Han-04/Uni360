import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/curved_back_button.dart';
import '../../core/widgets/worker_calendar_dialog.dart';
import '../preventive/data/assigned_work_repository.dart' show malaysiaToday;
import 'leave_document_button.dart';
import 'worker_leave_repository.dart';

String _leaveDuration(DateTime first, DateTime last) {
  final startDay = DateTime.utc(first.year, first.month, first.day);
  final endDay = DateTime.utc(last.year, last.month, last.day);
  final days = endDay.difference(startDay).inDays + 1;
  return '$days ${days == 1 ? "day" : "days"}';
}

class WorkerLeaveEntry extends StatelessWidget {
  const WorkerLeaveEntry({
    super.key,
    required this.workerId,
    required this.repository,
  });
  final String workerId;
  final WorkerLeaveRepository repository;

  Future<void> _apply(BuildContext context) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => Theme(
          data: buildWorkerTheme(Theme.of(context)),
          child: _LeaveForm(repository: repository),
        ),
      ),
    );
    if (saved == true && context.mounted) {
      showMessage(context, 'Leave request submitted.');
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: SurfaceCard(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(
              Icons.event_busy_outlined,
              color: WorkerColors.blue,
            ),
            title: const Text('Apply for leave'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _apply(context),
          ),
          ListTile(
            leading: const Icon(Icons.history, color: WorkerColors.blue),
            title: const Text('Leave history'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (context) => Theme(
                  data: buildWorkerTheme(Theme.of(context)),
                  child: _LeaveHistory(
                    workerId: workerId,
                    repository: repository,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _LeaveHistory extends StatefulWidget {
  const _LeaveHistory({required this.workerId, required this.repository});
  final String workerId;
  final WorkerLeaveRepository repository;

  @override
  State<_LeaveHistory> createState() => _LeaveHistoryState();
}

class _LeaveHistoryState extends State<_LeaveHistory> {
  int page = 0;
  late Future<List<WorkerLeave>> _requests = _load();

  Future<List<WorkerLeave>> _load() =>
      widget.repository.list(workerId: widget.workerId, page: page);

  Future<void> _refresh() async {
    final request = _load();
    setState(() {
      _requests = request;
    });
    try {
      await request;
    } on Exception {
      /* Rendered by the request list. */
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: CurvedBackButton.forRoute(context),
      title: const Text('Leave history'),
      actions: [
        IconButton(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh leave requests',
        ),
      ],
    ),
    body: SafeArea(
      child: FutureBuilder(
        future: _requests,
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const <WorkerLeave>[];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (snapshot.connectionState != ConnectionState.done)
                  const LinearProgressIndicator()
                else if (snapshot.hasError)
                  const InfoBanner(
                    'Could not load leave requests. Refresh to try again.',
                    warning: true,
                  )
                else if (rows.isEmpty)
                  const Text('You have no leave requests.')
                else
                  for (final leave in rows.take(25))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              leave.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              leave.first == leave.last
                                  ? dateLabel(leave.first)
                                  : '${dateLabel(leave.first)} – ${dateLabel(leave.last)}',
                            ),
                            Text(_leaveDuration(leave.first, leave.last)),
                            const SizedBox(height: 6),
                            _LeaveStatus(leave: leave),
                            const SizedBox(height: 8),
                            Text(leave.reason),
                            LeaveDocumentButton(
                              leave: leave,
                              repository: widget.repository,
                            ),
                            if (leave.note case final note?)
                              Text('Review note · $note'),
                          ],
                        ),
                      ),
                    ),
                if (page > 0 || rows.length > 25)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: page > 0
                            ? () {
                                page--;
                                _refresh();
                              }
                            : null,
                        child: const Text('Previous'),
                      ),
                      TextButton(
                        onPressed: rows.length > 25
                            ? () {
                                page++;
                                _refresh();
                              }
                            : null,
                        child: const Text('Next'),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _LeaveStatus extends StatelessWidget {
  const _LeaveStatus({required this.leave});

  final WorkerLeave leave;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (leave.status) {
      'approved' => (const Color(0xFFDDF6E9), const Color(0xFF146345)),
      'rejected' => (const Color(0xFFFFE4E4), const Color(0xFF9C2525)),
      _ => (const Color(0xFFFFEECF), const Color(0xFF825000)),
    };
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: background,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          leave.statusOn(malaysiaToday()),
          style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _LeaveForm extends StatefulWidget {
  const _LeaveForm({required this.repository});
  final WorkerLeaveRepository repository;

  @override
  State<_LeaveForm> createState() => _LeaveFormState();
}

class _LeaveFormState extends State<_LeaveForm> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  String? _kind, _error;
  DateTime? _first, _last;
  LeaveDocument? _document;
  bool _picking = false;
  bool _saving = false;

  String? get _selectedDuration {
    final first = _first;
    final last = _last;
    if (first == null || last == null) return null;
    return _leaveDuration(first, last);
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final now = malaysiaToday();
    final minimum = start ? now : _first ?? now;
    final maximum = start
        ? DateTime(now.year + 1, now.month, now.day)
        : minimum.add(const Duration(days: 365));
    final current = (start ? _first : _last) ?? minimum;
    final date = await showDialog<DateTime>(
      context: context,
      builder: (_) => WorkerCalendarDialog(
        title: start ? 'Select start date' : 'Select end date',
        today: now,
        selected: current.isBefore(minimum) || current.isAfter(maximum)
            ? minimum
            : current,
        firstDate: minimum,
        lastDate: maximum,
      ),
    );
    if (date == null || !mounted) return;
    setState(() {
      if (start) {
        _first = date;
        if (_last == null ||
            _last!.isBefore(date) ||
            _last!.difference(date).inDays > 365) {
          _last = date;
        }
      } else {
        _last = date;
      }
    });
  }

  Future<void> _submit() async {
    if (_saving || _picking || !_form.currentState!.validate()) return;
    final first = _first;
    final last = _last;
    if (first == null || last == null) {
      setState(() => _error = 'Choose a start and end date.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.submit(
        _kind!,
        first,
        last,
        _reason.text.trim(),
        document: _document,
      );
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.code == '23514'
              ? error.message
              : 'Could not submit your request. Try again.',
        );
      }
    } on Exception {
      if (mounted) {
        setState(() => _error = 'Could not submit your request. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDocument() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'PDF or photo',
            extensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
            mimeTypes: [
              'application/pdf',
              'image/jpeg',
              'image/png',
              'image/webp',
            ],
            uniformTypeIdentifiers: [
              'com.adobe.pdf',
              'public.jpeg',
              'public.png',
              'org.webmproject.webp',
            ],
          ),
        ],
      );
      if (file == null || !mounted) return;
      if (await file.length() > LeaveDocument.maxBytes) {
        throw const FormatException('Choose one PDF or photo up to 10 MB.');
      }
      final document = LeaveDocument(file.name, await file.readAsBytes());
      if (mounted) setState(() => _document = document);
    } on FormatException {
      if (mounted) {
        setState(
          () => _error = 'Choose one PDF, JPG, PNG or WebP file up to 10 MB.',
        );
      }
    } on Exception {
      if (mounted) {
        setState(() => _error = 'Could not open the file. Try again.');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        leading: CurvedBackButton.forRoute(context),
        title: const Text('Apply for leave'),
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Your administrator will review this request. Dates use Malaysia time.',
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Leave type'),
                isExpanded: true,
                items: [
                  for (final type in leaveTypes.entries)
                    DropdownMenuItem(value: type.key, child: Text(type.value)),
                ],
                validator: (value) =>
                    value == null ? 'Choose a leave type.' : null,
                onChanged: _saving ? null : (value) => _kind = value,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _pick(true),
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _first == null
                      ? 'Start date'
                      : 'Starts · ${dateLabel(_first!)}',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving || _first == null
                    ? null
                    : () => _pick(false),
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _last == null ? 'End date' : 'Ends · ${dateLabel(_last!)}',
                ),
              ),
              if (_selectedDuration case final duration?) ...[
                const SizedBox(height: 8),
                Text(
                  'Note: You are applying for $duration of leave.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: WorkerColors.deepBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                enabled: !_saving,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(labelText: 'Reason'),
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? 'Enter a reason for your leave.'
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                'Supporting document (optional)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Text('One PDF or photo, up to 10 MB.'),
              const SizedBox(height: 8),
              if (_document case final doc?)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    doc.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  leading: const Icon(Icons.description_outlined),
                  trailing: IconButton(
                    tooltip: 'Remove supporting document',
                    onPressed: _saving || _picking
                        ? null
                        : () => setState(() => _document = null),
                    icon: const Icon(Icons.close),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _saving || _picking ? null : _pickDocument,
                icon: const Icon(Icons.attach_file),
                label: Text(
                  _document == null
                      ? 'Attach supporting document'
                      : 'Replace supporting document',
                ),
              ),
              if (_error case final error?) InfoBanner(error, warning: true),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving || _picking ? null : _submit,
                child: Text(_saving ? 'Submitting…' : 'Submit request'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
