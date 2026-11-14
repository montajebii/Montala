/// Tests for the portfolio valuation math: units from the transaction log,
/// the value series against a synthetic price archive, and sell validation.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/models.dart';
import 'package:montala/core/portfolio/portfolio_calc.dart';
import 'package:montala/core/portfolio/portfolio_models.dart';

PriceRow _row(int y, int m, int d, int close) => PriceRow(
      date: DateTime(y, m, d),
      persianDate: '',
      open: close,
      low: close,
      high: close,
      close: close,
    );

PortfolioTx _tx(
  DateTime date,
  String asset,
  String type,
  double units,
  double price,
) =>
    PortfolioTx(
      date: date,
      assetId: asset,
      type: type,
      units: units,
      unitPriceToman: price,
    );

void main() {
  final history = <String, List<PriceRow>>{
    'sekee': [
      _row(1404, 1, 1, 100000000),
      _row(1404, 1, 2, 110000000),
      _row(1404, 1, 4, 120000000), // no trading on day 3
      _row(1404, 1, 5, 130000000),
    ],
    'gold18': [
      _row(1404, 1, 1, 10000000),
      _row(1404, 1, 2, 11000000),
      _row(1404, 1, 3, 12000000),
      _row(1404, 1, 4, 13000000),
      _row(1404, 1, 5, 14000000),
    ],
  };

  group('unitsAt', () {
    test('buy then partial sell', () {
      final txs = [
        _tx(DateTime(1404, 1, 1), 'sekee', 'BUY', 2, 100000000),
        _tx(DateTime(1404, 1, 3), 'sekee', 'SELL', 0.5, 115000000),
      ];
      expect(unitsAt(txs, DateTime(1404, 1, 1))['sekee'], 2);
      expect(unitsAt(txs, DateTime(1404, 1, 2))['sekee'], 2);
      expect(unitsAt(txs, DateTime(1404, 1, 3))['sekee'], closeTo(1.5, 1e-9));
      // Before any transaction: no entry.
      expect(unitsAt(txs, DateTime(1403, 12, 30)).containsKey('sekee'),
          isFalse);
    });

    test('backdated buy shifts history', () {
      final txs = [
        _tx(DateTime(1404, 1, 2), 'sekee', 'BUY', 1, 110000000),
        _tx(DateTime(1403, 6, 1), 'sekee', 'BUY', 3, 90000000),
      ];
      expect(unitsAt(txs, DateTime(1403, 12, 1))['sekee'], 3);
      expect(unitsAt(txs, DateTime(1404, 1, 2))['sekee'], 4);
    });
  });

  group('assertSellAllowed', () {
    test('overselling throws', () {
      final txs = [
        _tx(DateTime(1404, 1, 1), 'sekee', 'BUY', 1, 100000000),
      ];
      expect(
        () => assertSellAllowed(txs,
            _tx(DateTime(1404, 1, 2), 'sekee', 'SELL', 2, 110000000)),
        throwsA(isA<PortfolioValidationException>()),
      );
    });

    test('selling exactly the holdings passes', () {
      final txs = [
        _tx(DateTime(1404, 1, 1), 'sekee', 'BUY', 2, 100000000),
        _tx(DateTime(1404, 1, 2), 'sekee', 'SELL', 1, 110000000),
      ];
      // Selling 1 more on day 3: 2 - 1 = 1 held → allowed.
      expect(
        () => assertSellAllowed(txs,
            _tx(DateTime(1404, 1, 3), 'sekee', 'SELL', 1, 120000000)),
        returnsNormally,
      );
    });

    test('editing a sell ignores its own previous effect', () {
      final txs = [
        _tx(DateTime(1404, 1, 1), 'sekee', 'BUY', 2, 100000000),
      ];
      // An existing SELL of 2 being re-validated against the log that still
      // contains it must not double-count itself.
      final edited = _tx(DateTime(1404, 1, 2), 'sekee', 'SELL', 2, 110000000)
          .copyWith(id: 7);
      expect(() => assertSellAllowed(txs + [edited], edited), returnsNormally);
    });
  });

  group('portfolioSeries', () {
    test('snaps to the nearest earlier trading day', () {
      final txs = [
        _tx(DateTime(1404, 1, 1), 'sekee', 'BUY', 1, 100000000),
      ];
      final series = portfolioSeries(
        txs: txs,
        history: history,
        basis: PriceBasis.close,
        from: DateTime(1404, 1, 1),
        to: DateTime(1404, 1, 5),
      );
      // Days 1, 2, 4, 5 have sekee prices (day 3 has none for sekee but gold
      // does — the union uses each asset's own rows).
      expect(series.length, 4);
      expect(series[0].totalToman, 100000000);
      expect(series[1].totalToman, 110000000);
      expect(series[2].totalToman, 120000000);
      expect(series[3].totalToman, 130000000);
    });

    test('multiple assets compose into the total', () {
      final txs = [
        _tx(DateTime(1404, 1, 1), 'sekee', 'BUY', 1, 100000000),
        _tx(DateTime(1404, 1, 2), 'gold18', 'BUY', 10, 11000000),
      ];
      final series = portfolioSeries(
        txs: txs,
        history: history,
        basis: PriceBasis.close,
        from: DateTime(1404, 1, 1),
        to: DateTime(1404, 1, 2),
      );
      expect(series[0].totalToman, 100000000);
      // Day 2: coin + 10 g × 11,000,000.
      expect(series[1].totalToman, 110000000 + 110000000);
      expect(series[1].valueByAsset['sekee'], 110000000);
      expect(series[1].valueByAsset['gold18'], 110000000);
    });

    test('sell drops the value after the sale date', () {
      final txs = [
        _tx(DateTime(1404, 1, 1), 'gold18', 'BUY', 10, 10000000),
        _tx(DateTime(1404, 1, 4), 'gold18', 'SELL', 10, 13000000),
      ];
      final series = portfolioSeries(
        txs: txs,
        history: history,
        basis: PriceBasis.close,
        from: DateTime(1404, 1, 1),
        to: DateTime(1404, 1, 5),
      );
      expect(series[2].totalToman, 120000000); // 10 g × 12M still held day 3
      // Day 5: everything sold → gold contributes nothing; sekee absent.
      expect(series[3].totalToman, 0);
    });
  });

  group('latestPoint', () {
    test('uses the last close of each asset', () {
      final txs = [
        _tx(DateTime(1404, 1, 1), 'gold18', 'BUY', 2, 10000000),
      ];
      final point = latestPoint(
        txs: txs,
        history: history,
        basis: PriceBasis.close,
      );
      expect(point, isNotNull);
      expect(point!.valueByAsset['gold18'], 2 * 14000000);
      expect(point.totalToman, 28000000);
    });

    test('null when nothing is held', () {
      expect(
        latestPoint(txs: const [], history: history,
            basis: PriceBasis.close),
        isNull,
      );
    });
  });

  test('firstTxDate picks the earliest transaction', () {
    expect(
      firstTxDate([
        _tx(DateTime(1404, 3, 1), 'sekee', 'BUY', 1, 1),
        _tx(DateTime(1403, 1, 1), 'sekee', 'BUY', 1, 1),
      ]),
      DateTime(1403, 1, 1),
    );
    expect(firstTxDate(const []), isNull);
  });
}
