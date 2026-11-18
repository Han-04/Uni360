import 'package:flutter/material.dart';

import 'admin_catalog.dart'
    show facilityPaths, isToilet, namedOptions, taskCategory;
import 'admin_data.dart';
import 'admin_widgets.dart';

const _frequency = {'daily': 'Daily', 'weekly': 'Weekly', 'monthly': 'Monthly'};

List<String> _times(AdminRow values) {
  final times = (values['times'] as List<String?>).whereType<String>().toList();
  if (times.length != (values['times'] as List).length || times.isEmpty) {
    throw const FormatException('Choose each start time.');
  }
  if (times.toSet().length != times.length) {
    throw const FormatException('Each start time must be different.');
  }
  return times;
}

String _localTime(Object? value) =>
    value == null ? 'Choose time' : '$value'.substring(0, 5);

Widget _timeFields(
  BuildContext context,
  AdminRow values,
  VoidCallback refresh, {
  bool multiple = true,
}) {
  final times = values['times'] as List<String?>;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Start times (Malaysia time)'),
      for (final (index, time) in times.indexed)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final parts = time?.split(':');
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: parts == null
                        ? const TimeOfDay(hour: 8, minute: 0)
                        : TimeOfDay(
                            hour: int.parse(parts[0]),
                            minute: int.parse(parts[1]),
                          ),
                  );
                  if (picked != null) {
                    times[index] =
                        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}:00';
                    refresh();
                  }
                },
                icon: const Icon(Icons.schedule),
                label: Text(_localTime(time)),
              ),
              if (multiple && times.length > 1)
                IconButton(
                  tooltip: 'Remove time ${index + 1}',
                  onPressed: () {
                    times.removeAt(index);
                    refresh();
                  },
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
      if (multiple)
        TextButton(
          onPressed: () {
            times.add(null);
            refresh();
          },
          child: const Text('Add time'),
        ),
    ],
  );
}

class AdminFacilitySchedules extends StatefulWidget {
  const AdminFacilitySchedules({
    super.key,
    required this.data,
    required this.facility,
    required this.back,
  });
  final AdminData data;
  final AdminRow facility;
  final VoidCallback back;

  @override
  State<AdminFacilitySchedules> createState() => _AdminFacilitySchedulesState();
}

class _AdminFacilitySchedulesState extends State<AdminFacilitySchedules> {
  AdminData get data => widget.data;
  AdminRow get facility => widget.facility;
  late var listing = load();

  Future<(List<AdminRow>, List<AdminRow>)> load() async {
    final rows = await Future.wait([
      data
          .table('preventive_task_plan')
          .select(
            'is_active,preventive_task_definition(id,title,is_active),preventive_schedule(id,frequency,starts_on,ends_on,local_time,is_active)',
          )
          .eq('facility_id', facility['id']),
      data
          .table('preventive_task_definition')
          .select('id,title')
          .eq('is_active', true)
          .order('title', ascending: true),
    ]);
    final slots =
        [
          for (final plan in rows[0])
            if (plan['preventive_task_definition'] case final AdminRow template)
              for (final slot in adminRows(plan['preventive_schedule']))
                if (slot['is_active'] == true)
                  {
                    ...slot,
                    'template': template,
                    'plan_active': plan['is_active'],
                  },
        ]..sort(
          (a, b) => '${a['template']['title']} ${a['local_time']}'.compareTo(
            '${b['template']['title']} ${b['local_time']}',
          ),
        );
    return (slots, rows[1]);
  }

  void reload() {
    final next = load();
    setState(() {
      listing = next;
    });
  }

  Future<void> edit(List<AdminRow> templates, [AdminRow? slot]) async {
    final saved = await adminForm(
      context,
      slot == null ? 'Assign task template' : 'Edit schedule time',
      {
        'frequency': slot?['frequency'] ?? 'daily',
        'first': slot == null
            ? adminToday()
            : DateTime.parse(slot['starts_on'] as String),
        'last': slot?['ends_on'] == null
            ? null
            : DateTime.parse(slot!['ends_on'] as String),
        'times': <String?>[slot?['local_time'] as String?],
      },
      (values, refresh) => [
        if (slot == null)
          adminSelect(
            values,
            'template',
            'Task template',
            namedOptions(templates, name: 'title'),
            refresh,
            required: true,
          )
        else
          Text(slot['template']['title'] as String),
        adminSelect(
          values,
          'frequency',
          'Repeat',
          _frequency,
          refresh,
          required: true,
        ),
        adminDate(context, values, 'first', 'Starts on', refresh),
        adminDate(
          context,
          values,
          'last',
          'Ends on (optional)',
          refresh,
          clearable: true,
        ),
        if (values['frequency'] == 'weekly')
          const Text('Repeats on the weekday of the start date.'),
        if (values['frequency'] == 'monthly')
          const Text('Repeats on the day of the month of the start date.'),
        _timeFields(context, values, refresh, multiple: slot == null),
      ],
      (values) async {
        final first = values['first'] as DateTime;
        final last = values['last'] as DateTime?;
        if (last != null && last.isBefore(first)) {
          throw const FormatException(
            'The end date must be on or after the start date.',
          );
        }
        await data.client.rpc(
          'save_preventive_facility_schedule',
          params: {
            'target_facility': facility['id'],
            'target_template': slot?['template']['id'] ?? values['template'],
            'repeat_frequency': values['frequency'],
            'first_date': isoDate(first),
            'last_date': last == null ? null : isoDate(last),
            'times': _times(values),
            'replaced_schedule': slot?['id'],
          },
        );
      },
      action: 'Save schedule',
    );
    if (saved && mounted) {
      reload();
      adminMessage(context, 'Schedule saved.');
    }
  }

  Future<void> _deactivateRecord(AdminRow slot) async {
    final saved = await adminConfirm(
      context,
      'Deactivate schedule time?',
      '${slot['template']['title']} at ${_localTime(slot['local_time'])} will stop recurring. Existing work orders will be kept.',
      'Deactivate',
      () => data.write(
        data
            .table('preventive_schedule')
            .update({'is_active': false})
            .eq('id', slot['id'])
            .eq('is_active', true),
      ),
    );
    if (saved && mounted) {
      reload();
      adminMessage(context, 'Schedule deactivated.');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      adminBackAction('Facilities', widget.back),
      AdminLoad(listing, (result) {
        final (slots, templates) = result;
        final active = facility['effective_active'] == true;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminHeading(
              '${facility['name']} schedules',
              subtitle: 'Malaysia time',
              actions: [
                FilledButton(
                  onPressed: active && templates.isNotEmpty
                      ? () => edit(templates)
                      : null,
                  child: const Text('Assign task template'),
                ),
              ],
            ),
            if (!active)
              const Text(
                'Activate the facility and its parent locations to add schedules.',
              ),
            if (active && templates.isEmpty)
              const Text('Create an active task template first.'),
            AdminTable(
              ['Task template', 'Repeats', 'Time', 'Starts', 'Ends', 'Actions'],
              [
                for (final slot in slots)
                  [
                    adminCell(
                      '${slot['template']['title']}${slot['plan_active'] != true || slot['template']['is_active'] != true ? " · Inactive assignment" : ""}',
                    ),
                    adminCell(_frequency[slot['frequency']]),
                    adminCell(_localTime(slot['local_time'])),
                    adminCell(slot['starts_on']),
                    adminCell(slot['ends_on']),
                    adminActions([
                      if (active && slot['template']['is_active'] == true)
                        adminAction('Edit', () => edit(templates, slot)),
                      adminAction('Deactivate', () => _deactivateRecord(slot)),
                    ]),
                  ],
              ],
              empty: 'No task schedules for this facility.',
            ),
          ],
        );
      }, retry: reload),
    ],
  );
}

class AdminRangeSchedule extends StatefulWidget {
  const AdminRangeSchedule({
    super.key,
    required this.data,
    required this.template,
    required this.back,
  });
  final AdminData data;
  final AdminRow template;
  final VoidCallback back;

  @override
  State<AdminRangeSchedule> createState() => _AdminRangeScheduleState();
}

class _AdminRangeScheduleState extends State<AdminRangeSchedule> {
  AdminData get data => widget.data;
  AdminRow get template => widget.template;
  late var facilities = data.facilities();
  AdminRow? parameters, draft;
  int? approved;

  final _form = GlobalKey<FormState>();
  late final values = <String, dynamic>{
    'first': adminToday(),
    'frequency': 'daily',
    'work_minutes': template['duration_minutes'],
    'times': <String?>[null],
    'building': '',
  };
  final selected = <String>{};
  bool busy = false;
  String? error;

  List<Widget> fields(List<AdminRow> rows, Map<String, String> paths) {
    void refresh() => setState(() {});
    final toilets = taskCategory(template) == 'Toilet Cleaning';
    final available = {
      for (final row in rows)
        if (row['effective_active'] == true && (!toilets || isToilet(row)))
          row['id'] as String: paths[row['id']]!,
    };
    final ordered = available.keys.toList()
      ..sort((a, b) => available[a]!.compareTo(available[b]!));
    final buildings =
        available.values.map((path) => path.split(' / ').first).toSet().toList()
          ..sort();
    final search = fieldText(values, 'search').toLowerCase();
    final building = fieldText(values, 'building');
    final matched = ordered.where((id) {
      final name = available[id]!;
      return (building.isEmpty || name.split(' / ').first == building) &&
          name.toLowerCase().contains(search);
    }).toList();
    final count = matched.where(selected.contains).length;
    return [
      Text(toilets ? 'Toilets to clean' : 'Facilities'),
      TextFormField(
        initialValue: fieldText(values, 'search'),
        decoration: const InputDecoration(
          labelText: 'Search by building, floor or room',
        ),
        onChanged: (value) {
          values['search'] = value;
          refresh();
        },
      ),
      const SizedBox(height: 8),
      adminSelect(values, 'building', 'Building or site', {
        '': 'All locations',
        for (final name in buildings) name: name,
      }, refresh),
      CheckboxListTile(
        title: const Text('Select all results'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        tristate: true,
        value: count == 0
            ? false
            : count == matched.length
            ? true
            : null,
        onChanged: matched.isEmpty
            ? null
            : (_) {
                if (count == matched.length) {
                  selected.removeAll(matched);
                } else {
                  selected.addAll(matched);
                }
                refresh();
              },
      ),
      Text('${matched.length} shown · ${selected.length} selected'),
      SizedBox(
        height: 185,
        child: ListView(
          primary: false,
          children: [
            for (final id in matched)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(available[id]!),
                value: selected.contains(id),
                onChanged: (checked) {
                  if (checked == true) {
                    selected.add(id);
                  } else {
                    selected.remove(id);
                  }
                  refresh();
                },
              ),
          ],
        ),
      ),
      adminSelect(values, 'frequency', 'Repeat', _frequency, refresh),
      adminDate(context, values, 'first', 'Starts on', refresh),
      adminDate(context, values, 'last', 'Ends on', refresh),
      adminText(
        values,
        'work_minutes',
        'Work time per location (minutes)',
        required: true,
        minimumNumber: 1,
        maximumNumber: 720,
      ),
      _timeFields(context, values, refresh),
      const Text(
        'Tasks can be staggered after each start time to fit available shifts.',
      ),
    ];
  }

  Future<void> generate() async {
    if (busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (selected.isEmpty) {
        throw const FormatException('Select at least one location.');
      }
      final first = values['first'] as DateTime;
      final last = values['last'] as DateTime?;
      if (last == null || last.isBefore(first)) {
        throw const FormatException(
          'Choose an end date on or after the start date.',
        );
      }
      final input = {
        'target_facilities': selected.toList(),
        'target_template': template['id'],
        'repeat_frequency': values['frequency'],
        'first_date': isoDate(first),
        'last_date': isoDate(last),
        'times': _times(values),
        'work_minutes': int.parse(fieldText(values, 'work_minutes')),
      };
      final result = await data.client.rpc(
        'review_preventive_range',
        params: input,
      ) as AdminRow;
      if (mounted) {
        setState(() {
          draft = result;
          parameters = input;
          approved = null;
        });
        Scrollable.maybeOf(context)?.position.jumpTo(0);
      }
    } catch (failure) {
      if (mounted) setState(() => error = adminError(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget scheduleForm(List<AdminRow> rows, Map<String, String> paths) =>
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  IgnorePointer(
                    ignoring: busy,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: fields(rows, paths),
                    ),
                  ),
                  if (error case final message?)
                    Text(
                      message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: busy ? null : generate,
                      child: Text(busy ? 'Generating…' : 'Auto Schedule'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      adminBackAction('Task templates', widget.back),
      AdminLoad(
        facilities,
        (rows) {
          final paths = facilityPaths(rows);
          final input = parameters;
          final result = draft;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminHeading(
                input == null ? 'Schedule task' : 'Review auto schedule',
                subtitle: template['title'] as String,
                actions: [
                  if (input != null)
                    OutlinedButton(
                      onPressed: () => setState(() {
                        parameters = null;
                        draft = null;
                        approved = null;
                      }),
                      child: const Text('Edit schedule'),
                    ),
                ],
              ),
              if (input == null) scheduleForm(rows, paths),
              if (input != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${input['first_date']} to ${input['last_date']} · Malaysia time',
                  ),
                ),
              if (result != null && approved == null)
                _ScheduleDraft(
                  key: ObjectKey(result),
                  draft: result,
                  location: (row) => paths[row['facility_id']],
                  approve: (reviewed, verified) => data.client
                      .rpc(
                        'review_preventive_range',
                        params: {
                          ...input!,
                          'reviewed': reviewed,
                          'verified': verified,
                        },
                      )
                      .then((value) => value as int),
                  published: (count) => setState(() => approved = count),
                ),
              if (approved case final count?) ...[
                Text('$count assignments approved.'),
                _ScheduledTasks(
                  data: data,
                  first: DateTime.parse(input!['first_date'] as String),
                  last: DateTime.parse(input['last_date'] as String),
                  template: input['target_template'] as String,
                  facilities: (input['target_facilities'] as List)
                      .cast<String>(),
                ),
              ],
            ],
          );
        },
        retry: () {
          final next = data.facilities();
          setState(() {
            facilities = next;
          });
        },
      ),
    ],
  );
}

class _ScheduledTasks extends StatefulWidget {
  const _ScheduledTasks({
    required this.data,
    required this.first,
    this.last,
    this.template,
    this.facilities,
  });
  final AdminData data;
  final DateTime first;
  final DateTime? last;
  final String? template;
  final List<String>? facilities;

  @override
  State<_ScheduledTasks> createState() => _ScheduledTasksState();
}

class _ScheduledTasksState extends State<_ScheduledTasks> {
  int page = 0;
  Map<String, AdminRow> workers = {};
  late var listing = load();

  Future<List<AdminRow>> load() async {
    final plan = widget.template != null || widget.facilities != null
        ? ',preventive_task_plan!inner(zone_id)'
        : '';
    var query = widget.data
        .table('preventive_work_order')
        .select('$orderFields$plan')
        .isFilter('cancelled_at', null)
        .gte('scheduled_for', midnight(widget.first));
    if (widget.last case final last?) {
      query = query.lt(
        'scheduled_for',
        midnight(last.add(const Duration(days: 1))),
      );
    }
    if (widget.template case final template?) {
      query = query.eq('preventive_task_plan.task_definition_id', template);
    }
    if (widget.facilities case final ids?) {
      query = query.inFilter('preventive_task_plan.facility_id', ids);
    }
    final rows = await query
        .order('scheduled_for', ascending: true)
        .order('id')
        .range(page * 20, (page + 1) * 20);
    if (rows.isNotEmpty && workers.isEmpty) {
      workers = await widget.data.workerDirectory();
    }
    return rows;
  }

  void reload() {
    final next = load();
    setState(() {
      listing = next;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AdminHeading(
        'Scheduled tasks',
        subtitle: widget.last == null
            ? 'Upcoming from ${isoDate(widget.first)} · Malaysia time'
            : '${isoDate(widget.first)}${widget.first == widget.last ? "" : " to ${isoDate(widget.last!)}"} · Malaysia time',
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
              ['Date', 'Task', 'Location', 'Time', 'Worker', 'Status'],
              [
                for (final row in rows.take(20))
                  [
                    adminCell(isoDate(adminDay(row['scheduled_for']))),
                    adminCell(row['title']),
                    adminCell(orderLocation(row)),
                    adminCell(scheduleTime(row)),
                    adminCell(
                      row['worker_id'] == null
                          ? '—'
                          : workerLabel(workers[row['worker_id']]),
                    ),
                    adminCell(
                      row['worker_id'] == null
                          ? 'Coverage needed'
                          : orderStatus(row),
                    ),
                  ],
              ],
              empty: 'No scheduled assignments match these filters.',
            ),
            AdminPager(
              page: page,
              next: rows.length > 20,
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
  );
}

class _ScheduleDraft extends StatefulWidget {
  const _ScheduleDraft({
    super.key,
    required this.draft,
    required this.location,
    required this.approve,
    required this.published,
  });
  final AdminRow draft;
  final String? Function(AdminRow) location;
  final Future<int> Function(List<AdminRow>, List<AdminRow>?) approve;
  final ValueChanged<int> published;

  @override
  State<_ScheduleDraft> createState() => _ScheduleDraftState();
}

class _ScheduleDraftState extends State<_ScheduleDraft> {
  bool verified = false;

  @override
  Widget build(BuildContext context) {
    final rows = adminRows(widget.draft['rows']);
    final warnings = adminRows(widget.draft['warnings']);
    final assigned = rows.where((row) => row['worker_id'] != null).toList();
    final workloads = <(String, String), (AdminRow, int)>{};
    final totals = <String, (AdminRow, int, int)>{};
    for (final row in assigned) {
      final id = row['worker_id'] as String;
      final key = (id, isoDate(adminDay(row['occurrence'])));
      final minutes = row['duration_minutes'] as int;
      final daily = workloads[key];
      final period = totals[id];
      workloads[key] = (daily?.$1 ?? row, (daily?.$2 ?? 0) + minutes);
      totals[id] = (row, (period?.$2 ?? 0) + 1, (period?.$3 ?? 0) + minutes);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (warnings.isNotEmpty) ...[
          const AdminHeading(
            'Verify existing tasks',
            subtitle:
                'Confirm that another visit is intentional before approving.',
          ),
          AdminTable(
            ['Date', 'Location', 'Task', 'Existing time', 'Source'],
            [
              for (final row in warnings)
                [
                  adminCell(row['date']),
                  adminCell(row['location'] ?? 'Campaign'),
                  adminCell(row['task']),
                  adminCell(_localTime(row['time'])),
                  adminCell(row['source']),
                ],
            ],
            empty: 'No duplicates.',
          ),
          CheckboxListTile(
            value: verified,
            onChanged: (value) => setState(() => verified = value == true),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'I verified these existing tasks and intend to proceed.',
            ),
          ),
        ],
        AdminHeading(
          'Draft assignments',
          subtitle:
              '${assigned.length} assigned · ${rows.length - assigned.length} unassigned · Malaysia time',
          actions: [
            FilledButton(
              onPressed: assigned.isNotEmpty && (warnings.isEmpty || verified)
                  ? () async {
                      int? count;
                      final saved = await adminConfirm(
                        context,
                        'Approve schedule?',
                        'Publish ${assigned.length} reviewed assignments as work orders. Unassigned tasks will stay available for another draft.',
                        'Approve assignments',
                        () async {
                          count = await widget.approve(
                            rows,
                            verified ? warnings : null,
                          );
                        },
                      );
                      if (saved && mounted) widget.published(count!);
                    }
                  : null,
              child: const Text('Approve assignments'),
            ),
          ],
        ),
        AdminTable(
          ['Date', 'Task', 'Location', 'Time', 'Duration', 'Worker'],
          [
            for (final row in rows)
              [
                adminCell(isoDate(adminDay(row['occurrence']))),
                adminCell(row['title']),
                adminCell(widget.location(row) ?? row['facility']),
                adminCell(
                  row['starts'] != null
                      ? scheduleTime(row, start: 'starts', end: 'ends')
                      : 'From ${malaysiaClock(row['occurrence'])}',
                ),
                adminCell('${row['duration_minutes']} min'),
                adminCell(
                  row['worker_name'] ?? 'Unassigned · No eligible worker',
                ),
              ],
          ],
          empty: 'No outstanding tasks match this schedule.',
        ),
        if (workloads.keys.map((key) => key.$2).toSet().length > 1) ...[
          const AdminHeading('Work added across this period'),
          AdminTable(
            ['Worker', 'Tasks', 'Draft work time'],
            [
              for (final (row, count, minutes) in totals.values)
                [
                  adminCell('${row['worker_name']} · ${row['employee_id']}'),
                  adminCell(count),
                  adminCell('$minutes min'),
                ],
            ],
            empty: 'No assignments.',
          ),
        ],
        if (workloads.isNotEmpty) ...[
          const AdminHeading('Staff workload by date'),
          AdminTable(
            [
              'Date',
              'Worker',
              'Worked',
              'Existing load',
              'Added',
              'Projected / daily limit',
            ],
            [
              for (final entry in workloads.entries)
                [
                  adminCell(entry.key.$2),
                  adminCell(
                    '${entry.value.$1['worker_name']} · ${entry.value.$1['employee_id']}',
                  ),
                  adminCell('${entry.value.$1['worked_minutes']} min'),
                  adminCell('${entry.value.$1['booked_before']} min'),
                  adminCell('${entry.value.$2} min'),
                  adminCell(
                    '${(entry.value.$1['booked_before'] as num) + entry.value.$2} / ${entry.value.$1['work_limit']} min',
                  ),
                ],
            ],
            empty: 'No assignments.',
          ),
        ],
      ],
    );
  }
}
