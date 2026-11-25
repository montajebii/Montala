/// مُنتَلا — entry point.
///
/// Startup order:
///  1. select the sqflite factory for this platform (native FFI vs wasm),
///  2. load preferences,
///  3. import the bundled CSVs on first run,
///  4. show the UI.
///
/// Every async step below is bounded by a timeout and wrapped in its own
/// try/catch. On the web a stalled asset fetch, a blocked storage API or a
/// plugin that never answers must never keep [runApp] from being called —
/// otherwise the HTML splash (`در حال آماده‌سازی داده‌ها...`) spins forever
/// and the `flutter-first-frame` event never fires.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/calc/calculator.dart';
import 'core/db/app_db.dart';
import 'core/db/db_factory_native.dart'
    if (dart.library.js_interop) 'core/db/db_factory_web.dart';
import 'core/db/importer.dart';
import 'core/models.dart';
import 'core/net/price_sync.dart';
import 'core/net/updater.dart';
import 'core/portfolio/portfolio_snapshot.dart';
import 'core/portfolio/portfolio_store.dart';
import 'core/settings/settings.dart';
import 'core/symbols.dart';
import 'ui/app_scope.dart';
import 'ui/screens/launcher_screen.dart';
import 'ui/theme.dart';

/// Set once the root widget is up; keeps the watchdog and a late-arriving
/// bootstrap result from calling [runApp] a second time.
bool _didRunApp = false;

/// The startup watchdog, cancelled as soon as any [runApp] call wins.
Timer? _startupWatchdog;

/// Runs [app] exactly once — the first caller wins, later callers are no-ops.
void _runAppOnce(Widget app) {
  _startupWatchdog?.cancel();
  if (_didRunApp) return;
  _didRunApp = true;
  runApp(app);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Watchdog: every awaited startup step has its own timeout, so this should
  // never fire. But if a Future ever stalls beneath that layer (a plugin that
  // never answers its channel, a wedged engine), the user still gets a real
  // screen instead of an endless splash.
  _startupWatchdog = Timer(const Duration(seconds: 15), () {
    debugPrint('startup watchdog: bootstrap did not finish within 15s');
    _runAppOnce(
      const StartupFailureApp(error: 'startup watchdog: bootstrap exceeded 15s'),
    );
  });

  // Startup touches the database and the network. If anything throws there, a
  // bare exception would leave the splash screen spinning forever with no
  // explanation, so failures are reported on screen instead.
  try {
    await _bootstrap();
  } catch (error, stack) {
    debugPrint('startup failed: $error\n$stack');
    _runAppOnce(StartupFailureApp(error: error));
  }
}

Future<void> _bootstrap() async {
  // The web engine does not implement orientation locking; on some desktop
  // browsers the underlying platform channel can stall, so skip it entirely
  // on the web.
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  try {
    await initDatabaseFactoryForPlatform().timeout(const Duration(seconds: 3));
  } catch (error, stack) {
    debugPrint('db factory init failed (continuing): $error\n$stack');
  }

  final settings = Settings();
  // Storage can be blocked in some browsers (private mode, sandboxed iframes,
  // hardened cookie settings) and SharedPreferences.getInstance() can stall
  // there. Booting with the defaults is always better than not booting; the
  // preferences simply do not persist for that session.
  try {
    await settings.load().timeout(const Duration(seconds: 3));
  } catch (error, stack) {
    debugPrint('settings.load failed (using defaults): $error\n$stack');
  }

  // First-run CSV import. A missing or stalled asset must not take startup
  // down: the importer already skips bad files itself, and this outer timeout
  // bounds the whole import so a slow connection boots with partial data
  // instead of hanging. The launch sync fills any gaps after the first frame.
  try {
    await Importer.importAllIfNeeded().timeout(const Duration(seconds: 3));
  } catch (error, stack) {
    debugPrint('seed import failed (starting empty): $error\n$stack');
  }

  final history = <String, List<PriceRow>>{};
  for (final symbol in kSymbols) {
    try {
      history[symbol.id] = await AppDb.pricesForSymbol(symbol.id)
          .timeout(const Duration(seconds: 3));
    } catch (error, stack) {
      debugPrint('pricesForSymbol(${symbol.id}) failed: $error\n$stack');
      history[symbol.id] = const <PriceRow>[];
    }
  }

  final calculator = Calculator(history);

  /// Fetches every symbol, reloads the in-memory archive, tells the tools
  /// that the prices changed, and appends/refreshes the value snapshot.
  /// Returns the per-symbol results so the launch sync can distinguish
  /// success from a fully failed run.
  Future<List<SymbolUpdateResult>> updatePrices() async {
    final updater = Updater();
    final results = await updater.updateAll();
    if (results.any((r) => r.ok)) {
      await settings.setLastUpdate(DateTime.now());
    }
    for (final symbol in kSymbols) {
      history[symbol.id] = await AppDb.pricesForSymbol(symbol.id);
    }
    calculator.markPricesChanged();

    // The snapshot is local and small; a failure here must never turn a
    // successful price refresh into an error for the user.
    try {
      final store = createPortfolioStore();
      try {
        final txs = await store.transactions();
        await capturePortfolioSnapshot(
          store: store,
          txs: txs,
          history: history,
          basis: settings.basis,
        );
      } finally {
        await store.close();
      }
    } catch (error) {
      debugPrint('portfolio snapshot failed: $error');
    }
    return results;
  }

  Future<void> refresh() async {
    await updatePrices();
  }

  // Always reached: every await above is either bounded by a timeout or
  // wrapped in a try/catch, so data loading can no longer block the first
  // frame (and the `flutter-first-frame` event that removes the HTML splash).
  // `history` may be empty after a fully failed import; the UI renders empty
  // states and the background sync repopulates the data.
  _runAppOnce(
    MontalaApp(
      settings: settings,
      calculator: calculator,
      refreshData: refresh,
      backgroundUpdate: updatePrices,
    ),
  );
}

class MontalaApp extends StatefulWidget {
  final Settings settings;
  final Calculator calculator;
  final Future<void> Function() refreshData;

  /// Runs once, after the first frame, when [Settings.autoUpdate] is on.
  final Future<List<SymbolUpdateResult>> Function()? backgroundUpdate;

  const MontalaApp({
    super.key,
    required this.settings,
    required this.calculator,
    required this.refreshData,
    this.backgroundUpdate,
  });

  @override
  State<MontalaApp> createState() => _MontalaAppState();
}

class _MontalaAppState extends State<MontalaApp> {
  PriceSyncController? _sync;

  @override
  void initState() {
    super.initState();
    final run = widget.backgroundUpdate;
    if (!widget.settings.autoUpdate || run == null) return;
    final sync = PriceSyncController(run: run);
    _sync = sync;
    // Never await here: runApp and the first frame are already done, and the
    // sync must not delay painting the launcher.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      sync.start();
    });
  }

  @override
  void dispose() {
    _sync?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      settings: widget.settings,
      calculator: widget.calculator,
      refreshData: widget.refreshData,
      child: AnimatedBuilder(
        animation: widget.settings,
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
                child: _SyncShell(
                  sync: _sync,
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
            home: const LauncherScreen(),
          );
        },
      ),
    );
  }
}

/// Thin, quiet progress strip shown while the launch sync runs. It overlays
/// the top edge of the app bar, so nothing shifts when it appears or clears.
class _SyncShell extends StatelessWidget {
  final PriceSyncController? sync;
  final Widget child;

  const _SyncShell({required this.sync, required this.child});

  @override
  Widget build(BuildContext context) {
    final controller = sync;
    if (controller == null) return child;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.state.running) return child;
        return Stack(
          children: [
            child,
            Positioned(
              top: MediaQuery.of(context).padding.top,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Semantics(
                  label: 'به‌روزرسانی قیمت‌ها',
                  child: const SizedBox(
                    height: 2,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
