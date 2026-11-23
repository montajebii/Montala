/// Round-trip tests for both portfolio stores: the native SQLite one (through
/// the real sqflite_ffi factory, like the smoke test) and the web
/// SharedPreferences one (through the shared_preferences mock).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/portfolio/portfolio_models.dart';
import 'package:montala/core/portfolio/portfolio_store.dart';
import 'package:montala/core/portfolio/portfolio_store_io.dart';
import 'package:montala/core/portfolio/portfolio_store_web_io.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'portfolio_test_helpers.dart';

PortfolioTx _tx(
  DateTime date,
  String asset,
  String type,
  double units,
  double price,
) =>
    PortfolioTx(
      date: date,
      assetId: asset,
      type: type,
      units: units,
      unitPriceToman: price,
    );

void main() {
  group('SqlitePortfolioStore (native backend)', () {
    late PortfolioStore store;

    setUpAll(() async {
      await initTestDatabaseFactory();
    });

    setUp(() async {
      store = createPortfolioStore();
      await store.replaceAll(const []);
      await store.replaceAllSnapshots(const []);
    });

    tearDown(() => store.close());

    test('add, read back ordered, update, delete', () async {
      final a = await store.addTransaction(_tx(
        DateTime(2026, 1, 5), 'sekee', 'BUY', 1, 100000000,
      ));
      final b = await store.addTransaction(_tx(
        DateTime(2026, 1, 2), 'gold18', 'BUY', 3.5, 10000000,
      ));
      expect(b.id, isNotNull);

      var txs = await store.transactions();
      expect(txs.length, 2);
      // Ordered by date ascending regardless of insert order.
      expect(txs.first.assetId, 'gold18');

      await store.updateTransaction(
        b.copyWith(units: 4, note: 'تعدیل'),
      );
      txs = await store.transactions();
      final updated = txs.firstWhere((t) => t.id == b.id);
      expect(updated.units, 4);
      expect(updated.note, 'تعدیل');

      await store.deleteTransaction(a.id!);
      txs = await store.transactions();
      expect(txs.length, 1);
      expect(txs.first.assetId, 'gold18');
    });

    test('replaceAll wipes and re-inserts', () async {
      await store.addTransaction(_tx(
        DateTime(2026, 1, 5), 'sekee', 'BUY', 1, 100000000,
      ));
      await store.replaceAll([
        _tx(DateTime(2026, 2, 1), 'gold24', 'BUY', 10, 30000000),
        _tx(DateTime(2026, 2, 2), 'gold24', 'SELL', 4, 31000000),
      ]);
      final txs = await store.transactions();
      expect(txs.length, 2);
      expect(txs.map((t) => t.type), ['BUY', 'SELL']);
    });

    test('v1 database upgrades without losing rows or ids', () async {
      final dir = await Directory.systemTemp.createTemp('montala_migrate');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'montala_portfolio.db');
      final v1 = await openDatabase(path, version: 1, onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE portfolio_transactions (
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
          'CREATE INDEX idx_ptx_date ON portfolio_transactions(date)',
        );
        await db.insert('portfolio_transactions', {
          'date': '2026-01-05',
          'asset_id': 'sekee',
          'type': 'BUY',
          'units': 1,
          'unit_price_toman': 100000000,
          'note': 'پس‌تاریخ',
        });
        await db.insert('portfolio_transactions', {
          'date': '2026-02-01',
          'asset_id': 'gold18',
          'type': 'SELL',
          'units': 3.5,
          'unit_price_toman': 25000000.5,
          'note': null,
        });
      });
      await v1.close();

      final migrated = SqlitePortfolioStore(databasePath: path);
      addTearDown(() => migrated.close());
      final txs = await migrated.transactions();
      expect(txs.length, 2);
      expect(txs.map((t) => t.id), [1, 2]);
      expect(txs.first.timestamp, DateTime(2026, 1, 5));
      expect(txs.first.assetId, 'sekee');
      expect(txs.first.note, 'پس‌تاریخ');
      expect(txs.first.totalToman, 100000000);
      expect(txs.first.source, 'legacy');
      expect(txs.first.incomplete, isFalse);
      expect(txs.last.unitPriceToman, 25000000.5);
      expect(txs.last.totalToman, 87500001.75);
    });

    test('snapshots: add, read back, move timestamp, replace all', () async {
      final a = await store.addSnapshot(PortfolioSnapshot(
        timestamp: DateTime(2026, 11, 20, 16, 50, 13),
        lines: const [
          SnapshotLine(assetId: 'sekee', units: 1, valueToman: 100),
          SnapshotLine(assetId: 'gold18', units: 5.98, valueToman: 200),
        ],
        totalToman: 300,
        source: 'launch',
      ));
      expect(a.id, isNotNull);
      await store.addSnapshot(PortfolioSnapshot(
        timestamp: DateTime(2026, 11, 21, 9, 0),
        lines: const [
          SnapshotLine(assetId: 'sekee', units: 1, valueToman: 110),
        ],
        totalToman: 110,
        source: 'recalc',
      ));

      var snaps = await store.snapshots();
      expect(snaps.length, 2);
      expect(snaps.first.lineFor('gold18')!.valueToman, 200);
      expect(snaps.last.totalToman, 110);

      await store.updateSnapshotTimestamp(a.id!, DateTime(2026, 11, 20, 17, 0));
      snaps = await store.snapshots();
      expect(snaps.first.timestamp, DateTime(2026, 11, 20, 17, 0));
      expect(snaps.length, 2);

      await store.replaceAllSnapshots([
        PortfolioSnapshot(
          timestamp: DateTime(2026, 11, 22, 10, 0),
          lines: const [SnapshotLine(assetId: 'sekee', units: 2, valueToman: 220)],
          totalToman: 220,
          source: 'import',
        ),
      ]);
      snaps = await store.snapshots();
      expect(snaps.length, 1);
      expect(snaps.single.id, 1);
      expect(snaps.single.totalToman, 220);
      expect(snaps.single.source, 'import');
    });
  });

  group('PrefsPortfolioStore (web backend, via mock prefs)', () {
    late PortfolioStore store;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      store = PrefsPortfolioStore();
    });

    test('persists across store instances', () async {
      await store.addTransaction(_tx(
        DateTime(2026, 1, 5), 'sekee', 'BUY', 1, 100000000,
      ));

      // A fresh instance re-reads from preferences — the reload path.
      final second = PrefsPortfolioStore();
      final txs = await second.transactions();
      expect(txs.length, 1);
      expect(txs.first.assetId, 'sekee');
      expect(txs.first.units, 1);
    });

    test('add / update / delete / replaceAll', () async {
      final a = await store.addTransaction(_tx(
        DateTime(2026, 1, 5), 'sekee', 'BUY', 1, 100000000,
      ));
      await store.updateTransaction(a.copyWith(units: 2));
      expect((await store.transactions()).single.units, 2);

      await store.replaceAll([
        _tx(DateTime(2026, 3, 1), 'gold18', 'BUY', 5, 11000000),
      ]);
      expect((await store.transactions()).single.assetId, 'gold18');

      await store.deleteTransaction(1);
      expect(await store.transactions(), isEmpty);
    });

    test('v1 document migrates to v2, preserving ids and data', () async {
      SharedPreferences.setMockInitialValues({
        'portfolio_transactions_v1': jsonEncode([
          {
            'id': 7,
            'date': '2026-01-05',
            'asset': 'sekee',
            'type': 'BUY',
            'units': 1,
            'unit_price_toman': 100000000,
            'note': 'از نسخه اول',
          },
          {
            'id': 9,
            'date': '2026-02-01',
            'asset': 'gold18',
            'type': 'SELL',
            'units': 2,
            'unit_price_toman': 20000000,
          },
        ]),
      });
      final migrated = PrefsPortfolioStore();
      final txs = await migrated.transactions();
      expect(txs.length, 2);
      expect(txs.map((t) => t.id), [7, 9]);
      expect(txs.first.timestamp, DateTime(2026, 1, 5));
      expect(txs.first.totalToman, 100000000);
      expect(txs.first.source, 'legacy');
      expect(txs.first.note, 'از نسخه اول');

      final prefs = await SharedPreferences.getInstance();
      // The verified v2 document exists and the old key is gone.
      expect(prefs.getString(PrefsPortfolioStore.keyV2), isNotNull);
      expect(prefs.getString(PrefsPortfolioStore.keyV1), isNull);

      final fresh = PrefsPortfolioStore();
      expect((await fresh.transactions()).length, 2);
    });

    test('snapshots persist across instances', () async {
      final saved = await store.addSnapshot(PortfolioSnapshot(
        timestamp: DateTime(2026, 11, 20, 16, 50, 13),
        lines: const [SnapshotLine(assetId: 'sekee', units: 1, valueToman: 100)],
        totalToman: 100,
        source: 'launch',
      ));
      await store.updateSnapshotTimestamp(
          saved.id!, DateTime(2026, 11, 20, 18, 0));

      final second = PrefsPortfolioStore();
      final snaps = await second.snapshots();
      expect(snaps.length, 1);
      expect(snaps.single.timestamp, DateTime(2026, 11, 20, 18, 0));
      expect(snaps.single.lineFor('sekee')!.units, 1);
    });
  });
}
