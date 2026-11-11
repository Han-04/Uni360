import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common.dart';
import '../../application/preventive_controller.dart';
import '../../domain/work_order.dart';

class EvidenceScreen extends StatefulWidget {
  const EvidenceScreen({
    super.key,
    required this.controller,
    required this.order,
  });
  final PreventiveController controller;
  final WorkOrder order;
  @override
  State<EvidenceScreen> createState() => _EvidenceScreenState();
}

class _EvidenceScreenState extends State<EvidenceScreen> {
  bool _capturing = false;
  Future<void> _capture() async {
    setState(() => _capturing = true);
    try {
      await widget.controller.capture(widget.order);
    } on StateError catch (e) {
      if (mounted) {
        showMessage(context, e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _capturing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Capture evidence')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const InfoBanner(
                'Simulated camera · Each capture adds a sample evidence record with a timestamp and facility coordinates. No photograph is taken.',
              ),
              const SizedBox(height: 20),
              Container(
                height: 260,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.photo_camera_outlined,
                      size: 72,
                      color: Color(0xFF8DCCC4),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'DEMO CAMERA',
                      style: TextStyle(
                        color: Colors.white,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.order.facility.assetTag,
                      style: const TextStyle(color: Color(0xFFBDD0E1)),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Camera-only capture will be connected later.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFBDD0E1), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _capturing ? null : _capture,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Capture sample evidence'),
              ),
              SectionHeading(
                '${widget.order.evidence.length} / ${widget.order.requiredPhotos} required captures',
              ),
              ...widget.order.evidence.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SurfaceCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE7F4F2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.image_outlined,
                            color: AppColors.teal,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sample capture ${entry.key + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${dateLabel(entry.value.capturedAt)} · ${timeLabel(entry.value.capturedAt)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                              Text(
                                '${entry.value.latitude.toStringAsFixed(5)}, ${entry.value.longitude.toStringAsFixed(5)}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove sample capture',
                          onPressed: () => widget.controller.removeEvidence(
                            widget.order,
                            entry.value,
                          ),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done · Return to checklist'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
