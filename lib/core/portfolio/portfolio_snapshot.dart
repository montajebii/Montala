/// Value-history capture for the portfolio tool.
///
/// A snapshot is the answer to "what was the portfolio worth at this instant":
/// units held from the transaction log × the latest price of each asset. It is
/// the in-app replacement for m0ntIsRich's appended `sarmaye_history.csv`
/// rows, but it is now derived on demand instead of being the only history.
///
/// Deduplication rule: when the new total matches the last snapshot within a
/// relative 1e-9 tolerance, only the timestamp moves forward (the value did
/// not change, so a new row would be noise). A changed total appends a row.
library;

import 'dart:math' as math;

import '../models.dart';
import '../symbols.dart';
import 'portfolio_calc.dart';
import 'portfolio_models.dart';
import 'portfolio_store.dart';

/// Builds and persists one snapshot. Returns the stored snapshot, or null when
/// nothing is held / no asset has a price.
Future<PortfolioSnapshot?> capturePortfolioSnapshot({
  required PortfolioStore store,
  required List<PortfolioTx> txs,
  required Map<String, List<PriceRow>> history,
  required PriceBasis basis,
  String source = 'launch',
  DateTime? now,
}) async {
  final point = latestPoint(txs: txs, history: history, basis: basis);
  if (point == null) return null;

  final timestamp = now ?? DateTime.now();
  final existing = await store.snapshots();
  final last = existing.isEmpty ? null : existing.last;

  if (last != null && _sameTotal(last.totalToman, point.totalToman)) {
    if (last.id == null) return last;
    await store.updateSnapshotTimestamp(last.id!, timestamp);
    return last.copyWith(timestamp: timestamp);
  }

  final snapshot = PortfolioSnapshot(
    timestamp: timestamp,
    lines: snapshotLines(point),
    totalToman: point.totalToman,
    source: source,
  );
  return store.addSnapshot(snapshot);
}

/// Asset lines in the app's canonical symbol order, skipping zero holdings.
List<SnapshotLine> snapshotLines(PortfolioPoint point) {
  final ordered = <SnapshotLine>[];
  for (final symbol in kSymbols) {
    final units = point.unitsByAsset[symbol.id] ?? 0;
    if (units.abs() < 1e-12) continue;
    ordered.add(SnapshotLine(
      assetId: symbol.id,
      units: units,
      valueToman: point.valueByAsset[symbol.id] ?? 0,
    ));
  }
  return ordered;
}

/// Relative equality with an absolute floor of 1e-9 Toman, so a zero-valued
/// portfolio and tiny totals behave sanely.
bool _sameTotal(double a, double b) {
  final scale = math.max(1.0, math.max(a.abs(), b.abs()));
  return (a - b).abs() <= 1e-9 * scale;
}
