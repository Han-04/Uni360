import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common.dart';
import '../../application/preventive_controller.dart';
import '../../domain/work_order.dart';
import '../widgets/work_order_card.dart';
import 'evidence_screen.dart';
import 'verification_screen.dart';

class WorkOrderScreen extends StatefulWidget {
  const WorkOrderScreen({
    super.key,
    required this.controller,
    required this.order,
  });
  final PreventiveController controller;
  final WorkOrder order;
  @override
  State<WorkOrderScreen> createState() => _WorkOrderScreenState();
}

class _WorkOrderScreenState extends State<WorkOrderScreen> {
  late final _notes = TextEditingController(text: widget.order.notes);
  late bool _attested = widget.order.attested;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.order.isEditable) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    try {
      widget.controller.saveDraft(widget.order, _notes.text, _attested);
      showMessage(context, 'Draft saved for this demo session.');
    } on StateError catch (e) {
      showMessage(context, e.message);
    }
  }

  Future<void> _submit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit for review?'),
        content: const Text(
          'Your checklist, evidence and notes will be sent for administrator review. The work order will be completed after approval.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit evidence'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    try {
      widget.controller.submit(widget.order, _notes.text, _attested);
      showMessage(
        context,
        'Evidence submitted. Awaiting administrator review.',
      );
    } on StateError catch (e) {
      showMessage(context, e.message);
    }
  }

  Future<void> _contact() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Facilities support',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text('Nur Aina · Facilities Administrator'),
              const SizedBox(height: 8),
              const SelectableText('facilities@uni360.example'),
              const SizedBox(height: 16),
              const InfoBanner(
                'Sample contact only. This demo does not send messages.',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text:
                            'Work order ${widget.order.id}: ${widget.order.title}\nFacility: ${widget.order.facility.name}\nPlease assist with this work order.',
                      ),
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                    if (mounted) {
                      showMessage(this.context, 'Work order details copied.');
                    }
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy work order details'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final o = widget.order;
      final editable = o.isEditable;
      final elapsed = o.startedAt == null
          ? Duration.zero
          : (o.submittedAt ?? DateTime.now()).difference(o.startedAt!);
      final canSubmit =
          editable &&
          o.completedItems == o.checklist.length &&
          o.evidence.length >= o.requiredPhotos &&
          _attested;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Work order'),
          actions: [
            IconButton(
              tooltip: 'Contact administrator',
              onPressed: _contact,
              icon: const Icon(Icons.support_agent),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  o.id,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  o.title,
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusChip(o.status),
                    Text(
                      '${o.priority.label} priority · ${o.category}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (o.adminRemarks != null) ...[
                  InfoBanner(
                    'Administrator: ${o.adminRemarks}',
                    warning: o.status != WorkStatus.completed,
                  ),
                  const SizedBox(height: 16),
                ],
                if (o.status == WorkStatus.reworkRequired) ...[
                  FilledButton.icon(
                    onPressed: () {
                      try {
                        widget.controller.restartRework(o);
                        _notes.clear();
                        setState(() => _attested = false);
                        showMessage(
                          context,
                          'Rework acknowledged. Check in again and capture new evidence.',
                        );
                      } on StateError catch (e) {
                        showMessage(context, e.message);
                      }
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Acknowledge & begin rework'),
                  ),
                  const SizedBox(height: 16),
                ],
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            color: AppColors.teal,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  o.facility.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  o.facility.location,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Asset ${o.facility.assetTag}',
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 32),
                      _DetailRow(
                        'Scheduled',
                        '${dateLabel(o.scheduledAt)} · ${timeLabel(o.scheduledAt)}',
                      ),
                      const SizedBox(height: 12),
                      _DetailRow(
                        'Due',
                        '${dateLabel(o.dueAt)} · ${timeLabel(o.dueAt)}',
                      ),
                      const SizedBox(height: 12),
                      _DetailRow(
                        'Plan',
                        '${o.frequency} · ${o.estimatedMinutes} min',
                      ),
                    ],
                  ),
                ),
                const SectionHeading('Work instructions'),
                Text(
                  o.instructions,
                  style: const TextStyle(color: AppColors.muted, height: 1.6),
                ),
                if (o.status == WorkStatus.assigned) ...[
                  const SizedBox(height: 20),
                  const InfoBanner(
                    'Verify your location and the facility QR before starting. Complete every checklist item and capture the required evidence.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VerificationScreen(
                          controller: widget.controller,
                          order: o,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.my_location),
                    label: const Text('Verify location & check in'),
                  ),
                ],
                if (o.startedAt != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Text(
                          editable ? 'WORK TIMER' : 'RECORDED WORK DURATION',
                          style: const TextStyle(
                            color: Color(0xFFBDD0E1),
                            fontSize: 10,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          durationLabel(
                            elapsed.isNegative ? Duration.zero : elapsed,
                          ),
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SectionHeading(
                  'Checklist',
                  action: Text(
                    '${o.completedItems}/${o.checklist.length}',
                    style: const TextStyle(
                      color: AppColors.teal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: o.checklist
                        .map(
                          (item) => CheckboxListTile(
                            value: item.done,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              item.label,
                              style: const TextStyle(fontSize: 14, height: 1.4),
                            ),
                            onChanged: editable
                                ? (value) {
                                    widget.controller.toggleChecklist(
                                      o,
                                      item,
                                      value ?? false,
                                    );
                                    setState(() => _attested = false);
                                  }
                                : null,
                          ),
                        )
                        .toList(),
                  ),
                ),
                SectionHeading(
                  'Completion evidence',
                  action: Text(
                    '${o.evidence.length}/${o.requiredPhotos}',
                    style: const TextStyle(
                      color: AppColors.teal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (o.evidence.isEmpty)
                  const SurfaceCard(
                    child: Text(
                      'No evidence captured yet. Complete check-in to enable capture.',
                      style: TextStyle(color: AppColors.muted, height: 1.5),
                    ),
                  )
                else
                  ...o.evidence.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SurfaceCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.image_outlined,
                              color: AppColors.teal,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Simulated capture ${entry.key + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${dateLabel(entry.value.capturedAt)} · ${timeLabel(entry.value.capturedAt)}',
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    'GPS ${entry.value.latitude.toStringAsFixed(5)}, ${entry.value.longitude.toStringAsFixed(5)}',
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (editable) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EvidenceScreen(
                          controller: widget.controller,
                          order: o,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Capture evidence'),
                  ),
                ],
                if ((widget.controller.previousEvidence[o.id]?.length ?? 0) >
                    0) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${widget.controller.previousEvidence[o.id]!.length} earlier captures retained in rework history.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
                if (editable) ...[
                  const SectionHeading('Completion notes'),
                  TextField(
                    controller: _notes,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      hintText: 'Record readings, work performed or anything the administrator should know.',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _attested,
                    onChanged: (v) => setState(() => _attested = v ?? false),
                    title: const Text(
                      'I confirm all checklist items were completed correctly.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: canSubmit ? _submit : null,
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Submit for review'),
                  ),
                  if (!canSubmit)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'Complete the checklist, add the required captures and confirm your work to submit.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _save,
                    child: const Text('Save as draft'),
                  ),
                ] else if (o.notes.isNotEmpty) ...[
                  const SectionHeading('Submitted notes'),
                  SurfaceCard(
                    child: Text(o.notes, style: const TextStyle(height: 1.5)),
                  ),
                ],
                if (o.status == WorkStatus.evidenceSubmitted) ...[
                  const SizedBox(height: 20),
                  const InfoBanner(
                    'Evidence submitted · Awaiting administrator review. Your work order will be completed only after approval.',
                  ),
                ],
                const SectionHeading('Activity timeline'),
                SurfaceCard(
                  child: Column(
                    children: [
                      for (var i = 0; i < o.history.length; i++)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: i == o.history.length - 1 ? 0 : 20,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.check_circle,
                                  size: 18,
                                  color: AppColors.teal,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      o.history[i].label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${dateLabel(o.history[i].at)} · ${timeLabel(o.history[i].at)}',
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                    if (o.history[i].detail != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        o.history[i].detail!,
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 12,
                                          height: 1.5,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (o.status == WorkStatus.evidenceSubmitted)
                        const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.hourglass_top,
                            color: AppColors.muted,
                          ),
                          title: Text(
                            'Administrator review pending',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _contact,
                  icon: const Icon(Icons.support_agent),
                  label: const Text('Contact administrator'),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 88,
        child: Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}
