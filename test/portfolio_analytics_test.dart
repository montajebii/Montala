/// Tests for the portfolio analytics: average-cost positions, realized P/L,
/// moving averages, volatility and z-score anomalies.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/models.dart';
import 'package:montala/core/portfolio/portfolio_analytics.dart';
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
  group('portfolioReport (average cost)', () {
    final history = <String, List<PriceRow>>{
      'sekee': [_row(2026, 1, 1, 120000000)],
    };

    test('single buy: cost basis, market value, roi', () {
      final report = portfolioReport(
        txs: [
          _tx(DateTime(2026, 1, 1), 'sekee', 'BUY', 2, 100000000),
        ],
        history: history,
        basis: PriceBasis.close,
      );
      final p = report.positions.single;
      expect(p.units, 2);
      expect(p.avgCostToman, 100000000);
      expect(p.costBasisToman, 200000000);
      expect(p.marketValueToman, 240000000);
      expect(p.roiPct, closeTo(20, 1e-9));
      expect(report.realizedPnlToman, 0);
    });

    test('sell realizes pnl against average cost', () {
      final report = portfolioReport(
        txs: [
          _tx(DateTime(2026, 1, 1), 'sekee', 'BUY', 2, 100000000),
          _tx(DateTime(2026, 1, 2), 'sekee', 'SELL', 1, 110000000),
        ],
        history: history,
        basis: PriceBasis.close,
      );
      // Sell at 110 over avg 100 → +10M realized.
      expect(report.realizedPnlToman, 10000000);
      // Remaining unit: cost 100M, worth 120M → +20%.
      final p = report.positions.single;
      expect(p.units, 1);
      expect(p.avgCostToman, 100000000);
      expect(p.roiPct, closeTo(20, 1e-9));
    });

    test('two buys blend the average cost', () {
      final report = portfolioReport(
        txs: [
          _tx(DateTime(2026, 1, 1), 'sekee', 'BUY', 1, 100000000),
          _tx(DateTime(2026, 1, 2), 'sekee', 'BUY', 1, 140000000),
        ],
        history: history,
        basis: PriceBasis.close,
      );
      expect(report.positions.single.avgCostToman, 120000000);
      // Worth 120M vs avg 120M → zero roi.
      expect(report.positions.single.roiPct, closeTo(0, 1e-9));
    });

    test('fully sold asset leaves no open position', () {
      final report = portfolioReport(
        txs: [
          _tx(DateTime(2026, 1, 1), 'sekee', 'BUY', 1, 100000000),
          _tx(DateTime(2026, 1, 2), 'sekee', 'SELL', 1, 110000000),
        ],
        history: history,
        basis: PriceBasis.close,
      );
      expect(report.positions, isEmpty);
      expect(report.realizedPnlToman, 10000000);
    });
  });

  group('movingAverage', () {
    test('window of 3 with null head', () {
      final ma = movingAverage([1, 2, 3, 4, 5], 3);
      expect(ma[0], isNull);
      expect(ma[1], isNull);
      expect(ma[2], closeTo(2, 1e-9));
      expect(ma[3], closeTo(3, 1e-9));
      expect(ma[4], closeTo(4, 1e-9));
      // Output aligns 1:1 with the input.
      expect(ma.length, 5);
    });

    test('window 1 is identity', () {
      expect(movingAverage([7, 8], 1), [7, 8]);
    });
  });

  group('volatilityPct', () {
    test('flat series has zero volatility', () {
      expect(volatilityPct([100, 100, 100, 100]), 0);
    });

    test('swingy series beats a calm one', () {
      final calm = [for (var i = 0; i < 40; i++) 100.0 + i];
      final wild = [for (var i = 0; i < 40; i++) 100.0 + (i.isEven ? 10 : -10)];
      expect(volatilityPct(wild)!, greaterThan(volatilityPct(calm)!));
    });

    test('too short returns null', () {
      expect(volatilityPct([1, 2]), isNull);
    });
  });

  group('zscoreAnomalies', () {
    test('flags the far outlier only', () {
      final series = <double>[for (var i = 0; i < 30; i++) 100.0 + i, 10000];
      final hits = zscoreAnomalies(series);
      expect(hits, [30]);
    });

    test('uniform series has none', () {
      expect(zscoreAnomalies([5, 5, 5, 5]), isEmpty);
    });
  });
}
