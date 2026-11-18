import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import 'corrective_facility_scanner.dart';
import 'corrective_photo_diagnostics.dart';
import 'corrective_repository.dart';
import 'corrective_widgets.dart';

typedef IncidentReportResult = ({String id, bool openDetails});

class IncidentReportScreen extends StatefulWidget {
  const IncidentReportScreen(
    this.repository, {
    super.key,
    this.pending,
    this.administrator = false,
  });
  final CorrectiveRepository repository;
  final CorrectiveIncident? pending;
  final bool administrator;

  @override
  State<IncidentReportScreen> createState() => _IncidentReportScreenState();
}

class _IncidentReportScreenState extends State<IncidentReportScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.pending?.title);
  late final _location = TextEditingController(text: widget.pending?.location);
  late final _description = TextEditingController(
    text: widget.pending?.description,
  );
  late final String _id = widget.pending?.id ?? widget.repository.newId();
  late Future<CorrectiveRow> _catalog = widget.repository.catalog();
  late String? _facility = widget.pending?.facilityId;
  String? _error, _stagedPath, _qr;
  late String? _category = widget.pending?.category ?? 'Other';
  late String _urgency = widget.pending?.urgency ?? 'Medium';
  Uint8List? _photo;
  CorrectiveRow? _photoDiagnostics;
  bool _busy = false;
  bool _submitted = false;
  bool get _nativeCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _scan() async {
    final code = await Navigator.of(context).push(
      MaterialPageRoute<String>(
        builder: (_) => const CorrectiveFacilityScanner(),
      ),
    );
    if (!mounted || code == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final facility = await widget.repository.lookupFacility(code);
      final locations = correctiveRows((await _catalog)['facilities']);
      if (mounted) {
        setState(() {
          _facility = facility;
          _qr = code;
          if (_location.text.trim().isEmpty) {
            for (final row in locations) {
              if (row['id'] == facility) {
                _location.text = (row['label'] as String).split(' / ').last;
                break;
              }
            }
          }
        });
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = correctiveError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dictate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final spoken = await const MethodChannel('uni360/speech')
          .invokeMethod<String>('listen');
      if (!mounted || spoken == null || spoken.trim().isEmpty) return;
      final full = [
        if (_description.text.trim().isNotEmpty) _description.text.trim(),
        spoken.trim(),
      ].join(' ');
      _description.text = full.length > 2000 ? full.substring(0, 2000) : full;
    } on PlatformException {
      if (mounted) {
        setState(
          () => _error = 'Voice input is unavailable on this device. You can type the description.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    if (!_submitted && !_busy && _stagedPath != null) {
      unawaited(widget.repository.discardDraft(_stagedPath!));
    }
    _title.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto(ImageSource source) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final diagnostics = await inspectCorrectivePhoto(bytes);
      if (!mounted) return;
      if (_stagedPath case final path?) {
        unawaited(widget.repository.discardDraft(path));
      }
      setState(() {
        _photo = bytes;
        _photoDiagnostics = diagnostics;
        _stagedPath = null;
      });
    } on Exception {
      if (mounted) {
        setState(
          () => _error = 'The photograph could not be opened. Check camera permissions or choose a different image.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _facility == null || _busy) return;
    if (!widget.administrator &&
        _photo == null &&
        widget.pending?.reportPhoto == null) {
      setState(
        () => _error = 'Attach a photograph of the fault before continuing.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final facilities = correctiveRows((await _catalog)['facilities']);
      final facilityName =
          widget.pending?.facility ??
          facilities.firstWhere((row) => row['id'] == _facility)['label']
              as String;
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Review your report'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  facilityName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(_location.text.trim()),
                correctiveGap(),
                Text(
                  _title.text.trim(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(_description.text.trim()),
                correctiveGap(),
                Text('${_category ?? 'Other'} · $_urgency priority'),
                if (_photo case final photo?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Image.memory(
                      photo,
                      height: 100,
                      fit: BoxFit.contain,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Edit report'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                widget.pending == null ? 'Submit report' : 'Save changes',
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      if (_photo case final photo?) {
        _stagedPath ??= await widget.repository.upload(
          _id,
          photo,
          report: true,
        );
      }
      if (!mounted) {
        if (_stagedPath case final path?) {
          unawaited(widget.repository.discardDraft(path));
        }
        return;
      }
      final report = {
        'id': _id,
        'facility_id': _facility,
        'qr': _qr,
        'category': _category,
        'urgency': _urgency,
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'location_detail': _location.text.trim(),
        if (_photoDiagnostics != null) 'photo_diagnostics': _photoDiagnostics,
      };
      if (widget.pending != null) {
        await widget.repository.reporterAction(_id, 'edit', {
          ...report,
          'photo': _stagedPath,
        });
        _submitted = true;
        if (mounted) Navigator.of(context).pop((id: _id, openDetails: false));
        return;
      }
      await widget.repository.report(report, photo: _stagedPath);
      _submitted = true;
      if (!mounted) return;
      final reference = widget.repository.reportReference(_id);
      final track = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Report received'),
          content: FutureBuilder(
            future: reference,
            builder: (context, snapshot) => Text(
              snapshot.hasData
                  ? '${snapshot.data} is awaiting maintenance review.'
                  : 'Your report is saved. Open it to view its reference and track progress.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Done'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Track report'),
            ),
          ],
        ),
      );
      if (mounted) {
        Navigator.of(context).pop((id: _id, openDetails: track == true));
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = correctiveError(error));
      } else if (_stagedPath case final path?) {
        unawaited(widget.repository.discardDraft(path));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.pending == null ? 'Report an incident' : 'Edit pending report',
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: FutureBuilder(
            future: _catalog,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: CorrectiveMessage(
                    correctiveError(snapshot.error!),
                    onRetry: () => setState(() {
                      _catalog = widget.repository.catalog();
                    }),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final locations = correctiveRows(snapshot.data!['facilities'])
                  .where(
                    (row) => !widget.administrator || row['can_manage'] == true,
                  )
                  .toList();
              final categories = {
                for (final row in correctiveRows(snapshot.data!['categories']))
                  row['name'] as String,
                if (widget.pending case final report?) report.category,
              }.toList();
              return Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    const CorrectiveHero(
                      title: 'Report a facility fault',
                      subtitle: 'Give campus operations the location and details they need to respond.',
                      icon: Icons.add_alert_outlined,
                    ),
                    correctiveGap(20),
                    if (locations.isEmpty && widget.pending == null)
                      const CorrectiveMessage(
                        'Ask an administrator to add a campus facility before submitting a report.',
                      ),
                    if (locations.isNotEmpty || widget.pending != null) ...[
                      if (_nativeCamera && widget.pending == null) ...[
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : _scan,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(
                            _qr == null
                                ? 'Scan facility QR'
                                : 'Scan another facility QR',
                          ),
                        ),
                        if (_qr != null)
                          const Text(
                            'Location matched to a registered Uni360 QR.',
                          ),
                        correctiveGap(),
                      ],
                      if (widget.pending case final report?)
                        Text(report.facility)
                      else
                        DropdownButtonFormField<String>(
                          key: ValueKey(_facility),
                          initialValue: _facility,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Facility or asset',
                          ),
                          items: locations
                              .map(
                                (row) => DropdownMenuItem<String>(
                                  value: row['id'] as String,
                                  child: Text(
                                    '${row['label']} · ${row['zone']}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) => setState(() {
                                  if (_facility != value) _qr = null;
                                  _facility = value;
                                }),
                          validator: (value) =>
                              value == null ? 'Select a facility.' : null,
                        ),
                      correctiveGap(),
                      TextFormField(
                        controller: _location,
                        enabled: !_busy,
                        maxLength: 160,
                        decoration: const InputDecoration(
                          labelText: 'Exact location',
                          hintText: 'Example: beside the main entrance',
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 3
                            ? 'Enter a more precise location.'
                            : null,
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: categories.contains(_category)
                            ? _category
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Reported category',
                        ),
                        items: categories
                            .map(
                              (label) => DropdownMenuItem(
                                value: label,
                                child: Text(label),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _category = value),
                        validator: (value) =>
                            value == null ? 'Select a category.' : null,
                      ),
                      correctiveGap(),
                      TextFormField(
                        controller: _title,
                        enabled: !_busy,
                        maxLength: 100,
                        decoration: const InputDecoration(
                          labelText: 'Short title',
                          hintText: 'Example: Burst pipe in washroom',
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 5
                            ? 'Enter a title of at least five characters.'
                            : null,
                      ),
                      TextFormField(
                        controller: _description,
                        enabled: !_busy,
                        maxLength: 2000,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'What happened?',
                          alignLabelWithHint: true,
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 10
                            ? 'Describe the fault in at least ten characters.'
                            : null,
                      ),
                      if (!kIsWeb &&
                          defaultTargetPlatform == TargetPlatform.android)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _dictate,
                          icon: const Icon(Icons.mic_none),
                          label: const Text('Dictate description'),
                        ),
                      correctiveGap(),
                      DropdownButtonFormField<String>(
                        initialValue: _urgency,
                        decoration: const InputDecoration(
                          labelText: 'Reported priority',
                        ),
                        items: correctiveUrgencies
                            .map(
                              (label) => DropdownMenuItem(
                                value: label,
                                child: Text(label),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _urgency = value!),
                      ),
                      correctiveGap(8),
                      const Text(
                        'Campus operations confirms the category and priority before assigning work.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                      correctiveGap(16),
                      if (_photo case final photo?) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            photo,
                            height: 180,
                            fit: BoxFit.cover,
                          ),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  if (_stagedPath case final path?) {
                                    unawaited(
                                      widget.repository.discardDraft(path),
                                    );
                                  }
                                  setState(() {
                                    _photo = null;
                                    _photoDiagnostics = null;
                                    _stagedPath = null;
                                  });
                                },
                          child: const Text('Remove photograph'),
                        ),
                      ],
                      if (_photo == null && widget.pending?.reportPhoto != null)
                        const Text(
                          'The current photograph will stay attached unless you replace it.',
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_nativeCamera)
                            OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _choosePhoto(ImageSource.camera),
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Take report photo'),
                            ),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _choosePhoto(ImageSource.gallery),
                            icon: const Icon(Icons.attach_file),
                            label: Text(
                              widget.administrator
                                  ? 'Attach photo (optional)'
                                  : 'Attach report photo',
                            ),
                          ),
                        ],
                      ),
                      if (_error case final error?) ...[
                        correctiveGap(),
                        CorrectiveMessage(error),
                      ],
                      correctiveGap(20),
                      FilledButton.icon(
                        onPressed: _busy ? null : _submit,
                        icon: const Icon(Icons.send_outlined),
                        label: Text(
                          _busy
                              ? 'Please wait'
                              : widget.pending == null
                              ? 'Review and submit'
                              : 'Review changes',
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
