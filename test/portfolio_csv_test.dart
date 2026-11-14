/// Tests for the portfolio CSV export/import: round-trip, quoting of notes,
/// and row-level error reporting instead of all-or-nothing failure.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/portfolio/portfolio_csv.dart';
import 'package:montala/core/portfolio/portfolio_models.dart';

void main() {
  group('encodeTxsCsv → parseTxsCsv round-trip', () {
    test('preserves every field', () {
      final txs = [
        PortfolioTx(
          date: DateTime(2026, 1, 5),
          assetId: 'sekee',
          type: 'BUY',
          units: 1,
          unitPriceToman: 100000000,
          note: 'هدیه پدربزرگ',
        ),
        PortfolioTx(
          date: DateTime(2026, 2, 1),
          assetId: 'gold18',
          type: 'SELL',
          units: 3.5,
          unitPriceToman: 25000000.5,
        ),
      ];
      final parsed = parseTxsCsv(encodeTxsCsv(txs));
      expect(parsed.ok, isTrue);
      expect(parsed.txs.length, 2);

      expect(parsed.txs[0].assetId, 'sekee');
      expect(parsed.txs[0].note, 'هدیه پدربزرگ');
      // Output is date-sorted.
      expect(parsed.txs[0].date, DateTime(2026, 1, 5));
      expect(parsed.txs[1].units, 3.5);
      expect(parsed.txs[1].unitPriceToman, 25000000.5);
      expect(parsed.txs[1].note, isNull);
    });

    test('notes containing commas and quotes survive quoting', () {
      final csv = [
        kPortfolioCsvHeader,
        '2026-01-05,sekee,BUY,1,100000000,"خرید، با ویرگول"',
        '2026-01-06,sekee,SELL,1,110000000,"گفت ""فروش"" گفت"',
      ].join('\n');
      final parsed = parseTxsCsv(csv);
      expect(parsed.errors, isEmpty);
      expect(parsed.txs[0].note, 'خرید، با ویرگول');
      expect(parsed.txs[1].note, 'گفت "فروش" گفت');
    });

    test('header-only file parses to nothing', () {
      final parsed = parseTxsCsv('$kPortfolioCsvHeader\n');
      expect(parsed.txs, isEmpty);
      expect(parsed.errors, isEmpty);
    });
  });

  group('parseTxsCsv error reporting', () {
    test('bad rows are reported per line, good rows kept', () {
      final csv = [
        kPortfolioCsvHeader,
        '2026-01-05,sekee,BUY,1,100000000,', // ok
        'not-a-date,sekee,BUY,1,100000000,', // bad date
        '2026-01-06,gold18,HODL,1,10000000,', // bad type
        '2026-01-07,gold18,BUY,0,10000000,', // zero units
        '2026-01-08,gold18,BUY,2', // wrong column count
      ].join('\n');
      final parsed = parseTxsCsv(csv);
      expect(parsed.txs.length, 1);
      expect(parsed.errors.length, 4);
      expect(parsed.errors.first, contains('خط 3'));
    });

    test('numbers with thousands separators still parse', () {
      final parsed = parseTxsCsv(
        '$kPortfolioCsvHeader\n2026-01-05,sekee,BUY,2,"120,000,000",',
      );
      expect(parsed.txs.single.unitPriceToman, 120000000);
    });
  });
}
