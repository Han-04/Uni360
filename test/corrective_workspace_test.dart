import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uni360/app/uni360_app.dart';
import 'package:uni360/core/theme/app_theme.dart';
import 'package:uni360/core/widgets/phone_viewport.dart';
import 'package:uni360/features/corrective/corrective_admin.dart';
import 'package:uni360/features/corrective/corrective_analytics.dart';
import 'package:uni360/features/corrective/corrective_case_pdf.dart';
import 'package:uni360/features/corrective/corrective_photo_diagnostics.dart';
import 'package:uni360/features/corrective/corrective_repository.dart';
import 'package:uni360/features/corrective/corrective_widgets.dart';
import 'package:uni360/features/corrective/incident_report_screen.dart';
import 'package:uni360/features/preventive/admin/admin_dashboard.dart';
import 'package:uni360/features/preventive/admin/admin_data.dart';
import 'package:uni360/shared/account/account.dart';
import 'package:uni360/shared/account/presentation/account_profile_screen.dart';

import 'support/test_accounts.dart';

class _CorrectiveFixture extends CorrectiveRepository {
  _CorrectiveFixture(
    this.actor, {
    required this.status,
    this.ownsReport = false,
    this.savedPhoto,
  }) : super(
         SupabaseClient(
           'https://example.invalid',
           'test-key',
           authOptions: const AuthClientOptions(autoRefreshToken: false),
         ),
       );

  final String actor;
  final bool ownsReport;
  final String? savedPhoto;
  final photoPreviews = <String>[];
  final extraIncidents = <CorrectiveIncident>[];
  List<CorrectiveRow> extraFacilities = const [];
  CorrectiveRow? configuredSite;
  String status;
  bool withdrawn = false;
  final actions = <String>[];
  final updates = <CorrectiveRow>[];
  static const id = 'test-incident';

  CorrectiveIncident get incident => CorrectiveIncident({
    'id': id,
    'reference': 1,
    'facility_id': 'facility',
    'title': 'Burst pipe',
    'facility_name': 'Campus / Library',
    'location_detail': 'First floor',
    'category': 'Plumbing',
    'urgency': 'Critical',
    'status': status,
    'reporter_name': 'Campus staff',
    'reporter_id': ownsReport ? actor : 'reporter',
    if (withdrawn) 'withdrawn_at': '2026-11-12T04:10:00Z',
    'worker_name': 'Test Account',
    'worker_id': actor,
    'description': 'Water is pooling around the sink.',
    'report_photo': savedPhoto,
    'created_at': '2026-11-12T04:00:00Z',
    'attempt': 1,
    'checklist': ['Confirm the repair'],
  });

  @override
  Future<int> unreadNotifications() async => 0;

  @override
  Future<List<CorrectiveRow>> categories() async => [
    {'name': 'Plumbing', 'team': 'Plumbing', 'active': true},
  ];

  @override
  Future<List<CorrectiveRow>> notifications() async => updates;

  @override
  Future<List<CorrectiveIncident>> list(
    String actor, {
    bool admin = false,
  }) async => [incident, ...extraIncidents];

  @override
  Future<CorrectiveRow?> site(String id) async => null;

  @override
  Future<CorrectiveRow> saveSite(String id, CorrectiveRow payload) async {
    expect(id, 'facility');
    return configuredSite = {...payload, 'qr_token': 'test-token'};
  }

  @override
  Future<CorrectiveDetail> detail(String id) async =>
      CorrectiveDetail(incident, [], [], []);

  @override
  String get actorId => actor;

  @override
  Future<String> photoUrl(String path) async {
    photoPreviews.add(path);
    throw const CorrectiveException(
      'Image network is unavailable in this test',
    );
  }

  @override
  Future<CorrectiveRow> adminOptions(String id) async => {
    'candidates': [],
    'preventive': [],
    'triage': {'category': 'Plumbing', 'confidence': 87, 'priority': 'High'},
  };

  @override
  Future<CorrectiveRow> catalog() async => {
    'facilities': [
      ...extraFacilities,
      {
        'id': 'facility',
        'label': 'Library',
        'zone': 'Campus',
        'can_manage': true,
      },
    ],
    'categories': [
      {'name': 'Plumbing', 'team': 'Plumbing'},
    ],
  };

  @override
  RealtimeChannel watch(
    String listener,
    void Function() onChange, {
    String? incidentId,
  }) => client.channel(listener);

  @override
  Future<void> unwatch(RealtimeChannel channel) async {}

  @override
  Future<void> reporterAction(
    String id,
    String command,
    CorrectiveRow payload,
  ) async {
    actions.add(command);
    if (command == 'withdraw') {
      status = 'dismissed';
      withdrawn = true;
    }
  }

  @override
  Future<void> action(
    String id,
    String command, {
    bool admin = false,
    CorrectiveRow payload = const {},
  }) async {
    actions.add(command);
    if (command == 'acknowledge') status = 'acknowledged';
    if (command == 'start') status = 'in_progress';
    if (command == 'review_approve') {
      expect(admin, isTrue);
      expect(payload['category'], 'Plumbing');
      expect(payload['urgency'], 'High');
      status = 'approved';
    }
    if (command == 'approve') {
      expect(admin, isTrue);
      expect(payload['note'], 'Repair verified on site.');
      status = 'resolved';
    }
  }
}

class _AdminFixture extends AdminData {
  _AdminFixture(super.client);

  @override
  Future<AdminRow> accounts(String action, AdminRow values) async => {
    'rows': <AdminRow>[],
    'hasNext': false,
  };
}

Future<void> _signIn(
  WidgetTester tester,
  TestAccounts accounts,
  _CorrectiveFixture corrective, {
  double width = 390,
  AdminData? administration,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    Uni360App(
      accounts: accounts,
      loadAssignedWork: (_, _) async => [],
      corrective: corrective,
      administration: administration,
    ),
  );
  expect(find.text('Welcome to Uni360'), findsOneWidget);
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).first, TestAccounts.email);
  await tester.enterText(
    find.byType(TextFormField).last,
    TestAccounts.password,
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
}

Future<void> _openAdminQueue(
  WidgetTester tester,
  _CorrectiveFixture repository,
) async {
  tester.view.physicalSize = const Size(790, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: CorrectiveAdmin(
          repository: repository,
          administratorId: repository.actor,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.4);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Photo analysis detects underexposed evidence', (tester) async {
    final result = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawColor(const Color(0xff050505), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final photo = await picture.toImage(18, 16);
      final png = await photo.toByteData(format: ui.ImageByteFormat.png);
      photo.dispose();
      picture.dispose();
      return inspectCorrectivePhoto(png!.buffer.asUint8List());
    });
    expect(result, {'quality': 'dark'});
  });

  test('An approved case exports a PDF document', () async {
    final repository = _CorrectiveFixture('worker', status: 'resolved');
    final bytes = await createCorrectiveCasePdf(
      await repository.detail(_CorrectiveFixture.id),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(
      String.fromCharCodes(bytes.skip(bytes.length - 20)),
      contains('%%EOF'),
    );
  });

  testWidgets(
    'Reporter opens the report workspace without technician navigation',
    (tester) async {
      final accounts = TestAccounts(role: AccountRole.reporter);
      final repository = _CorrectiveFixture(
        accounts.profile.id,
        status: 'reported',
      );
      await _signIn(tester, accounts, repository, width: 1280);
      expect(
        tester.getSize(find.byType(SafeArea).first).width,
        PhoneViewport.maxWidth,
      );
      expect(find.text('Preventive Maintenance'), findsNothing);
      await _tapVisible(tester, find.text('Corrective Maintenance'));
      final theme = Theme.of(tester.element(find.text('Reports overview')));
      expect(theme.colorScheme.primary, WorkerColors.blue);
      expect(theme.scaffoldBackgroundColor, WorkerColors.background);
      expect(find.text('My reports'), findsOneWidget);
      expect(find.byTooltip('Report an incident'), findsOneWidget);
      expect(find.text('Assigned'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Admin login opens the dedicated portal from mobile sign-in', (
    tester,
  ) async {
    final accounts = TestAccounts(role: AccountRole.administrator);
    final repository = _CorrectiveFixture(
      accounts.profile.id,
      status: 'reported',
    );
    await _signIn(
      tester,
      accounts,
      repository,
      width: 1280,
      administration: _AdminFixture(repository.client),
    );
    expect(find.text('Use Admin login on the Uni360 website.'), findsOneWidget);
    expect(find.text('Campus operations'), findsNothing);

    await _tapVisible(tester, find.text('Admin login'));
    expect(find.byType(AdminDashboard), findsOneWidget);
    expect(tester.getSize(find.byType(AdminDashboard)).width, 1280);
    expect(find.text('Administrator sign-in'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Sign in to your account'), findsOneWidget);
    expect(
      tester.getSize(find.byType(SafeArea).first).width,
      PhoneViewport.maxWidth,
    );

    await _tapVisible(tester, find.text('Admin login'));
    await tester.enterText(
      find.byType(TextFormField).first,
      TestAccounts.email,
    );
    await tester.enterText(
      find.byType(TextFormField).last,
      TestAccounts.password,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Worker accounts'), findsOneWidget);
    final dashboardFont = Theme.of(tester.element(find.text('Worker accounts')))
        .textTheme
        .bodyMedium
        ?.fontFamily;

    await _tapVisible(tester, find.widgetWithText(ListTile, 'All incidents'));
    expect(tester.getSize(find.byType(CorrectiveAdmin)).width, 1034);
    expect(find.text('Corrective Maintenance'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    final correctiveFont = Theme.of(
      tester.element(find.byType(CorrectiveAdmin)),
    ).textTheme.bodyMedium?.fontFamily;
    expect(correctiveFont, dashboardFont);
    await tester.tap(find.text('Campus / Library'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Review and approve'), findsOneWidget);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Incident history'), findsOneWidget);
    expect(find.text('Review and approve'), findsNothing);
    await tester.tap(find.text('Back to incidents'));
    await tester.pumpAndSettle();
    expect(find.text('Burst pipe'), findsOneWidget);

    await _tapVisible(tester, find.widgetWithText(ListTile, 'Assign work'));
    expect(find.textContaining('No repairs need assignment'), findsOneWidget);
    expect(find.text('Burst pipe'), findsNothing);
    await _tapVisible(tester, find.widgetWithText(ListTile, 'Review reports'));
    expect(find.text('Burst pipe'), findsOneWidget);
    await _tapVisible(tester, find.widgetWithText(ListTile, 'Analytics'));
    expect(find.text('Corrective analytics'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    await _tapVisible(tester, find.widgetWithText(ListTile, 'Settings'));
    expect(find.text('Facility check-in settings'), findsOneWidget);
    expect(find.text('Maintenance categories'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    repository.extraFacilities = [
      for (var i = 0; i < 2000; i++)
        {'id': 'room-$i', 'label': 'Block A / Room $i', 'can_manage': true},
      {
        'id': 'restricted',
        'label': 'Library restricted store',
        'can_manage': false,
      },
    ];
    await tester.tap(find.text('Facility check-in settings'));
    await tester.pumpAndSettle();
    expect(find.text('Block A / Room 0'), findsNothing);
    final facilitySearch = find.widgetWithText(
      TextField,
      'Search for a facility',
    );
    await tester.enterText(facilitySearch, 'library');
    await tester.pumpAndSettle();
    expect(find.text('Library restricted store'), findsNothing);
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.text('Use current location'), findsOneWidget);
    expect(find.text('Latitude'), findsNothing);
    final pinField = find.widgetWithText(TextFormField, 'Paste a map pin');
    await tester.enterText(pinField, '91, 101.728');
    await tester.tap(find.text('Save site'));
    await tester.pumpAndSettle();
    expect(repository.configuredSite, isNull);
    await tester.enterText(pinField, '3.215, 101.728');
    await tester.tap(find.text('Save site'));
    await tester.pumpAndSettle();
    expect(repository.configuredSite?['latitude'], 3.215);
    expect(repository.configuredSite?['longitude'], 101.728);
    expect(repository.configuredSite?['radius_m'], 60);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.widgetWithText(ListTile, 'All incidents'));
    await tester.tap(find.text('Report an incident'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.byType(IncidentReportScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Back to incidents'));
    await tester.pumpAndSettle();
    expect(find.text('Burst pipe'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 500));
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.widgetWithText(ListTile, 'Account management'),
    );
    expect(find.text('Worker accounts'), findsOneWidget);
  });

  testWidgets('The admin incident list defaults to every status', (
    tester,
  ) async {
    final repository = _CorrectiveFixture('admin', status: 'reported');
    repository.extraIncidents.addAll([
      CorrectiveIncident({
        ...repository.incident.data,
        'id': 'archived-case',
        'title': 'Archived repair',
        'status': 'resolved',
        'archived_at': '2026-11-13T04:00:00Z',
      }),
      CorrectiveIncident({
        ...repository.incident.data,
        'id': 'withdrawn-case',
        'title': 'Withdrawn repair',
        'status': 'dismissed',
        'withdrawn_at': '2026-11-13T04:00:00Z',
      }),
    ]);
    await _openAdminQueue(tester, repository);
    expect(find.text('All statuses'), findsOneWidget);
    expect(find.text('Burst pipe'), findsOneWidget);
    expect(find.text('Archived repair'), findsOneWidget);
    expect(find.text('Withdrawn repair'), findsOneWidget);
    await tester.tap(find.text('All statuses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Active incidents'));
    await tester.pumpAndSettle();
    expect(find.text('Burst pipe'), findsOneWidget);
    expect(find.text('Archived repair'), findsNothing);
    expect(find.text('Withdrawn repair'), findsNothing);
  });

  testWidgets('Admin filters open a compact report date dialog', (
    tester,
  ) async {
    final repository = _CorrectiveFixture('admin', status: 'reported');
    repository.extraIncidents.add(
      CorrectiveIncident({
        ...repository.incident.data,
        'id': 'medium-case',
        'title': 'Leaking tap',
        'urgency': 'Medium',
      }),
    );
    await _openAdminQueue(tester, repository);
    expect(find.text('All priorities'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Filters'));
    await tester.pumpAndSettle();
    expect(find.text('All priorities'), findsOneWidget);
    await tester.tap(find.text('Select report dates'));
    await tester.pumpAndSettle();
    final dateDialog = find.descendant(
      of: find.byType(DateRangePickerDialog),
      matching: find.byType(Dialog),
    );
    final size = tester.getSize(dateDialog);
    expect(size.width, lessThanOrEqualTo(488));
    expect(size.height, lessThanOrEqualTo(580));
    expect(find.text('Apply dates'), findsOneWidget);
    final today = find
        .descendant(
          of: dateDialog,
          matching: find.text(DateTime.now().day.toString()),
        )
        .hitTestable()
        .first;
    await tester.tap(today);
    await tester.pumpAndSettle();
    await tester.tap(today);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply dates'));
    await tester.pumpAndSettle();
    expect(dateDialog, findsNothing);
    expect(find.text('Filters (1)'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All priorities'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Medium').last);
    await tester.pumpAndSettle();
    expect(find.text('Filters (1)'), findsOneWidget);
    expect(find.text('Leaking tap'), findsOneWidget);
    expect(find.text('Burst pipe'), findsNothing);
    final mediumBadge = find.widgetWithText(CorrectiveBadge, 'Medium');
    expect(
      tester.widget<CorrectiveBadge>(mediumBadge).foreground,
      const Color(0xFFAD4400),
    );
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('All priorities'), findsOneWidget);
    expect(find.text('Burst pipe'), findsOneWidget);
  });

  testWidgets('Analytics can exclude demo incidents', (tester) async {
    final repository = _CorrectiveFixture('admin', status: 'reported');
    final demo = CorrectiveIncident({
      ...repository.incident.data,
      'title': '[Demo] Broken chair',
      'triage': {'demo_seed': 'test'},
      'created_at': '2026-10-31T16:15:00Z',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CorrectiveAnalyticsScreen([demo], onRefresh: () {}),
        ),
      ),
    );
    expect(find.text('1 demo report included'), findsOneWidget);
    expect(find.text('Reports by month'), findsOneWidget);
    expect(find.byTooltip('November 2026: 1 report'), findsOneWidget);
    expect(find.byTooltip('October 2026: 0 reports'), findsOneWidget);
    expect(
      find.text(
        'No reports are available for the selected period and filters.',
      ),
      findsNothing,
    );
    await tester.tap(find.text('Include demo reports'));
    await tester.pumpAndSettle();
    expect(find.text('1 demo report included'), findsNothing);
    expect(find.text('Reports by month'), findsNothing);
    expect(
      find.text(
        'No reports are available for the selected period and filters.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Intake displays triage and requires approval before dispatch', (
    tester,
  ) async {
    final accounts = TestAccounts(role: AccountRole.administrator);
    final repository = _CorrectiveFixture(
      accounts.profile.id,
      status: 'reported',
    );
    await _openAdminQueue(tester, repository);
    await _tapVisible(tester, find.text('Burst pipe'));
    expect(find.textContaining('87%'), findsOneWidget);
    expect(find.text('Assign approved work'), findsNothing);
    await _tapVisible(tester, find.text('Review and approve'));
    await tester.tap(find.text('Approve report'));
    await tester.pumpAndSettle();
    expect(repository.actions, ['review_approve']);
    expect(find.text('Assign approved work'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Only the reporter can open the edit form with saved evidence', (
    tester,
  ) async {
    const path = 'report/current.jpg';
    final owner = _CorrectiveFixture(
      'reporter',
      status: 'reported',
      ownsReport: true,
      savedPhoto: path,
    );
    await tester.pumpWidget(
      MaterialApp(home: IncidentReportScreen(owner, pending: owner.incident)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Current attachment'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Current attachment'), findsOneWidget);
    expect(owner.photoPreviews, [path]);
    expect(find.byType(CheckboxListTile), findsNothing);

    final administrator = _CorrectiveFixture('admin', status: 'reported');
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('other-session'),
        home: IncidentReportScreen(
          administrator,
          pending: owner.incident,
          administrator: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining('Only the original reporter'), findsOneWidget);
    expect(administrator.photoPreviews, isEmpty);
  });

  testWidgets('Incident details show the description and photo finding', (
    tester,
  ) async {
    final repository = _CorrectiveFixture('reporter', status: 'reported');
    final incident = CorrectiveIncident({
      ...repository.incident.data,
      'triage': {
        'vision_status': 'vision_fault',
        'observation': 'Possible visible leak from sink plumbing.',
        'photo_category': 'Plumbing',
        'photo_priority': 'Medium',
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: IncidentSummary(incident, repository),
          ),
        ),
      ),
    );
    expect(find.text('Water is pooling around the sink.'), findsOneWidget);
    expect(
      find.text('Possible visible leak from sink plumbing.'),
      findsOneWidget,
    );
    expect(find.text('Photo priority · Medium'), findsOneWidget);
  });

  test(
    'Report status badges distinguish pending, withdrawn and successful cases',
    () {
      CorrectiveBadge badge(String status, {bool withdrawn = false}) =>
          CorrectiveBadge.status(
            CorrectiveIncident({
              'status': status,
              if (withdrawn) 'withdrawn_at': '2026-11-26T15:46:00Z',
            }),
          );
      expect(badge('reported').background, const Color(0xFFFFF0A7));
      expect(
        badge('dismissed', withdrawn: true).background,
        const Color(0xFFFFE6E7),
      );
      expect(badge('approved').background, const Color(0xFFD8F5E4));
      expect(badge('resolved').background, const Color(0xFFD8F5E4));
    },
  );

  testWidgets('A reporter can confirm withdrawal of a pending report', (
    tester,
  ) async {
    final accounts = TestAccounts(role: AccountRole.reporter);
    final repository = _CorrectiveFixture(
      accounts.profile.id,
      status: 'reported',
      ownsReport: true,
    );
    await _signIn(tester, accounts, repository);
    await _tapVisible(tester, find.text('Corrective Maintenance'));
    await _tapVisible(tester, find.text('Burst pipe'));
    final withdraw = find.widgetWithText(FilledButton, 'Withdraw report');
    final trigger = tester.widget<FilledButton>(withdraw);
    expect(
      Theme.of(tester.element(withdraw)).colorScheme.primary,
      WorkerColors.blue,
    );
    expect(
      trigger.style?.backgroundColor?.resolve({}),
      Theme.of(tester.element(withdraw)).colorScheme.error,
    );
    await _tapVisible(tester, find.text('Withdraw report'));
    expect(find.text('Withdraw this report?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.actions, isEmpty);
    await _tapVisible(tester, find.text('Withdraw report'));
    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();
    expect(repository.actions, ['withdraw']);
    expect(find.text('Withdrawn'), findsOneWidget);
    expect(find.text('Edit pending report'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Worker filters fit a narrow screen and reset the result list', (
    tester,
  ) async {
    final accounts = TestAccounts();
    final repository = _CorrectiveFixture(
      accounts.profile.id,
      status: 'assigned',
    );
    await _signIn(tester, accounts, repository, width: 320);
    await _tapVisible(tester, find.text('Corrective Maintenance'));
    await _tapVisible(tester, find.text('Filters'));
    await _tapVisible(tester, find.text('All priorities'));
    await tester.tap(find.text('Low').last);
    await tester.pumpAndSettle();
    expect(find.text('No incidents match these filters.'), findsOneWidget);
    expect(find.text('Burst pipe'), findsNothing);
    await _tapVisible(tester, find.text('Clear filters'));
    expect(find.text('Burst pipe'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Corrective footer switches the worker sections on a narrow phone',
    (tester) async {
      final accounts = TestAccounts();
      final repository =
          _CorrectiveFixture(
              accounts.profile.id,
              status: 'assigned',
              ownsReport: true,
            )
            ..updates.add({
              'title': 'Assigned to you',
              'incident_title': 'Burst pipe',
              'created_at': '2026-11-12T04:00:00Z',
            });
      await _signIn(tester, accounts, repository, width: 320);
      await _tapVisible(tester, find.text('Corrective Maintenance'));
      final footer = find.byKey(const ValueKey('corrective-footer'));
      final footerTop = tester.getTopLeft(footer).dy;
      final addIncident = find.byTooltip('Report an incident');
      expect(tester.getCenter(addIncident).dx, tester.getCenter(footer).dx);
      expect(
        tester.getBottomLeft(find.byType(ListView)).dy,
        lessThanOrEqualTo(footerTop),
      );
      expect(find.text('Assigned incidents'), findsOneWidget);

      await tester.tap(find.text('My reports'));
      await tester.pumpAndSettle();
      expect(find.text('Report history'), findsOneWidget);
      expect(find.byTooltip('Report an incident'), findsOneWidget);

      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();
      expect(find.text('Assigned to you'), findsOneWidget);
      expect(find.text('Report history'), findsNothing);
      expect(tester.getTopLeft(footer).dy, footerTop);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountProfileScreen), findsOneWidget);
      expect(find.text('My profile'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit profile'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Updated Worker',
      );
      await _tapVisible(tester, find.text('Update Profile'));
      expect(find.text('Updated Worker'), findsOneWidget);

      await tester.tap(addIncident);
      await tester.pumpAndSettle();
      expect(find.text('Report an incident'), findsOneWidget);
      expect(find.text('Reported priority'), findsNothing);
      await _tapVisible(tester, find.text('Add photo or video'));
      expect(find.text('Choose a photo'), findsOneWidget);
      expect(find.text('Choose a video'), findsOneWidget);
      expect(find.textContaining('Up to 30 seconds'), findsWidgets);
      await tester.tapAt(const Offset(20, 100));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Assigned'));
      await tester.pumpAndSettle();
      expect(find.text('Assigned incidents'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('Preventive Maintenance'));
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Updated Worker'), findsOneWidget);
    },
  );

  testWidgets(
    'Worker switches maintenance modules and starts a verified repair',
    (tester) async {
      final accounts = TestAccounts();
      final repository = _CorrectiveFixture(
        accounts.profile.id,
        status: 'assigned',
      );
      await _signIn(tester, accounts, repository);
      expect(find.text('Campus operations'), findsOneWidget);
      await _tapVisible(tester, find.text('Preventive Maintenance'));
      expect(find.textContaining('assignments'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('Corrective Maintenance'));
      await _tapVisible(tester, find.text('Burst pipe'));
      await _tapVisible(tester, find.text('Acknowledge assignment'));
      expect(repository.actions, ['acknowledge']);
      expect(find.text('Scan facility QR and check in'), findsOneWidget);
      repository.status = 'checked_in';
      await tester.tap(find.byTooltip('Refresh incident'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('Start work timer'));
      expect(repository.actions, ['acknowledge', 'start']);
      expect(find.text('Complete the site visit'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Administrator approves submitted corrective work with review remarks',
    (tester) async {
      final accounts = TestAccounts(role: AccountRole.administrator);
      final repository = _CorrectiveFixture(
        accounts.profile.id,
        status: 'submitted',
      );
      await _openAdminQueue(tester, repository);
      expect(find.text('All incidents'), findsOneWidget);
      await _tapVisible(tester, find.text('Burst pipe'));
      await _tapVisible(tester, find.text('Approve and resolve'));
      await tester.enterText(
        find.byType(TextFormField).last,
        'Repair verified on site.',
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(repository.actions, ['approve']);
      expect(find.text('Resolved'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
