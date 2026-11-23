/// Tests for the live quote service — the parser port of m0ntIsRich's
/// `_parse_rial` (including the odd real-world payloads), the estjt HTML
/// extraction, and the carry-forward merge of the board.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:montala/core/net/live_quotes.dart';

String _fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('parseLooseMarketNumber (port of _parse_rial)', () {
    test('plain Toman number', () {
      final r = parseLooseMarketNumber('253,700,000');
      expect(r, isNotNull);
      expect(r!.value, 253700000);
      expect(r.isUsd, isFalse);
    });

    test('trailing minus marker is stripped (tgju trend column)', () {
      final r = parseLooseMarketNumber('333,847,000-');
      expect(r!.value, 333847000);
    });

    test('multiple dots collapse to the first one (real tgju anomaly)', () {
      // tgju انس نقره once served this; the Python port keeps the same
      // lossy behaviour so values stay comparable.
      final r = parseLooseMarketNumber('49.3211.36');
      expect(r!.value, closeTo(49.321136, 1e-9));
    });

    test('mixed comma/dot payload (real tgju anomaly)', () {
      final r = parseLooseMarketNumber('4,560,4000.38');
      expect(r!.value, closeTo(45604000.38, 1e-6));
    });

    test('Persian digits normalize to ASCII', () {
      final r = parseLooseMarketNumber('۲۵۳,۷۰۰٬۰۰۰'.replaceAll('٬', ','));
      expect(r!.value, 253700000);
    });

    test('dollar figure is flagged, not converted', () {
      final r = parseLooseMarketNumber(r'$3,875');
      expect(r!.value, 3875);
      expect(r.isUsd, isTrue);
    });

    test('garbage returns null', () {
      expect(parseLooseMarketNumber(''), isNull);
      expect(parseLooseMarketNumber('—'), isNull);
      expect(parseLooseMarketNumber('داده‌ای نیست'), isNull);
    });
  });

  group('parseEstjtHtml', () {
    const fixture = '''
    <html><body><main>
      <div class="tt-tv__prices">
        <div class="tt-price-card">
          <span class="tt-price-card__label">سکه طرح جدید</span>
          <span class="tt-price-card__value is-up">253,700,000</span>
        </div>
        <div class="tt-price-card">
          <span class="tt-price-card__label">طلای ۱۸ عیار</span>
          <span class="tt-price-card__value is-down">24,989,700</span>
        </div>
        <div class="tt-price-card">
          <span class="tt-price-card__label">انس جهانی طلا</span>
          <span class="tt-price-card__value">\$3,875</span>
        </div>
        <div class="tt-price-card">
          <span class="tt-price-card__label">طلا ۲۴ عیار</span>
          <span class="tt-price-card__value is-up">33,000,000</span>
        </div>
      </div>
      <div class="tt-tv__updated-floating">
        آخرین بروزرسانی قیمت: ۱۳ آبان ۱۴۰۵ - ۲۳:۱۷:۰۳
      </div>
    </main></body></html>
    ''';

    test('real estjt board fixture parses the shared rows', () {
      final snap = parseEstjtHtml(
        _fixture('estjt_tv.html'),
        fetchedAt: DateTime(2026, 11, 20),
      );
      // estjt quotes Toman directly, except the dollar ounce.
      expect(snap.cells['sekee']!.value, 244000000);
      expect(snap.cells['sekee']!.isUsd, isFalse);
      expect(snap.cells['gold18']!.value, 23551500);
      expect(snap.cells['gold_ons']!.value, 3570);
      expect(snap.cells['gold_ons']!.isUsd, isTrue);
    });

    test('labels map to canonical keys and values parse', () {
      final snap = parseEstjtHtml(fixture, fetchedAt: DateTime(2026));
      expect(snap.source, 'estjt');
      expect(snap.cells['sekee']?.value, 253700000);
      expect(snap.cells['sekee']?.isUsd, isFalse);
      expect(snap.cells['gold18']?.value, 24989700);
      // The historical spelling «طلا ۲۴ عیار» still maps via the alias table.
      expect(snap.cells['gold24']?.value, 33000000);
      // World ounce keeps its dollar flag and skips the Toman path.
      expect(snap.cells['gold_ons']?.value, 3875);
      expect(snap.cells['gold_ons']?.isUsd, isTrue);
      // Rows not on the page come back absent.
      expect(snap.cells.containsKey('gold_futures'), isFalse);
      // estjt's own update-time line survives as the note.
      expect(snap.note, contains('۱۴۰۵'));
    });

    test('unknown label is skipped, not crashed on', () {
      const html = '''
      <div class="tt-tv__prices">
        <div class="tt-price-card">
          <span class="tt-price-card__label">چیز ناشناخته</span>
          <span class="tt-price-card__value">123</span>
        </div>
      </div>''';
      final snap = parseEstjtHtml(html, fetchedAt: DateTime(2026));
      expect(snap.cells, isEmpty);
    });

    test('missing board container throws a descriptive error', () {
      expect(
        () => parseEstjtHtml('<html><body></body></html>',
            fetchedAt: DateTime(2026)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('tgju live widget feed (real fixture, 2026-11-20)', () {
    late LiveSnapshot snap;

    setUpAll(() async {
      final body = _fixture('tgju_live_widget.json');
      final client = MockClient((request) async {
        expect(request.url.host, 'api.tgju.org');
        expect(request.url.path, '/v1/widget/tmp');
        expect(request.url.queryParameters['keys'], contains('silver_999'));
        return http.Response(body, 200,
            headers: {'content-type': 'application/json'});
      });
      snap = await fetchTgjuLive(client: client);
    });

    test('gold ounce keeps its USD value (not 367 Toman)', () {
      final cell = snap.cells['gold_ons']!;
      expect(cell.isUsd, isTrue);
      expect(cell.value, closeTo(3569.88, 1e-9));
      final (:value, :unit) = formatLiveCell(cell, true);
      expect(unit, 'دلار');
      expect(value, r'$۳٬۵۶۹٫۸۸');
    });

    test('silver ounce keeps its USD value (not 4 Toman)', () {
      final cell = snap.cells['silver_ons']!;
      expect(cell.isUsd, isTrue);
      expect(cell.value, closeTo(41.97, 1e-9));
      final (:value, :unit) = formatLiveCell(cell, true);
      expect(unit, 'دلار');
      expect(value, r'$۴۱٫۹۷');
    });

    test('silver 999 is the live Rial quote converted once', () {
      final cell = snap.cells['silver_999']!;
      expect(cell.isUsd, isFalse);
      // Live p was 4,051,800 Rial; the board stores Toman.
      expect(cell.value, closeTo(405180, 1e-9));

      final toman = formatLiveCell(cell, true);
      expect(toman.unit, 'تومان');
      expect(toman.value, '۴۰۵٬۱۸۰');

      final rial = formatLiveCell(cell, false);
      expect(rial.unit, 'ریال');
      expect(rial.value, '۴٬۰۵۱٬۸۰۰');
    });

    test('all 13 board slugs are populated', () {
      expect(snap.cells.length, kLiveBoardRows.length);
      for (final row in kLiveBoardRows) {
        expect(snap.cells[row.key]?.value, isNotNull, reason: row.key);
      }
    });
  });

  group('daily archive fixture (the old, stale source)', () {
    test('silver_999 tail is the previous close, not the live value', () {
      final payload =
          jsonDecode(_fixture('tgju_summary_silver_999.json')) as Map;
      final last = (payload['data'] as List).last as List;
      final close = parseLooseMarketNumber('${last[3]}')!;
      expect(close.value, 4166300); // 2026-11-19 close, Rial
      expect(close.value / 10, 416630); // what the board used to show

      final livePayload =
          jsonDecode(_fixture('tgju_live_widget.json')) as Map;
      final indicators =
          (livePayload['response'] as Map)['indicators'] as List;
      final live = indicators.firstWhere((i) => i['name'] == 'silver_999');
      expect(live['p'], '4051800');
      expect(int.parse(live['p'] as String), isNot(close.value.round()));
    });
  });

  group('board merge + change (port of merge_with_previous)', () {
    test('missing fresh cell carries the previous value forward as stale', () {
      final prev = {
        'sekee': const LiveCell(value: 253700000),
        'gold18': const LiveCell(value: 24989700),
      };
      final fresh = {
        'sekee': const LiveCell(value: 254000000),
        // gold18 fetch failed this round
      };
      final merged = mergeCells(previous: prev, fresh: fresh);
      expect(merged['sekee']!.value, 254000000);
      expect(merged['sekee']!.stale, isFalse);
      expect(merged['gold18']!.value, 24989700);
      expect(merged['gold18']!.stale, isTrue);
      // Rows with no data on either side stay empty, not null-keyed.
      expect(merged['silver_ons']!.value, isNull);
    });

    test('fallback fills missing rows and tags the source visibly', () {
      final primary = {
        'sekee': const LiveCell(value: 253700000),
      };
      final tgju = {
        'sekee': const LiveCell(value: 254000000),
        'gold18': const LiveCell(value: 24989700),
      };
      final out = fallbackMissing(
        primary: primary,
        fallback: tgju,
        source: 'tgju',
      );
      expect(out['sekee']!.value, 253700000);
      expect(out['sekee']!.fallbackSource, isNull);
      expect(out['gold18']!.value, 24989700);
      expect(out['gold18']!.stale, isTrue);
      expect(out['gold18']!.fallbackSource, 'tgju');
      // Never fabricated.
      expect(out['silver_ons']!.value, isNull);
    });

    test('changePct', () {
      expect(changePct(100, 110), closeTo(10, 1e-9));
      expect(changePct(110, 100), closeTo(-9.0909, 1e-3));
      expect(changePct(null, 100), isNull);
      expect(changePct(100, null), isNull);
      expect(changePct(0, 5), isNull);
    });
  });

  group('formatLiveCell (unit display + Toman/Rial toggle)', () {
    test('dollar cells show cents and دلار', () {
      final (:value, :unit) =
          formatLiveCell(const LiveCell(value: 3883.4, isUsd: true), true);
      expect(value, r'$۳٬۸۸۳٫۴۰');
      expect(unit, 'دلار');
    });

    test('toman mode keeps stored value', () {
      final (:value, :unit) =
          formatLiveCell(const LiveCell(value: 37000000), true);
      expect(unit, 'تومان');
      expect(value, contains('۳۷٬۰۰۰٬۰۰۰'));
    });

    test('rial mode multiplies by ten and relabels', () {
      final (:value, :unit) =
          formatLiveCell(const LiveCell(value: 37000000), false);
      expect(unit, 'ریال');
      expect(value, contains('۳۷۰٬۰۰۰٬۰۰۰'));
    });

    test('empty cell renders a dash with no unit', () {
      final (:value, :unit) = formatLiveCell(const LiveCell(), true);
      expect(value, '—');
      expect(unit, isEmpty);
    });
  });
}
