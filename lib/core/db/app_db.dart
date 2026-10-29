/// Platform-agnostic price storage facade.
///
/// The concrete backend is chosen at compile time by the conditional import:
/// SQLite on Android/Windows/Linux, an in-memory table on the web. Callers never
/// need to know which one is active.
library;

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'memory_store.dart'
    if (dart.library.io) 'sqlite_store.dart' as platform;
import 'store_backend.dart';

class AppDb {
  static PriceStoreBackend? _backend;

  /// The active backend, created on first use.
  static PriceStoreBackend get _store => _backend ??= platform.createPriceStore();

  /// Drops the cached backend. Tests use this to start from a clean database.
  @visibleForTesting
  static void resetForTests() => _backend = null;

  static Future<void> upsertPrices(String symbol, List<PriceRow> rows) =>
      _store.upsertPrices(symbol, rows);

  static Future<List<PriceRow>> pricesForSymbol(String symbol) =>
      _store.pricesForSymbol(symbol);

  static Future<DateTime?> maxDate(String symbol) => _store.maxDate(symbol);

  static Future<int> rowCount(String symbol) => _store.rowCount(symbol);

  static Future<String?> metaGet(String key) => _store.metaGet(key);

  static Future<void> metaSet(String key, String value) =>
      _store.metaSet(key, value);

  static Future<void> close() async {
    await _store.close();
    _backend = null;
  }

  static Future<String> debugDatabasePath() => _store.debugPath();
}
