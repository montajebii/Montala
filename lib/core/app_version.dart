/// In-app version strings.
///
/// Kept in sync with `pubspec.yaml` by `tools/release.py`; the test
/// `test/version_consistency_test.dart` fails if they ever drift.
library;

/// Semantic version, without the Android build number, e.g. `1.2.0`.
const String kAppVersion = '1.2.1';

/// Same version with Persian digits and the Persian decimal separator, for UI.
const String kAppVersionFa = '۱٫۲٫۱';
