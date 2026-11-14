/// Round-trip tests for both portfolio stores: the native SQLite one (through
/// the real sqflite_ffi factory, like the smoke test) and the web
/// SharedPreferences one (through the shared_preferences mock).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/portfolio/portfolio_models.dart';
import 'package:montala/core/portfolio/portfolio_store.dart';
import 'package:montala/core/portfolio/portfolio_store_web_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });
}
