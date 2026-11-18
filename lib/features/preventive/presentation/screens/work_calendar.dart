import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/worker_calendar_dialog.dart';
import '../../data/assigned_work_repository.dart';

class WorkCalendar extends StatelessWidget {
  const WorkCalendar({super.key, required this.selected, required this.orders});

  final DateTime? selected;
  final Future<List<AssignedWork>> orders;

  static const _overdueColor = Color(0xFFB12D38);

  @override
  Widget build(BuildContext context) => FutureBuilder<List<AssignedWork>>(
    future: orders,
    builder: (context, snapshot) {
      final dates = <DateTime, bool>{};
      for (final order in snapshot.data ?? const <AssignedWork>[]) {
        final day = DateUtils.dateOnly(order.starts);
        dates[day] =
            dates[day] == true ||
            order.displayStatus == AssignedWorkStatus.overdue;
      }
      return WorkerCalendarDialog(
        title: 'Task calendar',
        today: malaysiaToday(),
        selected: selected,
        firstDate: DateTime(1),
        lastDate: DateTime(9999, 12, 31),
        markers: {
          for (final entry in dates.entries)
            entry.key: (
              color: entry.value
                  ? _overdueColor
                  : DateUtils.isSameDay(entry.key, selected)
                  ? Colors.white
                  : WorkerColors.blue,
              label: entry.value ? 'Overdue tasks' : 'Has tasks',
            ),
        },
        footer: switch (snapshot.connectionState) {
          ConnectionState.waiting => const LinearProgressIndicator(
            semanticsLabel: 'Loading task markers',
          ),
          _ when snapshot.hasError => const Text(
            'Task markers are unavailable.',
            style: TextStyle(color: AppColors.muted),
          ),
          _ => const Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 6,
            children: [
              Text('●  Tasks', style: TextStyle(color: WorkerColors.deepBlue)),
              Text('●  Overdue', style: TextStyle(color: _overdueColor)),
            ],
          ),
        },
      );
    },
  );
}
