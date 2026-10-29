/// The "if I had bought X on date A and sold on date B" engine.
///
/// Rules (from the project brief):
///  * Buy leg uses the configured [PriceBasis] (default Open).
///  * Sell leg uses the configured basis (default Close).
///  * When a requested date has no data (weekend / holiday / future), the
///    nearest *earlier* trading day is used.
///  * A date in the future of the last recorded day is estimated by
///    [estimateFuturePrice] and flagged `estimated`.
library;

import 'dart:math' as math;

import '../models.dart';
import '../symbols.dart';
import 'forecast.dart';

/// How many days past the newest recorded row still count as "the same
/// trading period" rather than a future date needing a forecast.
///
/// Exchanges are shut at weekends and on holidays, so the newest candle is
/// routinely 1-3 days old. Anything beyond that is treated as a real forecast
/// request.
const int kNearTermToleranceDays = 5;

class CalcInput {
  final int amountRial;
  final DateTime buyDate;
  final DateTime sellDate;
  final PriceBasis basis;
  /// When false, each symbol gets the whole amount independently (so the
  /// numbers are comparable side by side). When true the amount is split
  /// equally across all symbols (a real portfolio).
  final bool splitAmount;

  const CalcInput({
    required this.amountRial,
    required this.buyDate,
    required this.sellDate,
    required this.basis,
    required this.splitAmount,
  });
}

/// Binary search for the last row whose date <= [target].
/// Returns null when every row is after [target].
PriceRow? rowOnOrBefore(List<PriceRow> rows, DateTime target) {
  if (rows.isEmpty) return null;
  var lo = 0, hi = rows.length - 1;
  PriceRow? found;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (!rows[mid].date.isAfter(target)) {
      found = rows[mid];
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return found;
}

class Calculator {
  final Map<String, List<PriceRow>> _history;

  Calculator(this._history);

  List<PriceRow> historyFor(String symbolId) => _history[symbolId] ?? const [];

  /// All results for [input], sorted best profit percent first.
  PortfolioResult run(CalcInput input) {
    final results = <SymbolCalcResult>[];
    for (final symbol in kSymbols) {
      results.add(_calcOne(symbol, input));
    }
    final usable = results.where((r) => r.hasResult).toList()
      ..sort((a, b) => (b.profitPercent ?? 0).compareTo(a.profitPercent ?? 0));
    final unusable = results.where((r) => !r.hasResult).toList()
      ..sort((a, b) => a.symbolId.compareTo(b.symbolId));
    return PortfolioResult(
      ranked: [...usable, ...unusable],
      calculatedAt: DateTime.now(),
    );
  }

  SymbolCalcResult _calcOne(AssetSymbol symbol, CalcInput input) {
    final rows = historyFor(symbol.id);
    final perSymbolRial = input.splitAmount
        ? input.amountRial ~/ math.max(1, kSymbols.length)
        : input.amountRial;

    final buyRow = rowOnOrBefore(rows, input.buyDate);
    if (buyRow == null) {
      // Bought before the series starts — nothing to show.
      return SymbolCalcResult(
        symbolId: symbol.id,
        tradableAtBuy: false,
        estimated: false,
        investedRial: perSymbolRial,
      );
    }

    final buyPrice = buyRow.byBasis(input.basis);
    if (buyPrice <= 0) {
      return SymbolCalcResult(
        symbolId: symbol.id,
        tradableAtBuy: false,
        estimated: false,
        investedRial: perSymbolRial,
      );
    }

    // Sell leg: recorded row, or an estimate if the date is beyond history.
    final lastRow = rows.last;
    final sellRow = rowOnOrBefore(rows, input.sellDate);
    // A requested date only a few days past the last recorded row is not a
    // forecast: exchanges close for weekends and holidays, so "today" routinely
    // sits 1-3 days beyond the newest candle. Treating that as a prediction
    // wrongly labels an entirely historical comparison as an estimate. Only a
    // genuinely distant date is forecast.
    final gapDays = input.sellDate.difference(lastRow.date).inDays;
    final sellIsFuture = gapDays > kNearTermToleranceDays;

    int? sellPrice;
    bool estimated = false;
    DateTime? sellDateUsed;

    if (sellIsFuture) {
      final est = estimateFuturePrice(
        rows,
        input.sellDate,
        basis: input.basis,
      );
      if (est == null) {
        return SymbolCalcResult(
          symbolId: symbol.id,
          tradableAtBuy: true,
          buyDateUsed: buyRow.date,
          buyPrice: buyPrice,
          estimated: false,
          investedRial: perSymbolRial,
        );
      }
      sellPrice = est.round();
      estimated = true;
      sellDateUsed = input.sellDate;
    } else {
      if (sellRow == null) {
        return SymbolCalcResult(
          symbolId: symbol.id,
          tradableAtBuy: true,
          buyDateUsed: buyRow.date,
          buyPrice: buyPrice,
          estimated: false,
          investedRial: perSymbolRial,
        );
      }
      sellPrice = sellRow.byBasis(input.basis);
      sellDateUsed = sellRow.date;
    }

    // Selling on/before the buy day is not a meaningful round trip; report the
    // buy leg only.
    if (!sellDateUsed.isAfter(buyRow.date)) {
      return SymbolCalcResult(
        symbolId: symbol.id,
        tradableAtBuy: true,
        buyDateUsed: buyRow.date,
        buyPrice: buyPrice,
        estimated: false,
        investedRial: perSymbolRial,
      );
    }

    final units = perSymbolRial / buyPrice;
    final finalValue = (units * sellPrice).round();
    final profit = finalValue - perSymbolRial;
    final percent = perSymbolRial == 0 ? 0.0 : profit / perSymbolRial * 100.0;

    return SymbolCalcResult(
      symbolId: symbol.id,
      tradableAtBuy: true,
      buyDateUsed: buyRow.date,
      buyPrice: buyPrice,
      sellPrice: sellPrice,
      estimated: estimated,
      sellDateUsed: sellDateUsed,
      units: units,
      investedRial: perSymbolRial,
      finalValueRial: finalValue,
      profitRial: profit,
      profitPercent: percent,
    );
  }
}
