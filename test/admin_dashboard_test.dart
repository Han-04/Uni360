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

class _UnusedSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestAdministration extends AdminData {
  _TestAdministration() : super(_UnusedSupabaseClient());

  final saved = <AdminRow>[];
  final createdFacilities = <AdminRow>[];

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
  Future<int> overdueCount() async => 1;

  @override
  Future<List<AdminRow>> overdueOrders(int page) async => [
    for (final row in await scheduledTasksOn(
      'Toilet Cleaning',
      adminToday().subtract(const Duration(days: 1)),
    ))
      {...row, 'title': 'Toilet Cleaning'},
  ];

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
  Future<U> then<U>(FutureOr<U> Function(T) onValue, {Function? onError}) =>
      Future.value(result).then(onValue, onError: onError);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      switch (invocation.memberName) {
        #eq || #gte || #gt || #lt || #isFilter || #order || #range => this,
        _ => super.noSuchMethod(invocation),
      };
}

Future<void> enterAdmin(
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
    await enterAdmin(
      tester,
      AccountRole.administrator,
      data: _WorkforceProfileFixture(),
    );
    await tester.tap(find.text('Workforce management'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open profile').first);
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
      expect(
        style?.backgroundColor?.resolve({WidgetState.hovered}),
        Colors.black,
      );
      expect(
        style?.foregroundColor?.resolve({WidgetState.hovered}),
        Colors.white,
      );
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
    await enterAdmin(tester, AccountRole.administrator);
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
    await enterAdmin(tester, AccountRole.administrator);
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
    await enterAdmin(tester, AccountRole.administrator, data: data);
    expect(find.text('Enabled Worker'), findsOneWidget);
    expect(find.text('Disabled Worker'), findsOneWidget);
    await tester.tap(find.text('All statuses'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Inactive'));
    await tester.pumpAndSettle();
    expect(find.text('Enabled Worker'), findsNothing);
    expect(find.text('Disabled Worker'), findsOneWidget);
  });

  testWidgets(
    'Flutter Web keeps admin sign-in, facility hierarchy and sign-out on the admin route',
    (tester) async {
      await enterAdmin(tester, AccountRole.administrator);
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
      await tester.tap(find.text('Block D ›'));
      await tester.pumpAndSettle();
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
    await enterAdmin(tester, AccountRole.superAdministrator, data: admin);
    await tester.tap(find.text('Facilities').first);
    await tester.pumpAndSettle();

    final typeInput = find.byKey(const ValueKey('facility_type_label'));
    for (final (label, name, type, customType, parentId) in [
      ('Create facility', 'Test Arena', 'building', 'Sports complex', null),
      ('Add level', 'Ground Floor', 'floor', 'Concourse', 'new-0'),
      ('Add room', 'T001', 'room', 'Lecture room', 'new-1'),
      ('Add property', 'Air-conditioning', 'asset', 'Split unit', 'new-2'),
    ]) {
      await tester.tap(find.widgetWithText(FilledButton, label));
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
      await tester.tap(find.text('$name ›'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Room property'), findsOneWidget);
    expect(find.text('Split unit'), findsOneWidget);
    expect(find.text('Add property'), findsNothing);
    expect(find.text('/ T001'), findsOneWidget);
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
    await enterAdmin(tester, AccountRole.administrator);
    await tester.tap(find.text('Facilities').first);
    await tester.pumpAndSettle();
    final top = tester.getTopLeft(find.text('Facilities').last).dy;
    await tester.tap(find.text('Schedule Task'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byType(AdminTaskTemplates)).dy,
      closeTo(top, 1),
    );
    await tester.tap(find.text('Task approvals'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(AdminApprovals)).dy, closeTo(top, 1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Flutter Web admin login rejects worker accounts', (
    tester,
  ) async {
    await enterAdmin(tester, AccountRole.worker);
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
