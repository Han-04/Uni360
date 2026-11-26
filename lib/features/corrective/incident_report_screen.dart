import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/curved_back_button.dart';
import '../preventive/admin/admin_widgets.dart';
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
    this.onExit,
  });
  final CorrectiveRepository repository;
  final CorrectiveIncident? pending;
  final bool administrator;
  final ValueChanged<IncidentReportResult?>? onExit;

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
  Uint8List? _photo;
  Uint8List? _video;
  String? _videoName;
  CorrectiveRow? _photoDiagnostics;
  bool _busy = false;
  bool _submitted = false;
  bool get _canOpenForm =>
      widget.pending?.canEditReport(widget.repository.actorId) ?? true;
  bool get _nativeCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  void _exit(IncidentReportResult? result) {
    if (widget.onExit case final exit?) {
      exit(result);
    } else {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _chooseEvidence() => showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (kIsWeb || _nativeCamera)
            _evidenceOption(
              sheet,
              'Take a photo',
              Icons.photo_camera_outlined,
              ImageSource.camera,
            ),
          if (_nativeCamera)
            _evidenceOption(
              sheet,
              'Record a video',
              Icons.videocam_outlined,
              ImageSource.camera,
              video: true,
            ),
          _evidenceOption(
            sheet,
            'Choose a photo',
            Icons.image_outlined,
            ImageSource.gallery,
          ),
          _evidenceOption(
            sheet,
            'Choose a video',
            Icons.video_library_outlined,
            ImageSource.gallery,
            video: true,
          ),
        ],
      ),
    ),
  );

  Widget _evidenceOption(
    BuildContext sheet,
    String label,
    IconData icon,
    ImageSource source, {
    bool video = false,
  }) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    subtitle: video ? const Text('Up to 30 seconds · MP4 or MOV') : null,
    onTap: () {
      Navigator.pop(sheet);
      unawaited(_pickEvidence(source, video: video));
    },
  );

  Future<void> _scan() async {
    final code = await Navigator.of(context).push(
      correctivePage<String>(
        context,
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

  void _clearEvidence() {
    if (_stagedPath case final path?) {
      unawaited(widget.repository.discardDraft(path));
    }
    _photo = null;
    _video = null;
    _videoName = null;
    _photoDiagnostics = null;
    _stagedPath = null;
  }

  Future<void> _pickEvidence(ImageSource source, {required bool video}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picker = ImagePicker();
      final file = video
          ? await picker.pickVideo(
              source: source,
              maxDuration: const Duration(seconds: 30),
            )
          : await picker.pickImage(
              source: source,
              maxWidth: 1600,
              imageQuality: 82,
            );
      if (file == null) return;
      if (await file.length() > 10 * 1024 * 1024) {
        throw const CorrectiveException(
          'Choose an attachment of 10 MB or smaller.',
        );
      }
      final bytes = await file.readAsBytes();
      final diagnostics = video ? null : await inspectCorrectivePhoto(bytes);
      if (!mounted) return;
      setState(() {
        _clearEvidence();
        _photo = video ? null : bytes;
        _video = video ? bytes : null;
        _videoName = video ? file.name : null;
        _photoDiagnostics = diagnostics;
      });
    } on CorrectiveException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(
          () => _error = 'The attachment could not be opened. Check permissions or choose another file.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_canOpenForm ||
        !_form.currentState!.validate() ||
        _facility == null ||
        _busy) {
      return;
    }
    if (!widget.administrator &&
        _photo == null &&
        _video == null &&
        widget.pending?.reportPhoto == null) {
      setState(
        () => _error =
            'Attach a photo or a video of the fault before continuing.',
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
                const Text(
                  'Uni360 assesses category and priority when you submit.',
                ),
                if (_videoName case final name?) Text('Video: $name'),
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
      if ((_photo ?? _video) case final evidence?) {
        _stagedPath ??= await widget.repository.upload(
          _id,
          evidence,
          report: true,
          video: _video != null,
        );
      }
      final attachment = _stagedPath ?? widget.pending?.reportPhoto;
      if (attachment != null &&
          (_stagedPath != null || !correctiveIsVideo(attachment))) {
        try {
          await widget.repository.inspectReportEvidence(attachment);
        } on Exception {
          if (correctiveIsVideo(attachment)) rethrow;
          // The server can accept a photo and use text triage if its evidence check is unavailable.
        }
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
        if (mounted) _exit((id: _id, openDetails: false));
        return;
      }
      await widget.repository.report(report, photo: _stagedPath);
      _submitted = true;
      if (!mounted) return;
      final receipt = widget.repository.reportReceipt(_id);
      final track = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Report received'),
          content: FutureBuilder(
            future: receipt,
            builder: (context, snapshot) => Text(
              snapshot.data ??
                  'Your report is saved. Open it to track progress.',
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
        _exit((id: _id, openDetails: track == true));
      }
    } on Exception catch (error) {
      if (mounted) {
        final message = correctiveError(error);
        setState(() {
          _error = message;
          if (widget.pending == null &&
              const {
                'This campus location is inactive. Select another facility.',
                'Select an existing campus facility.',
              }.contains(message)) {
            _facility = null;
            _qr = null;
            _catalog = widget.repository.catalog();
            _error = 'This location is no longer available. Select another facility to continue.';
          }
        });
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
      leading: widget.onExit == null
          ? CurvedBackButton.forRoute(context)
          : IconButton(
              icon: CurvedBackButton.icon,
              tooltip: 'Back to incidents',
              onPressed: _busy ? null : () => _exit(null),
            ),
      title: Text(
        widget.pending == null ? 'Report an incident' : 'Edit pending report',
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: FutureBuilder(
            future: _canOpenForm ? _catalog : null,
            builder: (context, snapshot) {
              if (!_canOpenForm) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: CorrectiveMessage(
                    'Only the original reporter can edit a report awaiting review.',
                  ),
                );
              }
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
              return Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    if (widget.administrator)
                      const AdminHeading('Report a facility fault')
                    else ...[
                      const CorrectiveHero(
                        title: 'Report a facility fault',
                        subtitle: 'Give campus operations the location and details they need to respond.',
                        icon: Icons.add_alert_outlined,
                        gradientColors: [
                          WorkerColors.blue,
                          WorkerColors.deepBlue,
                        ],
                      ),
                      correctiveGap(20),
                    ],
                    if (locations.isEmpty && widget.pending == null)
                      const CorrectiveMessage(
                        'No active facilities are available. Ask an administrator to check the campus catalog.',
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
                      correctiveGap(16),
                      if (widget.pending?.reportPhoto case final saved?) ...[
                        Text(
                          _photo != null || _video != null
                              ? 'Original attachment'
                              : 'Current attachment',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        correctiveGap(8),
                        CorrectivePhoto(
                          widget.repository,
                          saved,
                          key: ValueKey(saved),
                          label: 'View current report photograph',
                          previewHeight: 180,
                        ),
                        correctiveGap(),
                      ],
                      if ((_photo != null || _video != null) &&
                          widget.pending?.reportPhoto != null)
                        const Text(
                          'Replacement attachment',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      if (_photo case final photo?)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            photo,
                            height: 180,
                            fit: BoxFit.cover,
                          ),
                        ),
                      if (_videoName case final name?)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.videocam_outlined),
                          title: Text(name, overflow: TextOverflow.ellipsis),
                        ),
                      if (_photo != null || _video != null)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(_clearEvidence),
                          child: const Text('Remove attachment'),
                        ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _chooseEvidence,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(
                          _photo != null ||
                                  _video != null ||
                                  widget.pending?.reportPhoto != null
                              ? 'Replace photo or video'
                              : 'Add photo or video',
                        ),
                      ),
                      correctiveGap(8),
                      Text(
                        widget.administrator
                            ? 'Optional. Videos must be MP4 or MOV, up to 30 seconds and 10 MB.'
                            : 'One attachment, up to 10 MB. Videos must be MP4 or MOV and no longer than 30 seconds.',
                        style: const TextStyle(color: AppColors.muted),
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
