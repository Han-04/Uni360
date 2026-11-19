import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni360/features/preventive/admin/admin_filter_menu.dart';

void main() {
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
