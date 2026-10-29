/// SQLite backend for Android, Windows and Linux.
///
/// The sqflite factory is selected once at startup (see db_factory_io.dart);
/// this class only talks to the sqflite API.
library;

import 'package:sqflite/sqflite.dart';

import '../models.dart';
import 'db_path_io.dart';
import 'store_backend.dart';

/// Concrete SQLite backend.
class SqlitePriceStore implements PriceStoreBackend {
  static const dbName = 'montala.db';
  Database? _database;

  /// Must be called after the platform factory is initialized.
  Future<Database> get() async {
    if (_database != null) return _database!;

    final path = await resolveDatabasePath(dbName);

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE prices (
            symbol TEXT NOT NULL,
            date TEXT NOT NULL,
            persian_date TEXT NOT NULL,
            open INTEGER NOT NULL,
            low INTEGER NOT NULL,
            high INTEGER NOT NULL,
            close INTEGER NOT NULL,
            PRIMARY KEY (symbol, date)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_prices_symbol_date ON prices(symbol, date)',
        );
        await db.execute('''
          CREATE TABLE meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }

  @override
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  /// Path of the on-disk database. Used by tests to start clean.
  @override
  Future<String> debugPath() => resolveDatabasePath(dbName);

  // ------------------ prices ------------------
  @override
  Future<void> upsertPrices(
    String symbol,
    List<PriceRow> rows,
  ) async {
    final db = await get();
    const chunkSize = 500;
    for (var i = 0; i < rows.length; i += chunkSize) {
      final chunk = rows.sublist(
        i,
        (i + chunkSize).clamp(0, rows.length),
      );
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final r in chunk) {
          batch.insert(
            'prices',
            r.toDbMap(symbol),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    }
  }

  /// Rows for a symbol ordered by date ascending. Optionally bounded.
  @override
  Future<List<PriceRow>> pricesForSymbol(
    String symbol, {
    String? fromIso,
    String? toIso,
  }) async {
    final db = await get();
    final where = StringBuffer('symbol = ?');
    final args = <Object>[symbol];
    if (fromIso != null) {
      where.write(' AND date >= ?');
      args.add(fromIso);
    }
    if (toIso != null) {
      where.write(' AND date <= ?');
      args.add(toIso);
    }
    final maps = await db.query(
      'prices',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'date ASC',
    );
    return maps.map(PriceRow.fromDbMap).toList();
  }

  @override
  Future<DateTime?> maxDate(String symbol) async {
    final db = await get();
    final rows = await db.rawQuery(
      'SELECT MAX(date) AS m FROM prices WHERE symbol = ?',
      [symbol],
    );
    final m = rows.first['m'] as String?;
    return m == null ? null : PriceRow.parseIso(m);
  }

  @override
  Future<int> rowCount(String symbol) async {
    final db = await get();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM prices WHERE symbol = ?',
      [symbol],
    );
    return rows.first['c'] as int;
  }

  // ------------------ meta ------------------
  @override
  Future<String?> metaGet(String key) async {
    final db = await get();
    final rows = await db.query(
      'meta',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  @override
  Future<void> metaSet(String key, String value) async {
    final db = await get();
    await db.insert(
      'meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

/// Factory used by the conditional import in `app_db.dart`.
PriceStoreBackend createPriceStore() => SqlitePriceStore();
