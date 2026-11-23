/// Tests for the portfolio CSV export/import: the timestamped m0ntIsRich
/// schema, the first Montala release's day-only schema, the value-history
/// matrix, quoting, and row-level error reporting.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/portfolio/portfolio_csv.dart';
import 'package:montala/core/portfolio/portfolio_models.dart';

String _fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('encodeTxsCsv → parseTxsCsv round-trip', () {
    test('preserves every field, including sub-second timestamps', () {
      final txs = [
        PortfolioTx(
          timestamp: DateTime(2026, 1, 5, 9, 15, 30, 123, 456),
          assetId: 'sekee',
          type: 'BUY',
          units: 1,
          unitPriceToman: 100000000,
          totalToman: 100000000,
          source: 'import',
          note: 'هدیه پدربزرگ',
        ),
        PortfolioTx(
          timestamp: DateTime(2026, 2, 1, 18, 5, 1),
          assetId: 'gold18',
          type: 'SELL',
          units: 3.5,
          unitPriceToman: 25000000.5,
          totalToman: 87500001.75,
          note: null,
        ),
      ];
      final parsed = parseTxsCsv(encodeTxsCsv(txs));
      expect(parsed.ok, isTrue);
      expect(parsed.txs.length, 2);

      expect(parsed.txs[0].assetId, 'sekee');
      expect(parsed.txs[0].timestamp,
          DateTime(2026, 1, 5, 9, 15, 30, 123, 456));
      expect(parsed.txs[0].source, 'import');
      expect(parsed.txs[0].note, 'هدیه پدربزرگ');
      expect(parsed.txs[0].totalToman, 100000000);
      // Output is timestamp-sorted.
      expect(parsed.txs[1].units, 3.5);
      expect(parsed.txs[1].unitPriceToman, 25000000.5);
      expect(parsed.txs[1].totalToman, 87500001.75);
      expect(parsed.txs[1].note, isNull);
    });

    test('an explicit total that disagrees with price is preserved', () {
      final txs = [
        PortfolioTx(
          timestamp: DateTime(2026, 1, 5),
          assetId: 'sekee',
          type: 'BUY',
          units: 2,
          unitPriceToman: 100,
          totalToman: 250,
        ),
      ];
      final parsed = parseTxsCsv(encodeTxsCsv(txs));
      expect(parsed.ok, isTrue);
      expect(parsed.txs.single.unitPriceToman, 100);
      expect(parsed.txs.single.totalToman, 250);
    });

    test('incomplete rows keep blanks and stay incomplete', () {
      final txs = [
        PortfolioTx(
          timestamp: DateTime(2026, 3, 2, 12, 0, 0),
          assetId: 'gold24',
          type: 'BUY',
          units: 1.5,
          unitPriceToman: 0,
          totalToman: 0,
          incomplete: true,
        ),
      ];
      final csv = encodeTxsCsv(txs);
      expect(csv, contains('2026-03-02 12:00:00,gold24,BUY,1.5,,,manual,'));
      final parsed = parseTxsCsv(csv);
      expect(parsed.ok, isTrue);
      expect(parsed.txs.single.incomplete, isTrue);
      expect(parsed.txs.single.unitPriceToman, 0);
      expect(parsed.txs.single.totalToman, 0);
    });

    test('notes containing commas and quotes survive quoting', () {
      final csv = [
        kPortfolioCsvHeader,
        '2026-01-05 09:00:00,sekee,BUY,1,100000000,100000000,manual,'
            '"خرید، با ویرگول"',
        '2026-01-06 10:00:00,sekee,SELL,1,110000000,110000000,manual,'
            '"گفت ""فروش"" گفت"',
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

  group('legacy m0ntIsRich schema', () {
    test('parses the real Python transactions.csv (7 columns, no note)',
        () {
      final parsed = parseTxsCsv(_fixture('legacy_transactions.csv'));
      expect(parsed.ok, isTrue);
      expect(parsed.txs.length, 4);
      expect(parsed.txs.first.assetId, 'gold24'); // shemsh24 alias
      expect(parsed.txs.first.type, 'BUY');
      expect(parsed.txs.first.timestamp,
          DateTime(2026, 9, 3, 3, 41, 0));
      expect(parsed.txs.first.source, 'auto');
      expect(parsed.txs.first.totalToman, 7500000);
      expect(parsed.txs[1].timestamp,
          DateTime(2026, 9, 3, 4, 8, 21, 771, 873));
    });

    test('geram aliases map to gold ids', () {
      final csv = [
        'timestamp,asset,event_type,units,unit_price_toman,total_toman,source',
        '2026-01-01 00:00:00,geram18,BUY,2,10000000,20000000,auto',
      ].join('\n');
      final parsed = parseTxsCsv(csv);
      expect(parsed.txs.single.assetId, 'gold18');
      expect(parsed.txs.single.source, 'auto');
    });
  });

  group('first Montala release schema', () {
    test('day-only header still imports', () {
      final csv = [
        kLegacyPortfolioCsvHeader,
        '2026-01-05,sekee,BUY,1,100000000,"قدیمی"',
        '2026-01-06,gold18,SELL,2,20000000,',
      ].join('\n');
      final parsed = parseTxsCsv(csv);
      expect(parsed.ok, isTrue);
      expect(parsed.txs.length, 2);
      expect(parsed.txs[0].date, DateTime(2026, 1, 5));
      expect(parsed.txs[0].source, 'legacy');
      expect(parsed.txs[0].note, 'قدیمی');
      expect(parsed.txs[1].totalToman, 40000000);
    });
  });

  group('parseTxsCsv error reporting', () {
    test('bad rows are reported per line, good rows kept', () {
      final csv = [
        kPortfolioCsvHeader,
        '2026-01-05 09:00:00,sekee,BUY,1,100000000,100000000,manual,',
        'not-a-time,sekee,BUY,1,100000000,100000000,manual,',
        '2026-01-06 09:00:00,gold18,HODL,1,10000000,10000000,manual,',
        '2026-01-07 09:00:00,gold18,BUY,0,10000000,0,manual,',
        '2026-01-08 09:00:00,bogus,BUY,1,10000000,10000000,manual,',
      ].join('\n');
      final parsed = parseTxsCsv(csv);
      expect(parsed.txs.length, 1);
      expect(parsed.errors.length, 4);
      expect(parsed.errors.first, contains('خط 3'));
    });

    test('blank money columns become an incomplete row, not an error', () {
      final csv = [
        kPortfolioCsvHeader,
        '2026-01-05 09:00:00,gold24,BUY,2,,,manual,',
      ].join('\n');
      final parsed = parseTxsCsv(csv);
      expect(parsed.errors, isEmpty);
      expect(parsed.txs.single.incomplete, isTrue);
      expect(parsed.txs.single.units, 2);
    });

    test('a total alone is enough to derive the unit price', () {
      final csv = [
        kPortfolioCsvHeader,
        '2026-01-05 09:00:00,gold24,BUY,2,,120000000,manual,',
      ].join('\n');
      final parsed = parseTxsCsv(csv);
      expect(parsed.ok, isTrue);
      expect(parsed.txs.single.unitPriceToman, 60000000);
      expect(parsed.txs.single.incomplete, isFalse);
    });

    test('numbers with thousands separators and Persian digits parse', () {
      final parsed = parseTxsCsv(
        '$kPortfolioCsvHeader\n'
        '2026-01-05 09:00:00,sekee,BUY,2,"۱۲۰٬۰۰۰٬۰۰۰",'
        '"۲۴۰٬۰۰۰٬۰۰۰",manual,',
      );
      expect(parsed.ok, isTrue);
      expect(parsed.txs.single.unitPriceToman, 120000000);
      expect(parsed.txs.single.totalToman, 240000000);
    });
  });

  group('snapshot CSV', () {
    test('round-trips the matrix with canonical asset order', () {
      final snapshots = [
        PortfolioSnapshot(
          timestamp: DateTime(2026, 11, 20, 16, 50, 13),
          lines: const [
            SnapshotLine(assetId: 'sekee', units: 1, valueToman: 253300000),
            SnapshotLine(assetId: 'gold18', units: 5.98, valueToman: 148733962),
          ],
          totalToman: 402033962,
          source: 'launch',
        ),
        PortfolioSnapshot(
          timestamp: DateTime(2026, 11, 21, 9, 0, 0),
          lines: const [
            SnapshotLine(assetId: 'sekee', units: 1, valueToman: 254000000),
          ],
          totalToman: 254000000,
          source: 'recalc',
        ),
      ];
      final parsed = parseSnapshotsCsv(encodeSnapshotsCsv(snapshots));
      expect(parsed.ok, isTrue);
      expect(parsed.snapshots.length, 2);
      expect(parsed.snapshots.first.lines.length, 2);
      expect(parsed.snapshots.first.lineFor('sekee')!.units, 1);
      expect(parsed.snapshots.first.totalToman, 402033962);
      expect(parsed.snapshots.first.source, 'launch');
      expect(parsed.snapshots[1].source, 'recalc');
    });

    test('parses the real m0ntIsRich sarmaye_history.csv', () {
      final parsed = parseSnapshotsCsv(
        _fixture('legacy_sarmaye_history.csv'),
      );
      expect(parsed.ok, isTrue);
      expect(parsed.snapshots.length, 3);
      final first = parsed.snapshots.first;
      expect(first.timestamp, DateTime(2026, 11, 15, 15, 11, 9));
      expect(first.lineFor('sekee')!.units, 1);
      expect(first.lineFor('gold24')!.units, 5);
      expect(first.lineFor('gold18')!.valueToman, 148733962);
      expect(first.totalToman, 567828962);
      expect(first.source, 'import');
    });

    test('a missing total is the sum of the asset values', () {
      final csv = [
        'timestamp,sekee_units,sekee_value_toman,total_toman',
        '2026-01-05 10:00:00,1,100000000,',
      ].join('\n');
      final parsed = parseSnapshotsCsv(csv);
      expect(parsed.ok, isTrue);
      expect(parsed.snapshots.single.totalToman, 100000000);
    });

    test('unrecognised header is reported', () {
      final parsed = parseSnapshotsCsv('foo,bar,baz\n1,2,3\n');
      expect(parsed.snapshots, isEmpty);
      expect(parsed.errors, isNotEmpty);
    });
  });
}
