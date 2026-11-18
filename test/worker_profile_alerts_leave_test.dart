import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uni360/app/uni360_app.dart';
import 'package:uni360/features/preventive/data/assigned_work_repository.dart';
import 'package:uni360/features/preventive/data/preventive_alert_repository.dart';
import 'package:uni360/features/workforce/worker_leave_repository.dart';

import 'support/test_accounts.dart';

class _UnusedClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Alerts extends PreventiveAlertRepository {
  _Alerts() : super(_UnusedClient());
  bool read = false;

  @override
  Future<List<PreventiveAlert>> load(String workerId) async => [
    PreventiveAlert(
      'alert',
      'Task approved',
      'Toilet Cleaning was approved.',
      DateTime.utc(2026, 11, 17),
      read,
      senderName: 'Test Administrator',
    ),
  ];

  @override
  Future<void> markRead(String workerId, String id) async {
    expect(id, 'alert');
    read = true;
  }
}

class _Leave extends WorkerLeaveRepository {
  _Leave() : super(_UnusedClient());

  @override
  Future<bool> isOnLeave(String workerId, DateTime date) async => false;

  @override
  Future<String> workerStatus(String workerId, DateTime date) async => 'Active';

  @override
  Future<List<WorkerLeave>> list({
    String? workerId,
    String? status,
    int page = 0,
  }) async => [
    if (submitted case (final kind, final reason))
      WorkerLeave.fromRow({
        'id': 'leave-1',
        'worker_id': workerId,
        'leave_type': kind,
        'starts_on': '2026-11-18',
        'ends_on': '2026-11-19',
        'reason': reason,
        'status': 'pending',
        'requested_at': '2026-11-18T03:00:00Z',
        'reassigned_count': 0,
        'uncovered_count': 0,
        'active_count': 0,
      }),
  ];

  (String, String)? submitted;

  @override
  Future<void> submit(
    String kind,
    DateTime first,
    DateTime last,
    String reason, {
    LeaveDocument? document,
  }) async {
    expect(last, DateTime(first.year, first.month, first.day + 1));
    submitted = (kind, reason);
  }
}

void main() {
  test('Supporting documents recognize both PDFs and photos', () {
    final pdf = LeaveDocument(
      'medical.pdf',
      Uint8List.fromList('%PDF-1.7'.codeUnits),
    );
    final photo = LeaveDocument(
      'image.jpeg',
      Uint8List.fromList([255, 216, 255]),
    );
    expect(pdf.mime, 'application/pdf');
    expect(photo.mime, 'image/jpeg');
    expect(() => LeaveDocument('bad.pdf', Uint8List(8)), throwsFormatException);
  });

  testWidgets(
    'Worker can read an approval alert and edit contact details from a separate profile screen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final accounts = TestAccounts();
      final alerts = _Alerts();
      final leave = _Leave();
      await tester.pumpWidget(
        Uni360App(
          accounts: accounts,
          loadAssignedWork: (_, _) async => [],
          alerts: alerts,
          leave: leave,
        ),
      );
      await tester.enterText(
        find.byType(TextFormField).at(0),
        TestAccounts.email,
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        TestAccounts.password,
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();
      expect(find.text('Task approved'), findsOneWidget);
      expect(find.text('Test Administrator'), findsOneWidget);
      final message = find.text('Toilet Cleaning was approved.');
      final date = find.text('17 Nov 2026');
      final notificationText = [
        find.text('Test Administrator'),
        find.text('Task approved'),
        message,
      ];
      for (final text in notificationText) {
        final style = tester.widget<Text>(text).style!;
        expect(style.fontWeight, FontWeight.w700);
        expect(style.fontSize, isNull);
      }
      expect(tester.widget<Text>(date).style?.fontWeight, FontWeight.w700);
      await tester.tap(find.text('Task approved'));
      await tester.pumpAndSettle();
      expect(alerts.read, true);
      expect(find.text('Notification'), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        'Toilet Cleaning was approved.',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      for (final text in notificationText) {
        expect(tester.widget<Text>(text).style?.fontWeight, FontWeight.w400);
      }
      expect(tester.widget<Text>(date).style?.fontWeight, FontWeight.w400);
      await tester.tap(message);
      await tester.pumpAndSettle();
      expect(find.text('Notification'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Date availability'), findsNothing);
      expect(find.text('Active'), findsOneWidget);
      await tester.ensureVisible(find.text('Update Profile'));
      await tester.tap(find.text('Update Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Choose profile photo'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Updated Worker',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '0123456789');
      await tester.ensureVisible(find.text('Update Profile'));
      await tester.tap(find.text('Update Profile'));
      await tester.pumpAndSettle();
      expect(accounts.profile.name, 'Updated Worker');
      expect(accounts.profile.phone, '0123456789');
      expect(find.byType(TextFormField), findsNothing);

      await tester.scrollUntilVisible(find.text('Apply for leave'), 160);
      await tester.tap(find.text('Apply for leave'));
      await tester.pumpAndSettle();
      expect(find.text('Apply for leave'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Supporting document (optional)'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Supporting document (optional)'), findsOneWidget);
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annual leave').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start date'));
      await tester.pumpAndSettle();
      expect(find.text('Select start date'), findsOneWidget);
      final localizations = MaterialLocalizations.of(
        tester.element(find.text('Select start date')),
      );
      final today = malaysiaToday();
      final todayLabel = localizations.formatFullDate(today);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Previous month',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip(todayLabel));
      await tester.pumpAndSettle();
      expect(
        find.text('Note: You are applying for 1 day of leave.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.textContaining('Ends ·'));
      await tester.tap(find.textContaining('Ends ·'));
      await tester.pumpAndSettle();
      expect(find.text('Select end date'), findsOneWidget);
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      if (tomorrow.month != today.month) {
        await tester.tap(find.byTooltip('Next month'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip(localizations.formatFullDate(tomorrow)));
      await tester.pumpAndSettle();
      expect(
        find.text('Note: You are applying for 2 days of leave.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField), 'Family event');
      await tester.ensureVisible(find.text('Submit request'));
      await tester.tap(find.text('Submit request'));
      await tester.pumpAndSettle();
      expect(leave.submitted, ('annual', 'Family event'));
      expect(find.text('My profile'), findsOneWidget);
      await tester.ensureVisible(find.text('Leave history'));
      await tester.tap(find.text('Leave history'));
      await tester.pumpAndSettle();
      expect(find.text('Pending approval'), findsOneWidget);
      expect(find.text('2 days'), findsOneWidget);
      expect(find.text('Family event'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
