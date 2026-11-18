import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uni360/app/uni360_app.dart';
import 'package:uni360/core/theme/app_theme.dart';
import 'package:uni360/core/widgets/phone_viewport.dart';
import 'package:uni360/features/corrective/corrective_admin.dart';
import 'package:uni360/features/corrective/corrective_case_pdf.dart';
import 'package:uni360/features/corrective/corrective_photo_diagnostics.dart';
import 'package:uni360/features/corrective/corrective_repository.dart';
import 'package:uni360/shared/account/account.dart';
import 'package:uni360/shared/account/presentation/admin_portal_view.dart';

import 'support/test_accounts.dart';

class _CorrectiveFixture extends CorrectiveRepository {
  _CorrectiveFixture(
    this.actor, {
    required this.status,
    this.ownsReport = false,
  }) : super(
         SupabaseClient(
           'https://example.invalid',
           'test-key',
           authOptions: const AuthClientOptions(autoRefreshToken: false),
         ),
       );

  final String actor;
  final bool ownsReport;
  String status;
  bool withdrawn = false;
  final actions = <String>[];
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
    'created_at': '2026-11-12T04:00:00Z',
    'attempt': 1,
    'checklist': ['Confirm the repair'],
  });

  @override
  Future<int> unreadNotifications() async => 0;

  @override
  Future<List<CorrectiveIncident>> list(
    String actor, {
    bool admin = false,
  }) async => [incident];

  @override
  Future<CorrectiveDetail> detail(String id) async =>
      CorrectiveDetail(incident, [], [], []);

  @override
  Future<CorrectiveRow> adminOptions(String id) async => {
    'candidates': [],
    'preventive': [],
    'triage': {'category': 'Plumbing', 'confidence': 87, 'priority': 'High'},
  };

  @override
  Future<CorrectiveRow> catalog() async => {
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

Future<void> _signIn(
  WidgetTester tester,
  TestAccounts accounts,
  _CorrectiveFixture corrective, {
  double width = 390,
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
      home: CorrectiveAdmin(
        repository: repository,
        administratorId: repository.actor,
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
      expect(find.text('My reports'), findsOneWidget);
      expect(find.text('Report an incident'), findsOneWidget);
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
    await _signIn(tester, accounts, repository, width: 1280);
    expect(find.text('Use Admin login on the Uni360 website.'), findsOneWidget);
    expect(find.text('Campus operations'), findsNothing);

    await _tapVisible(tester, find.text('Admin login'));
    expect(find.byType(AdminPortalView), findsOneWidget);
    expect(
      tester.getSize(find.byType(AdminPortalView)).width,
      kIsWeb ? 1280 : PhoneViewport.maxWidth,
    );
    expect(find.text('Uni360 Administration'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Sign in to your account'), findsOneWidget);
    expect(
      tester.getSize(find.byType(SafeArea).first).width,
      PhoneViewport.maxWidth,
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
    await _tapVisible(tester, find.text('Filter by priority and status'));
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
      expect(find.text('Incident command centre'), findsOneWidget);
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
