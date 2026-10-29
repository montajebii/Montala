import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/calc/valuation.dart';
import 'package:montala/core/models.dart';

PriceRow row(String iso, int price) => PriceRow(
      date: DateTime.parse(iso),
      persianDate: 'x',
      open: price,
      low: price,
      high: price,
      close: price,
    );

void main() {
  final history = {
    'sekee': [
      row('2024-01-01', 400000000),
      row('2024-01-03', 410000000),
      row('2024-01-05', 420000000),
    ],
    'dollar': [
      row('2024-01-01', 500000),
      row('2024-01-02', 510000),
    ],
  };

  group('valueBasket', () {
    test('values multiple holdings on an exact date', () {
      final r = valueBasket(
        history: history,
        holdings: const [
          ValuationHolding(symbolId: 'sekee', quantity: 40),
          ValuationHolding(symbolId: 'dollar', quantity: 1000),
        ],
        date: DateTime(2024, 1, 5),
        basis: PriceBasis.close,
      );

      expect(r.lines.length, 2);
      // Dollar has no row on Jan 5, so it snaps back to Jan 2 (510000).
      expect(r.totalRial, 40 * 420000000 + 1000 * 510000);
      final sekee = r.lines.firstWhere((l) => l.symbolId == 'sekee');
      expect(sekee.dateUsed, DateTime(2024, 1, 5));
      expect(sekee.priceUsed, 420000000);
    });

    test('snaps back to the nearest earlier trading day', () {
      final r = valueBasket(
        history: history,
        holdings: const [ValuationHolding(symbolId: 'dollar', quantity: 2)],
        date: DateTime(2024, 1, 4), // no dollar row this day
        basis: PriceBasis.close,
      );

      final line = r.lines.single;
      expect(line.hasData, isTrue);
      expect(line.dateUsed, DateTime(2024, 1, 2));
      expect(line.valueRial, 2 * 510000);
    });

    test('honours the price basis (open vs close)', () {
      final mixed = {
        'dollar': [
          PriceRow(
            date: DateTime(2024, 1, 1),
            persianDate: 'x',
            open: 100,
            low: 90,
            high: 120,
            close: 110,
          ),
        ],
      };

      final openBasis = valueBasket(
        history: mixed,
        holdings: const [ValuationHolding(symbolId: 'dollar', quantity: 3)],
        date: DateTime(2024, 1, 2),
        basis: PriceBasis.open,
      );
      expect(openBasis.totalRial, 300);

      final closeBasis = valueBasket(
        history: mixed,
        holdings: const [ValuationHolding(symbolId: 'dollar', quantity: 3)],
        date: DateTime(2024, 1, 2),
        basis: PriceBasis.close,
      );
      expect(closeBasis.totalRial, 330);
    });

    test('fractional quantities are valued', () {
      final r = valueBasket(
        history: history,
        holdings: const [ValuationHolding(symbolId: 'sekee', quantity: 2.5)],
        date: DateTime(2024, 1, 5),
        basis: PriceBasis.close,
      );
      expect(r.totalRial, (2.5 * 420000000).round());
    });

    test('symbols without data on/before the date are flagged, not fatal', () {
      final r = valueBasket(
        history: history,
        holdings: const [
          ValuationHolding(symbolId: 'sekee', quantity: 1),
          ValuationHolding(symbolId: 'gold18', quantity: 10), // not in history
        ],
        date: DateTime(2024, 1, 5),
        basis: PriceBasis.close,
      );

      final gold = r.lines.firstWhere((l) => l.symbolId == 'gold18');
      expect(gold.hasData, isFalse);
      expect(gold.valueRial, isNull);
      // The priced symbol still contributes to the total.
      expect(r.totalRial, 420000000);
    });

    test('total is null when nothing could be priced', () {
      final r = valueBasket(
        history: history,
        holdings: const [ValuationHolding(symbolId: 'gold18', quantity: 10)],
        date: DateTime(2024, 1, 5),
        basis: PriceBasis.close,
      );
      expect(r.totalRial, isNull);
    });

    test('a date before every series yields an empty, null-total result', () {
      final r = valueBasket(
        history: history,
        holdings: const [
          ValuationHolding(symbolId: 'sekee', quantity: 1),
          ValuationHolding(symbolId: 'dollar', quantity: 1),
        ],
        date: DateTime(2020, 1, 1),
        basis: PriceBasis.close,
      );
      expect(r.lines.every((l) => !l.hasData), isTrue);
      expect(r.totalRial, isNull);
    });

    test('zero-quantity holdings are ignored', () {
      final r = valueBasket(
        history: history,
        holdings: const [
          ValuationHolding(symbolId: 'sekee', quantity: 0),
          ValuationHolding(symbolId: 'dollar', quantity: 1),
        ],
        date: DateTime(2024, 1, 2),
        basis: PriceBasis.close,
      );
      expect(r.lines.length, 1);
      expect(r.lines.single.symbolId, 'dollar');
    });
  });
}
