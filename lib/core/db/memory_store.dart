/// In-memory price store for the web build.
///
/// The whole dataset is ~1.4 MB of CSV, so it is parsed once and kept in memory.
/// This avoids the wasm SQLite path entirely: that path needs an IndexedDB
/// filesystem shim (`sqlite3.wasm` + a shared worker) which fails opaquely in
/// some browsers, taking the whole app down at startup.
///
/// Updates still work: freshly fetched rows are merged into the in-memory table.
/// Nothing is persisted across reloads, so each page load re-seeds from the
/// bundled CSVs — which is exactly what the previous IndexedDB cache did on a
/// cold start, minus the failure modes.
library;

import '../models.dart';
import 'store_backend.dart';

class MemoryPriceStore implements PriceStoreBackend {
  /// symbol -> date ISO -> row. A map keyed by date gives us upsert semantics
  /// and deduplication for free.
  final Map<String, Map<String, PriceRow>> _tables = {};
  final Map<String, String> _meta = {};

  /// Sorted, cached views rebuilt lazily after a write.
  final Map<String, List<PriceRow>> _sortedCache = {};

  @override
  Future<void> upsertPrices(String symbol, List<PriceRow> rows) async {
    final table = _tables.putIfAbsent(symbol, () => {});
    for (final row in rows) {
      table[row.dateIso] = row;
    }
    _sortedCache.remove(symbol);
  }

  @override
  Future<List<PriceRow>> pricesForSymbol(String symbol) async {
    final cached = _sortedCache[symbol];
    if (cached != null) return cached;
    final table = _tables[symbol];
    if (table == null || table.isEmpty) return const [];
    final rows = table.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    _sortedCache[symbol] = rows;
    return rows;
  }

  @override
  Future<DateTime?> maxDate(String symbol) async {
    final rows = await pricesForSymbol(symbol);
    return rows.isEmpty ? null : rows.last.date;
  }

  @override
  Future<int> rowCount(String symbol) async =>
      (await pricesForSymbol(symbol)).length;

  @override
  Future<String?> metaGet(String key) async => _meta[key];

  @override
  Future<void> metaSet(String key, String value) async {
    _meta[key] = value;
  }

  @override
  Future<void> close() async {
    _tables.clear();
    _sortedCache.clear();
    _meta.clear();
  }

  @override
  Future<String> debugPath() async => 'memory:montala';
}

/// Factory used by the conditional import in `app_db.dart`.
PriceStoreBackend createPriceStore() => MemoryPriceStore();
