/// مُنتَلا — entry point.
///
/// Startup order:
///  1. select the sqflite factory for this platform (native FFI vs wasm),
///  2. load preferences,
///  3. import the bundled CSVs on first run,
///  4. show the UI.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/calc/calculator.dart';
import 'core/db/app_db.dart';
import 'core/db/db_factory_native.dart'
    if (dart.library.js_interop) 'core/db/db_factory_web.dart';
import 'core/db/importer.dart';
import 'core/models.dart';
import 'core/net/updater.dart';
import 'core/settings/settings.dart';
import 'core/symbols.dart';
import 'ui/app_scope.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Startup touches the database and the network. If anything throws there, a
  // bare exception would leave the splash screen spinning forever with no
  // explanation, so failures are reported on screen instead.
  try {
    await _bootstrap();
  } catch (error, stack) {
    debugPrint('startup failed: $error\n$stack');
    runApp(StartupFailureApp(error: error));
  }
}

Future<void> _bootstrap() async {
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  await initDatabaseFactoryForPlatform();

  final settings = Settings();
  await settings.load();

  await Importer.importAllIfNeeded();

  final history = <String, List<PriceRow>>{};
  for (final symbol in kSymbols) {
    history[symbol.id] = await AppDb.pricesForSymbol(symbol.id);
  }

  final calculator = Calculator(history);

  Future<void> refresh() async {
    final updater = Updater();
    final results = await updater.updateAll();
    if (results.any((r) => r.ok)) {
      await settings.setLastUpdate(DateTime.now());
    }
    for (final symbol in kSymbols) {
      history[symbol.id] = await AppDb.pricesForSymbol(symbol.id);
    }
  }

  runApp(
    MontalaApp(
      settings: settings,
      calculator: calculator,
      refreshData: refresh,
    ),
  );
}

class MontalaApp extends StatelessWidget {
  final Settings settings;
  final Calculator calculator;
  final Future<void> Function() refreshData;

  const MontalaApp({
    super.key,
    required this.settings,
    required this.calculator,
    required this.refreshData,
  });

  @override
  Widget build(BuildContext context) {
    return AppScope(
      settings: settings,
      calculator: calculator,
      refreshData: refreshData,
      child: AnimatedBuilder(
        animation: settings,
        builder: (context, _) {
          return MaterialApp(
            title: 'مُنتَلا',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(),
            locale: const Locale('fa', 'IR'),
            supportedLocales: const [Locale('fa', 'IR')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) {
              return Directionality(
                textDirection: TextDirection.rtl,
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}

/// Shown when startup fails, so the user sees the reason instead of an endless
/// splash screen. Deliberately dependency-free: it must render even when the
/// database or preferences are broken.
class StartupFailureApp extends StatelessWidget {
  final Object error;

  const StartupFailureApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                         size: 34, color: MontalaColors.loss),
                    const SizedBox(height: Space.m),
                    const Text(
                      'راه‌اندازی برنامه ناموفق بود',
                      style: TextStyle(
                        fontFamily: 'Vazirmatn',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Space.s),
                    const Text(
                      'داده‌های قیمت بارگذاری نشد. اگر این پیام تکرار شد، برنامه را ببندید و دوباره باز کنید.',
                      style: TextStyle(
                        fontFamily: 'Vazirmatn',
                        fontSize: 12.5,
                        height: 1.8,
                        color: MontalaColors.inkMuted,
                      ),
                    ),
                    const SizedBox(height: Space.l),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(Space.m),
                      decoration: BoxDecoration(
                        color: MontalaColors.lossSoft,
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                      child: Text(
                        '$error',
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: MontalaColors.loss,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
