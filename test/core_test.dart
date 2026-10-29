import 'package:flutter_test/flutter_test.dart';
import 'package:montala/core/db/importer.dart';
import 'package:montala/core/models.dart';
import 'package:montala/core/util/format.dart';
import 'package:montala/core/util/jalali.dart';

void main() {
  group('Jalali conversion', () {
    test('known anchor dates round-trip', () {
      expect(formatJalali(DateTime(2026, 10, 27)), '1405/08/05');
      expect(formatJalali(DateTime(2024, 3, 20)), '1403/01/01');
      expect(formatJalali(DateTime(2021, 3, 21)), '1400/01/01');
      expect(formatJalali(DateTime(2010, 4, 4)), '1389/01/15');
    });

    test('leap years are detected', () {
      expect(jalaliMonthLength(1403, 12), 30); // 1403 is leap
      expect(jalaliMonthLength(1404, 12), 29);
    });

    test('gregorianToJalali / jalaliToGregorian are inverse', () {
      for (var d = DateTime(2020, 1, 1);
          d.isBefore(DateTime(2027, 1, 1));
          d = d.add(const Duration(days: 37))) {
        final j = gregorianToJalali(d);
        final back = jalaliToGregorian(j);
        expect(back.year, d.year);
        expect(back.month, d.month);
        expect(back.day, d.day);
      }
    });
  });

  group('formatting', () {
    test('groups thousands with the Arabic separator', () {
      expect(formatIntFa(1234567), '۱٬۲۳۴٬۵۶۷');
      expect(formatIntFa(999), '۹۹۹');
      expect(formatIntFa(1000), '۱٬۰۰۰');
    });

    test('negative numbers keep a leading minus', () {
      expect(groupThousands(-1234), '-1٬234');
    });

    test('percent formatting signs correctly', () {
      expect(formatPercentFa(12.34), '+۱۲٫۳٪');
      expect(formatPercentFa(-5.05), '−۵٫۰٪');
      expect(formatPercentFa(0), '۰٫۰٪');
    });

    test('Toman display divides by ten', () {
      expect(formatMoneyFa(1000000, inToman: true), '۱۰۰٬۰۰۰');
      expect(formatMoneyFa(1000000, inToman: false), '۱٬۰۰۰٬۰۰۰');
    });

    test('Persian and Arabic digits normalise to ASCII', () {
      expect(normalizeDigits('۱۲۳۴'), '1234');
      expect(normalizeDigits('٤٥٦'), '456');
    });
  });

  group('CSV importer', () {
    test('parses the project CSV format', () {
      const csv = 'Date,Persian_Date,Open,Low,High,Close\r\n'
          '2013/07/22,1392/04/31,1000000,1000000,1000000,1000000\r\n'
          '\r\n'
          '2013/07/23,1392/05/01,1005000,1004000,1009000,1007000\r\n';
      final rows = Importer.parseCsv(csv);
      expect(rows.length, 2);
      expect(rows.first.date, DateTime(2013, 7, 22));
      expect(rows.first.close, 1000000);
      expect(rows.last.persianDate, '1392/05/01');
    });

    test('skips malformed lines without throwing', () {
      const csv = 'Date,Persian_Date,Open,Low,High,Close\n'
          'not-a-date,1392/04/31,1,1,1,1\n'
          '2013/07/24,1392/05/02,abc,1,1,1\n'
          '2013/07/25,1392/05/03,1,1,1,1\n';
      final rows = Importer.parseCsv(csv);
      expect(rows.length, 1);
      expect(rows.single.close, 1);
    });

    test('PriceRow survives a DB map round-trip', () {
      final r = PriceRow(
        date: DateTime(2026, 10, 27),
        persianDate: '1405/08/05',
        open: 2711850,
        low: 2694600,
        high: 2735000,
        close: 2695000,
      );
      final back = PriceRow.fromDbMap(r.toDbMap('dollar'));
      expect(back.dateIso, '2026-10-27');
      expect(back.close, r.close);
      expect(back.byBasis(PriceBasis.open), 2711850);
      expect(back.byBasis(PriceBasis.close), 2695000);
    });
  });
}
