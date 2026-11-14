/// Native (Android / Windows / Linux) portfolio store: its own small SQLite
/// database, separate from the price archive so the two can evolve freely.
library;

import 'package:sqflite/sqflite.dart';

import '../db/db_path_io.dart';
import 'portfolio_models.dart';
import 'portfolio_store.dart';

class SqlitePortfolioStore implements PortfolioStore {
  static const dbName = 'montala_portfolio.db';
  Database? _database;

  Future<Database> get() async {
    if (_database != null) return _database!;
    final path = await resolveDatabasePath(dbName);
    _database = await openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS portfolio_transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date TEXT NOT NULL,
          asset_id TEXT NOT NULL,
          type TEXT NOT NULL,
          units REAL NOT NULL,
          unit_price_toman REAL NOT NULL,
          note TEXT
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ptx_date '
        'ON portfolio_transactions(date)',
      );
    });
    return _database!;
  }

  @override
  Future<List<PortfolioTx>> transactions() async {
    final db = await get();
    final maps = await db.query(
      'portfolio_transactions',
      orderBy: 'date ASC, id ASC',
    );
    return maps.map(PortfolioTx.fromDbMap).toList();
  }

  @override
  Future<PortfolioTx> addTransaction(PortfolioTx tx) async {
    final db = await get();
    final id = await db.insert('portfolio_transactions', tx.toDbMap());
    return tx.copyWith(id: id);
  }

  @override
  Future<void> updateTransaction(PortfolioTx tx) async {
    final db = await get();
    await db.update(
      'portfolio_transactions',
      tx.toDbMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [tx.id],
    );
  }

  @override
  Future<void> deleteTransaction(int id) async {
    final db = await get();
    await db.delete('portfolio_transactions', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> replaceAll(List<PortfolioTx> txs) async {
    final db = await get();
    await db.transaction((txn) async {
      await txn.delete('portfolio_transactions');
      final batch = txn.batch();
      for (final tx in txs) {
        batch.insert('portfolio_transactions', tx.toDbMap());
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

/// Factory used by the conditional import in `portfolio_store.dart`.
PortfolioStore createPlatformPortfolioStore() => SqlitePortfolioStore();
