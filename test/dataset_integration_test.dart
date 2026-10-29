/// Integration tests against the real bundled CSVs.
///
/// These catch the failures that unit tests with synthetic data cannot:
/// wrong column order in a CSV, a symbol registered without its asset file,
/// and calculations that blow up on real price magnitudes.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/calc/calculator.dart';
import 'package:montala/core/db/importer.dart';
import 'package:montala/core/models.dart';
import 'package:montala/core/symbols.dart';

void main() {
  // WidgetsFlutterBinding is required for rootBundle access.
  TestWidgetsFlutterBinding.ensureInitialized();

  final histories = <String, List<PriceRow>>{};

  setUpAll(() {
    for (final symbol in kSymbols) {
      final file = File(symbol.csvAsset);
      expect(file.existsSync(), isTrue,
          reason: 'missing bundled asset ${symbol.csvAsset}');
      histories[symbol.id] = Importer.parseCsv(file.readAsStringSync());
    }
  });

  test('every registered symbol has a non-empty, ascending history', () {
    for (final symbol in kSymbols) {
      final rows = histories[symbol.id]!;
      expect(rows.length, greaterThan(3000),
          reason: '${symbol.id} looks truncated');
      for (var i = 1; i < rows.length; i++) {
        expect(rows[i].date.isAfter(rows[i - 1].date), isTrue,
            reason: '${symbol.id} is not strictly ascending at $i');
      }
      expect(rows.last.date.year, greaterThanOrEqualTo(2026),
          reason: '${symbol.id} last row is stale: ${rows.last.date}');
    }
  });

  test('real prices are positive and OHLC-consistent after parsing', () {
    for (final symbol in kSymbols) {
      for (final r in histories[symbol.id]!) {
        expect(r.open, greaterThan(0), reason: '${symbol.id} ${r.dateIso} open');
        expect(r.close, greaterThan(0), reason: '${symbol.id} ${r.dateIso} close');
        expect(r.high, greaterThanOrEqualTo(r.open),
            reason: '${symbol.id} ${r.dateIso} high < open');
        expect(r.high, greaterThanOrEqualTo(r.close),
            reason: '${symbol.id} ${r.dateIso} high < close');
        expect(r.low, lessThanOrEqualTo(r.open),
            reason: '${symbol.id} ${r.dateIso} low > open');
        expect(r.low, lessThanOrEqualTo(r.close),
            reason: '${symbol.id} ${r.dateIso} low > close');
      }
    }
  });

  test('a one-year dollar purchase produces a plausible result', () {
    final calc = Calculator(histories);
    final result = calc.run(CalcInput(
      amountRial: 100000000, // 10 million Toman
      buyDate: DateTime(2025, 10, 27),
      sellDate: DateTime(2026, 10, 27),
      basis: PriceBasis.close,
      splitAmount: false,
    ));

    final dollar = result.ranked.firstWhere((r) => r.symbolId == 'dollar');
    expect(dollar.hasResult, isTrue);
    expect(dollar.buyDateUsed!.year, 2025);
    expect(dollar.sellDateUsed, DateTime(2026, 10, 27));
    expect(dollar.estimated, isFalse);
    // Dollar went from roughly 1.0-1.1M to 2.7M rial per USD in this window,
    // so the simulated position must have grown substantially.
    expect(dollar.profitPercent!, greaterThan(50));
    expect(dollar.finalValueRial!, greaterThan(100000000));
    // Units = amount / price, and value = units * sell price: check it holds.
    final recomputed = (dollar.units! * dollar.sellPrice!).round();
    expect((recomputed - dollar.finalValueRial!).abs(), lessThanOrEqualTo(1));
  });

  test('all seven symbols are usable for a 2014 buy date', () {
    final calc = Calculator(histories);
    final result = calc.run(CalcInput(
      amountRial: 70000000,
      buyDate: DateTime(2014, 6, 1),
      sellDate: DateTime(2026, 10, 27),
      basis: PriceBasis.close,
      splitAmount: false,
    ));
    final usable = result.ranked.where((r) => r.hasResult).toList();
    expect(usable.length, kSymbols.length,
        reason: 'symbols failing: '
            '${result.ranked.where((r) => !r.hasResult).map((r) => r.symbolId).toList()}');
    // Ranking must be sorted descending by profit percent.
    for (var i = 1; i < usable.length; i++) {
      expect(usable[i - 1].profitPercent!,
          greaterThanOrEqualTo(usable[i].profitPercent!));
    }
    // Everything in Rial terms grew over 12 years in this market.
    expect(usable.every((r) => r.profitPercent! > 0), isTrue);
  });

  test('a holiday buy date snaps back to the previous trading day', () {
    final calc = Calculator(histories);
    final rows = histories['dollar']!;
    // Pick a gap day: a date not present in the series but inside its range.
    DateTime? gap;
    for (var d = DateTime(2025, 1, 1);
        d.isBefore(DateTime(2025, 3, 1));
        d = d.add(const Duration(days: 1))) {
      if (!rows.any((r) => r.date == d)) {
        gap = d;
        break;
      }
    }
    expect(gap, isNotNull, reason: 'no gap day found in the sample window');

    final result = calc.run(CalcInput(
      amountRial: 10000000,
      buyDate: gap!,
      sellDate: DateTime(2026, 10, 27),
      basis: PriceBasis.close,
      splitAmount: false,
    ));
    final dollar = result.ranked.firstWhere((r) => r.symbolId == 'dollar');
    expect(dollar.hasResult, isTrue);
    expect(dollar.buyDateUsed!.isBefore(gap), isTrue,
        reason: 'should have snapped back, got ${dollar.buyDateUsed}');
    expect(gap.difference(dollar.buyDateUsed!).inDays, lessThanOrEqualTo(7));
  });

  test('today (a weekend gap after the last row) is NOT reported as an estimate',
      () {
    // Regression: the newest candle is often 1-3 days old because exchanges
    // close at weekends. Treating "today" as a future date made every ordinary
    // comparison show up as تخمینی and replaced a real +152% with a modelled
    // +143%. Any date within the near-term tolerance must use the last
    // recorded price instead.
    final calc = Calculator(histories);
    final lastRow = histories['dollar']!.last;
    final twoDaysLater = lastRow.date.add(const Duration(days: 2));

    final result = calc.run(CalcInput(
      amountRial: 100000000,
      buyDate: DateTime(2025, 10, 29),
      sellDate: twoDaysLater,
      basis: PriceBasis.close,
      splitAmount: false,
    ));
    final dollar = result.ranked.firstWhere((r) => r.symbolId == 'dollar');
    expect(dollar.estimated, isFalse,
        reason: 'a 2-day weekend gap must not be forecast');
    expect(dollar.sellPrice, lastRow.close);
    expect(dollar.sellDateUsed, lastRow.date);

    // And the number must be the plain historical multiple, not a model output.
    final buyRow = histories['dollar']!
        .lastWhere((r) => !r.date.isAfter(DateTime(2025, 10, 29)));
    final expectedPct = (lastRow.close / buyRow.close - 1) * 100;
    expect(dollar.profitPercent!, closeTo(expectedPct, 0.01));
  });

  test('a future comparison date yields a labelled estimate', () {
    final calc = Calculator(histories);
    final result = calc.run(CalcInput(
      amountRial: 100000000,
      buyDate: DateTime(2024, 1, 1),
      sellDate: DateTime(2028, 1, 1),
      basis: PriceBasis.close,
      splitAmount: false,
    ));
    final gold = result.ranked.firstWhere((r) => r.symbolId == 'gold18');
    expect(gold.hasResult, isTrue);
    expect(gold.estimated, isTrue);
    expect(gold.sellPrice, isNotNull);
    // The estimate must stay within a sane multiple of the last real price.
    final last = histories['gold18']!.last.close;
    expect(gold.sellPrice!, greaterThan(last ~/ 3));
    expect(gold.sellPrice!, lessThan(last * 20));
  });
}
