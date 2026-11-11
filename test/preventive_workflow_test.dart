import 'package:flutter_test/flutter_test.dart';
import 'package:uni360/features/preventive/application/preventive_controller.dart';
import 'package:uni360/features/preventive/data/mock_preventive_repository.dart';
import 'package:uni360/features/preventive/data/mock_verification_service.dart';
import 'package:uni360/features/preventive/domain/verification_service.dart';
import 'package:uni360/features/preventive/domain/work_order.dart';
import 'package:uni360/shared/account/account_controller.dart';
import 'package:uni360/shared/account/account_repository.dart';

import 'support/test_accounts.dart';

void main() {
  late MockPreventiveRepository repository;
  late PreventiveController controller;
  late AccountController accounts;
  late WorkOrder order;
  setUp(() async {
    accounts = AccountController(TestAccounts());
    await accounts.signIn(TestAccounts.email, TestAccounts.password);
    repository = MockPreventiveRepository(workerId: accounts.account!.id);
    controller = PreventiveController(
      repository,
      MockVerificationService(),
      accounts,
    );
    order = controller.orders.first;
  });
  tearDown(() {
    controller.dispose();
    accounts.dispose();
  });
  test('Only the assigned worker can access work orders', () async {
    expect(repository.workOrdersFor('OTHER-WORKER'), isEmpty);
    await accounts.signOut();
    expect(controller.orders, isEmpty);
    expect(() => controller.start(order), throwsStateError);
  });
  test('Invalid credentials deny access and email is normalized', () async {
    await accounts.signOut();
    await expectLater(
      accounts.signIn(TestAccounts.email, 'wrong'),
      throwsA(isA<AccountException>()),
    );
    expect(controller.orders, isEmpty);
    await accounts.signIn(
      ' ${TestAccounts.email.toUpperCase()} ',
      TestAccounts.password,
    );
    expect(controller.signedIn, isTrue);
  });
  test('Starting work requires both geofence and matching QR', () async {
    expect(() => controller.start(order), throwsStateError);
    await expectLater(controller.verifyQr(order), throwsStateError);
    await expectLater(
      controller.verifyLocation(order, outside: true),
      throwsStateError,
    );
    expect(controller.hasLocation(order), isFalse);
    await controller.verifyLocation(order);
    expect(() => controller.start(order), throwsStateError);
    await expectLater(
      controller.verifyQr(order, mismatched: true),
      throwsStateError,
    );
    expect(controller.hasQr(order), isFalse);
    await controller.verifyQr(order);
    controller.start(order);
    expect(order.status, WorkStatus.inProgress);
    expect(order.checkedInAt, isNotNull);
    expect(order.history.last.label, 'Work started');
    expect(() => controller.start(order), throwsStateError);
  });
  test(
    'A failed location recheck invalidates earlier location and QR',
    () async {
      await controller.verifyLocation(order);
      await controller.verifyQr(order);
      await expectLater(
        controller.verifyLocation(order, outside: true),
        throwsStateError,
      );
      expect(controller.hasQr(order), isFalse);
      expect(() => controller.start(order), throwsStateError);
    },
  );
  test('Geofence rejects inaccurate GPS and readings outside the boundary', () {
    final f = order.facility;
    expect(
      isInsideGeofence(LocationReading(f.latitude, f.longitude, 8), f),
      isTrue,
    );
    expect(
      isInsideGeofence(LocationReading(f.latitude, f.longitude, 80), f),
      isFalse,
    );
    expect(
      isInsideGeofence(LocationReading(f.latitude + .01, f.longitude, 8), f),
      isFalse,
    );
  });
  test('Completion requires checklist, evidence and confirmation; submission awaits approval', () async {
    await controller.verifyLocation(order);
    await controller.verifyQr(order);
    controller.start(order);
    expect(() => controller.submit(order, '', false), throwsStateError);
    for (final item in order.checklist) {
      controller.toggleChecklist(order, item, true);
    }
    expect(() => controller.submit(order, '', true), throwsStateError);
    for (var i = 0; i < order.requiredPhotos; i++) {
      await controller.capture(order);
    }
    expect(() => controller.submit(order, '', false), throwsStateError);
    controller.submit(order, 'Readings normal.', true);
    expect(order.status, WorkStatus.evidenceSubmitted);
    expect(order.status, isNot(WorkStatus.completed));
    expect(order.notes, 'Readings normal.');
    expect(order.submittedAt, isNotNull);
    expect(controller.notifications.first.workOrderId, order.id);
    await expectLater(controller.capture(order), throwsStateError);
    expect(
      () => controller.removeEvidence(order, order.evidence.first),
      throwsStateError,
    );
    expect(
      () => controller.toggleChecklist(order, order.checklist.first, false),
      throwsStateError,
    );
    expect(() => controller.submit(order, '', true), throwsStateError);
  });
  test('Draft survives navigation and sign-out within the session', () async {
    final active = controller.orders.firstWhere(
      (o) => o.status == WorkStatus.inProgress,
    );
    controller.toggleChecklist(active, active.checklist.first, true);
    await controller.capture(active);
    controller.saveDraft(active, 'Pressure reading recorded', false);
    await accounts.signOut();
    await accounts.signIn(TestAccounts.email, TestAccounts.password);
    final reopened = controller.orders.firstWhere((o) => o.id == active.id);
    expect(reopened.notes, 'Pressure reading recorded');
    expect(reopened.evidence, hasLength(1));
    expect(reopened.checklist.first.done, isTrue);
  });
  test(
    'Rework retains earlier evidence and feedback and requires a new check-in',
    () {
      final rework = controller.orders.firstWhere(
        (o) => o.status == WorkStatus.reworkRequired,
      );
      final count = rework.evidence.length;
      controller.restartRework(rework);
      expect(rework.status, WorkStatus.assigned);
      expect(rework.evidence, isEmpty);
      expect(controller.previousEvidence[rework.id], hasLength(count));
      expect(rework.checklist.every((c) => !c.done), isTrue);
      expect(rework.attested, isFalse);
      expect(rework.adminRemarks, isNotEmpty);
      expect(() => controller.start(rework), throwsStateError);
    },
  );
  test(
    'Profile edits preserve protected fields and password changes work',
    () async {
      final before = accounts.account!;
      await accounts.updateProfile('Amir Razak', '+60 12-456 7890');
      expect(accounts.account!.id, before.id);
      expect(accounts.account!.email, before.email);
      expect(accounts.account!.employeeId, before.employeeId);
      expect(accounts.account!.role, before.role);
      expect(accounts.account!.name, 'Amir Razak');
      await expectLater(
        accounts.changePassword('wrong', 'NewPass@123'),
        throwsA(isA<AccountException>()),
      );
      await accounts.changePassword(TestAccounts.password, 'NewPass@123');
      await accounts.signOut();
      await expectLater(
        accounts.signIn(before.email, TestAccounts.password),
        throwsA(isA<AccountException>()),
      );
      await accounts.signIn(before.email, 'NewPass@123');
      expect(accounts.account!.id, before.id);
    },
  );
  test('Idle sessions expire before a mutation can occur', () {
    accounts.lastActivity = DateTime.now().subtract(
      const Duration(minutes: 16),
    );
    expect(() => controller.start(order), throwsStateError);
    expect(controller.signedIn, isFalse);
    expect(accounts.sessionMessage, contains('expired'));
  });
  test('Read alerts update the unread count', () {
    final count = controller.unreadCount;
    controller.markRead(controller.notifications.first);
    expect(controller.unreadCount, count - 1);
    controller.markAllRead();
    expect(controller.unreadCount, 0);
  });
}
