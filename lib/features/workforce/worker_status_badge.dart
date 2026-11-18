import 'dart:async';

import 'package:flutter/material.dart';

import '../preventive/data/assigned_work_repository.dart' show malaysiaToday;
import 'worker_leave_repository.dart';

class WorkerStatusBadge extends StatefulWidget {
  const WorkerStatusBadge({
    super.key,
    required this.workerId,
    required this.repository,
  });

  final String workerId;
  final WorkerLeaveRepository repository;

  @override
  State<WorkerStatusBadge> createState() => _WorkerStatusBadgeState();
}

class _WorkerStatusBadgeState extends State<WorkerStatusBadge>
    with WidgetsBindingObserver {
  String? _status;
  Timer? _timer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final status = await widget.repository.workerStatus(
        widget.workerId,
        malaysiaToday(),
      );
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted && _status == null) {
        setState(() => _status = 'Status unavailable');
      }
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final (background, foreground) = switch (status) {
      'On leave' => (const Color(0xFFFFEDC0), const Color(0xFF653C00)),
      'Active' => (colors.primaryContainer, colors.onPrimaryContainer),
      _ => (colors.surfaceContainerHighest, colors.onSurfaceVariant),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          status,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: foreground),
        ),
      ),
    );
  }
}
