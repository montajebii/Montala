/// Basket valuation: "I had these quantities on date D — what were they
/// worth in Rial at that moment?"
///
/// Primary use case: pricing a registered mahr (مهریه) at its valuation date.
/// Each held symbol is priced on the nearest earlier trading day with the
/// configured price basis — the same rules as the profit calculator.
library;

import 'calculator.dart';
import '../models.dart';

/// Values [holdings] at [date] using [history].
///
/// Holdings with a non-positive quantity are skipped. Symbols without any
/// recorded row on/before [date] come back with `hasData: false`; the total
/// only counts symbols that could be priced.
ValuationResult valueBasket({
  required Map<String, List<PriceRow>> history,
  required List<ValuationHolding> holdings,
  required DateTime date,
  required PriceBasis basis,
}) {
  final lines = <ValuationLine>[];
  var total = 0.0;
  var anyPriced = false;

  for (final holding in holdings) {
    if (!holding.isHeld) continue;
    final rows = history[holding.symbolId] ?? const <PriceRow>[];
    final row = rowOnOrBefore(rows, date);
    if (row == null) {
      lines.add(ValuationLine(
        symbolId: holding.symbolId,
        quantity: holding.quantity,
        hasData: false,
      ));
      continue;
    }
    final price = row.byBasis(basis);
    final value = holding.quantity * price;
    total += value;
    anyPriced = true;
    lines.add(ValuationLine(
      symbolId: holding.symbolId,
      quantity: holding.quantity,
      hasData: true,
      dateUsed: row.date,
      priceUsed: price,
      valueRial: value,
    ));
  }

  return ValuationResult(
    requestedDate: date,
    basis: basis,
    lines: lines,
    totalRial: anyPriced ? total.round() : null,
    calculatedAt: DateTime.now(),
  );
}
