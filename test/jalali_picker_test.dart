/// Widget tests for the Jalali date picker's quick-jump features:
/// year double-arrows and the month/year view behind the header tap.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/util/jalali.dart';
import 'package:montala/core/util/jalali_picker.dart';
import 'package:montala/ui/theme.dart';

/// Boots a minimal RTL app and opens the picker; [result] receives whatever
/// the dialog returns when it closes.
class _Harness {
  DateTime? result;
}

void main() {
  // Same range the tools use: 2005..now+8.
  final firstDate = DateTime(2005, 1, 1);
  final lastDate = DateTime(2034, 12, 31);

  Future<_Harness> openPicker(
    WidgetTester tester, {
    DateTime? initial,
    DateTime? first,
    DateTime? last,
  }) async {
    final harness = _Harness();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                harness.result = await showJalaliDatePicker(
                  context,
                  initialDate: initial ?? DateTime(2026, 11, 13),
                  firstDate: first ?? firstDate,
                  lastDate: last ?? lastDate,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets('year double-arrows jump the view one year', (tester) async {
    await openPicker(tester);
    // 2026-11-13 → آبان ۱۴۰۵.
    expect(find.text('آبان ۱۴۰۵'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left));
    await tester.pumpAndSettle();
    expect(find.text('آبان ۱۴۰۶'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_right));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_right));
    await tester.pumpAndSettle();
    expect(find.text('آبان ۱۴۰۴'), findsOneWidget);
  });

  testWidgets('header tap opens month/year view and jumps months',
      (tester) async {
    final harness = await openPicker(tester);

    await tester.tap(find.text('آبان ۱۴۰۵'));
    await tester.pumpAndSettle();

    expect(find.text('انتخاب ماه و سال'), findsOneWidget);
    expect(find.text('فروردین'), findsOneWidget);

    // Jump far back: the year list starts at the viewed year (۱۴۰۵) scrolled
    // down, so drag toward earlier years (negative delta = reveal items
    // above) until ۱۳۸۹, the very first year, is visible.
    await tester.scrollUntilVisible(
      find.text('۱۳۸۹'),
      -100,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
        matchRoot: true,
      ),
    );
    await tester.tap(find.text('۱۳۸۹'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('فروردین'));
    await tester.pumpAndSettle();

    // Back on the day grid for فروردین ۱۳۸۹.
    expect(find.text('انتخاب ماه و سال'), findsNothing);
    expect(find.text('فروردین ۱۳۸۹'), findsOneWidget);

    // Select day 1 and confirm → the dialog returns that day.
    await tester.tap(find.text('۱'));
    await tester.tap(find.text('تأیید'));
    await tester.pumpAndSettle();

    final j = gregorianToJalali(harness.result!);
    expect(j.year, 1389);
    expect(j.month, 1);
    expect(j.day, 1);
  });

  testWidgets('months outside the range are disabled', (tester) async {
    // Range starting mid-آبان ۱۴۰۵: earlier months of ۱۴۰۵ must be dead.
    await openPicker(
      tester,
      first: DateTime(2026, 11, 13),
      initial: DateTime(2026, 11, 13),
    );

    await tester.tap(find.text('آبان ۱۴۰۵'));
    await tester.pumpAndSettle();

    // Tapping a disabled month must not leave the month/year view.
    await tester.tap(find.text('فروردین'));
    await tester.pumpAndSettle();
    expect(find.text('انتخاب ماه و سال'), findsOneWidget);

    // The first enabled month still works.
    await tester.tap(find.text('آبان'));
    await tester.pumpAndSettle();
    expect(find.text('آبان ۱۴۰۵'), findsOneWidget);
  });
}
