import 'package:flutter/material.dart';

import 'admin_data.dart';
import 'admin_widgets.dart';

class AdminApprovals extends StatefulWidget {
  const AdminApprovals({super.key, required this.data});
  final AdminData data;

  @override
  State<AdminApprovals> createState() => _AdminApprovalsState();
}

class _AdminApprovalsState extends State<AdminApprovals> {
  AdminData get data => widget.data;
  int page = 0;
  String? selected;
  late var listing = load();
  Future<(AdminRow, List<String?>)>? submission;
  Map<String, AdminRow> workers = {};

  Future<List<AdminRow>> load() async {
    final rows = await data
        .table('preventive_work_order')
        .select('$orderFields,submitted_at')
        .eq('status', 'submitted')
        .isFilter('cancelled_at', null)
        .order('submitted_at', ascending: true)
        .order('id')
        .range(page * 25, (page + 1) * 25);
    if (rows.isNotEmpty && workers.isEmpty) {
      workers = await data.workerDirectory();
    }
    return rows;
  }

  void reload() {
    final next = load();
    setState(() {
      listing = next;
    });
  }

  Future<(AdminRow, List<String?>)> loadSubmission(String id) async {
    final row = await data
        .table('preventive_work_order')
        .select(
          '$orderFields,submitted_at,instructions,checklist,checked_items,worker_notes,location_verified_at,preventive_work_evidence(path)',
        )
        .eq('id', id)
        .eq('status', 'submitted')
        .isFilter('cancelled_at', null)
        .maybeSingle();
    if (row == null) {
      throw const FormatException('This task is no longer awaiting review.');
    }
    final evidence = await Future.wait(
      adminRows(row['preventive_work_evidence']).map((photo) async {
        try {
          return await data.client.storage
              .from('preventive-work-evidence')
              .createSignedUrl(photo['path'] as String, 300);
        } catch (_) {
          return null;
        }
      }),
    );
    return (row, evidence);
  }

  void open(String id) => setState(() {
    selected = id;
    submission = loadSubmission(id);
  });
  void close() => setState(() {
    selected = null;
    listing = load();
  });

  Future<void> review(AdminRow row, bool approve) async {
    final action = approve ? 'Approve completion' : 'Return for changes';
    final saved = await adminForm(
      context,
      action,
      {},
      (values, _) => approve
          ? [Text('Mark ${row['title']} as completed?')]
          : [
              adminText(
                values,
                'feedback',
                'Feedback',
                required: true,
                lines: 3,
              ),
            ],
      (values) async {
        await data.client.rpc(
          'review_work_submission',
          params: {
            'target_order': row['id'],
            'approve': approve,
            'feedback': optionalField(values, 'feedback'),
          },
        );
      },
      action: action,
    );
    if (saved && mounted) {
      page = 0;
      close();
      adminMessage(
        context,
        approve
            ? 'Work order completed.'
            : 'Work order returned to the worker.',
      );
    }
  }

  Widget photo(String url, int index) => SizedBox(
    width: 220,
    height: 150,
    child: OutlinedButton(
      onPressed: () => adminDetails(context, 'Evidence photo ${index + 1}', [
        InteractiveViewer(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Text(
              'Could not load this photo. Reopen the submission to retry.',
            ),
          ),
        ),
      ]),
      child: Image.network(
        url,
        fit: BoxFit.contain,
        semanticLabel: 'Evidence photo ${index + 1}',
        errorBuilder: (_, _, _) => const Text('Could not load photo'),
      ),
    ),
  );

  Widget detail(AdminRow row, List<String?> evidence) {
    final checklist = (row['checklist'] as List).cast<String>();
    final checked = (row['checked_items'] as List).cast<int>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminHeading(
          row['title'] as String,
          subtitle:
              '${workerLabel(workers[row['worker_id']])} · ${orderLocation(row)}',
          actions: [
            OutlinedButton(
              onPressed: () => review(row, false),
              child: const Text('Return for changes'),
            ),
            FilledButton(
              onPressed: evidence.isNotEmpty && !evidence.contains(null)
                  ? () => review(row, true)
                  : null,
              child: const Text('Approve completion'),
            ),
          ],
        ),
        Text('Submitted ${malaysiaStamp(row['submitted_at'])} · Malaysia time'),
        if (row['location_verified_at'] case final String verified)
          Text('Campus location verified ${malaysiaStamp(verified)}'),
        const SizedBox(height: 18),
        Text(row['instructions'] as String),
        const SizedBox(height: 18),
        Text('Checklist', style: Theme.of(context).textTheme.titleLarge),
        if (checklist.isEmpty) const Text('This task has no checklist.'),
        for (final (index, item) in checklist.indexed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              checked.contains(index)
                  ? Icons.check_circle_outline
                  : Icons.circle_outlined,
            ),
            title: Text(item),
          ),
        if ((row['worker_notes'] as String).isNotEmpty) ...[
          Text('Worker notes', style: Theme.of(context).textTheme.titleLarge),
          Text(row['worker_notes'] as String),
        ],
        const SizedBox(height: 18),
        Text('Photo evidence', style: Theme.of(context).textTheme.titleLarge),
        if (evidence.isEmpty) const Text('No evidence photos are available.'),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (index, url) in evidence.indexed)
              if (url == null)
                const Text(
                  'Could not open an evidence photo. Reopen this submission to retry.',
                )
              else
                photo(url, index),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (selected case final id?) ...[
        adminBackAction('Task approvals', close),
        AdminLoad(
          submission!,
          ((AdminRow, List<String?>) result) => detail(result.$1, result.$2),
          retry: () => open(id),
        ),
      ] else ...[
        AdminHeading(
          'Task approvals',
          subtitle: 'Review the checklist and evidence for submitted work.',
          actions: [
            OutlinedButton(onPressed: reload, child: const Text('Refresh')),
          ],
        ),
        AdminLoad(
          listing,
          (rows) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminTable(
                [
                  'Task',
                  'Worker',
                  'Location',
                  'Scheduled',
                  'Submitted',
                  'Actions',
                ],
                [
                  for (final row in rows.take(25))
                    [
                      adminCell(row['title']),
                      adminCell(workerLabel(workers[row['worker_id']])),
                      adminCell(orderLocation(row)),
                      adminCell(malaysiaStamp(row['scheduled_for'])),
                      adminCell(malaysiaStamp(row['submitted_at'])),
                      adminAction('Review', () => open(row['id'] as String)),
                    ],
                ],
                empty: 'No tasks are awaiting approval.',
              ),
              AdminPager(
                page: page,
                next: rows.length > 25,
                change: (number) {
                  page = number;
                  reload();
                },
              ),
            ],
          ),
          retry: reload,
        ),
      ],
    ],
  );
}
