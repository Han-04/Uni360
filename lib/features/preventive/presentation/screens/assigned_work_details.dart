import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common.dart';
import '../../../../core/widgets/curved_back_button.dart';
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
      _order.displayStatus == AssignedWorkStatus.inProgress;
  Timer? _dayRefresh;

  @override
  void initState() {
    super.initState();
    _dayRefresh = Timer.periodic(
      const Duration(minutes: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _dayRefresh?.cancel();
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
      MaterialPageRoute(
        builder: (_) =>
            InheritedTheme.captureAll(context, const WorkEvidenceCamera()),
      ),
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
    final inProgress = _order.displayStatus == AssignedWorkStatus.inProgress;
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
            _WorkOrderSummary(order: _order),
            if (_order.displayStatus == AssignedWorkStatus.overdue)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: InfoBanner(
                  'The scheduled day has passed. Contact your administrator about this overdue task.',
                  warning: true,
                ),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_order.feedback.isNotEmpty) ...[
              const SectionHeading('Review feedback'),
              Text(_order.feedback),
            ],
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
              const SizedBox(height: 14),
              _WorkOrderChecklist(
                order: _order,
                onChanged: _editing
                    ? (index, checked) => _change(
                        (actions) =>
                            actions.checkItem(_order.id, index, checked),
                      )
                    : null,
              ),
            ],
            if (widget.actions != null &&
                _order.displayStatus == AssignedWorkStatus.assigned) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () {
                        if (_order.displayStatus ==
                            AssignedWorkStatus.assigned) {
                          _change((actions) => actions.start(_order.id));
                        } else {
                          setState(() {});
                        }
                      },
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

class _WorkOrderSummary extends StatelessWidget {
  const _WorkOrderSummary({required this.order});

  final AssignedWork order;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            order.title,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: ShapeDecoration(
              color: order.displayStatus == AssignedWorkStatus.overdue
                  ? const Color(0xFFFFE4E4)
                  : WorkerColors.tint,
              shape: const StadiumBorder(),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                order.displayStatus.label,
                style: text.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: order.displayStatus == AssignedWorkStatus.overdue
                      ? const Color(0xFF9C2525)
                      : WorkerColors.deepBlue,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _metadata(
            Icons.calendar_today_outlined,
            '${dateLabel(order.starts)} · ${assignedWorkTime(order)}',
          ),
          for (final location in order.locations) ...[
            const SizedBox(height: 7),
            _metadata(Icons.place_outlined, location),
          ],
          if (order.instructions.trim().isNotEmpty) ...[
            const Divider(height: 24),
            Text(
              'Instructions',
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              order.instructions,
              style: text.bodyMedium?.copyWith(height: 1.45),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metadata(IconData icon, String label) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 17, color: WorkerColors.blue),
      const SizedBox(width: 8),
      Expanded(child: Text(label)),
    ],
  );
}

class _WorkOrderChecklist extends StatelessWidget {
  const _WorkOrderChecklist({required this.order, required this.onChanged});

  final AssignedWork order;
  final void Function(int index, bool checked)? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = order.checklist.length;
    final completed = order.checkedItems
        .where((index) => index >= 0 && index < total)
        .length;
    final progress = '$completed/$total completed';
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Checklist',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            children: [
              const Text('Progress', style: TextStyle(color: AppColors.muted)),
              Text(
                progress,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 7),
          LinearProgressIndicator(
            value: completed / total,
            semanticsLabel: 'Checklist progress',
            minHeight: 6,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: WorkerColors.tint,
            color: WorkerColors.blue,
          ),
          const SizedBox(height: 14),
          for (final (index, item) in order.checklist.indexed) ...[
            if (index > 0) const SizedBox(height: 7),
            _item(context, index, item),
          ],
        ],
      ),
    );
  }

  Widget _item(BuildContext context, int index, String item) {
    final checked = order.checkedItems.contains(index);
    return Material(
      color: checked ? WorkerColors.background : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFDDE3EC)),
      ),
      clipBehavior: Clip.antiAlias,
      child: CheckboxListTile(
        contentPadding: const EdgeInsets.only(left: 2, right: 10),
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
        title: Text(
          item,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: checked ? AppColors.muted : AppColors.navy,
            decoration: checked ? TextDecoration.lineThrough : null,
          ),
        ),
        value: checked,
        onChanged: onChanged == null
            ? null
            : (value) => onChanged!(index, value == true),
      ),
    );
  }
}
