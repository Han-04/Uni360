import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/curved_back_button.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../preventive/data/assigned_work_repository.dart' show malaysiaToday;
import 'leave_document_button.dart';
import 'worker_leave_repository.dart';

class WorkerLeaveEntry extends StatelessWidget {
  const WorkerLeaveEntry({
    super.key,
    required this.workerId,
    required this.repository,
  });
  final String workerId;
  final WorkerLeaveRepository repository;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionHeading('Leave'),
      OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                WorkerLeaveScreen(workerId: workerId, repository: repository),
          ),
        ),
        icon: const Icon(Icons.event_busy_outlined),
        label: const Text('Apply for leave'),
      ),
    ],
  );
}

class WorkerLeaveScreen extends StatefulWidget {
  const WorkerLeaveScreen({
    super.key,
    required this.workerId,
    required this.repository,
  });
  final String workerId;
  final WorkerLeaveRepository repository;

  @override
  State<WorkerLeaveScreen> createState() => _WorkerLeaveScreenState();
}

class _WorkerLeaveScreenState extends State<WorkerLeaveScreen> {
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

  Future<void> _apply() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _LeaveForm(repository: widget.repository),
      ),
    );
    if (saved == true && mounted) {
      page = 0;
      _refresh();
      showMessage(context, 'Leave request submitted.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: CurvedBackButton.forRoute(context),
      title: const Text('Leave requests'),
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
                FilledButton.icon(
                  onPressed: _apply,
                  icon: const Icon(Icons.add),
                  label: const Text('Apply for leave'),
                ),
                const SectionHeading('My requests'),
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
                            Text(leave.statusOn(malaysiaToday())),
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

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final now = malaysiaToday();
    final minimum = start ? now : _first ?? now;
    final date = await showDatePicker(
      context: context,
      firstDate: minimum,
      initialDate: (start ? _first : _last) ?? minimum,
      lastDate: start
          ? DateTime(now.year + 1, now.month, now.day)
          : minimum.add(const Duration(days: 365)),
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
