import 'package:flutter/material.dart';

import 'admin_data.dart';
import 'admin_widgets.dart';

class AdminScheduleReview extends StatefulWidget {
  const AdminScheduleReview({
    super.key,
    required this.data,
    required this.back,
  });

  final AdminData data;
  final VoidCallback back;

  @override
  State<AdminScheduleReview> createState() => _AdminScheduleReviewState();
}

class _AdminScheduleReviewState extends State<AdminScheduleReview> {
  late var tasks = widget.data.scheduledTaskNames();
  String? selected;

  void reload() {
    final next = widget.data.scheduledTaskNames();
    setState(() => tasks = next);
  }

  void openTask(String? name) {
    setState(() => selected = name);
    Scrollable.maybeOf(context)?.position.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final task = selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (task == null) ...[
          adminBackAction('Task templates', widget.back),
          const AdminHeading(
            'Review auto schedule',
            subtitle: 'Select a scheduled task to view its assignments.',
          ),
          AdminLoad(tasks, (names) {
            if (names.isEmpty) {
              return const Text('No scheduled tasks are available.');
            }
            return Card(
              child: Column(
                children: [
                  for (final name in names)
                    ListTile(
                      title: Text(name),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openTask(name),
                    ),
                ],
              ),
            );
          }, retry: reload),
        ] else ...[
          adminBackAction('Scheduled task names', () => openTask(null)),
          _TaskCalendar(key: ValueKey(task), data: widget.data, task: task),
        ],
      ],
    );
  }
}

class _TaskCalendar extends StatefulWidget {
  const _TaskCalendar({super.key, required this.data, required this.task});

  final AdminData data;
  final String task;

  @override
  State<_TaskCalendar> createState() => _TaskCalendarState();
}

class _TaskCalendarState extends State<_TaskCalendar> {
  DateTime date = adminToday();
  String search = '';
  int page = 0;
  late var listing = _load(date);
  Future<Map<String, AdminRow>>? workerDirectory;

  Future<(List<AdminRow>, Map<String, AdminRow>)> _load(DateTime day) async {
    final rows = await widget.data.scheduledTasksOn(widget.task, day);
    if (!rows.any((row) => row['worker_id'] != null)) {
      return (rows, const <String, AdminRow>{});
    }
    try {
      return (rows, await (workerDirectory ??= widget.data.workerDirectory()));
    } catch (_) {
      workerDirectory = null;
      rethrow;
    }
  }

  void selectDate(DateTime day) {
    final next = _load(day);
    setState(() {
      date = day;
      listing = next;
      page = 0;
    });
  }

  void refresh() {
    workerDirectory = null;
    selectDate(date);
  }

  Widget building(AdminRow order) {
    final paths = adminRows(order['preventive_work_order_target'])
        .map((target) => target['facility_path'] as String);
    final buildings =
        paths.map((path) => path.split(' / ').first).toSet().toList()..sort();
    final areas = paths.where((path) => path.contains(' / ')).toList()..sort();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        adminCell(buildings.join(', ')),
        if (areas.isNotEmpty)
          Tooltip(
            message: areas.join(', '),
            child: adminCell(areas.join(', ')),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AdminHeading(widget.task),
      SizedBox(
        width: 370,
        child: Card(
          color: Colors.white,
          child: CalendarDatePicker(
            initialDate: date,
            currentDate: adminToday(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2200),
            onDateChanged: selectDate,
          ),
        ),
      ),
      const SizedBox(height: 20),
      AdminHeading(
        'Assignments',
        subtitle:
            '${MaterialLocalizations.of(context).formatFullDate(date)} · Malaysia time',
        actions: [
          OutlinedButton(onPressed: refresh, child: const Text('Refresh')),
        ],
      ),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: TextField(
          decoration: const InputDecoration(
            labelText: 'Search by worker name',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() {
            search = value.trim().toLowerCase();
            page = 0;
          }),
        ),
      ),
      AdminLoad(listing, (result) {
        final (orders, workers) = result;
        final matching = search.isEmpty
            ? orders
            : orders.where((row) {
                final name = workers[row['worker_id']]?['full_name'] as String?;
                return name?.toLowerCase().contains(search) ?? false;
              }).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminTable(
              ['Building', 'Time', 'Assigned worker', 'Status'],
              [
                for (final row in matching.skip(page * 20).take(20))
                  [
                    building(row),
                    adminCell(scheduleTime(row)),
                    adminCell(
                      row['worker_id'] == null
                          ? 'Unassigned'
                          : workerLabel(workers[row['worker_id']]),
                    ),
                    adminCell(
                      row['worker_id'] == null
                          ? 'Coverage needed'
                          : orderStatus(row),
                    ),
                  ],
              ],
              empty: search.isEmpty
                  ? 'No assignments for this date.'
                  : 'No assignments match that worker name.',
              darkHeading: true,
            ),
            if (page > 0 || matching.length > 20)
              AdminPager(
                page: page,
                next: matching.length > (page + 1) * 20,
                change: (number) => setState(() => page = number),
              ),
          ],
        );
      }, retry: refresh),
    ],
  );
}
