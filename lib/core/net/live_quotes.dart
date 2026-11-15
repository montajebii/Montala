/// Live market quotes for the تابلو زنده board.
///
/// Ported from m0ntIsRich's ftgn.py + scraper.py with two adaptations that
/// suit a Flutter app:
///  * tgju prices come from the same JSON API the price updater uses
///    (`api.tgju.org`, CORS-free — works on every platform),
///  * estjt.ir is scraped from native platforms only; the site sends no CORS
///    header, so the web build shows the tgju column alone.
///
/// The number parser is an exact port of `_parse_rial`: Persian/Arabic digits
/// are normalized, commas are thousands separators, only the first dot is a
/// decimal point (later dots are collapsed away), trailing `-` is stripped.
/// Values that fall outside a row's sanity bounds are treated as parse
/// failures — the same guard `_filter_bad_prices` provides in Python.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../util/format.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

/// One cell of the board: a source's reading for one row.
@immutable
class LiveCell {
  /// Toman value (or USD for the world-ounce cell) — null when the source has
  /// no usable reading for the row.
  final double? value;

  /// The value is US dollars (world gold ounce), not Toman.
  final bool isUsd;

  const LiveCell({this.value, this.isUsd = false});

  static const empty = LiveCell();
}

/// One source's full reading at a moment in time.
@immutable
class LiveSnapshot {
  final String source; // 'tgju' | 'estjt'
  final DateTime fetchedAt;

  /// True when the reading could not be fetched and last-known values were
  /// carried forward (ftgn's 💾 cache indicator).
  final bool stale;

  final Map<String, LiveCell> cells;

  /// Free-form note (estjt's own update-time line, an error message, …).
  final String? note;

  const LiveSnapshot({
    required this.source,
    required this.fetchedAt,
    this.stale = false,
    required this.cells,
    this.note,
  });
}

/// Definition of one board row.
@immutable
class LiveBoardRow {
  final String key;
  final String labelFa;

  /// Raw Persian label as estjt.ir renders it (null → row not on estjt).
  final String? estjtLabel;

  /// tgju API instrument slug (null → row not on tgju).
  final String? tgjuSlug;

  /// Sanity bounds in Toman; readings outside them are dropped. Null bounds
  /// (unusual-scale rows like silver or the world ounce) skip the check.
  final double? minToman;
  final double? maxToman;

  const LiveBoardRow({
    required this.key,
    required this.labelFa,
    this.estjtLabel,
    this.tgjuSlug,
    this.minToman,
    this.maxToman,
  });

  bool get onEstjt => estjtLabel != null;
  bool get onTgju => tgjuSlug != null;
}

/// The board rows — the shared gold/coin instruments both sources carry plus
/// the tgju-only extras (silver, molten gold, central-bank coin). Keys mirror
/// Montala's symbol ids where a row is one of the eight assets.
const List<LiveBoardRow> kLiveBoardRows = [
  LiveBoardRow(
    key: 'sekee',
    labelFa: 'سکه امامی',
    estjtLabel: 'سکه طرح جدید',
    tgjuSlug: 'sekee',
    minToman: 50000000,
    maxToman: 300000000,
  ),
  LiveBoardRow(
    key: 'sekeb',
    labelFa: 'سکه بهار آزادی',
    estjtLabel: 'سکه طرح قدیم',
    tgjuSlug: 'sekeb',
    minToman: 30000000,
    maxToman: 300000000,
  ),
  LiveBoardRow(
    key: 'gold24',
    labelFa: 'طلای ۲۴ عیار',
    estjtLabel: 'طلای ۲۴ عیار',
    tgjuSlug: 'geram24',
    minToman: 1000000,
    maxToman: 50000000,
  ),
  LiveBoardRow(
    key: 'gold18',
    labelFa: 'طلای ۱۸ عیار',
    estjtLabel: 'طلای ۱۸ عیار',
    tgjuSlug: 'geram18',
    minToman: 1000000,
    maxToman: 50000000,
  ),
  LiveBoardRow(
    key: 'mesghal',
    labelFa: 'مثقال / مظنه تهران',
    estjtLabel: 'مظنه تهران',
    tgjuSlug: 'mesghal',
    minToman: 5000000,
    maxToman: 500000000,
  ),
  LiveBoardRow(
    key: 'nim',
    labelFa: 'نیم‌سکه',
    estjtLabel: 'نیم سکه',
    tgjuSlug: 'nim',
    minToman: 10000000,
    maxToman: 200000000,
  ),
  LiveBoardRow(
    key: 'rob',
    labelFa: 'ربع‌سکه',
    estjtLabel: 'ربع سکه',
    tgjuSlug: 'rob',
    minToman: 5000000,
    maxToman: 100000000,
  ),
  LiveBoardRow(
    key: 'gerami',
    labelFa: 'سکه گرمی',
    estjtLabel: 'سکه گرمی',
    tgjuSlug: 'gerami',
    minToman: 5000000,
    maxToman: 60000000,
  ),
  LiveBoardRow(
    key: 'gold_ons',
    labelFa: 'انس جهانی طلا',
    estjtLabel: 'انس جهانی طلا',
    tgjuSlug: 'ons',
  ),
  LiveBoardRow(
    key: 'gold_futures',
    labelFa: 'آبشده نقدی',
    tgjuSlug: 'gold_futures',
  ),
  LiveBoardRow(
    key: 'silver_ons',
    labelFa: 'انس نقره',
    tgjuSlug: 'silver',
  ),
  LiveBoardRow(
    key: 'silver_999',
    labelFa: 'گرم نقره ۹۹۹',
    tgjuSlug: 'silver_999',
  ),
  LiveBoardRow(
    key: 'seke_gc',
    labelFa: 'تمام سکه مرکزی',
    tgjuSlug: 'gc16',
  ),
];

/// Historical estjt label spellings → row key (port of `_LABEL_ALIASES`):
/// the site has drifted between «طلای ۲۴ عیار» and «طلا ۲۴ عیار» before.
const Map<String, String> kEstjtLabelAliases = {
  'طلا ۲۴ عیار': 'gold24',
  'طلا ۱۸ عیار': 'gold18',
};

/// estjt's raw Persian label → canonical row key.
final Map<String, String> kEstjtLabelToKey = {
  for (final row in kLiveBoardRows)
    if (row.estjtLabel != null) row.estjtLabel!: row.key,
  ...kEstjtLabelAliases,
};

/// Parses a loosely-formatted Persian market number — exact port of
/// m0ntIsRich's `_parse_rial` behaviour seen in real payloads:
///  * Persian/Arabic-Indic digits → ASCII,
///  * `$` marks a dollar figure (returned as-is, no ÷10),
///  * commas are thousands separators and are dropped,
///  * the first `.` is the decimal point; later dots collapse away
///    (`"49.3211.36"` → 49.321136),
///  * a trailing `-` (or `+`) sign marker is stripped,
///  * anything unparseable comes back null.
///
/// Returns the raw parsed value; dividing Rial→Toman is the caller's job.
({double value, bool isUsd})? parseLooseMarketNumber(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  final isUsd = s.contains('\$');
  const faDigits = '۰۱۲۳۴۵۶۷۸۹';
  const arDigits = '٠١٢٣٤٥٦٧٨٩';
  final buf = StringBuffer();
  for (final ch in s.runes) {
    final c = String.fromCharCode(ch);
    final fa = faDigits.indexOf(c);
    final ar = arDigits.indexOf(c);
    if (fa >= 0) {
      buf.write(fa);
    } else if (ar >= 0) {
      buf.write(ar);
    } else {
      buf.write(c);
    }
  }
  s = buf.toString();

  // Drop everything that is not a digit, dot or comma, then handle markers.
  s = s.replaceAll('\$', '').trim();
  while (s.endsWith('-') || s.endsWith('+')) {
    s = s.substring(0, s.length - 1).trim();
  }
  s = s.replaceAll(',', '');

  // Keep the first dot as the decimal point, collapse later dots away.
  final firstDot = s.indexOf('.');
  if (firstDot != -1) {
    final head = s.substring(0, firstDot + 1);
    final tail = s.substring(firstDot + 1).replaceAll('.', '');
    s = head + tail;
  }

  final value = double.tryParse(s);
  if (value == null) return null;
  return (value: value, isUsd: isUsd);
}

bool _inBounds(LiveBoardRow row, double toman) {
  final min = row.minToman;
  final max = row.maxToman;
  if (min == null || max == null) return true;
  return toman >= min && toman <= max;
}

/// Fetches the tgju column from `api.tgju.org` — the same endpoint the price
/// updater uses; the last table row's close is the live price. Each slug is
/// independent: a slug that fails just leaves its cell empty.
Future<LiveSnapshot> fetchTgjuLive({http.Client? client}) async {
  final ownClient = client ?? http.Client();
  try {
    final rows =
        kLiveBoardRows.where((r) => r.onTgju).toList(growable: false);
    final results = await Future.wait(
      rows.map((r) => _fetchTgjuSlug(ownClient, r)),
    );
    final cells = <String, LiveCell>{};
    for (var i = 0; i < rows.length; i++) {
      if (results[i] != null) cells[rows[i].key] = results[i]!;
    }
    return LiveSnapshot(
      source: 'tgju',
      fetchedAt: DateTime.now(),
      cells: cells,
    );
  } finally {
    if (client == null) ownClient.close();
  }
}

Future<LiveCell?> _fetchTgjuSlug(http.Client client, LiveBoardRow row) async {
  try {
    final uri = Uri.parse(
      'https://api.tgju.org/v1/market/indicator/summary-table-data/'
      '${row.tgjuSlug}?lang=fa&order_dir=asc',
    );
    final response = await client
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['data'] is! List) {
      return null;
    }
    final data = payload['data'] as List;
    if (data.isEmpty) return null;
    final last = data.last;
    if (last is! List || last.length < 4) return null;
    final parsed = parseLooseMarketNumber('${last[3]}');
    if (parsed == null) return null;
    // tgju quotes are Rial; the board speaks Toman.
    if (parsed.isUsd) return LiveCell(value: parsed.value, isUsd: true);
    final toman = parsed.value / 10;
    if (!_inBounds(row, toman)) return null;
    return LiveCell(value: toman);
  } catch (_) {
    return null;
  }
}

/// Scrapes the estjt.ir live board (native platforms only — no CORS header).
Future<LiveSnapshot> fetchEstjtLive({http.Client? client}) async {
  final ownClient = client ?? http.Client();
  try {
    final uri = Uri.parse('https://www.estjt.ir/tv/');
    final response = await ownClient
        .get(uri, headers: _browserHeaders)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}', uri);
    }
    return parseEstjtHtml(response.body, fetchedAt: DateTime.now());
  } finally {
    if (client == null) ownClient.close();
  }
}

/// Parses the estjt.ir/tv HTML — port of `_extract_estjt_prices`: the board
/// is the element carrying the `tt-tv__prices` class (in practice a `<main>`
/// tag), one `div.tt-price-card` per instrument with a label span and a
/// value span (value class carries up/down modifiers).
@visibleForTesting
LiveSnapshot parseEstjtHtml(String body, {required DateTime fetchedAt}) {
  final doc = html_parser.parse(body);
  // The live page renders `<main class="tt-tv__prices">` — match by class,
  // not by tag; when the container is missing entirely, fall back to
  // searching the whole document for cards.
  final board = doc.querySelector('.tt-tv__prices');
  final cardRoot = board ?? doc;
  final cards = cardRoot.querySelectorAll('div.tt-price-card');
  if (board == null && cards.isEmpty) {
    throw const FormatException('estjt: board container not found — site '
        'structure may have changed');
  }

  String? updateNote;
  final floating = doc.querySelector('div.tt-tv__updated-floating');
  if (floating != null) {
    final text = floating.text.trim();
    const prefix = 'آخرین بروزرسانی قیمت:';
    updateNote = text.startsWith(prefix)
        ? text.substring(prefix.length).trim()
        : text;
  }

  final cells = <String, LiveCell>{};
  for (final card in cards) {
    final labelSpan = card.querySelector('span.tt-price-card__label');
    if (labelSpan == null) continue;
    final key = kEstjtLabelToKey[labelSpan.text.trim()];
    if (key == null) continue;

    dom.Element? valueSpan;
    for (final span in card.querySelectorAll('span')) {
      final cls = span.className;
      if (cls.contains('tt-price-card__value')) {
        valueSpan = span;
        break;
      }
    }
    if (valueSpan == null) continue;
    final parsed = parseLooseMarketNumber(valueSpan.text);
    if (parsed == null) continue;

    final row = kLiveBoardRows.firstWhere((r) => r.key == key);
    if (parsed.isUsd) {
      cells[key] = LiveCell(value: parsed.value, isUsd: true);
    } else {
      final toman = parsed.value;
      if (_inBounds(row, toman)) {
        cells[key] = LiveCell(value: toman);
      }
    }
  }

  return LiveSnapshot(
    source: 'estjt',
    fetchedAt: fetchedAt,
    cells: cells,
    note: updateNote,
  );
}

/// Carries a fresh board snapshot over the previous one — port of ftgn's
/// `merge_with_previous`: a cell whose new reading is missing keeps the last
/// known value instead of flashing to empty.
Map<String, LiveCell> mergeCells({
  required Map<String, LiveCell> previous,
  required Map<String, LiveCell> fresh,
}) {
  final merged = <String, LiveCell>{};
  for (final row in kLiveBoardRows) {
    final f = fresh[row.key];
    final p = previous[row.key];
    if (f != null && f.value != null) {
      merged[row.key] = f;
    } else if (p != null && p.value != null) {
      merged[row.key] = p;
    } else {
      merged[row.key] = LiveCell.empty;
    }
  }
  return merged;
}

/// Percent change between two readings; null when either side is missing.
double? changePct(double? previous, double? current) {
  if (previous == null || current == null) return null;
  if (previous == 0) return null;
  return (current - previous) / previous * 100;
}

const String _userAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

const Map<String, String> _browserHeaders = {
  'User-Agent': _userAgent,
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'fa-IR,fa;q=0.9,en;q=0.8',
};

/// Formats one board cell for display: the grouped Persian-digit value and
/// the unit that goes next to it. Values are stored in Toman; with
/// [inToman] off they display ×10 as Rial. Dollar cells (world ounce) are
/// always labelled دلار.
({String value, String unit}) formatLiveCell(LiveCell cell, bool inToman) {
  final v = cell.value;
  if (v == null) return (value: '—', unit: '');
  if (cell.isUsd) {
    return (
      value: '\$${toPersianDigits(groupThousands(v.round()))}',
      unit: 'دلار',
    );
  }
  if (inToman) {
    return (value: toPersianDigits(groupThousands(v.round())), unit: 'تومان');
  }
  return (
    value: toPersianDigits(groupThousands((v * 10).round())),
    unit: 'ریال',
  );
}
