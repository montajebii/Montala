/// CSV export/import for the portfolio transaction log.
///
/// Schema: `date,asset,type,units,unit_price_toman,note` — one row per trade,
/// dates ISO (`YYYY-MM-DD`), asset = Montala symbol id, type BUY|SELL. The
/// note field is RFC-4180 quoted so commas inside it survive the round trip.
library;

import 'package:flutter/foundation.dart';

import 'portfolio_models.dart';

const String kPortfolioCsvHeader =
    'date,asset,type,units,unit_price_toman,note';

String encodeTxsCsv(List<PortfolioTx> txs) {
  final buf = StringBuffer('$kPortfolioCsvHeader\n');
  final ordered = [...txs]..sort((a, b) => a.date.compareTo(b.date));
  for (final tx in ordered) {
    buf.writeln([
      _isoDate(tx.date),
      tx.assetId,
      tx.type,
      _num(tx.units),
      _num(tx.unitPriceToman),
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
  var sawHeader = false;

  for (final rawLine in csv.split('\n')) {
    lineNo += 1;
    final line = rawLine.trimRight();
    if (line.trim().isEmpty) continue;
    final fields = _splitCsvLine(line);
    if (fields.length == 6 &&
        fields[0] == 'date' &&
        fields[1] == 'asset' &&
        !sawHeader) {
      sawHeader = true;
      continue;
    }
    if (fields.length != 6) {
      errors.add('خط $lineNo: تعداد ستون‌ها ${fields.length} است (۶ لازم است)');
      continue;
    }
    final date = DateTime.tryParse(fields[0]);
    if (date == null) {
      errors.add('خط $lineNo: تاریخ نامعتبر «${fields[0]}»');
      continue;
    }
    final asset = fields[1];
    if (asset.isEmpty) {
      errors.add('خط $lineNo: نماد دارایی خالی است');
      continue;
    }
    final type = fields[2].toUpperCase();
    if (type != 'BUY' && type != 'SELL') {
      errors.add('خط $lineNo: نوع تراکنش باید BUY یا SELL باشد');
      continue;
    }
    final units = double.tryParse(fields[3].replaceAll(',', ''));
    if (units == null || units <= 0) {
      errors.add('خط $lineNo: تعداد نامعتبر «${fields[3]}»');
      continue;
    }
    final price = double.tryParse(fields[4].replaceAll(',', ''));
    if (price == null || price <= 0) {
      errors.add('خط $lineNo: قیمت نامعتبر «${fields[4]}»');
      continue;
    }
    txs.add(PortfolioTx(
      date: DateTime(date.year, date.month, date.day),
      assetId: asset,
      type: type,
      units: units,
      unitPriceToman: price,
      note: fields[5].isEmpty ? null : fields[5],
    ));
  }

  return CsvParseResult(txs: txs, errors: errors);
}

@immutable
class CsvParseResult {
  final List<PortfolioTx> txs;
  final List<String> errors;

  const CsvParseResult({required this.txs, required this.errors});

  bool get ok => errors.isEmpty;
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _num(double v) {
  if (v == v.roundToDouble()) return v.round().toString();
  return v.toString();
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
