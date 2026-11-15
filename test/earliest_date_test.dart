/// Tests for [earliestDataDate] — the per-asset floor date pickers use so no
/// date without data can be displayed or selected.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/calc/calculator.dart';
import 'package:montala/core/models.dart';

PriceRow _row(int y, int m, int d) => PriceRow(
      date: DateTime(y, m, d),
      persianDate: '',
      open: 1,
      low: 1,
      high: 1,
      close: 1,
    );

void main() {
  final history = {
    'dollar': [_row(2010, 7, 25), _row(2010, 7, 26)],
    'gold18': [_row(2013, 7, 22), _row(2013, 7, 23)], // ۱۳۹۲/۰۴/۳۱
    'gold24': [_row(2012, 3, 1), _row(2012, 3, 2)],
    'empty': const <PriceRow>[],
  };

  test('global earliest across all series', () {
    expect(earliestDataDate(history), DateTime(2010, 7, 25));
  });

  test('per-asset floor picks only that series', () {
    expect(
      earliestDataDate(history, ids: {'gold18'}),
      DateTime(2013, 7, 22),
    );
    expect(
      earliestDataDate(history, ids: {'gold24', 'gold18'}),
      DateTime(2012, 3, 1),
    );
  });

  test('unknown/empty series falls back', () {
    final fallback = DateTime(2005, 1, 1);
    expect(earliestDataDate(history, ids: {'empty'}), fallback);
    expect(
      earliestDataDate(history, ids: {'empty'}, fallback: DateTime(2009)),
      DateTime(2009),
    );
    expect(earliestDataDate({}), fallback);
  });
}
