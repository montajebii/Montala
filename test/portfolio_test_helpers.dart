/// Shared helpers for the portfolio store tests.
library;

import 'package:montala/core/db/db_factory_native.dart';

/// Initializes the sqflite ffi factory so real SQLite works inside tests.
Future<void> initTestDatabaseFactory() => initDatabaseFactoryForPlatform();
