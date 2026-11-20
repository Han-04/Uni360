import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni360/features/preventive/admin/admin_widgets.dart';

void main() {
  testWidgets('Admin command fills from the pointer after the delay', (
    tester,
  ) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AdminCommandButton(
              label: 'Create worker',
              icon: Icons.add,
              onPressed: () => pressed = true,
            ),
          ),
        ),
      ),
    );
    final button = find.byType(FilledButton);
    final fill = find.descendant(of: button, matching: find.byType(ClipPath));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(20, 20));
    final topLeft = tester.getTopLeft(button);
    await mouse.moveTo(topLeft + const Offset(38, 22));
    await tester.pump(const Duration(milliseconds: 60));
    final pointer = topLeft + const Offset(5, 25);
    await mouse.moveTo(pointer);
    await tester.pump(const Duration(milliseconds: 45));
    expect(fill, findsNothing);

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 30));
    expect(fill, findsOneWidget);
    final paintedSize = tester.getSize(fill);
    final clip = tester.widget<ClipPath>(fill).clipper!.getClip(paintedSize);
    final paintedOrigin = tester.getTopLeft(fill) + clip.getBounds().center;
    expect((paintedOrigin - pointer).distance, lessThan(.01));
    expect(
      clip.contains(Offset(paintedSize.width - 1, paintedSize.height / 2)),
      isFalse,
    );
    final filledLabel = find.descendant(
      of: fill,
      matching: find.text('Create worker'),
    );
    expect(tester.widget<Text>(filledLabel).style?.color, Colors.white);

    await tester.tapAt(pointer);
    expect(pressed, isTrue);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(fill, findsNothing);
  });

  testWidgets('Filter hover waits and expands from the pointer', (
    tester,
  ) async {
    var selection = 'all';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: StatefulBuilder(
              builder: (context, setState) => AdminFilterMenu(
                label: 'Status',
                value: selection,
                options: const {'all': 'All statuses', 'active': 'Active'},
                onChanged: (value) => setState(() => selection = value),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('All statuses'));
    await tester.pumpAndSettle();

    final item = find.widgetWithText(MenuItemButton, 'Active');
    final fill = find.descendant(of: item, matching: find.byType(ClipPath));
    final pointer = tester.getTopLeft(item) + const Offset(39, 18);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(490, 360));
    await mouse.moveTo(pointer);
    await tester.pump(const Duration(milliseconds: 95));
    expect(fill, findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 45));
    expect(fill, findsOneWidget);
    final clip = tester.widget<ClipPath>(fill);
    final bounds = clip.clipper!.getClip(tester.getSize(fill)).getBounds();
    final actualOrigin = tester.getTopLeft(fill) + bounds.center;
    expect(actualOrigin.dx, closeTo(pointer.dx, .01));
    expect(actualOrigin.dy, closeTo(pointer.dy, .01));
    expect(bounds.width, greaterThan(0));
    expect(bounds.right, lessThan(tester.getSize(fill).width));

    await tester.tapAt(pointer);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(selection, 'active');
    expect(find.byType(MenuItemButton), findsNothing);
    expect(find.text('Active'), findsOneWidget);
  });
}
