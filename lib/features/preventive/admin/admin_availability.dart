import 'package:flutter/material.dart';

import 'admin_data.dart';
import 'admin_widgets.dart';

class AdminAvailability extends StatefulWidget {
  const AdminAvailability({
    super.key,
    required this.data,
    required this.workerId,
  });
  final AdminData data;
  final String workerId;

  @override
  State<AdminAvailability> createState() => _AdminAvailabilityState();
}

class _AdminAvailabilityState extends State<AdminAvailability> {
  static const _noAssignedTasksMessage = 'No assigned task for this date';

  AdminData get data => widget.data;
  String get workerId => widget.workerId;
  late DateTime month = DateTime.utc(adminToday().year, adminToday().month);
  DateTime? day;
  late var listing = load();
  late var performance = loadPerformance();
  Future<List<AdminRow>>? tasks;

  Future<List<AdminRow>> load() => data
      .table('worker_availability')
      .select(
        'availability_id,availability,shift_start,shift_end,availability_status,leave_status',
      )
      .eq('worker_id', workerId)
      .lt('shift_start', midnight(DateTime.utc(month.year, month.month + 1)))
      .gt('shift_end', midnight(month))
      .order('shift_start', ascending: true);

  Future<List<AdminRow>> loadTasks(DateTime date) => data
      .table('preventive_work_order')
      .select(
        '$orderFields,preventive_work_completion(work_order_id,actual_minutes)',
      )
      .eq('worker_id', workerId)
      .isFilter('cancelled_at', null)
      .gte('scheduled_for', midnight(date))
      .lt('scheduled_for', midnight(date.add(const Duration(days: 1))))
      .order('scheduled_for', ascending: true);

  Future<List<AdminRow>> loadPerformance() => data.all(
    data
        .table('preventive_work_completion')
        .select('work_order_id,completed_at,actual_minutes')
        .eq('worker_id', workerId)
        .gte('completed_at', midnight(month))
        .lt(
          'completed_at',
          midnight(DateTime.utc(month.year, month.month + 1)),
        ),
    'completed_at',
    'work_order_id',
  );

  void showDay(DateTime date) => setState(() {
    day = date;
    tasks = loadTasks(date);
  });

  void move(int months) => setState(() {
    month = DateTime.utc(month.year, month.month + months);
    day = null;
    tasks = null;
    listing = load();
    performance = loadPerformance();
  });

  List<AdminRow> dayRows(DateTime date, List<AdminRow> records) {
    final start = DateTime.parse(midnight(date));
    final end = start.add(const Duration(days: 1));
    return [
      for (final row in records)
        if (DateTime.parse(row['shift_start'] as String).isBefore(end) &&
            DateTime.parse(row['shift_end'] as String).isAfter(start))
          row,
    ];
  }

  bool onLeave(DateTime date, List<AdminRow> records) =>
      dayRows(date, records).any(
        (row) =>
            row['leave_status']?.toString().trim().toLowerCase() == 'approved',
      );

  Widget calendar(List<AdminRow> rows) {
    final count = DateTime.utc(month.year, month.month + 1, 0).day;
    return SizedBox(
      width: 490,
      child: Card(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => move(-1),
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Previous month',
                  ),
                  Text(
                    MaterialLocalizations.of(context).formatMonthYear(month),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    onPressed: () => move(1),
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Next month',
                  ),
                ],
              ),
              LayoutBuilder(
                builder: (context, size) {
                  final width = size.maxWidth / 7;
                  return Wrap(
                    children: [
                      for (final name in [
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun',
                      ])
                        SizedBox(
                          width: width,
                          height: 32,
                          child: Center(child: Text(name)),
                        ),
                      for (var index = 1; index < month.weekday; index++)
                        SizedBox(width: width, height: 44),
                      for (var index = 1; index <= count; index++)
                        dateButton(
                          DateTime.utc(month.year, month.month, index),
                          rows,
                          width,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              const Text('Green · Available   Yellow · Approved leave'),
            ],
          ),
        ),
      ),
    );
  }

  Widget dateButton(DateTime date, List<AdminRow> rows, double width) {
    final leave = onLeave(date, rows);
    final available =
        !leave &&
        dayRows(
          date,
          rows,
        ).any((row) => row['availability_status'] == 'available');
    final label = MaterialLocalizations.of(context).formatFullDate(date);
    return SizedBox(
      width: width,
      height: 44,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Tooltip(
          message:
              '$label${leave
                  ? " · Approved leave"
                  : available
                  ? " · Available"
                  : ""}',
          child: TextButton(
            onPressed: leave ? null : () => showDay(date),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: day == date && !leave
                  ? const Color(0xFFACE0D8)
                  : available
                  ? const Color(0xFFE2F5ED)
                  : null,
              disabledBackgroundColor: leave ? const Color(0xFFFFE8A4) : null,
              disabledForegroundColor: leave ? const Color(0xFF513800) : null,
            ),
            child: Text('${date.day}'),
          ),
        ),
      ),
    );
  }

  Widget timestamp(
    AdminRow values,
    String key,
    String label,
    VoidCallback refresh,
  ) {
    final current = values[key] as DateTime;
    final date = DateTime.utc(current.year, current.month, current.day);
    final time = TimeOfDay.fromDateTime(current);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(label),
        OutlinedButton(
          onPressed: () async {
            final selected = await pickAdminDate(context, date);
            if (selected != null) {
              values[key] = DateTime.utc(
                selected.year,
                selected.month,
                selected.day,
                time.hour,
                time.minute,
              );
              refresh();
            }
          },
          child: Text(isoDate(current)),
        ),
        OutlinedButton(
          onPressed: () async {
            final selected = await showTimePicker(
              context: context,
              initialTime: time,
            );
            if (selected != null) {
              values[key] = DateTime.utc(
                current.year,
                current.month,
                current.day,
                selected.hour,
                selected.minute,
              );
              refresh();
            }
          },
          child: Text(current.toIso8601String().substring(11, 16)),
        ),
      ],
    );
  }

  Future<void> edit(AdminRow row) async {
    final saved = await adminForm(
      context,
      'Edit availability',
      {
        'availability': row['availability'],
        'start': malaysiaDateTime(row['shift_start']),
        'end': malaysiaDateTime(row['shift_end']),
        'availability_status': row['availability_status'] ?? 'available',
        'leave_status': row['leave_status'] ?? 'none',
      },
      (values, refresh) => [
        const Text('Malaysia time'),
        const SizedBox(height: 10),
        adminText(values, 'availability', 'Label', required: true, max: 120),
        timestamp(values, 'start', 'Starts', refresh),
        const SizedBox(height: 8),
        timestamp(values, 'end', 'Ends', refresh),
        const SizedBox(height: 8),
        adminSelect(values, 'availability_status', 'Availability', {
          if (row['availability_status'] case final String value) value: value,
          'available': 'Available',
          'unavailable': 'Unavailable',
        }, refresh),
        adminSelect(values, 'leave_status', 'Leave status', {
          if (row['leave_status'] case final String value) value: value,
          'none': 'None',
          'pending': 'Pending',
          'approved': 'Approved',
          'rejected': 'Rejected',
        }, refresh),
      ],
      (values) async {
        final start = values['start'] as DateTime;
        final end = values['end'] as DateTime;
        if (!end.isAfter(start)) {
          throw const FormatException('The end must be after the start.');
        }
        final payload = {
          'availability': fieldText(values, 'availability'),
          'shift_start': start
              .subtract(const Duration(hours: 8))
              .toIso8601String(),
          'shift_end': end.subtract(const Duration(hours: 8)).toIso8601String(),
          'availability_status': values['availability_status'],
          'leave_status': values['leave_status'],
        };
        final table = data.table('worker_availability');
        await data.write(
          table
              .update(payload)
              .eq('worker_id', workerId)
              .eq('availability_id', row['availability_id']),
          'availability_id',
        );
        month = DateTime.utc(start.year, start.month);
      },
    );
    if (saved && mounted) {
      move(0);
      adminMessage(context, 'Availability saved.');
    }
  }

  Future<void> workedTime(AdminRow row, AdminRow completion) async {
    final saved = await adminForm(
      context,
      'Record worked time',
      {'minutes': completion['actual_minutes']},
      (values, _) => [
        adminText(
          values,
          'minutes',
          'Minutes worked',
          required: true,
          minimumNumber: 1,
          maximumNumber: 1440,
        ),
      ],
      (values) => data.write(
        data
            .table('preventive_work_completion')
            .update({'actual_minutes': int.parse(fieldText(values, 'minutes'))})
            .eq('work_order_id', row['id']),
        'work_order_id',
      ),
    );
    if (saved && mounted) {
      reloadPerformance();
      if (day != null) showDay(day!);
    }
  }

  void reloadPerformance() => setState(() {
    performance = loadPerformance();
  });

  Widget performanceSummary(List<AdminRow> completed) {
    final recorded = completed
        .map((row) => row['actual_minutes'])
        .whereType<int>();
    final minutes = recorded.fold(0, (total, value) => total + value);
    final worked = minutes < 60
        ? '$minutes min'
        : '${minutes ~/ 60} h ${minutes % 60} min';
    return AdminTable(
      ['Completed tasks', 'Recorded worked time', 'Tasks missing worked time'],
      [
        [
          adminCell(completed.length),
          adminCell(worked),
          adminCell(completed.length - recorded.length),
        ],
      ],
      empty: 'No performance records.',
      framed: false,
      darkHeading: true,
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AdminSectionCard(
        'Date availability',
        subtitle: 'Malaysia time',
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AdminLoad(
            listing,
            (rows) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: calendar(rows)),
                const SizedBox(height: 12),
                if (day case final selected?) ...[
                  AdminHeading('Assigned tasks · ${isoDate(selected)}'),
                  AdminLoad(
                    tasks!,
                    (orders) => AdminTable(
                      ['Task', 'Location', 'Time', 'Status', 'Worked time'],
                      [
                        for (final row in orders)
                          [
                            adminCell(row['title']),
                            adminCell(orderLocation(row)),
                            adminCell(scheduleTime(row)),
                            adminCell(orderStatus(row)),
                            if (row['preventive_work_completion']
                                case final AdminRow completion)
                              adminAction(
                                completion['actual_minutes'] == null
                                    ? 'Record worked time'
                                    : 'Worked ${completion['actual_minutes']} min · Edit',
                                () => workedTime(row, completion),
                              )
                            else
                              adminCell(null),
                          ],
                      ],
                      empty: _noAssignedTasksMessage,
                      emptyState: const AdminIllustratedEmptyState(
                        _noAssignedTasksMessage,
                        asset: 'assets/workforce/no-assigned-task.png',
                      ),
                      darkHeading: true,
                    ),
                    retry: () => showDay(selected),
                  ),
                  if (dayRows(selected, rows) case final selectedRecords
                      when selectedRecords.isNotEmpty)
                    ExpansionTile(
                      key: ValueKey(selected),
                      title: const Text('Availability for selected date'),
                      tilePadding: EdgeInsets.zero,
                      children: [
                        for (final row in selectedRecords)
                          ListTile(
                            title: Text('${row['availability']}'),
                            subtitle: Text(
                              '${malaysiaStamp(row['shift_start'])} – ${malaysiaStamp(row['shift_end'])} · ${row['availability_status']} · Leave ${row['leave_status']}',
                            ),
                            trailing:
                                row['availability'] == 'Approved leave' &&
                                    row['leave_status'] == 'approved'
                                ? const Text('Leave request')
                                : adminAction(
                                    'Edit availability',
                                    () => edit(row),
                                  ),
                          ),
                      ],
                    ),
                ] else
                  const Text('Select a date to see this worker’s tasks.'),
              ],
            ),
            retry: () => move(0),
          ),
        ),
      ),
      const SizedBox(height: 16),
      AdminSectionCard(
        'Worker performance',
        subtitle: MaterialLocalizations.of(context).formatMonthYear(month),
        child: AdminLoad(
          performance,
          performanceSummary,
          retry: reloadPerformance,
        ),
      ),
    ],
  );
}
