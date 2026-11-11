import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common.dart';
import '../../data/assigned_work_repository.dart';

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
  });

  final AssignedWork initial;
  final String workerId;
  final AssignedWorkActions? actions;

  @override
  State<AssignedWorkDetails> createState() => _AssignedWorkDetailsState();
}

class _AssignedWorkDetailsState extends State<AssignedWorkDetails> {
  late AssignedWork _order = widget.initial;
  late final _notes = TextEditingController(text: widget.initial.notes);
  bool _busy = false;
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
    Future<void> Function(AssignedWorkActions) action,
  ) async {
    final actions = widget.actions;
    if (actions == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(actions);
      final order = await actions.loadOrder(widget.workerId, _order.id);
      if (mounted) setState(() => _order = order);
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(
          () => _error = ['42501', '23514'].contains(error.code)
              ? error.message
              : 'Could not save the work order. Refresh and try again.',
        );
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not finish the request. Refresh and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPhoto(ImageSource source) => _change((actions) async {
    final photo = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    if (photo == null || !mounted) return;
    if (await photo.length() > AssignedWorkRepository.maxPhotoBytes) {
      throw const FormatException('Choose a photo under 10 MB.');
    }
    await actions.attachPhoto(
      widget.workerId,
      _order.id,
      await photo.readAsBytes(),
    );
  });

  Future<void> _submit() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit for approval?'),
        content: const Text(
          'Your administrator will review the checklist and photos.',
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
      await _change((actions) => actions.submit(_order.id, _notes.text));
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
    final canSubmit =
        _editing &&
        _order.checkedItems.length == _order.checklist.length &&
        _order.photoPaths.isNotEmpty;
    final camera =
        !kIsWeb &&
        [
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform);
    return Scaffold(
      appBar: AppBar(
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (camera)
                      OutlinedButton.icon(
                        onPressed: _editing
                            ? () => _pickPhoto(ImageSource.camera)
                            : null,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Take photo'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _editing
                          ? () => _pickPhoto(ImageSource.gallery)
                          : null,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Upload photo'),
                    ),
                  ],
                ),
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
              if (!canSubmit)
                const Text(
                  'Tick all checklist items and upload at least one photo.',
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
