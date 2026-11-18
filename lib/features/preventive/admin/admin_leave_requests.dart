import 'package:flutter/material.dart';

import '../../workforce/leave_document_button.dart';
import '../../workforce/worker_leave_repository.dart';
import 'admin_data.dart';
import 'admin_widgets.dart';

class AdminLeaveRequests extends StatefulWidget {
  const AdminLeaveRequests({super.key, required this.data});
  final AdminData data;

  @override
  State<AdminLeaveRequests> createState() => _AdminLeaveRequestsState();
}

class _AdminLeaveRequestsState extends State<AdminLeaveRequests> {
  late final _repository = WorkerLeaveRepository(widget.data.client);
  String? _filter = 'pending';
  int _page = 0;
  late var _listing = _load();
  Map<String, AdminRow> _workers = {};

  Future<List<WorkerLeave>> _load() async {
    final rows = await _repository.list(status: _filter, page: _page);
    if (rows.isNotEmpty && _workers.isEmpty) {
      _workers = await widget.data.workerDirectory();
    }
    return rows;
  }

  void _reload() {
    final next = _load();
    setState(() {
      _listing = next;
    });
  }

  String _coverage(LeaveCoverage result) => [
    '${result.reassigned} reassigned',
    if (result.uncovered > 0) '${result.uncovered} need coverage',
    if (result.active > 0) '${result.active} already in progress',
  ].join(' · ');

  void _details(WorkerLeave leave) => adminDetails(context, leave.title, [
    Text(workerLabel(_workers[leave.workerId])),
    Text('${leave.period} · ${leave.status}'),
    const SizedBox(height: 12),
    Text('Reason · ${leave.reason}'),
    LeaveDocumentButton(leave: leave, repository: _repository),
    if (leave.note case final note?) Text('Review note · $note'),
    if (leave.status == 'approved') Text(_coverage(leave.count)),
  ]);

  Future<void> _review(WorkerLeave leave, bool approve) async {
    final action = approve ? 'Approve leave' : 'Reject leave';
    LeaveCoverage? coverage;
    final saved = await adminForm(
      context,
      action,
      {},
      (values, _) => [
        Text(workerLabel(_workers[leave.workerId])),
        Text('${leave.title} · ${leave.period}'),
        const SizedBox(height: 8),
        Text(leave.reason),
        LeaveDocumentButton(leave: leave, repository: _repository),
        const SizedBox(height: 12),
        if (approve) ...[
          const Text(
            'Eligible workers will cover unstarted preventive tasks at the scheduled times. Any tasks without a replacement will be flagged in Scheduled tasks.',
          ),
          const SizedBox(height: 12),
        ],
        adminText(
          values,
          'note',
          approve ? 'Note (optional)' : 'Reason for rejection',
          required: !approve,
          max: 1000,
          lines: 3,
        ),
      ],
      (values) async {
        coverage = await _repository.review(
          leave.id,
          approve: approve,
          note: optionalField(values, 'note'),
        );
      },
      action: action,
    );
    if (saved && mounted) {
      _page = 0;
      _reload();
      adminMessage(
        context,
        approve
            ? 'Leave approved. ${_coverage(coverage!)}.'
            : 'Leave rejected.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AdminHeading(
        'Leave requests',
        subtitle: 'Review worker leave and check task coverage.',
        actions: [
          OutlinedButton(onPressed: _reload, child: const Text('Refresh')),
        ],
      ),
      SizedBox(
        width: 280,
        child: DropdownButtonFormField<String>(
          initialValue: _filter ?? '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Status'),
          items: const [
            DropdownMenuItem(value: '', child: Text('All requests')),
            DropdownMenuItem(value: 'pending', child: Text('Pending')),
            DropdownMenuItem(value: 'approved', child: Text('Approved')),
            DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
          ],
          onChanged: (filter) {
            _filter = filter == '' ? null : filter;
            _page = 0;
            _reload();
          },
        ),
      ),
      AdminLoad(
        _listing,
        (rows) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminTable(
              [
                'Worker',
                'Type',
                'Leave dates',
                'Status',
                'Coverage at review',
                'Actions',
              ],
              [
                for (final leave in rows.take(25))
                  [
                    adminCell(workerLabel(_workers[leave.workerId])),
                    adminCell(leave.title),
                    adminCell(leave.period),
                    adminCell(leave.statusOn(adminToday())),
                    adminCell(
                      leave.status == 'approved'
                          ? _coverage(leave.count)
                          : null,
                    ),
                    adminActions([
                      adminAction('View', () => _details(leave)),
                      if (leave.status == 'pending') ...[
                        adminAction('Approve', () => _review(leave, true)),
                        adminAction('Reject', () => _review(leave, false)),
                      ],
                    ]),
                  ],
              ],
              empty: 'No leave requests match this status.',
            ),
            AdminPager(
              page: _page,
              next: rows.length > 25,
              change: (index) {
                _page = index;
                _reload();
              },
            ),
          ],
        ),
        retry: _reload,
      ),
    ],
  );
}
