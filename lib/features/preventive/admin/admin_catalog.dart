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
  'asset': 'Property',
  'other': 'Other',
};

const _facilityTypeLabelKey = 'facility_type_label';

String? _facilityTypeLabel(AdminRow row) {
  final label = (row['metadata'] as Map?)?[_facilityTypeLabelKey];
  return label is String && label.trim().isNotEmpty
      ? label
      : _types[row['facility_type']];
}

const _childTypes = {'building': 'floor', 'floor': 'room', 'room': 'asset'};
const _addLabels = {
  'floor': 'Add level',
  'room': 'Add room',
  'asset': 'Add property',
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
  const AdminFacilities({super.key, required this.data, required this.padding});
  final AdminData data;
  final EdgeInsets padding;

  @override
  State<AdminFacilities> createState() => _AdminFacilitiesState();
}

class _AdminFacilitiesState extends State<AdminFacilities> {
  final navigator = GlobalKey<NavigatorState>();
  late final listing = ValueNotifier(widget.data.facilities());

  @override
  void dispose() {
    listing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NavigatorPopHandler<void>(
    onPopWithResult: (_) => navigator.currentState?.pop(),
    child: Navigator(key: navigator, onGenerateRoute: (_) => facilityRoute([])),
  );

  Route<void> facilityRoute(List<String> trail) => MaterialPageRoute<void>(
    settings: RouteSettings(name: trail.isEmpty ? '/' : trail.last),
    builder: (_) => SingleChildScrollView(
      padding: widget.padding,
      child: _FacilityPage(
        data: widget.data,
        listing: listing,
        trail: trail,
        open: (id) =>
            navigator.currentState!.push<void>(facilityRoute([...trail, id])),
      ),
    ),
  );
}

class _FacilityPage extends StatefulWidget {
  const _FacilityPage({
    required this.data,
    required this.listing,
    required this.trail,
    required this.open,
  });

  final AdminData data;
  final ValueNotifier<Future<List<AdminRow>>> listing;
  final List<String> trail;
  final ValueChanged<String> open;

  @override
  State<_FacilityPage> createState() => _FacilityPageState();
}

class _FacilityPageState extends State<_FacilityPage> {
  AdminData get data => widget.data;
  List<String> get trail => widget.trail;
  int page = 0;
  String search = '';
  AdminRow? schedule;

  void reload() => widget.listing.value = data.facilities();

  void backTo(String route) =>
      Navigator.of(context).popUntil(ModalRoute.withName(route));

  List<AdminRow> matches(List<AdminRow> rows, String? active) {
    final needle = search.toLowerCase();
    return [
      for (final row in rows)
        if (row['parent_id'] == active &&
            (active != null || row['facility_type'] == 'building') &&
            (row['metadata'] as Map?)?['arena_replaced'] != true &&
            (row['metadata'] as Map?)?['catalog_removed'] != true &&
            (row['name'] as String).toLowerCase().contains(needle))
          row,
    ];
  }

  Future<void> edit(
    List<AdminRow> facilities, {
    AdminRow? row,
    AdminRow? parent,
  }) async {
    final metadata = row?['metadata'] as Map? ?? const {};
    final additionalDetails = Map.of(metadata)..remove(_facilityTypeLabelKey);
    final createType = parent == null
        ? 'building'
        : _childTypes[parent['facility_type']];
    final addLabel = parent == null
        ? 'Create facility'
        : _addLabels[createType] ?? 'Add sub-location';
    final parents = {
      for (final item in facilities)
        if (item['id'] != row?['id'] &&
            (item['effective_active'] == true ||
                item['id'] == row?['parent_id']))
          item['id'] as String: item['name'] as String,
    };
    final saved = await adminForm(
      context,
      row != null ? 'Edit facility' : addLabel,
      {
        'name': row?['name'],
        'facility_type': row?['facility_type'] ?? createType ?? 'room',
        _facilityTypeLabelKey: metadata[_facilityTypeLabelKey],
        'parent_id': row?['parent_id'] ?? '',
        'metadata': additionalDetails.isEmpty
            ? ''
            : const JsonEncoder.withIndent('  ').convert(additionalDetails),
        'toilet': row != null && isToilet(row),
      },
      (values, refresh) => [
        if (parent != null && row == null) Text('Inside ${parent['name']}'),
        adminText(
          values,
          'name',
          switch (createType) {
            'floor' when row == null => 'Level name',
            'room' when row == null => 'Room name',
            'asset' when row == null => 'Property name',
            _ => 'Facility name',
          },
          required: true,
          max: 120,
        ),
        adminText(values, _facilityTypeLabelKey, 'Type', max: 120),
        if (row != null || createType == null)
          adminSelect(
            values,
            'facility_type',
            'Hierarchy type',
            _types,
            refresh,
            required: true,
          ),
        if (row != null)
          adminSelect(values, 'parent_id', 'Parent facility', {
            '': 'No parent',
            ...parents,
          }, refresh),
        if (values['facility_type'] == 'room')
          adminCheck(values, 'toilet', 'Toilet room', refresh),
        if (row != null || createType == null)
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
        if (type == 'room' && values['toilet'] == true) {
          decoded['room_type'] = 'toilet';
        } else if (decoded['room_type'] == 'toilet') {
          decoded.remove('room_type');
        }
        final customType = optionalField(values, _facilityTypeLabelKey);
        if (customType == null) {
          decoded.remove(_facilityTypeLabelKey);
        } else {
          decoded[_facilityTypeLabelKey] = customType;
        }
        final payload = {
          'name': fieldText(values, 'name'),
          'facility_type': type,
          'metadata': decoded,
          'parent_id': row != null
              ? optionalField(values, 'parent_id')
              : parent?['id'],
        };
        await data.saveFacility(payload, id: row?['id'] as String?);
      },
      action: row == null ? addLabel : 'Save changes',
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
    if (trail.isNotEmpty && parent == null) {
      return TextButton(
        onPressed: () => backTo('/'),
        child: const Text('Back to Facilities'),
      );
    }
    final currentType = parent?['facility_type'];
    final childLabel =
        _addLabels[_childTypes[currentType]] ?? 'Add sub-location';
    final entries = matches(rows, parent?['id'] as String?);
    final start = page * 25;
    final visible = entries.skip(start).take(25);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (parent != null)
          Wrap(
            children: [
              adminAction('Facilities', () => backTo('/')),
              for (final id in trail.take(trail.length - 1))
                if (byId[id] case final node?)
                  adminAction('/ ${node['name']}', () => backTo(id)),
            ],
          ),
        AdminHeading(
          (parent?['name'] as String?) ?? 'Facilities',
          subtitle: switch (currentType) {
            'building' => 'Open a level to see its rooms.',
            'floor' => 'Open a room to see its properties.',
            'room' => 'Equipment and other properties in this room.',
            'asset' => 'Room property',
            _ => 'Open a building to see its levels.',
          },
          actions: [
            if (parent != null)
              OutlinedButton(
                onPressed: () => setState(() => schedule = parent),
                child: const Text('Schedules for this location'),
              ),
            if (currentType != 'asset')
              FilledButton(
                onPressed: () => edit(rows, parent: parent),
                child: Text(parent == null ? 'Create facility' : childLabel),
              ),
          ],
        ),
        if (currentType == 'asset')
          AdminTable(
            ['Type', 'Status', 'Actions'],
            [
              [
                adminCell(_facilityTypeLabel(parent!)),
                adminCell(statusOf(parent)),
                adminActions([
                  adminAction('Edit', () => edit(rows, row: parent)),
                  if (parent['is_active'] == true)
                    adminAction('Deactivate', () => _deactivateRecord(parent)),
                ]),
              ],
            ],
            empty: 'No property details.',
          )
        else ...[
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
              for (final row in visible)
                [
                  adminAction(
                    '${row['name']} ›',
                    () => widget.open(row['id'] as String),
                  ),
                  adminCell(_facilityTypeLabel(row)),
                  adminCell(statusOf(row)),
                  adminActions([
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
          if (page > 0 || entries.length > 25)
            AdminPager(
              page: page,
              next: entries.length > start + 25,
              change: (number) => setState(() => page = number),
            ),
        ],
      ],
    );
  }

  String statusOf(AdminRow row) => row['is_active'] != true
      ? 'Inactive'
      : row['effective_active'] == true
      ? 'Active'
      : 'Parent inactive';

  @override
  Widget build(BuildContext context) {
    if (schedule case final location?) {
      return AdminFacilitySchedules(
        data: data,
        facility: location,
        back: () => setState(() => schedule = null),
      );
    }
    return ValueListenableBuilder(
      valueListenable: widget.listing,
      builder: (context, future, _) => AdminLoad(future, body, retry: reload),
    );
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
