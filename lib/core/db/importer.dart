/// First-run import of the bundled CSV seed datasets into SQLite.
library;

import 'package:flutter/services.dart' show rootBundle;

import '../models.dart';
import '../symbols.dart';
import 'app_db.dart';

class Importer {
  static const _importedFlag = 'assets_imported';

  /// Imports all bundled CSVs once. Returns the number of rows imported,
  /// or 0 when the import already happened.
  static Future<int> importAllIfNeeded() async {
    if (await AppDb.metaGet(_importedFlag) == '1') return 0;

    var total = 0;
    for (final symbol in kSymbols) {
      final csv = await rootBundle.loadString(symbol.csvAsset);
      final rows = parseCsv(csv);
      await AppDb.upsertPrices(symbol.id, rows);
      total += rows.length;
    }
    await AppDb.metaSet(_importedFlag, '1');
    await AppDb.metaSet('seed_imported_at', DateTime.now().toIso8601String());
    return total;
  }

  /// Parses the project's CSV format:
  /// Date,Persian_Date,Open,Low,High,Close with dates as YYYY/MM/DD.
  static List<PriceRow> parseCsv(String csv) {
    final rows = <PriceRow>[];
    for (final line in csv.split('\n').skip(1)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final cols = trimmed.split(',');
      if (cols.length < 6) continue;
      try {
        rows.add(
          PriceRow(
            date: PriceRow.parseDate(cols[0]),
            persianDate: cols[1].trim(),
            open: int.parse(cols[2].trim()),
            low: int.parse(cols[3].trim()),
            high: int.parse(cols[4].trim()),
            close: int.parse(cols[5].trim()),
          ),
        );
      } on FormatException {
        continue; // skip malformed lines
      }
    }
    return rows;
  }
}
