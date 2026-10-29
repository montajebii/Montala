/// Core data models shared across engine layers.
library;

import 'package:flutter/foundation.dart';

enum PriceBasis { open, close }

String priceBasisLabel(PriceBasis b) =>
    b == PriceBasis.open ? 'اولین قیمت روز (Open)' : 'آخرین قیمت روز (Close)';

/// One daily OHLC row for a symbol. Prices are Rial.
@immutable
class PriceRow {
  final DateTime date;
  final String persianDate; // e.g. "1405/08/05"
  final int open;
  final int low;
  final int high;
  final int close;

  const PriceRow({
    required this.date,
    required this.persianDate,
    required this.open,
    required this.low,
    required this.high,
    required this.close,
  });

  int byBasis(PriceBasis basis) => basis == PriceBasis.open ? open : close;

  /// ISO date string "YYYY-MM-DD" used as the DB key.
  String get dateIso =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static DateTime parseIso(String iso) => DateTime.parse(iso);

  /// Parses "2013/07/22" or "2013-07-22" into a date-only DateTime.
  static DateTime parseDate(String raw) {
    final parts = raw.trim().split(RegExp(r'[/\-]'));
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  Map<String, Object> toDbMap(String symbol) => {
        'symbol': symbol,
        'date': dateIso,
        'persian_date': persianDate,
        'open': open,
        'low': low,
        'high': high,
        'close': close,
      };

  static PriceRow fromDbMap(Map<String, Object?> m) => PriceRow(
        date: parseIso(m['date'] as String),
        persianDate: m['persian_date'] as String,
        open: m['open'] as int,
        low: m['low'] as int,
        high: m['high'] as int,
        close: m['close'] as int,
      );
}

/// Result of running the "what if I had bought" calculation for one symbol.
@immutable
class SymbolCalcResult {
  final String symbolId;
  final bool tradableAtBuy; // false when buy date precedes first data row
  final DateTime? buyDateUsed; // actual trading day used
  final int? buyPrice; // Rial
  final int? sellPrice; // Rial (estimated when [estimated])
  final bool estimated; // sell price comes from the trend forecast
  final DateTime? sellDateUsed;
  final double? units; // amount of the asset bought
  final int investedRial;
  final int? finalValueRial;
  final int? profitRial;
  final double? profitPercent;

  const SymbolCalcResult({
    required this.symbolId,
    required this.tradableAtBuy,
    this.buyDateUsed,
    this.buyPrice,
    this.sellPrice,
    required this.estimated,
    this.sellDateUsed,
    this.units,
    required this.investedRial,
    this.finalValueRial,
    this.profitRial,
    this.profitPercent,
  });

  bool get hasResult => finalValueRial != null && profitRial != null;
}

/// All symbol results for one query, ranked best to worst.
@immutable
class PortfolioResult {
  final List<SymbolCalcResult> ranked;
  final DateTime calculatedAt;

  const PortfolioResult({required this.ranked, required this.calculatedAt});
}

/// One holding of the basket-valuation feature: an amount of one symbol
/// owned at a past date (e.g. 40 Emami coins as mahr).
@immutable
class ValuationHolding {
  final String symbolId;
  final double quantity;

  const ValuationHolding({required this.symbolId, required this.quantity});

  bool get isHeld => quantity > 0;
}

/// Per-symbol line of a basket valuation.
@immutable
class ValuationLine {
  final String symbolId;
  final double quantity;

  /// False when the symbol has no recorded row on/before the requested date.
  final bool hasData;
  final DateTime? dateUsed;
  final int? priceUsed; // Rial per unit
  final double? valueRial;

  const ValuationLine({
    required this.symbolId,
    required this.quantity,
    required this.hasData,
    this.dateUsed,
    this.priceUsed,
    this.valueRial,
  });
}

/// Result of valuing a basket of holdings at one date.
@immutable
class ValuationResult {
  final DateTime requestedDate;
  final PriceBasis basis;
  final List<ValuationLine> lines;

  /// Null when no held symbol had data at the requested date.
  final int? totalRial;
  final DateTime calculatedAt;

  const ValuationResult({
    required this.requestedDate,
    required this.basis,
    required this.lines,
    required this.totalRial,
    required this.calculatedAt,
  });
}
