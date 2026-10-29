/// Price update engine — mirrors the Python crawlers in the repository root.
///
/// Fetches the full history of each symbol from the same tgju.org server API
/// the archive table uses and upserts it into SQLite. On the web this works
/// directly because the API sends `Access-Control-Allow-Origin: *`.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../symbols.dart';
import '../db/app_db.dart';

class SymbolUpdateResult {
  final String symbolId;
  final bool ok;
  final int rowsWritten;
  final DateTime? lastDate;
  final String? error;

  const SymbolUpdateResult({
    required this.symbolId,
    required this.ok,
    required this.rowsWritten,
    this.lastDate,
    this.error,
  });
}

class Updater {
  final http.Client _client;
  final Duration _timeout;

  Updater({http.Client? client, Duration? timeout })
      : _client = client ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 60);

  static const _userAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  Uri _uri(String apiName) => Uri.parse(
        'https://api.tgju.org/v1/market/indicator/summary-table-data/'
        '$apiName?lang=fa&order_dir=asc',
      );

  /// Fetches one symbol with up to [attempts] tries.
  Future<SymbolUpdateResult> updateSymbol(
    AssetSymbol symbol, {
    int attempts = 2,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final response = await _client
            .get(_uri(symbol.apiName), headers: {'User-Agent': _userAgent})
            .timeout(_timeout);
        if (response.statusCode != 200) {
          throw http.ClientException(
            'HTTP ${response.statusCode}',
            _uri(symbol.apiName),
          );
        }
        final rows = parseApiPayload(response.body);
        if (rows.isEmpty) {
          throw const FormatException('empty data payload');
        }
        await AppDb.upsertPrices(symbol.id, rows);
        return SymbolUpdateResult(
          symbolId: symbol.id,
          ok: true,
          rowsWritten: rows.length,
          lastDate: rows.last.date,
        );
      } catch (e) {
        lastError = e;
      }
    }
    return SymbolUpdateResult(
      symbolId: symbol.id,
      ok: false,
      rowsWritten: 0,
      error: lastError.toString(),
    );
  }

  /// Updates all symbols sequentially (keeps load on the API polite).
  Future<List<SymbolUpdateResult>> updateAll() async {
    await AppDb.metaSet(
      'last_update_attempt',
      DateTime.now().toIso8601String(),
    );
    final results = <SymbolUpdateResult>[];
    for (final symbol in kSymbols) {
      final r = await updateSymbol(symbol);
      results.add(r);
    }
    if (results.any((r) => r.ok)) {
      await AppDb.metaSet(
        'last_update_success',
        DateTime.now().toIso8601String(),
      );
    }
    return results;
  }

  /// Rows come as:
  /// [open, low, high, close, change(span), changePct(span), gregorian, persian]
  @visibleForTesting
  static List<PriceRow> parseApiPayload(String body) {
    final payload = jsonDecode(body);
    if (payload is! Map<String, dynamic> || payload['data'] is! List) {
      return const [];
    }
    final rows = <PriceRow>[];
    for (final item in payload['data'] as List) {
      if (item is! List || item.length < 8) continue;
      final gregorian = _plainText(item[6]);
      final persian = _plainText(item[7]);
      final open = _parsePrice(item[0]);
      final low = _parsePrice(item[1]);
      final high = _parsePrice(item[2]);
      final close = _parsePrice(item[3]);
      if (gregorian.isEmpty || persian.isEmpty) continue;
      if (open == null || low == null || high == null || close == null) {
        continue;
      }
      DateTime date;
      try {
        date = PriceRow.parseDate(gregorian);
      } on FormatException {
        continue;
      }
      rows.add(
        PriceRow(
          date: date,
          persianDate: persian,
          open: open,
          low: low,
          high: high,
          close: close,
        ),
      );
    }
    rows.sort((a, b) => a.date.compareTo(b.date));
    return rows;
  }

  static String _plainText(Object? v) {
    if (v is String) return v.trim();
    return '';
  }

  static int? _parsePrice(Object? v) {
    if (v is num) return v.round();
    if (v is String) {
      final cleaned = v.replaceAll(',', '').trim();
      if (cleaned.isEmpty || cleaned == '-') return null;
      return int.tryParse(cleaned);
    }
    return null;
  }
}
