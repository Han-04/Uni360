import 'dart:convert';

import 'package:flutter/material.dart';

import 'admin_data.dart';
import 'admin_schedule_review.dart';
import 'admin_scheduling.dart';
import 'admin_widgets.dart';

const _types = {
  'building': 'Building',
  'floor': 'Floor',
  'room': 'Room',
  'outdoor_area': 'Outdoor area',
  'asset': 'Asset',
  'other': 'Other',
};

const _checklists = {
  'Toilet Cleaning': [
    'Clean fixtures',
    'Mop floor',
    'Refill soap and paper',
    'Empty waste bins',
    'Report leaks or damaged fixtures',
  ],
  'Security Patrol': [
    'Check entrances and exits',
    'Check doors and gates',
    'Inspect corridors and common areas',
    'Record incidents or hazards',
  ],
  'Facility Safety Inspection': [
    'Check lighting',
    'Check exit access',
    'Record defects',
    'Inspect floors and walkways',
  ],
  'Gardening and Weeding': [
    'Remove weeds',
    'Water plants',
    'Trim overgrowth',
    'Clear garden waste',
    'Report damaged plants or equipment',
  ],
  'Mosquito Control Site Check': [
    'Check for standing water',
    'Record affected locations',
    'Submit site notes',
    'Check drains and gutters',
  ],
};

String taskCategory(AdminRow row) {
  const legacy = {
    'Toilet Cleaning': 'Cleaning',
    'Facility Safety Inspection': 'Inspection',
    'Mosquito Control Site Check': 'Pest Control',
  };
  final title = row['title'] as String;
  final category = row['category'] as String;
  return legacy[title] == category ? title : category;
}

bool isToilet(AdminRow row) =>
    row['facility_type'] == 'room' &&
    (row['metadata'] as Map?)?['room_type'] == 'toilet';

Map<String, String> namedOptions(List<AdminRow> rows, {String name = 'name'}) =>
    {for (final row in rows) row['id'] as String: row[name] as String};

Map<String, String> facilityPaths(List<AdminRow> rows) {
  final byId = {for (final row in rows) row['id']: row};
  return {for (final row in rows) row['id'] as String: pathFor(row, byId)};
}

String pathFor(AdminRow start, Map<dynamic, AdminRow> byId) {
  final names = <String>[];
  final visited = <Object?>{};
  for (
    AdminRow? row = start;
    row != null && visited.add(row['id']);
    row = byId[row['parent_id']]
  ) {
    names.add(row['name'] as String);
  }
  return names.reversed.join(' / ');
}

class AdminFacilities extends StatefulWidget {
  const AdminFacilities({super.key, required this.data});
  final AdminData data;

  @override
  State<AdminFacilities> createState() => _AdminFacilitiesState();
}

class _AdminFacilitiesState extends State<AdminFacilities> {
  AdminData get data => widget.data;
  late var listing = data.facilities();
  List<String> trail = [];
  bool other = false;
  int page = 0;
  String search = '';
  AdminRow? schedule;

  void reload() {
    final next = data.facilities();
    setState(() {
      listing = next;
    });
  }

  void open(List<String> path) => setState(() {
    trail = path;
    page = 0;
    search = '';
  });

  List<(AdminRow, int)> matches(List<AdminRow> rows, String? active) {
    final children = <Object?, List<AdminRow>>{};
    for (final row in rows) {
      children.putIfAbsent(row['parent_id'], () => []).add(row);
    }
    final needle = search.toLowerCase();
    final seen = <Object?>{active};
    List<(AdminRow, int)> branch(Object? parent, int depth) => [
      for (final row in children[parent] ?? const <AdminRow>[])
        if (seen.add(row['id'])) ...[
          (row, depth),
          ...branch(row['id'], depth + 1),
        ],
    ];
    bool nameMatches(AdminRow row) =>
        (row['name'] as String).toLowerCase().contains(needle);
    if (active == null) {
      return [
        for (final row in children[null] ?? const <AdminRow>[])
          if ((row['facility_type'] == 'building') != other && nameMatches(row))
            (row, 0),
      ];
    }
    final entries = branch(active, 0);
    if (needle.isEmpty) return entries;
    final visibleIds = <Object?>{};
    final byId = {for (final row in rows) row['id']: row};
    for (final (row, _) in entries.where((item) => nameMatches(item.$1))) {
      for (
        AdminRow? node = row;
        node != null && node['id'] != active && visibleIds.add(node['id']);
        node = byId[node['parent_id']]
      ) {}
    }
    return entries
        .where((entry) => visibleIds.contains(entry.$1['id']))
        .toList();
  }

  Future<void> edit(
    List<AdminRow> facilities, {
    AdminRow? row,
    AdminRow? parent,
  }) async {
    final metadata = row?['metadata'] as Map? ?? const {};
    final parents = {
      for (final item in facilities)
        if (item['id'] != row?['id'] &&
            (item['effective_active'] == true ||
                item['id'] == row?['parent_id']))
          item['id'] as String: item['name'] as String,
    };
    final saved = await adminForm(
      context,
      row != null
          ? 'Edit facility'
          : parent != null
          ? 'Add sub-location'
          : 'Create facility',
      {
        'name': row?['name'],
        'facility_type':
            row?['facility_type'] ??
            (parent != null
                ? 'room'
                : other
                ? 'outdoor_area'
                : 'building'),
        'parent_id': row?['parent_id'] ?? '',
        'metadata': metadata.isEmpty
            ? ''
            : const JsonEncoder.withIndent('  ').convert(metadata),
        'toilet': row != null && isToilet(row),
      },
      (values, refresh) => [
        if (parent != null && row == null) Text('Inside ${parent['name']}'),
        adminText(values, 'name', 'Name', required: true, max: 120),
        adminSelect(
          values,
          'facility_type',
          'Type',
          _types,
          refresh,
          required: true,
        ),
        if (row != null)
          adminSelect(values, 'parent_id', 'Parent facility', {
            '': 'No parent',
            ...parents,
          }, refresh),
        adminCheck(values, 'toilet', 'Toilet room', refresh),
        ExpansionTile(
          title: const Text('Additional facility details'),
          children: [
            adminText(values, 'metadata', 'Metadata (JSON object)', lines: 4),
          ],
        ),
      ],
      (values) async {
        final raw = optionalField(values, 'metadata');
        final decoded = raw == null ? <String, dynamic>{} : jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException(
            'Enter the facility details as a JSON object.',
          );
        }
        final type = values['facility_type'];
        if (values['toilet'] == true) {
          if (type != 'room') {
            throw const FormatException(
              'Choose Room as the facility type for a toilet.',
            );
          }
          decoded['room_type'] = 'toilet';
        } else if (decoded['room_type'] == 'toilet') {
          decoded.remove('room_type');
        }
        final payload = {
          'name': fieldText(values, 'name'),
          'facility_type': type,
          'metadata': decoded,
          'parent_id': row != null
              ? optionalField(values, 'parent_id')
              : parent?['id'],
        };
        final table = data.table('preventive_facility');
        await data.write(
          row != null
              ? table.update(payload).eq('id', row['id'])
              : table.insert(payload),
        );
        if (row == null && parent == null) other = type != 'building';
      },
      action: row == null ? 'Create facility' : 'Save changes',
    );
    if (saved && mounted) {
      if (row == null) {
        search = '';
        page = 0;
      }
      reload();
      adminMessage(context, 'Facility saved.');
    }
  }

  Future<void> _deactivateRecord(AdminRow row) async {
    final saved = await adminConfirm(
      context,
      'Deactivate facility?',
      'New work orders will be blocked for ${row['name']} and its sub-locations. Existing work orders will be kept.',
      'Deactivate',
      () => data.write(
        data
            .table('preventive_facility')
            .update({'is_active': false})
            .eq('id', row['id'])
            .eq('is_active', true),
      ),
    );
    if (saved && mounted) {
      reload();
      adminMessage(context, 'Facility deactivated.');
    }
  }

  Widget body(List<AdminRow> rows) {
    final byId = {for (final row in rows) row['id']: row};
    final parent = trail.isEmpty ? null : byId[trail.last];
    final entries = matches(rows, parent?['id'] as String?);
    final start = parent == null ? page * 25 : 0;
    final visible = parent == null ? entries.skip(start).take(25) : entries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (parent != null)
          Wrap(
            children: [
              adminAction(
                other ? 'Other locations' : 'Facilities',
                () => open([]),
              ),
              for (final (index, id) in trail.indexed)
                if (byId[id] case final node?)
                  adminAction(
                    '/ ${node['name']}',
                    () => open(trail.take(index + 1).toList()),
                  ),
            ],
          ),
        AdminHeading(
          (parent?['name'] as String?) ??
              (other ? 'Other locations' : 'Facilities'),
          subtitle: parent == null
              ? 'Open a building to see its floors and rooms.'
              : 'Floors, rooms and other spaces in this location.',
          actions: [
            if (parent == null)
              OutlinedButton(
                onPressed: () {
                  other = !other;
                  open([]);
                },
                child: Text(other ? 'Buildings' : 'Other locations'),
              )
            else
              OutlinedButton(
                onPressed: () => setState(() => schedule = parent),
                child: const Text('Schedules for this location'),
              ),
            FilledButton(
              onPressed: () => edit(rows, parent: parent),
              child: Text(
                parent == null ? 'Create facility' : 'Add sub-location',
              ),
            ),
          ],
        ),
        AdminSearch(
          'Search by name',
          (value) => setState(() {
            search = value;
            page = 0;
          }),
          key: ValueKey((trail, search)),
          initial: search,
        ),
        AdminTable(
          ['Facility', 'Type', 'Status', 'Actions'],
          [
            for (final (row, depth) in visible)
              [
                Padding(
                  padding: EdgeInsets.only(left: depth.clamp(0, 6) * 14.0),
                  child:
                      ['building', 'floor'].contains(row['facility_type']) ||
                          rows.any((entry) => entry['parent_id'] == row['id'])
                      ? adminAction(
                          '${row['name']} ›',
                          () => open(pathIds(row, byId)),
                        )
                      : adminCell(row['name']),
                ),
                adminCell(_types[row['facility_type']]),
                adminCell(
                  row['is_active'] != true
                      ? 'Inactive'
                      : row['effective_active'] == true
                      ? 'Active'
                      : 'Parent inactive',
                ),
                adminActions([
                  adminAction(
                    'View',
                    () => adminDetails(context, row['name'] as String, [
                      Text(_types[row['facility_type']] ?? 'Facility'),
                      Text(
                        'Parent facility · ${byId[row['parent_id']]?['name'] ?? "None"}',
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        const JsonEncoder.withIndent('  ')
                            .convert(row['metadata']),
                      ),
                    ]),
                  ),
                  adminAction('Edit', () => edit(rows, row: row)),
                  adminAction(
                    'Schedules',
                    () => setState(() => schedule = row),
                  ),
                  if (row['is_active'] == true)
                    adminAction('Deactivate', () => _deactivateRecord(row)),
                ]),
              ],
          ],
          empty: 'No matching facilities.',
        ),
        if (parent == null)
          AdminPager(
            page: page,
            next: entries.length > start + 25,
            change: (number) => setState(() => page = number),
          ),
      ],
    );
  }

  List<String> pathIds(AdminRow start, Map<dynamic, AdminRow> byId) {
    final path = <String>{};
    for (
      AdminRow? row = start;
      row != null && path.add(row['id'] as String);
      row = byId[row['parent_id']]
    ) {}
    return path.toList().reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    if (schedule case final location?) {
      return AdminFacilitySchedules(
        data: data,
        facility: location,
        back: () => setState(() => schedule = null),
      );
    }
    return AdminLoad(listing, body, retry: reload);
  }
}

class AdminTaskTemplates extends StatefulWidget {
  const AdminTaskTemplates({
    super.key,
    required this.data,
    required this.superAdmin,
  });
  final AdminData data;
  final bool superAdmin;

  @override
  State<AdminTaskTemplates> createState() => _AdminTaskTemplatesState();
}

class _AdminTaskTemplatesState extends State<AdminTaskTemplates> {
  AdminData get data => widget.data;
  String search = '';
  int page = 0;
  late var listing = load();
  bool reviewing = false;
  AdminRow? template;

  Future<(List<AdminRow>, List<AdminRow>)> load() async {
    var query = data.table('preventive_task_definition').select(taskFields);
    if (search.isNotEmpty) {
      final escaped = search.replaceAllMapped(
        RegExp(r'[\\%_]'),
        (value) => '\\${value[0]}',
      );
      query = query.ilike('title', '%$escaped%');
    }
    final results = await Future.wait([
      query
          .order('title', ascending: true)
          .order('id')
          .range(page * 25, (page + 1) * 25),
      data.zones(),
    ]);
    return (results[0], results[1]);
  }

  void reload() {
    final next = load();
    setState(() {
      listing = next;
    });
  }

  void back() => setState(() {
    reviewing = false;
    template = null;
    listing = load();
  });

  Future<void> edit(Map<String, String> zones, [AdminRow? row]) async {
    final roles = await _loadRoles();
    if (roles == null || !mounted) return;
    const defaults = [
      'Cleaner',
      'Facilities Maintenance Technician',
      'Gardener',
      'Pest Control Technician',
      'Security Guard',
    ];
    final choices = {
      ...defaults,
      ...roles,
      if (row?['required_job_role'] case final String role) role,
    }.toList()..sort();
    final original = row == null ? '' : taskCategory(row);
    final previous = (row?['checklist'] as List? ?? const []).cast<String>();
    final selected = <String, Set<String>>{original: previous.toSet()};
    final saved = await adminForm(
      context,
      row == null ? 'Create task template' : 'Edit task template',
      {
        'title': row?['title'],
        'category': original,
        'instructions': row?['instructions'],
        'duration_minutes': row?['duration_minutes'] ?? 30,
        'required_job_role': row?['required_job_role'] ?? '',
        'zone_id': widget.superAdmin ? '' : null,
      },
      (values, refresh) {
        final category = fieldText(values, 'category');
        final items = {
          ...(category == original ? previous : const <String>[]),
          ...?_checklists[category],
        };
        final checked = selected.putIfAbsent(category, () => {});
        return [
          if (row == null)
            adminSelect(
              values,
              'zone_id',
              'Zone',
              {if (widget.superAdmin) '': 'Campus-wide', ...zones},
              refresh,
              required: !widget.superAdmin,
            )
          else
            Text(zones[row['zone_id']] ?? 'Campus-wide'),
          adminText(values, 'title', 'Title', required: true, max: 120),
          adminSelect(
            values,
            'category',
            'Category',
            {
              for (final name in {
                ..._checklists.keys,
                if (original.isNotEmpty) original,
              })
                name: name,
            },
            refresh,
            required: true,
          ),
          adminText(
            values,
            'instructions',
            'Instructions',
            required: true,
            max: 4000,
            lines: 3,
          ),
          adminText(
            values,
            'duration_minutes',
            'Work time (minutes)',
            required: true,
            minimumNumber: 1,
            maximumNumber: 720,
          ),
          const Text('Checklist'),
          if (items.isEmpty)
            const Text('Choose a category to see checklist options.'),
          for (final item in items)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(item),
              value: checked.contains(item),
              onChanged: (value) {
                if (value == true) {
                  checked.add(item);
                } else {
                  checked.remove(item);
                }
                refresh();
              },
            ),
          adminSelect(values, 'required_job_role', 'Required job role', {
            '': 'Any job role',
            for (final role in choices) role: role,
          }, refresh),
        ];
      },
      (values) async {
        final category = fieldText(values, 'category');
        final chosen = selected[category] ?? {};
        final options = {
          ...(category == original ? previous : const <String>[]),
          ...?_checklists[category],
        };
        final payload = {
          'title': fieldText(values, 'title'),
          'category': category,
          'instructions': fieldText(values, 'instructions'),
          'checklist': options.where(chosen.contains).toList(),
          'required_job_role': optionalField(values, 'required_job_role'),
          'required_skill_id': null,
          'duration_minutes': int.parse(fieldText(values, 'duration_minutes')),
          if (row == null) 'zone_id': optionalField(values, 'zone_id'),
        };
        final table = data.table('preventive_task_definition');
        await data.write(
          row == null
              ? table.insert(payload)
              : table.update(payload).eq('id', row['id']),
        );
      },
      action: row == null ? 'Create task template' : 'Save changes',
    );
    if (saved && mounted) {
      if (row == null) {
        search = '';
        page = 0;
      }
      reload();
      adminMessage(context, 'Task template saved.');
    }
  }

  Future<Iterable<String>?> _loadRoles() async {
    try {
      final rows = await data.all(
        data.table('worker_profile').select('job_role'),
        'job_role',
        'worker_id',
      );
      return rows
          .map((row) => row['job_role'])
          .whereType<String>()
          .where((name) => name.trim().isNotEmpty);
    } catch (error) {
      if (mounted) adminMessage(context, adminError(error));
      return null;
    }
  }

  Future<void> _deactivateRecord(AdminRow row) async {
    final saved = await adminConfirm(
      context,
      'Deactivate task template?',
      'New work orders for ${row['title']} will be blocked. Existing work orders will be kept.',
      'Deactivate',
      () => data.write(
        data
            .table('preventive_task_definition')
            .update({'is_active': false})
            .eq('id', row['id'])
            .eq('is_active', true),
      ),
    );
    if (saved && mounted) {
      reload();
      adminMessage(context, 'Task template deactivated.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (reviewing) return AdminScheduleReview(data: data, back: back);
    if (template case final row?) {
      return AdminRangeSchedule(data: data, template: row, back: back);
    }
    return AdminLoad(listing, (result) {
      final (rows, zones) = (result.$1, namedOptions(result.$2));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeading(
            'Schedule Task',
            subtitle:
                'Manage templates, recurring times and worker assignments.',
            actions: [
              OutlinedButton(
                onPressed: () => setState(() => reviewing = true),
                child: const Text('Review auto schedule'),
              ),
              FilledButton(
                onPressed: zones.isNotEmpty || widget.superAdmin
                    ? () => edit(zones)
                    : null,
                child: const Text('Create task template'),
              ),
            ],
          ),
          AdminSearch(
            'Search by title',
            (value) {
              search = value;
              page = 0;
              reload();
            },
            key: ValueKey(search),
            initial: search,
          ),
          AdminTable(
            ['Title', 'Category', 'Zone', 'Status', 'Actions'],
            [
              for (final row in rows.take(25))
                [
                  adminCell(row['title']),
                  adminCell(taskCategory(row)),
                  adminCell(
                    row['zone_id'] == null
                        ? 'Campus-wide'
                        : zones[row['zone_id']] ?? 'Assigned zone',
                  ),
                  adminCell(row['is_active'] == true ? 'Active' : 'Inactive'),
                  adminActions([
                    adminAction(
                      'View',
                      () => adminDetails(context, row['title'] as String, [
                        Text(taskCategory(row)),
                        Text(row['instructions'] as String),
                        Text('Work time · ${row['duration_minutes']} min'),
                        Text(
                          'Required job role · ${row['required_job_role'] ?? "Any"}',
                        ),
                        for (final item
                            in (row['checklist'] as List).cast<String>())
                          Text('• $item'),
                      ]),
                    ),
                    adminAction('Edit', () => edit(zones, row)),
                    if (row['is_active'] == true) ...[
                      adminAction(
                        'Schedule',
                        () => setState(() => template = row),
                      ),
                      adminAction('Deactivate', () => _deactivateRecord(row)),
                    ],
                  ]),
                ],
            ],
            empty: 'No matching task templates.',
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
      );
    }, retry: reload);
  }
}
