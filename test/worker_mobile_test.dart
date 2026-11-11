import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni360/app/uni360_app.dart';
import 'package:uni360/core/theme/app_theme.dart';
import 'package:uni360/features/preventive/application/preventive_controller.dart';
import 'package:uni360/features/preventive/data/assigned_work_repository.dart';
import 'package:uni360/features/preventive/data/mock_preventive_repository.dart';
import 'package:uni360/features/preventive/data/mock_verification_service.dart';
import 'package:uni360/features/preventive/presentation/screens/assigned_work_details.dart';
import 'package:uni360/features/preventive/presentation/screens/worker_shell.dart';
import 'package:uni360/shared/account/account.dart';
import 'package:uni360/shared/account/account_controller.dart';

import 'support/test_accounts.dart';

Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(target), alignment: .3);
  await tester.pumpAndSettle();
}

Future<List<AssignedWork>> noWork(String worker, DateTime? date) async => [];

AssignedWork cleaningOn(DateTime date) => AssignedWork(
  id: 'approved-work-order',
  title: 'Approved toilet cleaning',
  instructions: 'Clean the assigned washroom.',
  starts: DateTime(date.year, date.month, date.day, 11),
  ends: DateTime(date.year, date.month, date.day, 12, 30),
  locations: const ['Block D / Level 1 / Female Toilet'],
  checklist: const ['Clean fixtures'],
);

class TestWorkActions implements AssignedWorkActions {
  final initial = cleaningOn(DateTime(2026, 11, 16));
  AssignedWorkStatus status = AssignedWorkStatus.assigned;
  final checkedItems = <int>{};
  final photoPaths = <String>[];
  String notes = '';

  @override
  Future<AssignedWork> loadOrder(String workerId, String orderId) async {
    expect(workerId, 'assigned-worker');
    expect(orderId, initial.id);
    return AssignedWork(
      id: initial.id,
      title: initial.title,
      instructions: initial.instructions,
      starts: initial.starts,
      ends: initial.ends,
      locations: initial.locations,
      checklist: initial.checklist,
      status: status,
      checkedItems: Set.of(checkedItems),
      photoPaths: List.of(photoPaths),
      notes: notes,
    );
  }

  @override
  Future<void> start(String orderId) async {
    status = AssignedWorkStatus.inProgress;
  }

  @override
  Future<void> checkItem(String orderId, int index, bool checked) async {
    expect(index, 0);
    if (checked) {
      checkedItems.add(index);
    } else {
      checkedItems.remove(index);
    }
  }

  @override
  Future<void> submit(String orderId, String notes) async {
    this.notes = notes;
    status = AssignedWorkStatus.submitted;
  }

  @override
  Future<void> attachPhoto(String workerId, String orderId, Uint8List bytes) =>
      throw UnimplementedError();

  @override
  Future<String> photoUrl(String path) => throw UnimplementedError();
}

void main() {
  testWidgets('Assigned work remains editable until it is submitted', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final actions = TestWorkActions();
    await tester.pumpWidget(
      MaterialApp(
        home: AssignedWorkDetails(
          initial: actions.initial,
          workerId: 'assigned-worker',
          actions: actions,
        ),
      ),
    );
    final checklist = find.byType(CheckboxListTile);
    final submit = find.widgetWithText(FilledButton, 'Submit for approval');
    expect(tester.widget<CheckboxListTile>(checklist).onChanged, isNull);
    await tester.tap(find.text('Start task'));
    await tester.pumpAndSettle();
    expect(find.text('In progress'), findsOneWidget);
    await tester.tap(checklist);
    await tester.pumpAndSettle();
    expect(actions.checkedItems, {0});
    await reveal(tester, submit);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    actions.photoPaths.add('evidence.jpg');
    await tester.tap(find.byTooltip('Refresh work order'));
    await tester.pumpAndSettle();
    await reveal(tester, submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Awaiting approval'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(checklist).onChanged, isNull);
    expect(find.text('Upload photo'), findsNothing);
  });

  testWidgets('Live worker task list requests the signed-in worker and date', (
    tester,
  ) async {
    final accounts = TestAccounts();
    final today = malaysiaToday();
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final dates = <DateTime?>[];
    await tester.pumpWidget(
      Uni360App(
        accounts: accounts,
        loadAssignedWork: (workerId, date) async {
          expect(workerId, accounts.profile.id);
          dates.add(date);
          return date == null || date == tomorrow ? [cleaningOn(tomorrow)] : [];
        },
      ),
    );
    await signIn(tester);
    expect(find.text('No assigned tasks'), findsOneWidget);
    expect(find.text('Air-conditioning service'), findsNothing);
    await tester.tap(find.text('My tasks'));
    await tester.pumpAndSettle();
    expect(dates.last, isNull);
    expect(find.text('Approved toilet cleaning'), findsOneWidget);
    await tester.tap(find.byTooltip('Next day'));
    await tester.pumpAndSettle();
    expect(dates.last, tomorrow);
    expect(find.text('Approved toilet cleaning'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous day'));
    await tester.pumpAndSettle();
    expect(find.text('No assigned tasks'), findsOneWidget);
    await tester.tap(find.byTooltip('Show all dates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approved toilet cleaning'));
    await tester.pumpAndSettle();
    expect(find.text('Clean the assigned washroom.'), findsOneWidget);
    expect(find.text('Clean fixtures'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final role in [
    AccountRole.superAdministrator,
    AccountRole.administrator,
  ]) {
    testWidgets(
      '${role.label} signs in to their account without worker navigation',
      (tester) async {
        await tester.pumpWidget(
          Uni360App(
            accounts: TestAccounts(role: role),
            loadAssignedWork: noWork,
          ),
        );
        await signIn(tester);
        expect(find.text(role.label), findsWidgets);
        expect(find.byType(NavigationBar), findsNothing);
        await reveal(tester, find.text('Sign out'));
        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();
        expect(find.text('Sign in to your account'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('Wide displays keep every route inside a portrait phone screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      Uni360App(
        accounts: TestAccounts(),
        loadAssignedWork: (_, _) async => [cleaningOn(malaysiaToday())],
      ),
    );
    expect(tester.getSize(find.byType(Scaffold)), const Size(430, 932));
    await signIn(tester);
    expect(tester.getSize(find.byType(Scaffold)), const Size(430, 932));
    expect(tester.getSize(find.byType(NavigationBar)).width, 430);
    await tester.tap(find.text('Approved toilet cleaning'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Scaffold)), const Size(430, 932));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final width in [320.0, 390.0, 600.0]) {
    testWidgets('Worker navigation fits a $width logical-pixel screen', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        Uni360App(accounts: TestAccounts(), loadAssignedWork: noWork),
      );
      await signIn(tester);
      expect(find.text('Today’s assignments'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('My tasks'));
      await tester.pumpAndSettle();
      expect(find.text('My work orders'), findsOneWidget);
      expect(find.text('No assigned tasks'), findsOneWidget);
      await tester.tap(find.text('Alerts'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing new yet'), findsOneWidget);
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Personal details'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('Worker can check in, capture evidence and submit for review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final accounts = AccountController(TestAccounts());
    await accounts.signIn(TestAccounts.email, TestAccounts.password);
    final controller = PreventiveController(
      MockPreventiveRepository(workerId: accounts.account!.id),
      MockVerificationService(),
      accounts,
    );
    addTearDown(accounts.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: WorkerShell(controller: controller),
      ),
    );
    await reveal(tester, find.text('Air-conditioning service').first);
    await tester.tap(find.text('Air-conditioning service').first);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Verify location & check in'));
    await tester.tap(find.text('Verify location & check in'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Verify demo location'));
    await tester.tap(find.text('Verify demo location'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Simulate matching QR scan'));
    await tester.tap(find.text('Simulate matching QR scan'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Check in & start work timer'));
    await tester.tap(find.text('Check in & start work timer'));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    scrollable.position.jumpTo(0);
    await tester.pump();
    expect(find.text('In progress'), findsWidgets);
    expect(controller.orders.first.startedAt, isNotNull);
    for (final item in controller.orders.first.checklist) {
      await reveal(tester, find.text(item.label));
      await tester.tap(find.text(item.label));
      await tester.pump();
    }
    await reveal(tester, find.text('Capture evidence'));
    await tester.tap(find.text('Capture evidence'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await reveal(tester, find.text('Capture sample evidence'));
      await tester.tap(find.text('Capture sample evidence'));
      await tester.pumpAndSettle();
    }
    await reveal(tester, find.text('Done · Return to checklist'));
    await tester.tap(find.text('Done · Return to checklist'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byType(TextField));
    await tester.enterText(
      find.byType(TextField),
      'Unit serviced. Readings normal.',
    );
    await reveal(
      tester,
      find.text('I confirm all checklist items were completed correctly.'),
    );
    await tester.tap(
      find.text('I confirm all checklist items were completed correctly.'),
    );
    await tester.pump();
    await reveal(tester, find.text('Submit for review'));
    await tester.tap(find.text('Submit for review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit evidence'));
    await tester.pumpAndSettle();
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    expect(find.text('Under review'), findsOneWidget);
    expect(controller.orders.first.evidence, hasLength(2));
    expect(controller.orders.first.notes, 'Unit serviced. Readings normal.');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> signIn(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).first, TestAccounts.email);
  await tester.enterText(
    find.byType(TextFormField).last,
    TestAccounts.password,
  );
  await reveal(tester, find.text('Sign in'));
  await tester.tap(find.text('Sign in'));
  await tester.pumpAndSettle();
}
