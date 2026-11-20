/// Store-screenshot generator for the مایکت listing.
///
/// Renders the real app screens to 1080×1920 goldens (at 3× density for
/// crisp text, downscaled by tools/make_store_screenshots.py afterwards).
///
/// Usage (writes goldens, does not compare):
///   STORE_SHOTS=1 flutter test test/store_screenshots --update-goldens
///
/// Without STORE_SHOTS every test returns immediately, so CI never compares
/// these outputs (some content legitimately depends on the run date).
///
/// No hand-made mockups: every image is the real widget tree of the screen,
/// seeded with fixed, realistic data. The one lib-side seam is
/// `LiveBoardScreen(seedTgju/seedEstjt/autoRefresh)` — HTTP cannot progress
/// under the fake-async test zone, so the live board renders from fixed
/// snapshots (values match the real estjt/tgju payloads of the day).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/calc/calculator.dart';
import 'package:montala/core/db/importer.dart';
import 'package:montala/core/models.dart';
import 'package:montala/core/net/live_quotes.dart';
import 'package:montala/core/portfolio/portfolio_store_web_io.dart';
import 'package:montala/core/settings/settings.dart';
import 'package:montala/core/symbols.dart';
import 'package:montala/main.dart';
import 'package:montala/ui/screens/live_board_screen.dart';
import 'package:montala/ui/screens/networth_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool get kStoreShots => Platform.environment['STORE_SHOTS'] == '1';

/// Raw output directory, relative to this test file.
const String _rawDir = '../../store/screenshots/raw';

bool _fontsLoaded = false;

/// Loads the bundled Vazirmatn family (Regular/Medium/Bold) so Persian text
/// renders exactly like on a device, not with the Ahem test font.
Future<void> _ensureFonts(WidgetTester tester) async {
  if (_fontsLoaded) return;
  await tester.runAsync(() async {
    final loader = FontLoader('Vazirmatn')
      ..addFont(rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Vazirmatn-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Vazirmatn-Bold.ttf'));
    await loader.load();

    // The Material icon font is not part of the test asset bundle; load it
    // from the Flutter SDK cache so AppBar/tile icons do not render as tofu.
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null) {
      final iconFile = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/'
        'MaterialIcons-Regular.otf',
      );
      if (iconFile.existsSync()) {
        final bytes = await iconFile.readAsBytes();
        final icons = FontLoader('MaterialIcons')
          ..addFont(Future.value(bytes.buffer.asByteData()));
        await icons.load();
      }
    }
  });
  _fontsLoaded = true;
}

/// The real bundled datasets (۸ دارایی، ۱۳۸۹ تا امروز) as the app's history.
Future<Map<String, List<PriceRow>>> _loadHistory() async {
  final history = <String, List<PriceRow>>{};
  for (final symbol in kSymbols) {
    final csv = await rootBundle.loadString(symbol.csvAsset);
    history[symbol.id] = Importer.parseCsv(csv);
  }
  return history;
}

Future<void> _setUpView(WidgetTester tester) async {
  // Physical 1080×1920 at 3× density → a standard phone logical size of
  // 360×640: the UI fills the frame at real mobile proportions instead of
  // floating small in a tablet-sized canvas.
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// A minimal, theme-matched phone status bar rendered above the app UI
/// (clock right — RTL phones mirror it — and wifi/signal/battery left).
/// Test-only scaffolding; part of the screenshot, not of the app.
Widget _phoneShell(Widget app) {
  const ink = Color(0xFF1E2321); // MontalaColors.ink
  const surface = Color(0xFFFCFAF7); // MontalaColors.surfaceWarm
  return Directionality(
    textDirection: TextDirection.rtl,
    child: Column(
      children: [
        Container(
          height: 24,
          color: surface,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          // Clock in the left corner; wifi/signal/battery grouped in the
          // right corner with the battery rightmost — laid out explicitly
          // LTR so the placement does not depend on ambient directionality.
          child: Row(
            textDirection: TextDirection.ltr,
            children: [
              const Text(
                '۱۲:۳۰',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Vazirmatn',
                  color: ink,
                ),
              ),
              const Spacer(),
              const Icon(Icons.signal_cellular_alt, size: 13, color: ink),
              const SizedBox(width: 5),
              const Icon(Icons.wifi, size: 13, color: ink),
              const SizedBox(width: 5),
              const Icon(Icons.battery_full, size: 15, color: ink),
            ],
          ),
        ),
        Expanded(child: app),
      ],
    ),
  );
}

/// Fixed live-board snapshots — the real estjt/tgju readings of a market
/// day, in the board's internal Toman representation.
const Map<String, LiveCell> kSeedEstjt = {
  'gold_ons': LiveCell(value: 3883, isUsd: true),
  'mesghal': LiveCell(value: 107910000),
  'gold18': LiveCell(value: 24911200),
  'gold24': LiveCell(value: 33211000),
  'sekeb': LiveCell(value: 246600000),
  'sekee': LiveCell(value: 253700000),
  'nim': LiveCell(value: 133400000),
  'rob': LiveCell(value: 72400000),
  'gerami': LiveCell(value: 37000000),
};

const Map<String, LiveCell> kSeedTgju = {
  'sekee': LiveCell(value: 253965000),
  'sekeb': LiveCell(value: 247045000),
  'gold24': LiveCell(value: 33384700),
  'gold18': LiveCell(value: 24911200),
  'mesghal': LiveCell(value: 108455000),
  'nim': LiveCell(value: 133190000),
  'rob': LiveCell(value: 72490000),
  'gerami': LiveCell(value: 37000000),
  'gold_ons': LiveCell(value: 409600000),
  'gold_futures': LiveCell(value: 1083050000),
  'silver_ons': LiveCell(value: 399500),
  'silver_999': LiveCell(value: 12810),
  'seke_gc': LiveCell(value: 302000),
};

/// A fixed, realistic transaction ledger (۱۴۰۲ تا ۱۴۰۴).
const List<Map<String, Object?>> kSeedTransactions = [
  {
    'date': '2023-05-14',
    'asset': 'sekee',
    'type': 'BUY',
    'units': 1,
    'unit_price_toman': 115000000,
    'note': 'خرید اول',
  },
  {
    'date': '2024-03-05',
    'asset': 'gold18',
    'type': 'BUY',
    'units': 10,
    'unit_price_toman': 24000000,
  },
  {
    'date': '2024-11-20',
    'asset': 'gold24',
    'type': 'BUY',
    'units': 0.5,
    'unit_price_toman': 30000000,
  },
  {
    'date': '2025-06-10',
    'asset': 'gold18',
    'type': 'BUY',
    'units': 3,
    'unit_price_toman': 31500000,
  },
  {
    'date': '2025-12-01',
    'asset': 'gold18',
    'type': 'SELL',
    'units': 4,
    'unit_price_toman': 45000000,
    'note': 'فروش بخشی',
  },
];

void main() {
  Future<MontalaApp> buildApp(WidgetTester tester) async {
    await _ensureFonts(tester);
    await _setUpView(tester);
    // Asset reads and prefs run on the real event loop — under fake async
    // rootBundle.loadString never completes.
    late MontalaApp app;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final settings = Settings();
      await settings.load();
      final history = await _loadHistory();
      app = MontalaApp(
        settings: settings,
        calculator: Calculator(history),
        refreshData: () async {},
      );
    });
    return app;
  }

  Future<void> golden(WidgetTester tester, String name) {
    return expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$_rawDir/$name.png'),
    );
  }

  testWidgets('01 launcher', (tester) async {
    if (!kStoreShots) return;
    final app = await buildApp(tester);
    await tester.pumpWidget(_phoneShell(app));
    await tester.pumpAndSettle();
    await golden(tester, '01-launcher');
  });

  testWidgets('02 profit/loss form + 03 ranked results', (tester) async {
    if (!kStoreShots) return;
    final app = await buildApp(tester);
    await tester.pumpWidget(_phoneShell(app));
    await tester.pumpAndSettle();

    await tester.tap(find.text('سود و زیان فرضی'));
    await tester.pumpAndSettle();

    // The form ships with the ۱۰۰٬۰۰۰٬۰۰۰ default; dates are today-ish.
    await golden(tester, '02-profit-loss');

    // Calculate and scroll the ranked results into view.
    await tester.tap(find.text('محاسبه سود و زیان'));
    await tester.pumpAndSettle();
    final summary = find.text('خلاصه نتیجه');
    await tester.ensureVisible(summary);
    await tester.pumpAndSettle();
    await golden(tester, '03-results');
  });

  testWidgets('04 live board', (tester) async {
    if (!kStoreShots) return;
    final app = await buildApp(tester);
    await tester.pumpWidget(_phoneShell(app));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('تابلو زنده'));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveBoardScreen(
          seedTgju: kSeedTgju,
          seedEstjt: kSeedEstjt,
          autoRefresh: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await golden(tester, '04-live-board');
  });

  testWidgets('05 valuation with result', (tester) async {
    if (!kStoreShots) return;
    final app = await buildApp(tester);
    await tester.pumpWidget(_phoneShell(app));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ارزش سبد در یک تاریخ'));
    await tester.pumpAndSettle();

    // kSymbols order: dollar, gold18, gold24, sekee, sekeb, nim, rob, gerami.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '500'); // dollar
    await tester.enterText(fields.at(1), '10'); // gold18
    await tester.enterText(fields.at(2), '2'); // gold24
    await tester.enterText(fields.at(3), '1'); // sekee
    await tester.pump();
    // Drop the caret first — a focused field keeps itself on screen and
    // would scroll back over the result card.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    // At the phone viewport the button sits below the fold — reveal it
    // first, then calculate (the screen auto-scrolls to the result).
    await tester.ensureVisible(find.text('محاسبه ارزش در این تاریخ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('محاسبه ارزش در این تاریخ'));
    await tester.pumpAndSettle();
    // Captured with the result-flash border on; flush the flash timer so the
    // test teardown does not complain about pending timers.
    await golden(tester, '05-valuation');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('06 transactions ledger', (tester) async {
    if (!kStoreShots) return;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await _ensureFonts(tester);
    await _setUpView(tester);
    late MontalaApp app;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({
        'portfolio_transactions_v1': jsonEncode(kSeedTransactions),
      });
      final settings = Settings();
      await settings.load();
      final history = await _loadHistory();
      app = MontalaApp(
        settings: settings,
        calculator: Calculator(history),
        refreshData: () async {},
      );
    });
    await tester.pumpWidget(_phoneShell(app));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('ارزش دارایی من'));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NetWorthScreen(
            storeOverride: PrefsPortfolioStore(), showFab: false),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('تراکنش‌ها'));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await golden(tester, '06-transactions');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('07 value-history chart', (tester) async {
    if (!kStoreShots) return;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await _ensureFonts(tester);
    await _setUpView(tester);
    late MontalaApp app;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({
        'portfolio_transactions_v1': jsonEncode(kSeedTransactions),
      });
      final settings = Settings();
      await settings.load();
      final history = await _loadHistory();
      app = MontalaApp(
        settings: settings,
        calculator: Calculator(history),
        refreshData: () async {},
      );
    });
    await tester.pumpWidget(_phoneShell(app));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('ارزش دارایی من'));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NetWorthScreen(
            storeOverride: PrefsPortfolioStore(), showFab: false),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('تاریخچه'));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await golden(tester, '07-history-analysis');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('08 jalali calendar', (tester) async {
    if (!kStoreShots) return;
    final app = await buildApp(tester);
    await tester.pumpWidget(_phoneShell(app));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ارزش سبد در یک تاریخ'));
    await tester.pumpAndSettle();

    // Open the real picker, then switch to the month/year quick-jump view.
    await tester.tap(find.byIcon(Icons.event_available));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();
    await golden(tester, '08-jalali-calendar');
  });
}
