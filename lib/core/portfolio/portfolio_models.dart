/// Portfolio data model — the «ارزش دارایی من» tool.
///
/// Transactions are the source of truth (the design fix for m0ntIsRich,
/// which had to append price snapshots because it had no daily price
/// database): the value of the portfolio at any date is derived from the
/// transactions and Montala's bundled price history, so backdated buys and
/// sells just work.
library;

import 'package:flutter/foundation.dart';

import '../symbols.dart';

/// Buy/sell of one asset on a user-chosen date.
@immutable
class PortfolioTx {
  /// Database id — null until persisted.
  final int? id;

  /// When the trade happened (user-chosen, may be backdated).
  final DateTime date;

  /// One of the [kSymbols] ids.
  final String assetId;

  /// 'BUY' or 'SELL'.
  final String type;

  /// Positive quantity of [assetId].
  final double units;

  /// Price per unit in Toman, as entered (defaults to the database close of
  /// [date] but stays editable).
  final double unitPriceToman;

  final String? note;

  const PortfolioTx({
    this.id,
    required this.date,
    required this.assetId,
    required this.type,
    required this.units,
    required this.unitPriceToman,
    this.note,
  });

  bool get isBuy => type == 'BUY';

  double get totalToman => units * unitPriceToman;

  PortfolioTx copyWith({
    int? id,
    DateTime? date,
    String? assetId,
    String? type,
    double? units,
    double? unitPriceToman,
    String? note,
  }) =>
      PortfolioTx(
        id: id ?? this.id,
        date: date ?? this.date,
        assetId: assetId ?? this.assetId,
        type: type ?? this.type,
        units: units ?? this.units,
        unitPriceToman: unitPriceToman ?? this.unitPriceToman,
        note: note ?? this.note,
      );

  Map<String, Object?> toDbMap() => {
        if (id != null) 'id': id,
        'date': _dateKey(date),
        'asset_id': assetId,
        'type': type,
        'units': units,
        'unit_price_toman': unitPriceToman,
        'note': note,
      };

  static PortfolioTx fromDbMap(Map<String, Object?> m) => PortfolioTx(
        id: m['id'] as int?,
        date: DateTime.parse(m['date'] as String),
        assetId: m['asset_id'] as String,
        type: m['type'] as String,
        units: (m['units'] as num).toDouble(),
        unitPriceToman: (m['unit_price_toman'] as num).toDouble(),
        note: m['note'] as String?,
      );

  Map<String, Object?> toJson() => {
        if (id != null) 'id': id,
        'date': _dateKey(date),
        'asset': assetId,
        'type': type,
        'units': units,
        'unit_price_toman': unitPriceToman,
        if (note != null) 'note': note,
      };

  static PortfolioTx fromJson(Map<String, dynamic> m) => PortfolioTx(
        id: m['id'] as int?,
        date: DateTime.parse(m['date'] as String),
        assetId: m['asset'] as String,
        type: m['type'] as String,
        units: (m['units'] as num).toDouble(),
        unitPriceToman: (m['unit_price_toman'] as num).toDouble(),
        note: m['note'] as String?,
      );

  /// Day-granular key so two trades on one day sort stably.
  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
