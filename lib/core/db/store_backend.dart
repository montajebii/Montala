/// Price storage contract.
///
/// Two backends implement it:
///  * `app_db_io.dart` — SQLite via sqflite (Android, Windows, Linux)
///  * `app_db_web.dart` — an in-memory table parsed from the bundled CSVs
///
/// The web backend is deliberately not SQLite: the wasm build needs an
/// IndexedDB filesystem shim that fails opaquely on some browsers, and the whole
/// dataset is only ~1.4 MB of CSV — small enough to hold in memory.
library;

import '../models.dart';

/// Storage operations the app needs. Implemented per platform.
///
/// A backend instance is created through the `createPriceStore()` factory that
/// each implementation file exposes.
abstract class PriceStoreBackend {
  Future<void> upsertPrices(String symbol, List<PriceRow> rows);

  /// Rows for [symbol] ordered by date ascending.
  Future<List<PriceRow>> pricesForSymbol(String symbol);

  Future<DateTime?> maxDate(String symbol);

  Future<int> rowCount(String symbol);

  Future<String?> metaGet(String key);

  Future<void> metaSet(String key, String value);

  Future<void> close();

  Future<String> debugPath();
}
