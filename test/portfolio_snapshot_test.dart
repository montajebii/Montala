/// Tests for the value-history capture: dedupe by unchanged total, append on
/// change, canonical line order, and the empty-portfolio case.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/models.dart';
import 'package:montala/core/portfolio/portfolio_models.dart';
import 'package:montala/core/portfolio/portfolio_snapshot.dart';
import 'package:montala/core/portfolio/portfolio_store_web_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

PriceRow _row(DateTime date, int close) => PriceRow(
      date: date,
      persianDate: '',
      open: close,
      low: close,
      high: close,
      close: close,
    );

Future<PrefsPortfolioStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = PrefsPortfolioStore();
  await store.addTransaction(PortfolioTx(
    timestamp: DateTime(2026, 1, 1),
    assetId: 'sekee',
    type: 'BUY',
    units: 1,
    unitPriceToman: 100,
    totalToman: 100,
  ));
  return store;
}

void main() {
  test('an unchanged total only moves the timestamp', () async {
    final store = await _store();
    final history = <String, List<PriceRow>>{
      'sekee': [_row(DateTime(2026, 11, 1), 100)],
    };

    final first = await capturePortfolioSnapshot(
      store: store,
      txs: await store.transactions(),
      history: history,
      basis: PriceBasis.close,
      now: DateTime(2026, 11, 20, 16, 0),
    );
    final second = await capturePortfolioSnapshot(
      store: store,
      txs: await store.transactions(),
      history: history,
      basis: PriceBasis.close,
      now: DateTime(2026, 11, 20, 17, 30),
    );

    final snaps = await store.snapshots();
    expect(snaps.length, 1);
    expect(snaps.single.id, first!.id);
    expect(second!.timestamp, DateTime(2026, 11, 20, 17, 30));
    expect(snaps.single.timestamp, DateTime(2026, 11, 20, 17, 30));
    expect(snaps.single.totalToman, 100);
    expect(snaps.single.source, 'launch');
  });

  test('a changed total appends a row', () async {
    final store = await _store();
    var history = <String, List<PriceRow>>{
      'sekee': [_row(DateTime(2026, 11, 1), 100)],
    };
    await capturePortfolioSnapshot(
      store: store,
      txs: await store.transactions(),
      history: history,
      basis: PriceBasis.close,
      now: DateTime(2026, 11, 20, 16, 0),
    );

    history['sekee'] = [_row(DateTime(2026, 11, 21), 110)];
    final second = await capturePortfolioSnapshot(
      store: store,
      txs: await store.transactions(),
      history: history,
      basis: PriceBasis.close,
      source: 'recalc',
      now: DateTime(2026, 11, 21, 9, 0),
    );

    final snaps = await store.snapshots();
    expect(snaps.length, 2);
    expect(snaps.first.totalToman, 100);
    expect(second!.totalToman, 110);
    expect(second.source, 'recalc');
    expect(snaps.last.id, second.id);
  });

  test('the dedupe tolerance is relative (1e-9)', () async {
    final store = await _store();
    var history = <String, List<PriceRow>>{
      'sekee': [_row(DateTime(2026, 11, 1), 1000000000)],
    };
    await capturePortfolioSnapshot(
      store: store,
      txs: await store.transactions(),
      history: history,
      basis: PriceBasis.close,
      now: DateTime(2026, 11, 20, 16, 0),
    );

    // One Toman on 1e9 is exactly the relative epsilon → deduped.
    history['sekee'] = [_row(DateTime(2026, 11, 21), 1000000001)];
    await capturePortfolioSnapshot(
      store: store,
      txs: await store.transactions(),
      history: history,
      basis: PriceBasis.close,
      now: DateTime(2026, 11, 21, 9, 0),
    );
    expect((await store.snapshots()).length, 1);

    // A clearly different price appends.
    history['sekee'] = [_row(DateTime(2026, 11, 22), 1010000000)];
    await capturePortfolioSnapshot(
      store: store,
      txs: await store.transactions(),
      history: history,
      basis: PriceBasis.close,
      now: DateTime(2026, 11, 22, 9, 0),
    );
    expect((await store.snapshots()).length, 2);
  });

  test('snapshot lines follow the canonical symbol order', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrefsPortfolioStore();
    await store.addTransaction(PortfolioTx(
      timestamp: DateTime(2026, 1, 1),
      assetId: 'gold18',
      type: 'BUY',
      units: 2,
      unitPriceToman: 10,
      totalToman: 20,
    ));
    await store.addTransaction(PortfolioTx(
      timestamp: DateTime(2026, 1, 1),
      assetId: 'sekee',
      type: 'BUY',
      units: 1,
      unitPriceToman: 50,
      totalToman: 50,
    ));
    final history = <String, List<PriceRow>>{
      'sekee': [_row(DateTime(2026, 11, 1), 50)],
      'gold18': [_row(DateTime(2026, 11, 1), 10)],
    };
    final saved = await capturePortfolioSnapshot(
      store: store,
      txs: await store.transactions(),
      history: history,
      basis: PriceBasis.close,
      now: DateTime(2026, 11, 20, 16, 0),
    );
    expect(saved!.lines.map((l) => l.assetId), ['gold18', 'sekee']);
    expect(saved.totalToman, 70);
  });

  test('nothing held → no snapshot', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrefsPortfolioStore();
    final saved = await capturePortfolioSnapshot(
      store: store,
      txs: const [],
      history: const {},
      basis: PriceBasis.close,
      now: DateTime(2026, 11, 20),
    );
    expect(saved, isNull);
    expect(await store.snapshots(), isEmpty);
  });
}
