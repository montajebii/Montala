/// Board-level behaviour when estjt fails: never blank a symbol that has a
/// recent value, fall back to tgju visibly, and keep working while offline.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/calc/calculator.dart';
import 'package:montala/core/net/live_quotes.dart';
import 'package:montala/core/settings/settings.dart';
import 'package:montala/ui/app_scope.dart';
import 'package:montala/ui/screens/live_board_screen.dart';
import 'package:montala/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Settings> _settings() async {
  SharedPreferences.setMockInitialValues({});
  final settings = Settings();
  await settings.load();
  return settings;
}

LiveSnapshot _tgju() => LiveSnapshot(
      source: 'tgju',
      fetchedAt: DateTime(2026, 11, 20, 16, 50),
      cells: const {
        'sekee': LiveCell(value: 253700000),
        'gold18': LiveCell(value: 24989700),
      },
    );

Future<void> _pumpBoard(
  WidgetTester tester, {
  required Future<LiveSnapshot> Function() tgjuLoader,
  required Future<LiveSnapshot> Function() estjtLoader,
}) async {
  tester.view.physicalSize = const Size(900, 1500);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final settings = await _settings();
  await tester.pumpWidget(
    AppScope(
      settings: settings,
      calculator: Calculator(const {}),
      refreshData: () async {},
      child: MaterialApp(
        theme: buildTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: LiveBoardScreen(
            autoRefresh: false,
            tgjuLoader: tgjuLoader,
            estjtLoader: estjtLoader,
            estjtMinInterval: Duration.zero,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('alternating estjt failures keep every row populated',
      (tester) async {
    var estjtCall = 0;

    await _pumpBoard(
      tester,
      tgjuLoader: () async => _tgju(),
      estjtLoader: () async {
        estjtCall += 1;
        if (estjtCall == 1) throw Exception('timeout');
        if (estjtCall == 2) {
          return LiveSnapshot(
            source: 'estjt',
            fetchedAt: DateTime(2026, 11, 20, 16, 51),
            cells: const {'sekee': LiveCell(value: 250000000)},
          );
        }
        throw Exception('timeout');
      },
    );
    await tester.pumpAndSettle();

    // Cold estjt failure: both rows come from tgju, tagged as such.
    expect(find.text('از tgju'), findsNWidgets(2));
    expect(find.text('کهنه'), findsNothing);
    expect(find.text('۲۵۳٬۷۰۰٬۰۰۰'), findsNWidgets(2)); // tgju + fallback
    expect(find.text('۲۴٬۹۸۹٬۷۰۰'), findsNWidgets(2));

    // Second attempt succeeds for one row: the fresh reading replaces the
    // fallback, the missing row keeps its last good value.
    await tester.tap(find.byTooltip('به‌روزرسانی'));
    await tester.pumpAndSettle();
    expect(estjtCall, 2);
    expect(find.text('۲۵۰٬۰۰۰٬۰۰۰'), findsOneWidget);
    expect(find.text('از tgju'), findsOneWidget); // gold18 still inherited
    expect(find.text('کهنه'), findsNothing);

    // Third attempt fails: the fresh row is carried forward and marked stale;
    // the inherited row stays tagged with its source.
    await tester.tap(find.byTooltip('به‌روزرسانی'));
    await tester.pumpAndSettle();
    expect(estjtCall, 3);
    expect(find.text('۲۵۰٬۰۰۰٬۰۰۰'), findsOneWidget);
    expect(find.text('کهنه'), findsOneWidget);
    expect(find.text('از tgju'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fully offline launch still renders the board', (tester) async {
    await _pumpBoard(
      tester,
      tgjuLoader: () async => throw Exception('offline'),
      estjtLoader: () async => throw Exception('offline'),
    );
    await tester.pumpAndSettle();

    expect(find.text('—'), findsWidgets);
    expect(find.textContaining('tgju قطع'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
