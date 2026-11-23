/// Widget tests for the portfolio tool's Phase 4 surface: incomplete rows are
/// visibly flagged and completed, «محاسبه مجدد» writes the value history, and
/// amounts always carry an explicit تومان/ریال unit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/calc/calculator.dart';
import 'package:montala/core/models.dart';
import 'package:montala/core/portfolio/portfolio_models.dart';
import 'package:montala/core/portfolio/portfolio_store_web_io.dart';
import 'package:montala/core/settings/settings.dart';
import 'package:montala/ui/app_scope.dart';
import 'package:montala/ui/screens/networth_screen.dart';
import 'package:montala/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

PriceRow _row(DateTime date, int close) => PriceRow(
      date: date,
      persianDate: '',
      open: close,
      low: close,
      high: close,
      close: close,
    );

Future<Settings> _settings({bool inToman = true}) async {
  SharedPreferences.setMockInitialValues({'in_toman': inToman});
  final settings = Settings();
  await settings.load();
  return settings;
}

Future<PrefsPortfolioStore> _seededStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = PrefsPortfolioStore();
  await store.addTransaction(PortfolioTx(
    timestamp: DateTime(2026, 1, 1, 9, 0),
    assetId: 'sekee',
    type: 'BUY',
    units: 1,
    unitPriceToman: 250000000,
    totalToman: 250000000,
  ));
  await store.addTransaction(PortfolioTx(
    timestamp: DateTime(2026, 1, 2, 10, 0),
    assetId: 'gold18',
    type: 'BUY',
    units: 5,
    unitPriceToman: 0,
    totalToman: 0,
    incomplete: true,
  ));
  return store;
}

Calculator _calculator() => Calculator({
      'sekee': [
        _row(DateTime(2026, 11, 19), 250000000),
        _row(DateTime(2026, 11, 20), 250000000),
      ],
      'gold18': [
        _row(DateTime(2026, 11, 19), 24000000),
        _row(DateTime(2026, 11, 20), 24000000),
      ],
    });

Future<void> _pump(
  WidgetTester tester,
  PrefsPortfolioStore store, {
  bool inToman = true,
  Calculator? calculator,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final settings = await _settings(inToman: inToman);
  await tester.pumpWidget(
    AppScope(
      settings: settings,
      calculator: calculator ?? _calculator(),
      refreshData: () async {},
      child: MaterialApp(
        theme: buildTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: NetWorthScreen(storeOverride: store),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('incomplete rows are flagged and can be completed', (tester) async {
    final store = await _seededStore();
    await _pump(tester, store);

    await tester.tap(find.text('تراکنش‌ها'));
    await tester.pumpAndSettle();

    expect(find.textContaining('تراکنش ناقص'), findsOneWidget);
    expect(find.text('نامشخص'), findsOneWidget);

    await tester.tap(find.textContaining('تراکنش ناقص'));
    await tester.pumpAndSettle();

    expect(find.text('تکمیل تراکنش'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'قیمت هر واحد (تومان)'),
      '24000000',
    );
    await tester.tap(find.text('ثبت'));
    await tester.pumpAndSettle();

    expect(find.textContaining('تراکنش ناقص'), findsNothing);
    expect(find.text('نامشخص'), findsNothing);
    expect(find.textContaining('۱۲۰٫۰ میلیون'), findsOneWidget);

    final stored = await store.transactions();
    final completed = stored.firstWhere((t) => t.assetId == 'gold18');
    expect(completed.incomplete, isFalse);
    expect(completed.unitPriceToman, 24000000);
    expect(completed.totalToman, 120000000);
  });

  testWidgets('«محاسبه مجدد» records the value once and refreshes it',
      (tester) async {
    final store = await _seededStore();
    await _pump(tester, store);

    await tester.tap(find.text('تاریخچه'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('محاسبه مجدد'));
    await tester.pumpAndSettle();

    expect(find.text('عکس‌های ارزش ثبت‌شده'), findsOneWidget);
    expect(find.textContaining('محاسبه مجدد'), findsOneWidget);
    var snaps = await store.snapshots();
    expect(snaps.length, 1);
    expect(snaps.single.totalToman, 370000000);

    // Same holdings, same prices → no duplicate row.
    await tester.tap(find.byTooltip('محاسبه مجدد'));
    await tester.pumpAndSettle();
    snaps = await store.snapshots();
    expect(snaps.length, 1);
  });

  testWidgets('the Rial setting converts every amount with a ریال unit',
      (tester) async {
    final store = await _seededStore();
    await _pump(tester, store, inToman: false);

    expect(find.textContaining('ریال'), findsWidgets);
    // 250,000,000 Toman = 2.5 میلیارد ریال.
    expect(find.textContaining('۲٫۵ میلیارد'), findsWidgets);
    expect(find.textContaining('تومان'), findsNothing);
  });
}
