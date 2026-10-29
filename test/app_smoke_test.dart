/// Headless smoke test: boots the real app against the real CSVs and drives
/// the form, so failures in the seed import, the calculation pipeline and the
/// widget tree surface in CI rather than only on a developer's desktop.
///
/// Real disk/SQLite work must run through `tester.runAsync`, because
/// `testWidgets` executes inside a fake-async zone where those futures never
/// complete.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/calc/calculator.dart';
import 'package:montala/core/db/app_db.dart';
import 'package:montala/core/db/db_factory_native.dart';
import 'package:montala/core/db/importer.dart';
import 'package:montala/core/models.dart';
import 'package:montala/core/settings/settings.dart';
import 'package:montala/core/symbols.dart';
import 'package:montala/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int expectedRows;
  final history = <String, List<PriceRow>>{};

  setUpAll(() async {
    await initDatabaseFactoryForPlatform();

    // Start from a clean database so the first-run gate is exercised.
    await AppDb.close();
    final dbFile = File(await AppDb.debugDatabasePath());
    if (dbFile.existsSync()) dbFile.deleteSync();

    // Expected row count straight from the CSV files (source of truth).
    expectedRows = 0;
    for (final symbol in kSymbols) {
      final f = File(symbol.csvAsset);
      expect(f.existsSync(), isTrue, reason: 'missing ${symbol.csvAsset}');
      expectedRows += f
          .readAsLinesSync()
          .skip(1)
          .where((l) => l.trim().isNotEmpty)
          .length;
    }

    final imported = await Importer.importAllIfNeeded();
    expect(imported, expectedRows,
        reason: 'every CSV row must survive the seed import');

    for (final symbol in kSymbols) {
      history[symbol.id] = await AppDb.pricesForSymbol(symbol.id);
    }
  });

  test('seed import fills SQLite for all seven symbols', () async {
    for (final symbol in kSymbols) {
      expect(await AppDb.rowCount(symbol.id), greaterThan(3000),
          reason: '${symbol.id} not imported');
      final last = await AppDb.maxDate(symbol.id);
      expect(last, isNotNull);
      expect(last!.isAfter(DateTime(2026, 1, 1)), isTrue,
          reason: '${symbol.id} max date is stale: $last');
    }
    // Idempotent: a second call must not re-import.
    expect(await Importer.importAllIfNeeded(), 0);
  });

  test('dashboard rows survive a SQLite round-trip', () async {
    for (final symbol in kSymbols) {
      final rows = history[symbol.id]!;
      expect(rows.length, greaterThan(3000));
      expect(rows.first.date.isBefore(rows.last.date), isTrue);
      expect(rows.last.close, greaterThan(0));
      // Persian date came back as stored.
      expect(rows.last.persianDate, isNotEmpty);
    }
  });

  testWidgets('UI boots, accepts input, and renders ranked results',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final settings = Settings();
    await settings.load();

    await tester.pumpWidget(
      MontalaApp(
        settings: settings,
        calculator: Calculator(history),
        refreshData: () async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مبلغ سرمایه‌گذاری'), findsOneWidget);
    expect(find.text('تاریخ خرید'), findsOneWidget);
    expect(find.text('تاریخ مقایسه'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '50000000');
    await tester.pump();

    await tester.tap(find.text('محاسبه سود و زیان'));
    await tester.pumpAndSettle();

    expect(find.text('خلاصه نتیجه'), findsOneWidget);
    expect(find.text('رتبه‌بندی بازدهی'), findsOneWidget);
    expect(find.text('جزئیات هر نماد'), findsOneWidget);
    for (final symbol in kSymbols) {
      expect(find.text(symbol.nameFa), findsWidgets,
          reason: '${symbol.nameFa} missing from results');
    }
    expect(find.byType(ErrorWidget), findsNothing);

    // Opening the detail sheet must not throw. Tap inside the results table
    // (the rank bars above it share the same label text).
    final tableLabel = find.text(kSymbols.first.nameFa).last;
    await tester.ensureVisible(tableLabel);
    await tester.pumpAndSettle();
    await tester.tap(tableLabel);
    await tester.pumpAndSettle();
    expect(find.text('سرمایه اولیه'), findsOneWidget);
    expect(find.text('ارزش نهایی'), findsOneWidget);
  });

  testWidgets('settings screen renders and the Toman toggle persists',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final settings = Settings();
    await settings.load();

    await tester.pumpWidget(
      MontalaApp(
        settings: settings,
        calculator: Calculator(history),
        refreshData: () async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.text('نمایش'), findsOneWidget);
    expect(find.text('داده'), findsOneWidget);

    final before = settings.inToman;
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(settings.inToman, isNot(before));
  });
}
