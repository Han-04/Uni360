import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uni360/app/uni360_app.dart';
import 'package:uni360/features/preventive/admin/admin_approvals.dart';
import 'package:uni360/features/preventive/admin/admin_catalog.dart';
import 'package:uni360/features/preventive/admin/admin_data.dart';
import 'package:uni360/features/preventive/admin/admin_schedule_review.dart';
import 'package:uni360/features/preventive/admin/admin_scheduling.dart';
import 'package:uni360/features/preventive/admin/admin_widgets.dart';
import 'package:uni360/shared/account/account.dart';

import 'support/test_accounts.dart';

class _TestSupabaseClient extends Fake implements SupabaseClient {
  @override
  SupabaseQuerySchema schema(String schema) => _LeaveQuerySchema();
}

class _LeaveQuerySchema extends Fake implements SupabaseQuerySchema {
  @override
  SupabaseQueryBuilder from(String table) => switch (table) {
    'worker_leave_request' => _FixtureQuery([]),
    _ => throw ArgumentError.value(table),
  };
}

class _TestAdministration extends AdminData {
  _TestAdministration({this.emptyLists = false}) : super(_TestSupabaseClient());

  final bool emptyLists;
  final saved = <AdminRow>[];
  final createdFacilities = <AdminRow>[];

  @override
  SupabaseQueryBuilder table(String name) => _FixtureQuery(switch (name) {
    'preventive_task_plan' => [],
    'preventive_task_definition' when emptyLists => [],
    'preventive_task_definition' => [
      {
        'title': 'Toilet Cleaning',
        'category': 'Cleaning',
        'instructions': 'Clean the fixtures.',
        'checklist': ['Clean fixtures'],
        'duration_minutes': 30,
        'is_active': true,
      },
      {
        'title': 'Archived task',
        'category': 'Inspection',
        'instructions': 'Inspect the facilities.',
        'checklist': ['Check the facilities'],
        'duration_minutes': 30,
        'is_active': false,
      },
    ],
    _ => throw ArgumentError.value(name),
  });

  @override
  Future<void> saveFacility(AdminRow values, {String? id}) async {
    if (id != null) {
      final index = createdFacilities.indexWhere((row) => row['id'] == id);
      createdFacilities[index] = {...createdFacilities[index], ...values};
      return;
    }
    createdFacilities.add({
      ...values,
      'id': 'new-${createdFacilities.length}',
      'is_active': true,
      'effective_active': true,
    });
  }

  @override
  Future<AdminRow> accounts(String action, AdminRow values) async {
    if (action == 'create') {
      saved.add({
        'full_name': values['name'],
        'employee_id': values['employeeId'],
        'is_active': true,
      });
      return {};
    }
    expect(action, 'list');
    final status = values['status'];
    return {
      'rows': [
        for (final row in saved)
          if (status == 'all' ||
              (row['is_active'] == true) == (status == 'active'))
            row,
      ],
      'hasNext': false,
    };
  }

  @override
  Future<List<AdminRow>> facilities() async => [
    {
      'id': 'building',
      'name': 'Block D',
      'facility_type': 'building',
      'is_active': true,
      'effective_active': true,
      'zone_id': 'zone',
    },
    {
      'id': 'floor',
      'parent_id': 'building',
      'name': 'Level 1',
      'facility_type': 'floor',
      'is_active': true,
      'effective_active': true,
      'zone_id': 'zone',
    },
    {
      'id': 'toilet',
      'parent_id': 'floor',
      'name': 'Female Toilet',
      'facility_type': 'room',
      'metadata': {'room_type': 'toilet'},
      'is_active': true,
      'effective_active': true,
      'zone_id': 'zone',
    },
    ...createdFacilities,
  ];

  @override
  Future<List<AdminRow>> zones() async => [
    {'id': 'zone', 'name': 'Main Campus'},
  ];

  DateTime? reviewDay;

  @override
  Future<List<String>> scheduledTaskNames() async => ['Toilet Cleaning'];

  @override
  Future<int> overdueCount() async => emptyLists ? 0 : 1;

  @override
  Future<List<AdminRow>> overdueOrders(int page) async => [
    if (!emptyLists)
      for (final row in await scheduledTasksOn(
        'Toilet Cleaning',
        adminToday().subtract(const Duration(days: 1)),
      ))
        {...row, 'title': 'Toilet Cleaning'},
  ];

  @override
  Future<T> withCatalogWorkOrders<T>(
    Future<T> Function(PostgrestFilterBuilder<PostgrestList> query) read, {
    String fields = orderFields,
  }) => read(
    _FixtureResponse([
      if (!emptyLists)
        {
          'id': 'submitted-cleaning',
          'title': 'Toilet Cleaning',
          'worker_id': 'worker',
          'status': 'submitted',
          'scheduled_for': '2026-11-17T11:00:00+08:00',
          'submitted_at': '2026-11-17T11:45:00+08:00',
          'instructions': 'Clean the fixtures.',
          'checklist': ['Clean fixtures'],
          'checked_items': [0],
          'worker_notes': '',
        },
    ]),
  );

  @override
  Future<List<AdminRow>> scheduledTasksOn(String title, DateTime date) async {
    expect(title, 'Toilet Cleaning');
    reviewDay = date;
    return [
      {
        'worker_id': 'worker',
        'status': 'in_progress',
        'scheduled_for': '${isoDate(date)}T11:00:00+08:00',
        'due_at': '${isoDate(date)}T12:30:00+08:00',
        'preventive_work_order_target': [
          {'facility_path': 'Block D / Level 1 / Female Toilet'},
        ],
      },
    ];
  }

  @override
  Future<Map<String, AdminRow>> workerDirectory() async => {
    'worker': {'full_name': 'Nur Hidayah', 'employee_id': 'EMP-CLEAN-11'},
  };

  @override
  Future<List<String>> workerJobRoles() async => ['Cleaner', 'Gardener'];

  @override
  Future<List<AdminRow>> workers({
    String search = '',
    int page = 0,
    String? jobRole,
  }) async => [
    for (final (name, employee, role) in [
      ('Nur Hidayah', 'EMP-CLEAN-11', 'Cleaner'),
      ('Arvind Kumar', 'EMP-GARDEN-01', 'Gardener'),
    ])
      if ((jobRole == null || jobRole == role) &&
          (name.contains(search) || employee.contains(search)))
        {
          'worker_id': employee,
          'full_name': name,
          'employee_id': employee,
          'job_role': role,
        },
  ];
}

class _WorkforceProfileFixture extends _TestAdministration {
  @override
  SupabaseQueryBuilder table(String name) => _FixtureQuery(switch (name) {
    'worker_profile' => [
      {
        'job_role': 'Cleaner',
        'employment_status': 'active',
        'current_workload': 0,
        'daily_work_limit_minutes': 480,
      },
    ],
    'worker_skill' ||
    'worker_certification' ||
    'worker_availability' ||
    'preventive_work_order' ||
    'preventive_work_completion' => [],
    _ => throw ArgumentError.value(name),
  });
}

class _FixtureQuery extends Fake implements SupabaseQueryBuilder {
  _FixtureQuery(this.rows);

  final PostgrestList rows;

  @override
  PostgrestFilterBuilder<PostgrestList> select([String columns = '*']) =>
      _FixtureResponse(rows);
}

class _FixtureResponse<T> extends Fake implements PostgrestFilterBuilder<T> {
  _FixtureResponse(this.result);

  final T result;

  @override
  PostgrestTransformBuilder<PostgrestMap> single() =>
      _FixtureResponse((result as PostgrestList).single);

  @override
  PostgrestTransformBuilder<PostgrestMap?> maybeSingle() =>
      _FixtureResponse((result as PostgrestList).singleOrNull);

  @override
  Future<U> then<U>(FutureOr<U> Function(T) onValue, {Function? onError}) =>
      Future.value(result).then(onValue, onError: onError);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      switch (invocation.memberName) {
        #eq || #gte || #gt || #lt || #isFilter || #order || #range => this,
        _ => super.noSuchMethod(invocation),
      };
}

Future<void> _enterAdmin(
  WidgetTester tester,
  AccountRole role, {
  AdminData? data,
}) async {
  tester.view.physicalSize = const Size(1440, 960);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    Uni360App(
      accounts: TestAccounts(role: role),
      administration: data ?? _TestAdministration(),
      loadAssignedWork: (_, _) async => [],
    ),
  );
  await tester.pumpAndSettle();
  final button = find.text('Admin login');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.text('Administrator sign-in'), findsOneWidget);
  await tester.enterText(find.byType(TextFormField).at(0), TestAccounts.email);
  await tester.enterText(
    find.byType(TextFormField).at(1),
    TestAccounts.password,
  );
  await tester.tap(find.text('Sign in'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Workforce profile styles columns and illustrates an empty day', (
    tester,
  ) async {
    await _enterAdmin(
      tester,
      AccountRole.administrator,
      data: _WorkforceProfileFixture(),
    );
    await tester.tap(find.text('Workforce management'));
    await tester.pumpAndSettle();
    final openProfile = find.widgetWithText(AdminCommandButton, 'Open profile');
    expect(
      tester.widget<AdminCommandButton>(openProfile.first).icon,
      Icons.account_circle_outlined,
    );
    await tester.ensureVisible(openProfile.first);
    await tester.tap(openProfile.first);
    await tester.pumpAndSettle();

    expect(find.text('Employment'), findsNothing);
    final profileHeading = tester.widget<Text>(find.text('Worker profile'));
    expect(profileHeading.style?.color, isNot(Colors.white));
    final profileTable = tester.widget<DataTable>(
      find.ancestor(
        of: find.text('Job role'),
        matching: find.byType(DataTable),
      ),
    );
    expect(profileTable.headingRowColor?.resolve({}), Colors.black);
    expect(profileTable.headingTextStyle?.color, Colors.white);

    final skills = find.widgetWithText(AdminSectionCard, 'Skills');
    final skillsTable = find.descendant(
      of: skills,
      matching: find.byType(DataTable),
    );
    expect(
      find.descendant(of: skillsTable, matching: find.text('Name')),
      findsOneWidget,
    );
    final skillColumns = tester.widget<DataTable>(skillsTable);
    expect(skillColumns.headingRowColor?.resolve({}), Colors.black);
    expect(skillColumns.headingTextStyle?.color, Colors.white);
    expect(
      find.widgetWithText(AdminIllustratedEmptyState, 'No Skill Added'),
      findsOneWidget,
    );

    for (final label in ['Edit profile', 'Add Skill', 'Add Certifications']) {
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, label),
      );
      final style = button.style;
      expect(style?.backgroundColor?.resolve({}), Colors.white);
      expect(style?.foregroundColor?.resolve({}), Colors.black);
    }

    final previousMonth = find.byTooltip('Previous month');
    await tester.ensureVisible(previousMonth);
    final nextMonth = find.byTooltip('Next month');
    final calendarCenter =
        (tester.getCenter(previousMonth).dx + tester.getCenter(nextMonth).dx) /
        2;
    final availabilityCard = find.widgetWithText(
      AdminSectionCard,
      'Date availability',
    );
    expect(calendarCenter, closeTo(tester.getCenter(availabilityCard).dx, 1));

    final day = find.descendant(of: availabilityCard, matching: find.text('1'));
    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.pumpAndSettle();
    final taskTable = tester.widget<DataTable>(
      find.ancestor(of: find.text('Task'), matching: find.byType(DataTable)),
    );
    expect(taskTable.headingRowColor?.resolve({}), Colors.black);
    expect(taskTable.headingTextStyle?.color, Colors.white);
    expect(find.text('No assigned task for this date'), findsOneWidget);
    final illustration = tester.widget<Image>(
      find.descendant(
        of: find.widgetWithText(
          AdminIllustratedEmptyState,
          'No assigned task for this date',
        ),
        matching: find.byType(Image),
      ),
    );
    expect(
      (illustration.image as AssetImage).assetName,
      'assets/workforce/no-assigned-task.png',
    );
  });

  testWidgets('Workforce filters the directory by job role and search', (
    tester,
  ) async {
    await _enterAdmin(tester, AccountRole.administrator);
    await tester.tap(find.text('Workforce management'));
    await tester.pumpAndSettle();
    final workforce = tester.widget<DataTable>(find.byType(DataTable));
    expect(workforce.headingRowColor?.resolve({}), Colors.black);
    expect(workforce.headingTextStyle?.color, Colors.white);
    expect(find.widgetWithText(AdminCommandButton, 'Search'), findsOneWidget);
    expect(find.text('Employment'), findsNothing);
    expect(find.text('Nur Hidayah'), findsOneWidget);
    expect(find.text('Arvind Kumar'), findsOneWidget);
    await tester.tap(find.text('All job roles'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Cleaner'));
    await tester.pumpAndSettle();
    expect(find.text('Nur Hidayah'), findsOneWidget);
    expect(find.text('Arvind Kumar'), findsNothing);
    await tester.enterText(find.byType(TextField), 'EMP-GARDEN-01');
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.text('No matching workers.'), findsOneWidget);
    await tester.tap(find.byType(AdminFilterMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'All job roles'));
    await tester.pumpAndSettle();
    expect(find.text('Arvind Kumar'), findsOneWidget);
    expect(find.text('Nur Hidayah'), findsNothing);
  });

  testWidgets('Administrator can open the overdue alert list', (tester) async {
    await _enterAdmin(tester, AccountRole.administrator);
    expect(find.byType(Badge), findsOneWidget);
    await tester.tap(find.text('Overdue tasks'));
    await tester.pumpAndSettle();
    final overdue = tester.widget<DataTable>(find.byType(DataTable));
    expect(overdue.headingRowColor?.resolve({}), Colors.black);
    expect(overdue.headingTextStyle?.color, Colors.white);
    expect(find.widgetWithText(AdminCommandButton, 'Refresh'), findsOneWidget);
    expect(find.text('Toilet Cleaning'), findsOneWidget);
    expect(find.text('Nur Hidayah · EMP-CLEAN-11'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Account status filters the account list', (tester) async {
    final data = _TestAdministration()
      ..saved.addAll([
        {'full_name': 'Enabled Worker', 'is_active': true},
        {'full_name': 'Disabled Worker', 'is_active': false},
      ]);
    await _enterAdmin(tester, AccountRole.administrator, data: data);
    expect(find.text('Enabled Worker'), findsOneWidget);
    expect(find.text('Disabled Worker'), findsOneWidget);
    final active = find.text('Active');
    expect(tester.widget<Text>(active).style?.color, const Color(0xFF17633B));
    final badge = tester.widget<DecoratedBox>(
      find.ancestor(of: active, matching: find.byType(DecoratedBox)).first,
    );
    expect((badge.decoration as BoxDecoration).color, const Color(0xFFE0F3E8));
    expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));
    final deactivate = find.widgetWithText(AdminCommandButton, 'Deactivate');
    expect(
      find.descendant(
        of: deactivate,
        matching: find.byIcon(Icons.person_off_outlined),
      ),
      findsOneWidget,
    );
    await tester.tap(deactivate);
    await tester.pumpAndSettle();
    expect(find.text('Deactivate account?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All statuses'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Inactive'));
    await tester.pumpAndSettle();
    expect(find.text('Enabled Worker'), findsNothing);
    expect(find.text('Disabled Worker'), findsOneWidget);
    expect(deactivate, findsNothing);
  });

  testWidgets(
    'Flutter Web keeps admin sign-in, facility hierarchy and sign-out on the admin route',
    (tester) async {
      await _enterAdmin(tester, AccountRole.administrator);
      expect(find.text('Worker accounts'), findsOneWidget);
      expect(
        find.widgetWithText(AdminCommandButton, 'Create worker'),
        findsOneWidget,
      );
      final accountsTable = tester.widget<DataTable>(find.byType(DataTable));
      expect(accountsTable.headingRowColor?.resolve({}), Colors.black);
      expect(accountsTable.headingTextStyle?.color, Colors.white);
      final accountsCard = tester.widget<Card>(
        find.ancestor(of: find.byType(DataTable), matching: find.byType(Card)),
      );
      expect(accountsCard.elevation, greaterThan(1));
      expect(tester.getSize(find.byType(Scaffold)).width, 1440);
      final route = ModalRoute.of(tester.element(find.text('Worker accounts')));
      expect(route?.settings.name, '/admin');
      await tester.tap(find.text('Create worker'));
      await tester.pumpAndSettle();
      final dialogContext = tester.element(find.byType(AlertDialog));
      expect(DialogTheme.of(dialogContext).elevation, 28);
      expect(
        DialogTheme.of(dialogContext).shadowColor,
        const Color(0xA6142234),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Sample Worker');
      await tester.enterText(fields.at(1), 'SAMPLE-1');
      await tester.enterText(fields.at(3), 'sample@uni360.example');
      await tester.enterText(fields.at(4), 'Example-Admin-Test');
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Sample Worker'), findsOneWidget);
      expect(find.text('SW'), findsOneWidget);
      expect(
        tester.getCenter(find.text('SW')).dx,
        lessThan(tester.getCenter(find.text('Sample Worker')).dx),
      );
      await tester.tap(find.text('Facilities').first);
      await tester.pumpAndSettle();
      final facilitiesTable = tester.widget<DataTable>(find.byType(DataTable));
      expect(facilitiesTable.headingRowColor?.resolve({}), Colors.black);
      expect(facilitiesTable.headingTextStyle?.color, Colors.white);
      expect(find.text('Zone'), findsNothing);
      expect(find.text('Other locations'), findsNothing);
      expect(find.text('View'), findsNothing);
      expect(find.text('Block D ›'), findsOneWidget);
      expect(find.text('Female Toilet'), findsNothing);
      expect(find.byType(AdminStatusBadge), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.block_outlined), findsOneWidget);
      final schedules = find.widgetWithText(AdminCommandButton, 'Schedules');
      expect(
        tester.widget<AdminCommandButton>(schedules).icon,
        Icons.calendar_month_outlined,
      );
      await tester.ensureVisible(schedules);
      await tester.tap(schedules);
      await tester.pumpAndSettle();
      expect(find.text('Block D schedules'), findsOneWidget);
      await tester.tap(find.text('Facilities').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block D ›'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(AdminCommandButton, 'Schedules for this location'),
        findsOneWidget,
      );
      expect(find.text('Level 1 ›'), findsOneWidget);
      expect(find.text('Female Toilet ›'), findsNothing);
      await tester.tap(find.text('Level 1 ›'));
      await tester.pumpAndSettle();
      expect(find.text('Female Toilet ›'), findsOneWidget);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Administrator sign-in'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Admin login'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Admin creates and opens each level of the facility hierarchy', (
    tester,
  ) async {
    final admin = _TestAdministration();
    await _enterAdmin(tester, AccountRole.superAdministrator, data: admin);
    await tester.tap(find.text('Facilities').first);
    await tester.pumpAndSettle();

    final typeInput = find.byKey(const ValueKey('facility_type_label'));
    for (final (label, name, type, customType, parentId, emptyMessage, icon)
        in [
          (
            'Create facility',
            'Test Arena',
            'building',
            'Sports complex',
            null,
            null,
            null,
          ),
          (
            'Add level',
            'Ground Floor',
            'floor',
            'Concourse',
            'new-0',
            'No levels added yet.',
            Icons.layers_outlined,
          ),
          (
            'Add room',
            'T001',
            'room',
            'Lecture room',
            'new-1',
            'No rooms added yet.',
            Icons.meeting_room_outlined,
          ),
          (
            'Add property',
            'Air-conditioning',
            'asset',
            'Split unit',
            'new-2',
            'No properties added yet.',
            Icons.inventory_2_outlined,
          ),
        ]) {
      if (emptyMessage != null) {
        final emptyState = tester.widget<AdminIllustratedEmptyState>(
          find.widgetWithText(AdminIllustratedEmptyState, emptyMessage),
        );
        expect(emptyState.asset, 'assets/facilities/empty-locations.png');
      }
      final addButton = find.widgetWithText(AdminCommandButton, label);
      expect(tester.widget<AdminCommandButton>(addButton).icon, icon);
      await tester.tap(addButton);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('name')), name);
      await tester.enterText(typeInput, customType);
      await tester.tap(find.widgetWithText(FilledButton, label).last);
      await tester.pumpAndSettle();
      expect(admin.createdFacilities.last['facility_type'], type);
      expect(admin.createdFacilities.last['parent_id'], parentId);
      expect(
        admin.createdFacilities.last['metadata']['facility_type_label'],
        customType,
      );
      expect(find.text(customType), findsOneWidget);
      expect(find.text('$name ›'), findsOneWidget);
      expect(find.byType(AdminIllustratedEmptyState), findsNothing);
      await tester.tap(find.text('$name ›'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Room property'), findsOneWidget);
    expect(find.text('Split unit'), findsOneWidget);
    expect(find.text('Add property'), findsNothing);
    expect(find.text('/ T001'), findsOneWidget);
    expect(find.byType(AdminStatusBadge), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.block_outlined), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.text('Room property')))?.settings.name,
      'new-3',
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(typeInput).initialValue, 'Split unit');
    await tester.enterText(typeInput, 'Inverter unit');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Inverter unit'), findsOneWidget);
    await tester.tap(find.text('/ T001'));
    await tester.pumpAndSettle();
    expect(find.text('Air-conditioning ›'), findsOneWidget);
    expect(find.text('Room property'), findsNothing);
    expect(
      ModalRoute.of(tester.element(find.text('Add property')))?.settings.name,
      'new-2',
    );
  });

  testWidgets('Scheduling and approvals start at the top of the dashboard', (
    tester,
  ) async {
    await _enterAdmin(tester, AccountRole.administrator);
    await tester.tap(find.text('Facilities').first);
    await tester.pumpAndSettle();
    final top = tester.getTopLeft(find.text('Facilities').last).dy;
    await tester.tap(find.text('Schedule Task'));
    await tester.pumpAndSettle();
    expect(find.text('Zone'), findsNothing);
    expect(
      tester.getTopLeft(find.byType(AdminTaskTemplates)).dy,
      closeTo(top, 1),
    );
    final statuses = tester.widgetList<AdminStatusBadge>(
      find.byType(AdminStatusBadge),
    );
    expect(statuses.map((badge) => badge.active), [true, false]);
    expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));
    final view = find.widgetWithText(AdminCommandButton, 'View');
    expect(view, findsNWidgets(2));
    expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(2));
    await tester.ensureVisible(view.first);
    await tester.tap(view.first);
    await tester.pumpAndSettle();
    expect(find.text('Clean the fixtures.'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    final deactivate = find.widgetWithText(AdminCommandButton, 'Deactivate');
    expect(
      find.descendant(
        of: deactivate,
        matching: find.byIcon(Icons.block_outlined),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(deactivate);
    await tester.tap(deactivate);
    await tester.pumpAndSettle();
    expect(find.text('Deactivate task template?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    final schedule = find.widgetWithText(AdminCommandButton, 'Schedule');
    expect(
      tester.widget<AdminCommandButton>(schedule).icon,
      Icons.event_available_outlined,
    );
    await tester.ensureVisible(schedule);
    await tester.tap(schedule);
    await tester.pumpAndSettle();
    expect(find.byType(AdminRangeSchedule), findsOneWidget);
    await tester.tap(find.text('Task approvals'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(AdminApprovals)).dy, closeTo(top, 1));
    final review = find.widgetWithText(AdminCommandButton, 'Review');
    expect(
      tester.widget<AdminCommandButton>(review).icon,
      Icons.fact_check_outlined,
    );
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.pumpAndSettle();
    expect(find.text('Clean the fixtures.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Empty admin lists display the task illustration and a message', (
    tester,
  ) async {
    await _enterAdmin(
      tester,
      AccountRole.administrator,
      data: _TestAdministration(emptyLists: true),
    );
    for (final (page, message) in const [
      ('Schedule Task', 'No task templates yet.'),
      ('Task approvals', 'No tasks are awaiting approval.'),
      ('Leave requests', 'No pending leave requests.'),
      ('Overdue tasks', 'No overdue tasks.'),
    ]) {
      await tester.tap(find.text(page));
      await tester.pumpAndSettle();
      final emptyState = tester.widget<AdminIllustratedEmptyState>(
        find.widgetWithText(AdminIllustratedEmptyState, message),
      );
      expect(emptyState.asset, 'assets/tasks/empty-tasks.png');
      expect(tester.widget<DataTable>(find.byType(DataTable)).rows, isEmpty);
    }
  });

  testWidgets('Flutter Web admin login rejects worker accounts', (
    tester,
  ) async {
    await _enterAdmin(tester, AccountRole.worker);
    expect(
      find.text('Use an Administrator or Super Administrator account.'),
      findsOneWidget,
    );
    expect(find.text('Worker accounts'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Schedule opens the location and time form inline', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminRangeSchedule(
              data: _TestAdministration(),
              template: const {
                'id': 'cleaning',
                'title': 'Toilet Cleaning',
                'category': 'Toilet Cleaning',
                'duration_minutes': 90,
              },
              back: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose locations and times'), findsNothing);
    expect(find.text('Toilets to clean'), findsOneWidget);
    expect(find.text('Block D / Level 1 / Female Toilet'), findsOneWidget);
    expect(find.text('Block D / Level 1'), findsNothing);
    expect(find.text('Auto Schedule'), findsOneWidget);
    await tester.ensureVisible(find.text('Auto Schedule'));
    await tester.tap(find.text('Auto Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Select at least one location.'), findsOneWidget);
  });

  testWidgets('Review selects a task, date and assigned worker', (
    tester,
  ) async {
    final data = _TestAdministration();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminScheduleReview(data: data, back: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsNothing);
    expect(find.text('Zone'), findsNothing);
    await tester.tap(find.text('Toilet Cleaning'));
    await tester.pumpAndSettle();
    final picker = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    final today = adminToday();
    final day = DateTime(today.year, today.month, today.day - 1);
    picker.onDateChanged(day);
    await tester.pumpAndSettle();
    expect(data.reviewDay, day);
    expect(find.text('Block D'), findsOneWidget);
    expect(find.text('11:00–12:30'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    final field = find.byType(TextField);
    await tester.ensureVisible(field);
    await tester.enterText(field, 'HIDAYAH');
    await tester.pumpAndSettle();
    expect(find.text('Nur Hidayah · EMP-CLEAN-11'), findsOneWidget);
    await tester.enterText(field, 'Faiz');
    await tester.pumpAndSettle();
    expect(find.text('No assignments match that worker name.'), findsOneWidget);
    expect(find.text('Nur Hidayah · EMP-CLEAN-11'), findsNothing);
  });
}
