/// Tests for the live quote service — the parser port of m0ntIsRich's
/// `_parse_rial` (including the odd real-world payloads), the estjt HTML
/// extraction, and the carry-forward merge of the board.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/net/live_quotes.dart';

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
          <span class="tt-price-card__label">طلا ۱۸ عیار</span>
          <span class="tt-price-card__value is-down">24,989,700</span>
        </div>
        <div class="tt-price-card">
          <span class="tt-price-card__label">انس جهانی طلا</span>
          <span class="tt-price-card__value">\$3,875</span>
        </div>
      </div>
      <div class="tt-tv__updated-floating">
        آخرین بروزرسانی قیمت: ۱۳ آبان ۱۴۰۵ - ۲۳:۱۷:۰۳
      </div>
    </main></body></html>
    ''';

    test('labels map to canonical keys and values parse', () {
      final snap = parseEstjtHtml(fixture, fetchedAt: DateTime(2026));
      expect(snap.source, 'estjt');
      expect(snap.cells['sekee']?.value, 253700000);
      expect(snap.cells['sekee']?.isUsd, isFalse);
      expect(snap.cells['gold18']?.value, 24989700);
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

  group('board merge + change (port of merge_with_previous)', () {
    test('missing fresh cell carries the previous value forward', () {
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
      expect(merged['gold18']!.value, 24989700);
      // Rows with no data on either side stay empty, not null-keyed.
      expect(merged['silver_ons']!.value, isNull);
    });

    test('changePct', () {
      expect(changePct(100, 110), closeTo(10, 1e-9));
      expect(changePct(110, 100), closeTo(-9.0909, 1e-3));
      expect(changePct(null, 100), isNull);
      expect(changePct(100, null), isNull);
      expect(changePct(0, 5), isNull);
    });
  });
}
