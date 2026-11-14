/// Portfolio valuation math — pure functions, no Flutter.
///
/// The design correction over m0ntIsRich's main.py: there are no appended
/// "snapshots". The units held at any date follow from the transaction log,
/// and the value follows from Montala's daily price archive, so the history
/// can be computed for any range — including before the user started using
/// the app.
library;

import 'package:flutter/foundation.dart';

import '../calc/calculator.dart';
import '../models.dart';
import 'portfolio_models.dart';

/// Value of the whole portfolio (and each asset) on one price date.
@immutable
class PortfolioPoint {
  final DateTime date;

  /// Total Toman value of everything that could be priced that day.
  final double totalToman;

  /// Per-asset values, Toman — only assets with a price on/before [date].
  final Map<String, double> valueByAsset;

  /// Per-asset units held that day (every asset with any transaction).
  final Map<String, double> unitsByAsset;

  const PortfolioPoint({
    required this.date,
    required this.totalToman,
    required this.valueByAsset,
    required this.unitsByAsset,
  });
}

/// Units held of each asset at [date] (inclusive of that day's trades).
Map<String, double> unitsAt(List<PortfolioTx> txs, DateTime date) {
  final units = <String, double>{};
  for (final tx in txs) {
    if (tx.date.isAfter(date)) continue;
    final signed = tx.isBuy ? tx.units : -tx.units;
    units[tx.assetId] = (units[tx.assetId] ?? 0) + signed;
  }
  return units;
}

/// Throws when [tx] would leave [assetId] with negative holdings considering
/// all other transactions (validation for the entry form). The transaction
/// being edited must not count itself — matched by identity or, when both
/// sides carry ids, by id.
void assertSellAllowed(
  List<PortfolioTx> existing,
  PortfolioTx tx,
) {
  if (tx.isBuy) return;
  final others = existing
      .where((t) =>
          !identical(t, tx) &&
          (tx.id == null || t.id != tx.id) &&
          t.assetId == tx.assetId)
      .toList();
  final units = unitsAt(others, tx.date)[tx.assetId] ?? 0;
  if (tx.units > units + 1e-9) {
    throw const PortfolioValidationException();
  }
}

class PortfolioValidationException implements Exception {
  const PortfolioValidationException();

  @override
  String toString() => 'فروش بیش از موجودی ممکن نیست';
}

/// Value series of the portfolio between [from] and [to], one point per
/// trading day that any held asset has a price row for. Units follow the
/// transaction log; prices snap to the nearest earlier trading day — the
/// same rule as `valueBasket`.
List<PortfolioPoint> portfolioSeries({
  required List<PortfolioTx> txs,
  required Map<String, List<PriceRow>> history,
  required PriceBasis basis,
  required DateTime from,
  required DateTime to,
}) {
  final day = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day);

  // All distinct price dates in range across held assets, ascending.
  final heldAssets = txs.map((t) => t.assetId).toSet();
  final dates = <String>{};
  for (final asset in heldAssets) {
    for (final row in history[asset] ?? const <PriceRow>[]) {
      final d = DateTime(row.date.year, row.date.month, row.date.day);
      if (d.isBefore(day) || d.isAfter(end)) continue;
      dates.add(_key(d));
    }
  }
  final sortedDates = dates.map(_parseKey).toList()..sort();

  // Units step-function per asset, driven by the transaction log.
  final txsByAsset = <String, List<PortfolioTx>>{};
  for (final tx in txs) {
    txsByAsset.putIfAbsent(tx.assetId, () => []).add(tx);
  }
  for (final list in txsByAsset.values) {
    list.sort((a, b) => a.date.compareTo(b.date));
  }

  final points = <PortfolioPoint>[];
  for (final date in sortedDates) {
    final valueByAsset = <String, double>{};
    final unitsNow = unitsAt(txs, date);
    var total = 0.0;
    for (final entry in unitsNow.entries) {
      final asset = entry.key;
      final units = entry.value;
      // Assets with (numerically) zero units don't contribute.
      if (units.abs() < 1e-12) continue;
      final row = rowOnOrBefore(history[asset] ?? const [], date);
      if (row == null) continue;
      final value = units * row.byBasis(basis);
      valueByAsset[asset] = value;
      total += value;
    }
    points.add(PortfolioPoint(
      date: date,
      totalToman: total,
      valueByAsset: valueByAsset,
      unitsByAsset: unitsNow,
    ));
  }
  return points;
}

/// Live valuation for "امروز": units now × the latest known price per asset.
PortfolioPoint? latestPoint({
  required List<PortfolioTx> txs,
  required Map<String, List<PriceRow>> history,
  required PriceBasis basis,
}) {
  final now = DateTime.now();
  final units = unitsAt(txs, now);
  if (units.isEmpty) return null;
  final valueByAsset = <String, double>{};
  var total = 0.0;
  var any = false;
  for (final entry in units.entries) {
    if (entry.value.abs() < 1e-12) continue;
    final rows = history[entry.key] ?? const <PriceRow>[];
    if (rows.isEmpty) continue;
    final price = rows.last.byBasis(basis);
    valueByAsset[entry.key] = entry.value * price;
    total += entry.value * price;
    any = true;
  }
  if (!any) return null;
  return PortfolioPoint(
    date: now,
    totalToman: total,
    valueByAsset: valueByAsset,
    unitsByAsset: units,
  );
}

/// First date that has any transaction (series start); null when empty.
DateTime? firstTxDate(List<PortfolioTx> txs) {
  if (txs.isEmpty) return null;
  return txs.map((t) => t.date).reduce((a, b) => a.isBefore(b) ? a : b);
}

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _parseKey(String k) {
  final parts = k.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}
