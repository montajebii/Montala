/// Estimates a sell price for a date that has no recorded trading data yet.
///
/// Deliberately simple and explainable — no machine learning. Two signals are
/// combined:
///  * a log-linear least-squares trend fitted to the recent window, which
///    captures compounding growth, and
///  * the window's median daily log-return, projected forward.
/// The two are averaged (geometric mean of the growth factors) and the result
/// is always labelled as an estimate in the UI.
library;

import 'dart:math' as math;

import '../models.dart';

/// How many trailing trading rows the trend is fitted on.
const int kForecastWindow = 180;

/// Returns the estimated price for [target] given [history] (ascending dates,
/// all on or before the last known trading day).
///
/// Returns null when there is not enough history to say anything useful.
double? estimateFuturePrice(
  List<PriceRow> history,
  DateTime target, {
  PriceBasis basis = PriceBasis.close,
  int window = kForecastWindow,
}) {
  if (history.length < 30) return null;

  final tail = history.length > window
      ? history.sublist(history.length - window)
      : history;

  final last = tail.last;
  final daysAhead = target.difference(last.date).inDays;
  if (daysAhead <= 0) return last.byBasis(basis).toDouble();

  final int n = tail.length;
  // x = days since first row of the window, y = ln(price)
  final origin = tail.first.date;
  var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumXX = 0.0;
  var prevPrice = 0.0;
  var prevDate = tail.first.date;
  final logReturns = <double>[];

  for (var i = 0; i < n; i++) {
    final row = tail[i];
    final x = row.date.difference(origin).inDays.toDouble();
    final p = row.byBasis(basis);
    if (p <= 0) return null;
    final y = math.log(p);
    sumX += x;
    sumY += y;
    sumXY += x * y;
    sumXX += x * x;
    if (i > 0) {
      final dt = row.date.difference(prevDate).inDays;
      if (dt > 0 && prevPrice > 0) {
        logReturns.add((y - math.log(prevPrice)) / dt);
      }
    }
    prevPrice = p.toDouble();
    prevDate = row.date;
  }

  final denom = n * sumXX - sumX * sumX;
  if (denom == 0) return null;
  final slope = (n * sumXY - sumX * sumY) / denom;
  final intercept = (sumY - slope * sumX) / n;

  // Signal 1: log-linear trend extrapolated to the target day.
  final xTarget = target.difference(origin).inDays.toDouble();
  final trendPrice = math.exp(intercept + slope * xTarget);

  // Signal 2: median daily log-return compounded forward.
  double medianPrice;
  if (logReturns.isEmpty) {
    medianPrice = trendPrice;
  } else {
    logReturns.sort();
    final mid = logReturns.length ~/ 2;
    final med = logReturns.length.isEven
        ? (logReturns[mid - 1] + logReturns[mid]) / 2
        : logReturns[mid];
    medianPrice = last.byBasis(basis) * math.exp(med * daysAhead);
  }

  // Geometric mean of the two growth paths, guarded against absurd results.
  final blended = math.sqrt(trendPrice * medianPrice);
  final lastPrice = last.byBasis(basis).toDouble();
  // Cap the estimate to a 10x..0.1x band over a year-scaled horizon so a bad
  // fit cannot produce a nonsense number.
  final years = daysAhead / 365.0;
  final maxFactor = math.pow(10.0, math.max(0.5, years * 2)).toDouble();
  final minFactor = 1 / maxFactor;
  return blended.clamp(lastPrice * minFactor, lastPrice * maxFactor);
}

/// Least-squares log growth rate per day over the trailing window.
/// Used by the UI to show "روند رشد" next to an estimate.
double dailyGrowthRate(
  List<PriceRow> history, {
  PriceBasis basis = PriceBasis.close,
  int window = kForecastWindow,
}) {
  if (history.length < 2) return 0;
  final tail = history.length > window
      ? history.sublist(history.length - window)
      : history;
  final origin = tail.first.date;
  final n = tail.length;
  var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumXX = 0.0;
  for (final row in tail) {
    final p = row.byBasis(basis);
    if (p <= 0) return 0;
    final x = row.date.difference(origin).inDays.toDouble();
    final y = math.log(p.toDouble());
    sumX += x;
    sumY += y;
    sumXY += x * y;
    sumXX += x * x;
  }
  final denom = n * sumXX - sumX * sumX;
  if (denom == 0) return 0;
  return (n * sumXY - sumX * sumY) / denom;
}
