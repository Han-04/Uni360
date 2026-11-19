import 'package:flutter/material.dart';

import 'admin_data.dart';
import 'admin_widgets.dart';

class AdminOverdueTasks extends StatefulWidget {
  const AdminOverdueTasks({super.key, required this.data});

  final AdminData data;

  @override
  State<AdminOverdueTasks> createState() => _AdminOverdueTasksState();
}

class _AdminOverdueTasksState extends State<AdminOverdueTasks> {
  int page = 0;
  late var listing = load();

  Future<(List<AdminRow>, Map<String, AdminRow>)> load() async {
    final rows = await widget.data.overdueOrders(page);
    final workers = rows.isEmpty
        ? const <String, AdminRow>{}
        : await widget.data.workerDirectory();
    return (rows, workers);
  }

  void reload() => setState(() => listing = load());

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AdminHeading(
        'Overdue tasks',
        subtitle: 'Assigned work left unfinished after its scheduled day in Malaysia.',
        actions: [AdminCommandButton(label: 'Refresh', onPressed: reload)],
      ),
      AdminLoad(listing, (result) {
        final (orders, workers) = result;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminTable(
              ['Task', 'Worker', 'Location', 'Scheduled', 'Status'],
              [
                for (final row in orders.take(25))
                  [
                    adminCell(row['title']),
                    adminCell(workerLabel(workers[row['worker_id']])),
                    adminCell(orderLocation(row)),
                    adminCell(malaysiaStamp(row['scheduled_for'])),
                    adminCell('Overdue'),
                  ],
              ],
              empty: 'No overdue tasks.',
              darkHeading: true,
            ),
            AdminPager(
              page: page,
              next: orders.length > 25,
              change: (number) {
                page = number;
                reload();
              },
            ),
          ],
        );
      }, retry: reload),
    ],
  );
}
