/// About-screen tests: the support line and the donation link must render
/// inside the version card (RTL, 360×640 store-screenshot viewport), and
/// tapping the link must hand the donation URL to url_launcher — intercepted
/// through the plugin's platform interface, never a real network launch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/app_version.dart';
import 'package:montala/ui/screens/about_screen.dart';
import 'package:url_launcher_platform_interface/link.dart' show LinkDelegate;
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records launch requests; never touches the real platform.
class _RecordingLauncher extends UrlLauncherPlatform {
  final urls = <String>[];
  final modes = <PreferredLaunchMode>[];

  /// When set, launchUrl throws this instead of recording.
  Object? throwOnLaunch;

  /// Return value of a successful (non-throwing) launch.
  bool succeed = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    final thrown = throwOnLaunch;
    if (thrown != null) throw thrown;
    urls.add(url);
    modes.add(options.mode);
    return succeed;
  }
}

Widget _app() => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: const AboutScreen(),
      ),
    );

/// The version card with the donation block is the last child of a lazy
/// ListView, far below the 360×640 fold — scroll it into view before any
/// find/tap, dragging upward so the list reveals content below the viewport.
Future<void> _scrollToDonationBlock(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.text('حمایت از مُنتَلا'),
    find.byType(Scrollable),
    const Offset(0, -300),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    UrlLauncherPlatform.instance = _RecordingLauncher();
  });

  testWidgets('About screen shows the support line and donation link '
      'without overflowing on a 360×640 viewport', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _scrollToDonationBlock(tester);

    expect(find.text('با حمایت‌های متین❤️'), findsOneWidget);
    expect(find.text('حمایت از مُنتَلا'), findsOneWidget);
    // The support block sits under the version number.
    expect(find.text('نسخه $kAppVersionFa'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'the donation block must not overflow the narrow viewport');
  });

  testWidgets('tapping the donation link requests an external launch of '
      'https://daramet.com/m0nt', (tester) async {
    final launcher = _RecordingLauncher();
    UrlLauncherPlatform.instance = launcher;

    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _scrollToDonationBlock(tester);

    await tester.tap(find.text('حمایت از مُنتَلا'));
    await tester.pumpAndSettle();

    expect(launcher.urls, ['https://daramet.com/m0nt']);
    expect(launcher.modes, [PreferredLaunchMode.externalApplication]);
    // Success must not surface an error snack bar.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a thrown launch failure shows a Persian snack bar instead of '
      'throwing', (tester) async {
    final launcher = _RecordingLauncher()
      ..throwOnLaunch = Exception('no handler for https://daramet.com/m0nt');
    UrlLauncherPlatform.instance = launcher;

    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _scrollToDonationBlock(tester);

    await tester.tap(find.text('حمایت از مُنتَلا'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('افتتاح پیوند حمایت'), findsOneWidget);
    expect(launcher.urls, isEmpty,
        reason: 'the mock throws before recording, so nothing was attempted '
            'successfully');
  });

  testWidgets('launchUrl resolving to false shows a Persian snack bar '
      'instead of throwing', (tester) async {
    final launcher = _RecordingLauncher()..succeed = false;
    UrlLauncherPlatform.instance = launcher;

    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _scrollToDonationBlock(tester);

    await tester.tap(find.text('حمایت از مُنتَلا'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('افتتاح پیوند حمایت'), findsOneWidget);
    // The mock records the attempt even when it resolves to false — the
    // launch request with the donation URL is what this asserts.
    expect(launcher.urls, ['https://daramet.com/m0nt']);
    expect(launcher.modes, [PreferredLaunchMode.externalApplication]);
  });
}
