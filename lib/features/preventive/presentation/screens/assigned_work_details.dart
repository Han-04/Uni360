import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/widgets/curved_back_button.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common.dart';
import '../../data/assigned_work_repository.dart';
import '../../data/campus_position.dart';
import 'work_evidence_camera.dart';

String assignedWorkTime(AssignedWork order) {
  final end = sameDay(order.starts, order.ends)
      ? timeLabel(order.ends)
      : '${dateLabel(order.ends)} ${timeLabel(order.ends)}';
  return '${timeLabel(order.starts)} – $end';
}

class AssignedWorkDetails extends StatefulWidget {
  const AssignedWorkDetails({
    super.key,
    required this.initial,
    required this.workerId,
    this.actions,
    this.readPosition = readCampusPosition,
  });

  final AssignedWork initial;
  final String workerId;
  final AssignedWorkActions? actions;
  final Future<CampusPosition> Function() readPosition;

  @override
  State<AssignedWorkDetails> createState() => _AssignedWorkDetailsState();
}

class _AssignedWorkDetailsState extends State<AssignedWorkDetails> {
  late AssignedWork _order = widget.initial;
  late final _notes = TextEditingController(text: widget.initial.notes);
  bool _busy = false;
  bool _verifyAgain = false;
  String? _error;
  bool get _editing =>
      !_busy &&
      widget.actions != null &&
      _order.status == AssignedWorkStatus.inProgress;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _change(
    Future<void> Function(AssignedWorkActions) action, {
    bool checksLocation = false,
  }) async {
    final actions = widget.actions;
    if (actions == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(actions);
      final order = await actions.loadOrder(widget.workerId, _order.id);
      if (mounted) {
        setState(() {
          _order = order;
          if (checksLocation) _verifyAgain = false;
        });
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() {
          if (checksLocation) _verifyAgain = true;
          _error = ['42501', '23514'].contains(error.code)
              ? error.message
              : 'Could not save the work order. Refresh and try again.';
        });
      }
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          if (checksLocation) _verifyAgain = true;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (checksLocation) _verifyAgain = true;
          _error = 'Could not finish the request. Refresh and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyLocation() => _change((actions) async {
    await actions.verifyLocation(_order.id, await widget.readPosition());
  }, checksLocation: true);

  Future<void> _takePhoto() => _change((actions) async {
    final photo = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const WorkEvidenceCamera()),
    );
    if (photo == null || !mounted) return;
    await actions.attachPhoto(
      widget.workerId,
      _order.id,
      photo,
      await widget.readPosition(),
    );
  }, checksLocation: true);

  Future<void> _submit() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit for approval?'),
        content: const Text(
          'Uni360 will check your location again before sending the checklist and photos to your administrator.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await _change((actions) async {
        await actions.submit(
          _order.id,
          _notes.text,
          await widget.readPosition(),
        );
      }, checksLocation: true);
    }
  }

  void _viewPhoto(String path) {
    final url = widget.actions!.photoUrl(path);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Evidence photo'),
        content: FutureBuilder<String>(
          future: url,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('Could not open the photo.');
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            return Image.network(
              snapshot.data!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Text('Could not load the photo.'),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inProgress = _order.status == AssignedWorkStatus.inProgress;
    final verified = _order.locationVerifiedAt != null && !_verifyAgain;
    final phoneApp = supportsCampusCapture;
    final canVerify = _editing && phoneApp;
    final canSubmit =
        canVerify &&
        verified &&
        _order.checkedItems.length == _order.checklist.length &&
        _order.hasCameraPhoto;
    return Scaffold(
      appBar: AppBar(
        leading: CurvedBackButton.forRoute(context),
        title: const Text('Work order'),
        actions: [
          if (widget.actions != null)
            IconButton(
              tooltip: 'Refresh work order',
              icon: const Icon(Icons.refresh),
              onPressed: _busy ? null : () => _change((_) async {}),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SectionHeading(_order.title),
            Text(_order.status.label),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 10),
            Text('${dateLabel(_order.starts)} · ${assignedWorkTime(_order)}'),
            for (final location in _order.locations) Text(location),
            if (_order.feedback.isNotEmpty) ...[
              const SectionHeading('Review feedback'),
              Text(_order.feedback),
            ],
            const SectionHeading('Instructions'),
            Text(_order.instructions),
            if (inProgress || _order.locationVerifiedAt != null) ...[
              const SectionHeading('Location verification'),
              if (verified)
                const Text('Verified inside TAR UMT Kuala Lumpur campus')
              else
                const Text(
                  'Verify that you are inside TAR UMT Kuala Lumpur campus.',
                ),
              if (inProgress)
                OutlinedButton.icon(
                  onPressed: canVerify ? _verifyLocation : null,
                  icon: const Icon(Icons.my_location),
                  label: Text(verified ? 'Verify again' : 'Verify location'),
                ),
              if (inProgress && !phoneApp)
                const Text(
                  'GPS verification requires the Uni360 Android or iOS app.',
                ),
            ],
            if (_order.checklist.isNotEmpty) ...[
              const SectionHeading('Checklist'),
              for (final (index, item) in _order.checklist.indexed)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(item),
                  value: _order.checkedItems.contains(index),
                  onChanged: _editing
                      ? (checked) => _change(
                          (actions) =>
                              actions.checkItem(_order.id, index, checked!),
                        )
                      : null,
                ),
            ],
            if (widget.actions != null &&
                _order.status == AssignedWorkStatus.assigned) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _change((actions) => actions.start(_order.id)),
                child: const Text('Start task'),
              ),
            ],
            if (inProgress || _order.photoPaths.isNotEmpty) ...[
              const SectionHeading('Photo evidence'),
              for (final (index, path) in _order.photoPaths.indexed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.image_outlined),
                  title: Text('Photo ${index + 1}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.actions == null ? null : () => _viewPhoto(path),
                ),
              if (inProgress)
                OutlinedButton.icon(
                  onPressed: canVerify && verified ? _takePhoto : null,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Take photo'),
                ),
              if (inProgress && !phoneApp)
                const Text(
                  'Photo capture requires the Uni360 Android or iOS app.',
                )
              else if (inProgress && !verified)
                const Text('Verify your location to enable the camera.'),
            ],
            if (inProgress) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _notes,
                enabled: _editing,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              const SizedBox(height: 12),
              if (phoneApp && !canSubmit)
                const Text(
                  'Verify your location, tick all checklist items and take at least one photo.',
                ),
              FilledButton(
                onPressed: canSubmit ? _submit : null,
                child: const Text('Submit for approval'),
              ),
            ] else if (_order.notes.isNotEmpty) ...[
              const SectionHeading('Notes'),
              Text(_order.notes),
            ],
          ],
        ),
      ),
    );
  }
}
