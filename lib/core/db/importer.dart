/// First-run import of the bundled CSV seed datasets into SQLite.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models.dart';
import '../symbols.dart';
import 'app_db.dart';

class Importer {
  static const _importedFlag = 'assets_imported';

  /// How long a single asset fetch may take before we give up on that file.
  /// (Startup applies a tighter outer bound on the whole import; this one
  /// keeps a stalled fetch from wedging a background import forever.)
  static const _perAssetTimeout = Duration(seconds: 5);

  /// Imports all bundled CSVs once. Returns the number of rows imported.
  ///
  /// Never throws for a single bad asset: a missing, malformed or stalled CSV
  /// is skipped and the loop continues, so one broken file can neither crash
  /// startup nor leave it hanging on the splash screen. Progress is tracked
  /// per symbol, so a skipped file is retried on the next launch instead of
  /// being lost behind a single global "imported" flag.
  static Future<int> importAllIfNeeded() async {
    // Legacy fast path: older installs marked the whole seed import done in
    // one shot; keep honouring that so nothing is re-imported there.
    if (await AppDb.metaGet(_importedFlag) == '1') return 0;

    var total = 0;
    var failures = 0;
    for (final symbol in kSymbols) {
      final flag = '$_importedFlag:${symbol.id}';
      if (await AppDb.metaGet(flag) == '1') continue;
      try {
        final csv = await rootBundle
            .loadString(symbol.csvAsset)
            .timeout(_perAssetTimeout);
        final rows = parseCsv(csv);
        await AppDb.upsertPrices(symbol.id, rows);
        await AppDb.metaSet(flag, '1');
        total += rows.length;
      } catch (error, stack) {
        failures++;
        debugPrint(
          'Importer: ${symbol.csvAsset} failed, skipping — $error\n$stack',
        );
      }
    }

    // Only mark the global flag when every symbol landed, so a partially
    // failed import is retried (per symbol) on the next launch.
    if (failures == 0) {
      await AppDb.metaSet(_importedFlag, '1');
      await AppDb.metaSet(
        'seed_imported_at',
        DateTime.now().toIso8601String(),
      );
    }
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
