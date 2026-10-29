import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/calc/calculator.dart';
import 'package:montala/core/calc/forecast.dart';
import 'package:montala/core/models.dart';

PriceRow row(String iso, int price) => PriceRow(
      date: DateTime.parse(iso),
      persianDate: 'x',
      open: price,
      low: price,
      high: price,
      close: price,
    );

List<PriceRow> series(DateTime start, int days, int startPrice, double dailyGrowth) {
  final out = <PriceRow>[];
  var p = startPrice.toDouble();
  for (var i = 0; i < days; i++) {
    final d = start.add(Duration(days: i));
    out.add(row(d.toIso8601String().substring(0, 10), p.round()));
    p *= 1 + dailyGrowth;
  }
  return out;
}

void main() {
  group('rowOnOrBefore', () {
    final rows = [
      row('2024-01-01', 100),
      row('2024-01-05', 110),
      row('2024-01-09', 120),
    ];

    test('returns exact match', () {
      expect(rowOnOrBefore(rows, DateTime(2024, 1, 5))!.close, 110);
    });

    test('falls back to the nearest earlier trading day', () {
      // 2024-01-07 is a gap between recorded days.
      final found = rowOnOrBefore(rows, DateTime(2024, 1, 7));
      expect(found!.date, DateTime(2024, 1, 5));
      expect(found.close, 110);
    });

    test('returns null when the target precedes the whole series', () {
      expect(rowOnOrBefore(rows, DateTime(2023, 12, 20)), isNull);
    });

    test('clamps to the last row for a later target', () {
      expect(rowOnOrBefore(rows, DateTime(2026, 1, 1))!.close, 120);
    });
  });

  group('Calculator', () {
    final hist = {
      'dollar': series(DateTime(2023, 1, 1), 700, 500000, 0.0008),
      'gold18': series(DateTime(2023, 1, 1), 700, 20000000, 0.0012),
    };

    test('computes a profit when price rose', () {
      final calc = Calculator(hist);
      final result = calc.run(CalcInput(
        amountRial: 100000000,
        buyDate: DateTime(2023, 6, 1),
        sellDate: DateTime(2024, 6, 1),
        basis: PriceBasis.close,
        splitAmount: false,
      ));
      final dollar = result.ranked.firstWhere((r) => r.symbolId == 'dollar');
      expect(dollar.hasResult, isTrue);
      expect(dollar.profitRial! > 0, isTrue);
      expect(dollar.profitPercent! > 0, isTrue);
      expect(dollar.estimated, isFalse);
    });

    test('marks a future sell date as estimated', () {
      final calc = Calculator(hist);
      final result = calc.run(CalcInput(
        amountRial: 50000000,
        buyDate: DateTime(2023, 6, 1),
        sellDate: DateTime(2030, 1, 1),
        basis: PriceBasis.close,
        splitAmount: false,
      ));
      final dollar = result.ranked.firstWhere((r) => r.symbolId == 'dollar');
      expect(dollar.hasResult, isTrue);
      expect(dollar.estimated, isTrue);
      expect(dollar.profitPercent! > 0, isTrue);
    });

    test('honours the buy basis (open vs close)', () {
      final open = <PriceRow>[
        PriceRow(
          date: DateTime(2023, 1, 1),
          persianDate: 'x',
          open: 100,
          low: 90,
          high: 120,
          close: 110,
        ),
        PriceRow(
          date: DateTime(2024, 1, 1),
          persianDate: 'x',
          open: 200,
          low: 190,
          high: 220,
          close: 210,
        ),
      ];
      final calc = Calculator({'dollar': open});

      final withOpen = calc
          .run(CalcInput(
            amountRial: 1000,
            buyDate: DateTime(2023, 1, 1),
            sellDate: DateTime(2024, 1, 1),
            basis: PriceBasis.open,
            splitAmount: false,
          ))
          .ranked
          .firstWhere((r) => r.symbolId == 'dollar');
      // 1000 rial / 100 = 10 units * 200 = 2000
      expect(withOpen.finalValueRial, 2000);

      final withClose = calc
          .run(CalcInput(
            amountRial: 1000,
            buyDate: DateTime(2023, 1, 1),
            sellDate: DateTime(2024, 1, 1),
            basis: PriceBasis.close,
            splitAmount: false,
          ))
          .ranked
          .firstWhere((r) => r.symbolId == 'dollar');
      // 1000 / 110 * 210 = 1909.09 -> 1909
      expect(withClose.finalValueRial, 1909);
    });

    test('reports assets with no data at the buy date as untradable', () {
      final calc = Calculator(hist);
      final result = calc.run(CalcInput(
        amountRial: 10000000,
        buyDate: DateTime(2001, 1, 1),
        sellDate: DateTime(2024, 1, 1),
        basis: PriceBasis.close,
        splitAmount: false,
      ));
      for (final r in result.ranked) {
        expect(r.tradableAtBuy, isFalse);
        expect(r.hasResult, isFalse);
      }
    });

    test('splitAmount divides the amount across all symbols', () {
      final calc = Calculator(hist);
      final result = calc.run(CalcInput(
        amountRial: 80000,
        buyDate: DateTime(2023, 6, 1),
        sellDate: DateTime(2024, 6, 1),
        basis: PriceBasis.close,
        splitAmount: true,
      ));
      final dollar = result.ranked.firstWhere((r) => r.symbolId == 'dollar');
      expect(dollar.investedRial, 10000); // 80000 / 8 symbols
    });
  });

  group('forecast', () {
    test('extrapolates a rising series upward', () {
      final h = series(DateTime(2023, 1, 1), 300, 1000, 0.001);
      final est = estimateFuturePrice(h, DateTime(2023, 12, 31));
      expect(est, isNotNull);
      expect(est! > h.last.close, isTrue);
    });

    test('returns null with too little history', () {
      final h = series(DateTime(2023, 1, 1), 5, 1000, 0.001);
      expect(estimateFuturePrice(h, DateTime(2024, 1, 1)), isNull);
    });

    test('growth rate sign matches the series direction', () {
      final up = series(DateTime(2023, 1, 1), 200, 1000, 0.002);
      final down = series(DateTime(2023, 1, 1), 200, 1000, -0.002);
      expect(dailyGrowthRate(up) > 0, isTrue);
      expect(dailyGrowthRate(down) < 0, isTrue);
    });
  });
}
