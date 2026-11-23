/// Phase 3: the launch price update is non-blocking, notifies price-dependent
/// widgets, respects the auto-update setting and fails quietly offline.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/calc/calculator.dart';
import 'package:montala/core/models.dart';
import 'package:montala/core/net/price_sync.dart';
import 'package:montala/core/net/updater.dart';
import 'package:montala/core/settings/settings.dart';
import 'package:montala/core/util/format.dart';
import 'package:montala/main.dart';
import 'package:montala/ui/app_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Settings> _settings({bool autoUpdate = true}) async {
  SharedPreferences.setMockInitialValues({'auto_update': autoUpdate});
  final settings = Settings();
  await settings.load();
  return settings;
}

class _PriceProbe extends StatelessWidget {
  const _PriceProbe();

  @override
  Widget build(BuildContext context) {
    final calculator = AppScope.of(context).calculator;
    return AnimatedBuilder(
      animation: calculator,
      builder: (context, _) {
        final rows = calculator.history['sekeb'] ?? const <PriceRow>[];
        return Text(rows.isEmpty ? 'بدون قیمت' : formatIntFa(rows.last.close));
      },
    );
  }
}

void main() {
  testWidgets('first frame renders while the launch update is still running',
      (tester) async {
    final settings = await _settings();
    final completer = Completer<List<SymbolUpdateResult>>();

    await tester.pumpWidget(
      MontalaApp(
        settings: settings,
        calculator: Calculator(const {}),
        refreshData: () async {},
        backgroundUpdate: () => completer.future,
      ),
    );
    await tester.pump(); // first frame + post-frame kickoff

    // The launcher is fully painted; the update has not completed.
    expect(find.text('مُنتَلا'), findsOneWidget);
    expect(find.text('جعبه‌ابزار'), findsOneWidget);
    expect(completer.isCompleted, isFalse);

    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    completer.complete(const []);
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('price-dependent widgets rebuild when the sync completes',
      (tester) async {
    final settings = await _settings();
    final calculator = Calculator({});
    final completer = Completer<List<SymbolUpdateResult>>();

    final sync = PriceSyncController(run: () async {
      final results = await completer.future;
      calculator.history['sekeb'] = [
        PriceRow(
          date: DateTime(2026, 11, 20),
          persianDate: '1405/08/29',
          open: 239000000,
          low: 238000000,
          high: 240000000,
          close: 239840000,
        ),
      ];
      calculator.markPricesChanged();
      return results;
    });

    await tester.pumpWidget(
      AppScope(
        settings: settings,
        calculator: calculator,
        refreshData: () async {},
        child: const MaterialApp(
          home: Scaffold(body: Center(child: _PriceProbe())),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('بدون قیمت'), findsOneWidget);

    final running = sync.start();
    await tester.pump();
    expect(find.text('بدون قیمت'), findsOneWidget); // update still pending

    completer.complete(const []);
    await running;
    await tester.pumpAndSettle();
    expect(find.text('۲۳۹٬۸۴۰٬۰۰۰'), findsOneWidget);
  });

  testWidgets('offline failure leaves the launcher intact', (tester) async {
    final settings = await _settings();

    await tester.pumpWidget(
      MontalaApp(
        settings: settings,
        calculator: Calculator(const {}),
        refreshData: () async {},
        backgroundUpdate: () async => throw Exception('offline'),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('مُنتَلا'), findsOneWidget);
    expect(find.text('سود و زیان فرضی'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto-update off never starts the background task',
      (tester) async {
    final settings = await _settings(autoUpdate: false);
    var calls = 0;

    await tester.pumpWidget(
      MontalaApp(
        settings: settings,
        calculator: Calculator(const {}),
        refreshData: () async {},
        backgroundUpdate: () async {
          calls += 1;
          return const [];
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
