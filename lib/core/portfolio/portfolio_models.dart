/// Portfolio data model — the «ارزش دارایی من» tool.
///
/// Transactions are the source of truth (the design fix for m0ntIsRich,
/// which had to append price snapshots because it had no daily price
/// database): the value of the portfolio at any date is derived from the
/// transactions and Montala's bundled price history, so backdated buys and
/// sells just work.
///
/// Two kinds of data live here:
///  * [PortfolioTx] — one buy/sell event. The timestamp is kept to the second
///    (m0ntIsRich's CSV is timestamped), while [PortfolioTx.date] still gives
///    the day used by the valuation math.
///  * [PortfolioSnapshot] — the value history m0ntIsRich wrote to
///    `sarmaye_history.csv`: per-asset units/values plus the total at one
///    instant. Montala regenerates these at launch and on demand.
library;

import 'package:flutter/foundation.dart';

import '../symbols.dart';

/// Timestamp format shared by the CSV files and the web document:
/// `YYYY-MM-DD HH:MM:SS`, with `.ffffff` appended only when the microseconds
/// are non-zero.
String formatPortfolioTimestamp(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  final base = '${d.year.toString().padLeft(4, '0')}-'
      '${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  final micros = d.millisecond * 1000 + d.microsecond;
  if (micros == 0) return base;
  return '$base.${micros.toString().padLeft(6, '0')}';
}

/// Day key (`YYYY-MM-DD`) used by the valuation math and by legacy rows.
String portfolioDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Parses a timestamp from CSV/JSON. Accepts `YYYY-MM-DD`,
/// `YYYY-MM-DD HH:MM[:SS[.ffffff]]`, ISO-8601 with `T`, and Persian/Arabic
/// digits (the CSV path normalizes them before calling this, but imports may
/// arrive from other tools).
DateTime? parsePortfolioTimestamp(String? raw) {
  if (raw == null) return null;
  final text = _normalizeDigits(raw.trim());
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

String _normalizeDigits(String input) {
  final sb = StringBuffer();
  for (final ch in input.runes) {
    if (ch >= 0x06F0 && ch <= 0x06F9) {
      sb.write(ch - 0x06F0);
    } else if (ch >= 0x0660 && ch <= 0x0669) {
      sb.write(ch - 0x0660);
    } else {
      sb.writeCharCode(ch);
    }
  }
  return sb.toString();
}

/// Buy/sell of one asset on a user-chosen date.
@immutable
class PortfolioTx {
  /// Database id — null until persisted.
  final int? id;

  /// Full moment of the trade (user-chosen, may be backdated). [date] is the
  /// day-granular view used by the valuation series.
  final DateTime timestamp;

  /// One of the [kSymbols] ids.
  final String assetId;

  /// 'BUY' or 'SELL'.
  final String type;

  /// Positive quantity of [assetId].
  final double units;

  /// Price per unit in Toman. Zero only for an [incomplete] row.
  final double unitPriceToman;

  /// Explicit cash amount in Toman. Kept separate from [units] ×
  /// [unitPriceToman] so an imported row whose total disagrees with its price
  /// can still be represented faithfully.
  final double totalToman;

  /// Where the row came from: `manual`, `auto`, `import`, or `legacy`.
  final String source;

  final String? note;

  /// The row is missing its price/total (typically imported from a CSV with
  /// blank money columns). The UI offers a completion flow; valuation skips
  /// these rows until they are completed.
  final bool incomplete;

  /// Builds a transaction. Callers may pass either [timestamp] or the legacy
  /// day-only [date]; when both are absent the current time is used.
  ///
  /// When exactly one of [unitPriceToman]/[totalToman] is supplied and the
  /// row is not marked incomplete, the other is derived. Pass
  /// `incomplete: true` to preserve an intentionally incomplete row.
  factory PortfolioTx({
    int? id,
    DateTime? timestamp,
    DateTime? date,
    required String assetId,
    required String type,
    required double units,
    double? unitPriceToman,
    double? totalToman,
    String source = 'manual',
    String? note,
    bool? incomplete,
  }) {
    final ts = timestamp ??
        (date == null
            ? DateTime.now()
            : DateTime(date.year, date.month, date.day));
    var price = unitPriceToman ?? 0;
    var total = totalToman ?? 0;
    final inc = incomplete ?? (price <= 0 || total <= 0);
    if (!inc) {
      if (total <= 0 && price > 0 && units > 0) total = units * price;
      if (price <= 0 && total > 0 && units > 0) price = total / units;
    }
    return PortfolioTx._(
      id: id,
      timestamp: ts,
      assetId: assetId,
      type: type,
      units: units,
      unitPriceToman: price,
      totalToman: total,
      source: source,
      note: note,
      incomplete: inc,
    );
  }

  const PortfolioTx._({
    this.id,
    required this.timestamp,
    required this.assetId,
    required this.type,
    required this.units,
    required this.unitPriceToman,
    required this.totalToman,
    required this.source,
    this.note,
    required this.incomplete,
  });

  /// Day-granular view used by holdings/valuation math.
  DateTime get date =>
      DateTime(timestamp.year, timestamp.month, timestamp.day);

  bool get isBuy => type == 'BUY';

  bool get isComplete => !incomplete;

  /// Price per unit, deriving it from an explicit total when needed.
  double get effectiveUnitPriceToman {
    if (unitPriceToman > 0) return unitPriceToman;
    if (totalToman > 0 && units > 0) return totalToman / units;
    return 0;
  }

  /// Cash amount, deriving it from the unit price when needed.
  double get effectiveTotalToman {
    if (totalToman > 0) return totalToman;
    return units * unitPriceToman;
  }

  PortfolioTx copyWith({
    int? id,
    DateTime? timestamp,
    DateTime? date,
    String? assetId,
    String? type,
    double? units,
    double? unitPriceToman,
    double? totalToman,
    String? source,
    String? note,
    bool? incomplete,
  }) {
    final ts = timestamp ??
        (date == null
            ? this.timestamp
            : DateTime(
                date.year, date.month, date.day, this.timestamp.hour,
                this.timestamp.minute, this.timestamp.second,
                this.timestamp.millisecond, this.timestamp.microsecond));
    return PortfolioTx(
      id: id ?? this.id,
      timestamp: ts,
      assetId: assetId ?? this.assetId,
      type: type ?? this.type,
      units: units ?? this.units,
      unitPriceToman: unitPriceToman ?? this.unitPriceToman,
      totalToman: totalToman ?? this.totalToman,
      source: source ?? this.source,
      note: note ?? this.note,
      incomplete: incomplete ?? this.incomplete,
    );
  }

  /// A completed copy of an incomplete row: both money fields filled and the
  /// flag cleared. The timestamp and id are preserved.
  PortfolioTx completedWithPrice(double price) => copyWith(
        unitPriceToman: price,
        totalToman: units * price,
        incomplete: false,
      );

  Map<String, Object?> toDbMap() => {
        if (id != null) 'id': id,
        'timestamp': formatPortfolioTimestamp(timestamp),
        'asset_id': assetId,
        'type': type,
        'units': units,
        'unit_price_toman': unitPriceToman,
        'total_toman': totalToman,
        'source': source,
        'note': note,
        'incomplete': incomplete ? 1 : 0,
      };

  static PortfolioTx fromDbMap(Map<String, Object?> m) {
    final timestamp = parsePortfolioTimestamp(
          m['timestamp'] as String?,
        ) ??
        parsePortfolioTimestamp(m['date'] as String?) ??
        DateTime.now();
    final price = (m['unit_price_toman'] as num?)?.toDouble() ?? 0;
    final total = (m['total_toman'] as num?)?.toDouble() ?? 0;
    final rawIncomplete = m['incomplete'];
    final incomplete = rawIncomplete is num
        ? rawIncomplete != 0
        : price <= 0 && total <= 0;
    return PortfolioTx(
      id: m['id'] as int?,
      timestamp: timestamp,
      assetId: m['asset_id'] as String,
      type: m['type'] as String,
      units: (m['units'] as num).toDouble(),
      unitPriceToman: price,
      totalToman: total,
      source: (m['source'] as String?) ?? 'legacy',
      note: m['note'] as String?,
      incomplete: incomplete,
    );
  }

  Map<String, Object?> toJson() => {
        if (id != null) 'id': id,
        'timestamp': formatPortfolioTimestamp(timestamp),
        'asset': assetId,
        'event_type': type,
        'units': units,
        'unit_price_toman': unitPriceToman,
        'total_toman': totalToman,
        'source': source,
        if (note != null) 'note': note,
        if (incomplete) 'incomplete': true,
      };

  static PortfolioTx fromJson(Map<String, dynamic> m) {
    final timestamp =
        parsePortfolioTimestamp(m['timestamp'] as String?) ??
            parsePortfolioTimestamp(m['date'] as String?) ??
            DateTime.now();
    final price = (m['unit_price_toman'] as num?)?.toDouble() ?? 0;
    final total = (m['total_toman'] as num?)?.toDouble() ?? 0;
    final rawIncomplete = m['incomplete'];
    final incomplete = rawIncomplete is bool
        ? rawIncomplete
        : rawIncomplete is num
            ? rawIncomplete != 0
            : price <= 0 && total <= 0;
    return PortfolioTx(
      id: m['id'] as int?,
      timestamp: timestamp,
      assetId: (m['asset'] ?? m['asset_id']) as String,
      type: (m['event_type'] ?? m['type']) as String,
      units: (m['units'] as num).toDouble(),
      unitPriceToman: price,
      totalToman: total,
      source: (m['source'] as String?) ?? 'legacy',
      note: m['note'] as String?,
      incomplete: incomplete,
    );
  }
}

/// One asset's line inside a [PortfolioSnapshot].
@immutable
class SnapshotLine {
  final String assetId;
  final double units;
  final double valueToman;

  const SnapshotLine({
    required this.assetId,
    required this.units,
    required this.valueToman,
  });

  Map<String, Object?> toJson() => {
        'asset': assetId,
        'units': units,
        'value_toman': valueToman,
      };

  static SnapshotLine fromJson(Map<String, dynamic> m) => SnapshotLine(
        assetId: (m['asset'] ?? m['asset_id']) as String,
        units: (m['units'] as num).toDouble(),
        valueToman: (m['value_toman'] as num).toDouble(),
      );
}

/// The portfolio's value at one instant — the in-app successor of
/// m0ntIsRich's `sarmaye_history.csv` rows.
@immutable
class PortfolioSnapshot {
  final int? id;
  final DateTime timestamp;
  final List<SnapshotLine> lines;
  final double totalToman;

  /// `launch`, `recalc`, `manual`, or `import`.
  final String source;

  const PortfolioSnapshot({
    this.id,
    required this.timestamp,
    required this.lines,
    required this.totalToman,
    this.source = 'launch',
  });

  Map<String, SnapshotLine> get byAsset =>
      {for (final line in lines) line.assetId: line};

  SnapshotLine? lineFor(String assetId) => byAsset[assetId];

  PortfolioSnapshot copyWith({
    int? id,
    DateTime? timestamp,
    List<SnapshotLine>? lines,
    double? totalToman,
    String? source,
  }) =>
      PortfolioSnapshot(
        id: id ?? this.id,
        timestamp: timestamp ?? this.timestamp,
        lines: lines ?? this.lines,
        totalToman: totalToman ?? this.totalToman,
        source: source ?? this.source,
      );

  Map<String, Object?> toJson() => {
        if (id != null) 'id': id,
        'timestamp': formatPortfolioTimestamp(timestamp),
        'lines': [for (final line in lines) line.toJson()],
        'total_toman': totalToman,
        'source': source,
      };

  static PortfolioSnapshot fromJson(Map<String, dynamic> m) =>
      PortfolioSnapshot(
        id: m['id'] as int?,
        timestamp: parsePortfolioTimestamp(m['timestamp'] as String?) ??
            DateTime.now(),
        lines: [
          for (final line in (m['lines'] as List? ?? const []))
            SnapshotLine.fromJson(line as Map<String, dynamic>),
        ],
        totalToman: (m['total_toman'] as num?)?.toDouble() ?? 0,
        source: (m['source'] as String?) ?? 'import',
      );
}
