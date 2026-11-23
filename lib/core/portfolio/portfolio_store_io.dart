/// Native (Android / Windows / Linux) portfolio store: its own small SQLite
/// database, separate from the price archive so the two can evolve freely.
///
/// Schema v2 adds full timestamps, explicit totals/source/incomplete flags and
/// the value-snapshot tables. The v1 → v2 upgrade runs inside sqflite's
/// version transaction, preserves every id, and verifies the copied rows
/// against the originals before dropping the old table — a mismatch aborts the
/// upgrade and leaves v1 untouched.
library;

import 'package:sqflite/sqflite.dart';

import '../db/db_path_io.dart';
import 'portfolio_models.dart';
import 'portfolio_store.dart';

class SqlitePortfolioStore implements PortfolioStore {
  static const dbName = 'montala_portfolio.db';
  static const schemaVersion = 2;

  /// Test seam: open an explicit database file (migration tests build a v1
  /// file in a temp directory). Null → the platform database directory.
  final String? databasePath;

  SqlitePortfolioStore({this.databasePath});

  Database? _database;

  Future<Database> get() async {
    if (_database != null) return _database!;
    final path = databasePath ?? await resolveDatabasePath(dbName);
    _database = await openDatabase(
      path,
      version: schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _database!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createTransactionTable(db);
    await _createSnapshotTables(db);
  }

  Future<void> _createTransactionTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS portfolio_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        asset_id TEXT NOT NULL,
        type TEXT NOT NULL,
        units REAL NOT NULL,
        unit_price_toman REAL NOT NULL,
        total_toman REAL NOT NULL,
        source TEXT NOT NULL DEFAULT 'manual',
        note TEXT,
        incomplete INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ptx_timestamp '
      'ON portfolio_transactions(timestamp)',
    );
  }

  Future<void> _createSnapshotTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS portfolio_snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        total_toman REAL NOT NULL,
        source TEXT NOT NULL DEFAULT 'launch'
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_psnap_timestamp '
      'ON portfolio_snapshots(timestamp)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS portfolio_snapshot_lines (
        snapshot_id INTEGER NOT NULL,
        asset_id TEXT NOT NULL,
        units REAL NOT NULL,
        value_toman REAL NOT NULL,
        PRIMARY KEY (snapshot_id, asset_id)
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion >= 2) return;

    // Read the complete v1 table first: the verification below compares every
    // preserved field, not just the row count.
    final before = await db.query('portfolio_transactions');
    final byId = <int, Map<String, Object?>>{
      for (final row in before) row['id'] as int: row,
    };

    await db.execute('DROP INDEX IF EXISTS idx_ptx_date');
    await db.execute(
      'ALTER TABLE portfolio_transactions RENAME TO portfolio_transactions_v1',
    );
    await _createTransactionTable(db);

    final batch = db.batch();
    for (final row in before) {
      final units = (row['units'] as num).toDouble();
      final price = (row['unit_price_toman'] as num).toDouble();
      final total = units * price;
      final date = parsePortfolioTimestamp(row['date'] as String?) ??
          DateTime.now();
      batch.insert('portfolio_transactions', {
        'id': row['id'],
        'timestamp': formatPortfolioTimestamp(date),
        'asset_id': row['asset_id'],
        'type': row['type'],
        'units': units,
        'unit_price_toman': price,
        'total_toman': total,
        'source': 'legacy',
        'note': row['note'],
        'incomplete': price > 0 ? 0 : 1,
      });
    }
    await batch.commit(noResult: true);

    final after = await db.query('portfolio_transactions');
    if (after.length != byId.length) {
      throw StateError(
        'portfolio migration failed: ${byId.length} rows in, '
        '${after.length} rows out',
      );
    }
    for (final row in after) {
      final old = byId[row['id']];
      if (old == null) {
        throw StateError(
          'portfolio migration failed: id ${row['id']} was not preserved',
        );
      }
      for (final key in ['asset_id', 'type', 'units', 'unit_price_toman',
        'note']) {
        if (old[key] != row[key]) {
          throw StateError(
            'portfolio migration failed: id ${row['id']} field $key changed',
          );
        }
      }
    }

    await db.execute('DROP TABLE portfolio_transactions_v1');
    await _createSnapshotTables(db);
  }

  @override
  Future<List<PortfolioTx>> transactions() async {
    final db = await get();
    final maps = await db.query(
      'portfolio_transactions',
      orderBy: 'timestamp ASC, id ASC',
    );
    return maps.map(PortfolioTx.fromDbMap).toList();
  }

  @override
  Future<PortfolioTx> addTransaction(PortfolioTx tx) async {
    final db = await get();
    final id = await db.insert(
      'portfolio_transactions',
      tx.toDbMap()..remove('id'),
    );
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
      await txn.rawDelete(
        "DELETE FROM sqlite_sequence WHERE name = 'portfolio_transactions'",
      );
      final batch = txn.batch();
      for (final tx in txs) {
        batch.insert(
          'portfolio_transactions',
          tx.toDbMap()..remove('id'),
        );
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<List<PortfolioSnapshot>> snapshots() async {
    final db = await get();
    final rows = await db.query(
      'portfolio_snapshots',
      orderBy: 'timestamp ASC, id ASC',
    );
    final lineRows = await db.query(
      'portfolio_snapshot_lines',
      orderBy: 'snapshot_id ASC, asset_id ASC',
    );
    final lines = <int, List<SnapshotLine>>{};
    for (final row in lineRows) {
      final snapshotId = row['snapshot_id'] as int;
      lines.putIfAbsent(snapshotId, () => []).add(SnapshotLine(
            assetId: row['asset_id'] as String,
            units: (row['units'] as num).toDouble(),
            valueToman: (row['value_toman'] as num).toDouble(),
          ));
    }
    return [
      for (final row in rows)
        PortfolioSnapshot(
          id: row['id'] as int,
          timestamp: parsePortfolioTimestamp(row['timestamp'] as String?) ??
              DateTime.now(),
          lines: lines[row['id'] as int] ?? const [],
          totalToman: (row['total_toman'] as num).toDouble(),
          source: (row['source'] as String?) ?? 'launch',
        ),
    ];
  }

  @override
  Future<PortfolioSnapshot> addSnapshot(PortfolioSnapshot snapshot) async {
    final db = await get();
    final id = await db.transaction((txn) async {
      final snapshotId = await txn.insert('portfolio_snapshots', {
        'timestamp': formatPortfolioTimestamp(snapshot.timestamp),
        'total_toman': snapshot.totalToman,
        'source': snapshot.source,
      });
      final batch = txn.batch();
      for (final line in snapshot.lines) {
        batch.insert('portfolio_snapshot_lines', {
          'snapshot_id': snapshotId,
          'asset_id': line.assetId,
          'units': line.units,
          'value_toman': line.valueToman,
        });
      }
      await batch.commit(noResult: true);
      return snapshotId;
    });
    return snapshot.copyWith(id: id);
  }

  @override
  Future<void> updateSnapshotTimestamp(int id, DateTime timestamp) async {
    final db = await get();
    await db.update(
      'portfolio_snapshots',
      {'timestamp': formatPortfolioTimestamp(timestamp)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> replaceAllSnapshots(List<PortfolioSnapshot> snapshots) async {
    final db = await get();
    await db.transaction((txn) async {
      await txn.delete('portfolio_snapshot_lines');
      await txn.delete('portfolio_snapshots');
      await txn.rawDelete(
        "DELETE FROM sqlite_sequence WHERE name = 'portfolio_snapshots'",
      );
      for (final snapshot in snapshots) {
        final id = await txn.insert('portfolio_snapshots', {
          'timestamp': formatPortfolioTimestamp(snapshot.timestamp),
          'total_toman': snapshot.totalToman,
          'source': snapshot.source,
        });
        final batch = txn.batch();
        for (final line in snapshot.lines) {
          batch.insert('portfolio_snapshot_lines', {
            'snapshot_id': id,
            'asset_id': line.assetId,
            'units': line.units,
            'value_toman': line.valueToman,
          });
        }
        await batch.commit(noResult: true);
      }
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
