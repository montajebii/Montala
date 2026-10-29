/// Native (Android / Windows / Linux) sqflite factory bootstrap.
library;

import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Selects the right sqflite factory for the running OS.
///
/// Android keeps the bundled platform factory; Windows and Linux use the
/// FFI implementation backed by sqlite3_flutter_libs.
Future<void> initDatabaseFactoryForPlatform() async {
  if (Platform.isLinux || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
