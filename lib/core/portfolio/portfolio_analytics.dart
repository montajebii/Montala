/// Portfolio analytics — ports of m0ntIsRich's trend/cost-basis analysis,
/// rewritten as pure Dart functions over the transaction log (the Python
/// version had to *infer* buys and sells from snapshot diffs; here they are
/// logged directly).
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'portfolio_models.dart';

/// Unrealized position of one asset, average-cost method.
@immutable
class AssetPosition {
  final String assetId;

  /// Units currently held.
  final double units;

  /// Average cost per unit of the currently held units, Toman.
  final double avgCostToman;

  /// Cost basis of the held units, Toman.
  final double costBasisToman;

  /// Current market value, Toman.
  final double marketValueToman;

  /// (market − cost) / cost × 100. Null when cost is zero.
  final double? roiPct;

  const AssetPosition({
    required this.assetId,
    required this.units,
    required this.avgCostToman,
    required this.costBasisToman,
    required this.marketValueToman,
    this.roiPct,
  });
}

/// Realized profit/loss of one SELL, valued with the average cost at the
/// moment of the sale.
@immutable
class RealizedSell {
  final PortfolioTx tx;

  /// (sellPrice − avgCost) × units, Toman. Positive = profit.
  final double pnlToman;

  const RealizedSell({required this.tx, required this.pnlToman});
}

/// Full position report: unrealized per asset + realized per sell.
@immutable
class PortfolioReport {
  final List<AssetPosition> positions;
  final List<RealizedSell> realizedSells;

  /// Sum of realized P/L over all sells, Toman.
  final double realizedPnlToman;

  const PortfolioReport({
    required this.positions,
    required this.realizedSells,
    required this.realizedPnlToman,
  });
}

/// Builds the report from the transaction log and the price archive.
PortfolioReport portfolioReport({
  required List<PortfolioTx> txs,
  required Map<String, List<PriceRow>> history,
  required PriceBasis basis,
}) {
  final ordered = [...txs]..sort((a, b) => a.date.compareTo(b.date));

  // Per-asset average-cost state.
  final units = <String, double>{};
  final cost = <String, double>{};
  final realized = <RealizedSell>[];
  var realizedTotal = 0.0;

  for (final tx in ordered) {
    final u = units[tx.assetId] ?? 0;
    final c = cost[tx.assetId] ?? 0.0;
    if (tx.isBuy) {
      units[tx.assetId] = u + tx.units;
      cost[tx.assetId] = c + tx.units * tx.unitPriceToman;
    } else {
      final avg = u > 0 ? c / u : 0.0;
      final pnl = (tx.unitPriceToman - avg) * tx.units;
      realized.add(RealizedSell(tx: tx, pnlToman: pnl));
      realizedTotal += pnl;
      units[tx.assetId] = u - tx.units;
      cost[tx.assetId] = c - avg * tx.units;
    }
  }

  final positions = <AssetPosition>[];
  for (final entry in units.entries) {
    final u = entry.value;
    if (u.abs() < 1e-9) continue;
    final c = cost[entry.key] ?? 0;
    final rows = history[entry.key] ?? const <PriceRow>[];
    if (rows.isEmpty) continue;
    final price = rows.last.byBasis(basis).toDouble();
    final value = u * price;
    positions.add(AssetPosition(
      assetId: entry.key,
      units: u,
      avgCostToman: c / u,
      costBasisToman: c,
      marketValueToman: value,
      roiPct: c != 0 ? (value - c) / c * 100 : null,
    ));
  }
  positions.sort((a, b) => b.marketValueToman.compareTo(a.marketValueToman));

  return PortfolioReport(
    positions: positions,
    realizedSells: realized,
    realizedPnlToman: realizedTotal,
  );
}

/// Simple moving average of [values] with window [window]; the head (shorter
/// than the window) is filled with nulls so the output aligns 1:1 with the
/// input — what MA(7)/MA(30)/MA(90) mean in `analyze_technical`.
List<double?> movingAverage(List<double> values, int window) {
  if (window <= 1) return [...values];
  final out = List<double?>.filled(values.length, null);
  var sum = 0.0;
  for (var i = 0; i < values.length; i++) {
    sum += values[i];
    if (i >= window) sum -= values[i - window];
    if (i >= window - 1) out[i] = sum / window;
  }
  return out;
}

/// Annualization-free daily volatility: the standard deviation of the last
/// [lookback] day-over-day percent changes, in percent.
double? volatilityPct(List<double> series, {int lookback = 30}) {
  if (series.length < 3) return null;
  final start = series.length > lookback ? series.length - lookback : 1;
  final returns = <double>[];
  for (var i = start; i < series.length; i++) {
    if (series[i - 1] == 0) continue;
    returns.add((series[i] - series[i - 1]) / series[i - 1] * 100);
  }
  if (returns.length < 2) return null;
  return _std(returns);
}

/// Indices of points whose z-score exceeds [threshold] — the anomaly hunt of
/// `analyze_technical` (z > 2).
List<int> zscoreAnomalies(List<double> series, {double threshold = 2}) {
  if (series.length < 3) return const [];
  final mean = series.fold(0.0, (a, b) => a + b) / series.length;
  final std = _std(series);
  if (std == 0) return const [];
  final hits = <int>[];
  for (var i = 0; i < series.length; i++) {
    if ((series[i] - mean).abs() / std > threshold) hits.add(i);
  }
  return hits;
}

double _std(List<double> xs) {
  final mean = xs.fold(0.0, (a, b) => a + b) / xs.length;
  final variance =
      xs.fold(0.0, (a, b) => a + (b - mean) * (b - mean)) / xs.length;
  return math.sqrt(variance);
}
