/// CSV export/import for the portfolio transaction log and value history.
///
/// Two transaction schemas are accepted:
///  * m0ntIsRich / current Montala:
///    `timestamp,asset,event_type,units,unit_price_toman,total_toman,source,note`
///    (the seven-column Python file without `note` also parses),
///  * the first Montala release:
///    `date,asset,type,units,unit_price_toman,note`.
///
/// Snapshots use m0ntIsRich's `sarmaye_history.csv` shape — one timestamped
/// row with `<asset>_units`/`<asset>_value_toman` pairs, a total and an
/// optional source column. Legacy asset names (`shemsh24`, `shemsh18`, …) are
/// mapped through [kAssetIdAliases].
///
/// Notes are RFC-4180 quoted so commas inside them survive the round trip.
library;

import 'package:flutter/foundation.dart';

import '../symbols.dart';
import 'portfolio_models.dart';

/// m0ntIsRich's asset names → Montala symbol ids, so files straight from the
/// Python tool import without conversion.
const Map<String, String> kAssetIdAliases = {
  'shemsh24': 'gold24',
  'shemsh18': 'gold18',
  'geram24': 'gold24',
  'geram18': 'gold18',
};

const String kPortfolioCsvHeader =
    'timestamp,asset,event_type,units,unit_price_toman,total_toman,source,note';

const String kLegacyPortfolioCsvHeader =
    'date,asset,type,units,unit_price_toman,note';

const String kSnapshotSourceColumn = 'source';

String encodeTxsCsv(List<PortfolioTx> txs) {
  final buf = StringBuffer('$kPortfolioCsvHeader\n');
  final ordered = [...txs]..sort((a, b) {
      final byTime = a.timestamp.compareTo(b.timestamp);
      if (byTime != 0) return byTime;
      return (a.id ?? 0).compareTo(b.id ?? 0);
    });
  for (final tx in ordered) {
    buf.writeln([
      formatPortfolioTimestamp(tx.timestamp),
      tx.assetId,
      tx.type,
      _num(tx.units),
      tx.unitPriceToman > 0 ? _num(tx.unitPriceToman) : '',
      tx.totalToman > 0 ? _num(tx.totalToman) : '',
      tx.source,
      _quote(tx.note ?? ''),
    ].join(','));
  }
  return buf.toString();
}

/// Parses CSV text into transactions; rows that cannot be understood are
/// reported in [CsvParseResult.errors] (1-based line numbers) instead of
/// failing the whole import.
CsvParseResult parseTxsCsv(String csv) {
  final txs = <PortfolioTx>[];
  final errors = <String>[];
  var lineNo = 0;
  _TxColumns? columns;
  var headerSeen = false;

  for (final rawLine in _lines(csv)) {
    lineNo += 1;
    final line = rawLine.trimRight();
    if (line.trim().isEmpty) continue;
    final fields = _splitCsvLine(line);
    if (!headerSeen && _isTxHeader(fields)) {
      columns = _TxColumns.fromHeader(fields);
      headerSeen = true;
      continue;
    }
    final cols = columns ?? _TxColumns.fromShape(fields);
    if (cols == null) {
      errors.add('خط $lineNo: ستون‌های فایل قابل تشخیص نیستند');
      continue;
    }
    final tx = _parseTxRow(fields, cols, lineNo, errors);
    if (tx != null) txs.add(tx);
  }

  return CsvParseResult(txs: txs, errors: errors);
}

PortfolioTx? _parseTxRow(
  List<String> fields,
  _TxColumns cols,
  int lineNo,
  List<String> errors,
) {
  String at(int index) =>
      index >= 0 && index < fields.length ? fields[index].trim() : '';

  final rawTimestamp = at(cols.timestamp);
  final timestamp = parsePortfolioTimestamp(rawTimestamp);
  if (timestamp == null) {
    errors.add('خط $lineNo: تاریخ/زمان نامعتبر «$rawTimestamp»');
    return null;
  }
  final asset = kAssetIdAliases[at(cols.asset)] ?? at(cols.asset);
  if (asset.isEmpty) {
    errors.add('خط $lineNo: نماد دارایی خالی است');
    return null;
  }
  if (!kSymbols.any((s) => s.id == asset)) {
    errors.add('خط $lineNo: نماد ناشناخته «${at(cols.asset)}»');
    return null;
  }
  final type = at(cols.type).toUpperCase();
  if (type != 'BUY' && type != 'SELL') {
    errors.add('خط $lineNo: نوع تراکنش باید BUY یا SELL باشد');
    return null;
  }
  final units = _parseNum(at(cols.units));
  if (units == null || units <= 0) {
    errors.add('خط $lineNo: تعداد نامعتبر «${at(cols.units)}»');
    return null;
  }
  final price = _parseNum(at(cols.price));
  final total = _parseNum(at(cols.total));
  final incomplete = (price == null || price <= 0) &&
      (total == null || total <= 0);
  final source = at(cols.source).isEmpty
      ? (cols.legacy ? 'legacy' : 'manual')
      : at(cols.source);
  final note = at(cols.note);

  return PortfolioTx(
    timestamp: timestamp,
    assetId: asset,
    type: type,
    units: units,
    unitPriceToman: price,
    totalToman: total,
    source: source,
    note: note.isEmpty ? null : note,
    incomplete: incomplete,
  );
}

/// Column indices for one CSV shape. `-1` means the column is absent.
class _TxColumns {
  final int timestamp;
  final int asset;
  final int type;
  final int units;
  final int price;
  final int total;
  final int source;
  final int note;
  final bool legacy;

  const _TxColumns({
    required this.timestamp,
    required this.asset,
    required this.type,
    required this.units,
    required this.price,
    required this.total,
    required this.source,
    required this.note,
    required this.legacy,
  });

  static bool _has(List<String> header, String name) =>
      header.any((f) => f.trim().toLowerCase() == name);

  static int _index(List<String> header, List<String> names) {
    for (var i = 0; i < header.length; i++) {
      if (names.contains(header[i].trim().toLowerCase())) return i;
    }
    return -1;
  }

  /// A header row is recognized by its first cell plus an asset column.
  static _TxColumns fromHeader(List<String> header) {    final legacy = header.first.trim().toLowerCase() == 'date' ||
        (_has(header, 'type') && !_has(header, 'event_type'));
    return _TxColumns(
      timestamp: _index(header, const ['timestamp', 'date']),
      asset: _index(header, const ['asset', 'asset_id', 'assetid', 'symbol']),
      type: _index(header, const ['event_type', 'type', 'event', 'side']),
      units: _index(header, const ['units', 'quantity', 'amount']),
      price: _index(
        header,
        const ['unit_price_toman', 'price', 'unit_price', 'price_toman'],
      ),
      total: _index(header, const ['total_toman', 'total', 'value_toman']),
      source: _index(header, const ['source', 'origin']),
      note: _index(header, const ['note', 'comment', 'description']),
      legacy: legacy,
    );
  }

  /// Headerless files: m0ntIsRich writes 7 columns, Montala 8, and the first
  /// Montala release wrote the six-column day-only schema.
  static _TxColumns? fromShape(List<String> fields) {
    if (fields.length >= 8) {
      return const _TxColumns(
        timestamp: 0,
        asset: 1,
        type: 2,
        units: 3,
        price: 4,
        total: 5,
        source: 6,
        note: 7,
        legacy: false,
      );
    }
    if (fields.length == 7) {
      return const _TxColumns(
        timestamp: 0,
        asset: 1,
        type: 2,
        units: 3,
        price: 4,
        total: 5,
        source: 6,
        note: -1,
        legacy: false,
      );
    }
    if (fields.length == 6) {
      return const _TxColumns(
        timestamp: 0,
        asset: 1,
        type: 2,
        units: 3,
        price: 4,
        total: -1,
        source: -1,
        note: 5,
        legacy: true,
      );
    }
    return null;
  }
}

bool _isTxHeader(List<String> fields) {
  if (fields.isEmpty) return false;
  final first = fields.first.trim().toLowerCase();
  if (first != 'timestamp' && first != 'date') return false;
  final lower = [for (final f in fields) f.trim().toLowerCase()];
  return lower.contains('asset') &&
      (lower.contains('event_type') || lower.contains('type'));
}

@immutable
class CsvParseResult {
  final List<PortfolioTx> txs;
  final List<String> errors;

  const CsvParseResult({required this.txs, required this.errors});

  bool get ok => errors.isEmpty;
}

// --------------------------------------------------------------------------
// snapshots

/// Header for [encodeSnapshotsCsv]; exported for tests and documentation.
String snapshotCsvHeader() {
  final header = <String>['timestamp'];
  for (final symbol in kSymbols) {
    header
      ..add('${symbol.id}_units')
      ..add('${symbol.id}_value_toman');
  }
  header
    ..add('total_toman')
    ..add(kSnapshotSourceColumn);
  return header.join(',');
}

String encodeSnapshotsCsv(List<PortfolioSnapshot> snapshots) {
  final buf = StringBuffer('${snapshotCsvHeader()}\n');
  final ordered = [...snapshots]..sort((a, b) {
      final byTime = a.timestamp.compareTo(b.timestamp);
      if (byTime != 0) return byTime;
      return (a.id ?? 0).compareTo(b.id ?? 0);
    });
  for (final snapshot in ordered) {
    final fields = <String>[formatPortfolioTimestamp(snapshot.timestamp)];
    for (final symbol in kSymbols) {
      final line = snapshot.lineFor(symbol.id);
      fields
        ..add(line == null ? '0' : _num(line.units))
        ..add(line == null ? '0' : _num(line.valueToman));
    }
    fields
      ..add(_num(snapshot.totalToman))
      ..add(snapshot.source);
    buf.writeln(fields.join(','));
  }
  return buf.toString();
}

SnapshotParseResult parseSnapshotsCsv(String csv) {
  final snapshots = <PortfolioSnapshot>[];
  final errors = <String>[];
  var lineNo = 0;
  _SnapshotColumns? columns;

  for (final rawLine in _lines(csv)) {
    lineNo += 1;
    final line = rawLine.trimRight();
    if (line.trim().isEmpty) continue;
    final fields = _splitCsvLine(line);
    if (columns == null) {
      final parsed = _SnapshotColumns.fromHeader(fields);
      if (parsed == null) {
        errors.add(
          'خط $lineNo: سرستون‌های تاریخچه ارزش قابل تشخیص نیستند '
          '(ستون‌های timestamp و <asset>_units لازم است)',
        );
        break;
      }
      columns = parsed;
      continue;
    }
    final snapshot = _parseSnapshotRow(fields, columns, lineNo, errors);
    if (snapshot != null) snapshots.add(snapshot);
  }

  snapshots.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return SnapshotParseResult(snapshots: snapshots, errors: errors);
}

PortfolioSnapshot? _parseSnapshotRow(
  List<String> fields,
  _SnapshotColumns columns,
  int lineNo,
  List<String> errors,
) {
  String at(int index) =>
      index >= 0 && index < fields.length ? fields[index].trim() : '';
  final rawTimestamp = at(columns.timestamp);
  final timestamp = parsePortfolioTimestamp(rawTimestamp);
  if (timestamp == null) {
    errors.add('خط $lineNo: تاریخ/زمان نامعتبر «$rawTimestamp»');
    return null;
  }

  final lines = <SnapshotLine>[];
  var sum = 0.0;
  for (final entry in columns.assets.entries) {
    final units = _parseNum(at(entry.value.units)) ?? 0;
    final value = _parseNum(at(entry.value.value)) ?? 0;
    if (units == 0 && value == 0) continue;
    lines.add(SnapshotLine(
      assetId: entry.key,
      units: units,
      valueToman: value,
    ));
    sum += value;
  }
  if (lines.isEmpty) {
    errors.add('خط $lineNo: هیچ دارایی‌ای در ردیف نیست');
    return null;
  }

  final explicitTotal = _parseNum(at(columns.total));
  final source = at(columns.source);
  return PortfolioSnapshot(
    timestamp: timestamp,
    lines: lines,
    totalToman: explicitTotal != null && explicitTotal > 0
        ? explicitTotal
        : sum,
    source: source.isEmpty ? 'import' : source,
  );
}

class _SnapshotColumns {
  final int timestamp;
  final int total;
  final int source;
  final Map<String, ({int units, int value})> assets;

  const _SnapshotColumns({
    required this.timestamp,
    required this.total,
    required this.source,
    required this.assets,
  });

  static _SnapshotColumns? fromHeader(List<String> header) {
    final lower = [for (final f in header) f.trim().toLowerCase()];
    final timestamp = lower.indexOf('timestamp');
    if (timestamp == -1) return null;

    final assets = <String, ({int units, int value})>{};
    for (var i = 0; i < lower.length; i++) {
      final name = lower[i];
      if (!name.endsWith('_units')) continue;
      final rawAsset = name.substring(0, name.length - '_units'.length);
      final asset = kAssetIdAliases[rawAsset] ?? rawAsset;
      if (!kSymbols.any((s) => s.id == asset)) continue;
      final value = lower.indexOf('${rawAsset}_value_toman');
      if (value == -1) continue;
      assets[asset] = (units: i, value: value);
    }
    if (assets.isEmpty) return null;
    return _SnapshotColumns(
      timestamp: timestamp,
      total: lower.indexOf('total_toman'),
      source: lower.indexOf(kSnapshotSourceColumn),
      assets: assets,
    );
  }
}

@immutable
class SnapshotParseResult {
  final List<PortfolioSnapshot> snapshots;
  final List<String> errors;

  const SnapshotParseResult({
    required this.snapshots,
    required this.errors,
  });

  bool get ok => errors.isEmpty;
}

// --------------------------------------------------------------------------
// shared

/// Splits into lines, dropping a UTF-8 BOM and normalizing CRLF.
List<String> _lines(String csv) {
  final text = csv.startsWith('\uFEFF') ? csv.substring(1) : csv;
  return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
}

String _num(double v) {
  if (v == v.roundToDouble()) return v.round().toString();
  return v.toString();
}

double? _parseNum(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  text = _normalizeDigits(text)
      .replaceAll('٬', '')
      .replaceAll('٫', '.')
      .replaceAll(',', '');
  return double.tryParse(text);
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

String _quote(String field) {
  if (!field.contains(',') && !field.contains('"') &&
      !field.contains('\n')) {
    return field;
  }
  return '"${field.replaceAll('"', '""')}"';
}

/// Splits one CSV line honouring RFC-4180 quoting.
List<String> _splitCsvLine(String line) {
  final fields = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buf.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      fields.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  fields.add(buf.toString());
  return fields;
}

/// Whether the first line of [text] looks like a value-history CSV (the
/// `<asset>_units` columns), so the import path can choose the parser.
bool looksLikeSnapshotCsv(String text) {
  for (final line in _lines(text)) {
    if (line.trim().isEmpty) continue;
    return line.contains('_units');
  }
  return false;
}
