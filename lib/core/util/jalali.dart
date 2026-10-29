/// Gregorian <-> Jalali (Solar Hijri) date conversion.
///
/// Port of the well-known jalaali-js algorithm (MIT licensed, by Behrang
/// Noruzi Niya). Accuracy verified for the years this app deals with
/// (roughly 1389..1410 Jalali).
library;

import 'package:flutter/foundation.dart';

class JalaliDate {
  final int year;
  final int month; // 1..12
  final int day; // 1..31

  const JalaliDate(this.year, this.month, this.day);

  bool operator <(JalaliDate other) => compareTo(other) < 0;
  bool operator <=(JalaliDate other) => compareTo(other) <= 0;

  int compareTo(JalaliDate other) {
    if (year != other.year) return year - other.year;
    if (month != other.month) return month - other.month;
    return day - other.day;
  }

  @override
  String toString() => '$year/${month.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}';
}

const List<String> kJalaliMonthNames = [
  'فروردین',
  'اردیبهشت',
  'خرداد',
  'تیر',
  'مرداد',
  'شهریور',
  'مهر',
  'آبان',
  'آذر',
  'دی',
  'بهمن',
  'اسفند',
];

const List<String> kJalaliWeekdayShort = [
  'شنبه',
  'یکشنبه',
  'دوشنبه',
  'سه‌شنبه',
  'چهارشنبه',
  'پنجشنبه',
  'جمعه',
];

int _div(int a, int b) => a ~/ b;

/// Number of days in a given Jalali month, accounting for leap years.
int jalaliMonthLength(int jy, int jm) {
  if (jm <= 6) return 31;
  if (jm <= 11) return 30;
  return isJalaliLeap(jy) ? 30 : 29;
}

/// This algorithm determines the Jalali leap year by finding the number of
/// days between two Jalali new years and dividing by 365.
bool isJalaliLeap(int jy) {
  return _jalCal(jy).leap == 0;
}

class _JalCalResult {
  final int leap;
  final int gy; // Gregorian year of the Jalali new year
  final int march; // Gregorian day of the Jalali new year (in March)
  const _JalCalResult(this.leap, this.gy, this.march);
}

const List<int> _breaks = [
  -61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181, 1210, 1635,
  2060, 2097, 2192, 2262, 2324, 2394, 2456, 3178,
];

_JalCalResult _jalCal(int jy) {
  final bl = _breaks.length;
  final gy = jy + 621;
  int leapJ = -14;
  int jp = _breaks[0];

  int jump = 0;
  for (int i = 1; i < bl; i += 1) {
    final jm = _breaks[i];
    jump = jm - jp;
    if (jy < jm) break;
    leapJ += _div(jump, 33) * 8 + _div(jump % 33, 4);
    jp = jm;
  }
  int n = jy - jp;

  leapJ += _div(n, 33) * 8 + _div(n % 33 + 3, 4);
  if (jump % 33 == 4 && jump - n == 4) leapJ += 1;

  final leapG = _div(gy, 4) - _div((_div(gy, 100) + 1) * 3, 4) - 150;
  final march = 20 + leapJ - leapG;

  // Find the limiting year for the Jalaali year jy.
  if (jump - n < 6) n = n - jump + _div(jump + 4, 33) * 33;
  var leap = (((n + 1) % 33) - 1) % 4;
  if (leap == -1) leap = 4;

  return _JalCalResult(leap, gy, march);
}

int _g2d(int gy, int gm, int gd) {
  var d = _div((gy + _div(gm - 8, 6) + 100100) * 1461, 4)
      + _div(153 * ((gm + 9) % 12) + 2, 5)
      + gd
      - 34840408;
  d = d - _div(_div(gy + 100100 + _div(gm - 8, 6), 100) * 3, 4) + 752;
  return d;
}

List<int> _d2g(int jdn) {
  var j = 4 * jdn + 139361631;
  j = j + _div(_div(4 * jdn + 183187720, 146097) * 3, 4) * 4 - 3908;
  final i = _div(j % 1461, 4) * 5 + 308;
  final gd = _div(i % 153, 5) + 1;
  final gm = (_div(i, 153) % 12) + 1;
  final gy = _div(j, 1461) - 100100 + _div(8 - gm, 6);
  return [gy, gm, gd];
}

int _j2d(int jy, int jm, int jd) {
  final r = _jalCal(jy);
  return _g2d(r.gy, 3, r.march) + (jm - 1) * 31 - _div(jm, 7) * (jm - 7) + jd - 1;
}

List<int> _d2j(int jdn) {
  final gy = _d2g(jdn)[0];
  var jy = gy - 621;
  final r = _jalCal(jy);
  final jdn1f = _g2d(gy, 3, r.march);
  var k = jdn - jdn1f; // days passed since 1 Farvardin

  if (k >= 0) {
    if (k <= 185) {
      // The first 6 months.
      final jm = 1 + _div(k, 31);
      return [jy, jm, _mod(k, 31) + 1];
    }
    // The remaining months.
    k -= 186;
  } else {
    // Previous Jalali year.
    jy -= 1;
    k += 179;
    if (r.leap == 1) k += 1;
  }
  final jm = 7 + _div(k, 30);
  return [jy, jm, _mod(k, 30) + 1];
}

int _mod(int a, int b) => a % b;

@visibleForTesting
List<int> debugD2j(int jdn) => _d2j(jdn);

/// Converts a Gregorian date to Jalali.
JalaliDate gregorianToJalali(DateTime g) {
  final jdn = _g2d(g.year, g.month, g.day);
  final j = _d2j(jdn);
  return JalaliDate(j[0], j[1], j[2]);
}

/// Converts a Jalali date to Gregorian.
DateTime jalaliToGregorian(JalaliDate j) {
  final jdn = _j2d(j.year, j.month, j.day);
  final g = _d2g(jdn);
  return DateTime(g[0], g[1], g[2]);
}

/// Persian weekday name (شنبه..جمعه) for a Gregorian date.
String jalaliWeekdayName(DateTime g) {
  // DateTime.weekday: Mon=1..Sun=7; Persian week starts Saturday.
  const map = {
    DateTime.saturday: 'شنبه',
    DateTime.sunday: 'یکشنبه',
    DateTime.monday: 'دوشنبه',
    DateTime.tuesday: 'سه‌شنبه',
    DateTime.wednesday: 'چهارشنبه',
    DateTime.thursday: 'پنجشنبه',
    DateTime.friday: 'جمعه',
  };
  return map[g.weekday]!;
}

/// e.g. "۱۴۰۵/۰۸/۰۶"
String formatJalali(DateTime g) {
  final j = gregorianToJalali(g);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${j.year}/${two(j.month)}/${two(j.day)}';
}

/// e.g. "پنجشنبه ۵ آبان ۱۴۰۴"
String formatJalaliLong(DateTime g) {
  final j = gregorianToJalali(g);
  return '${jalaliWeekdayName(g)} ${j.day} ${kJalaliMonthNames[j.month - 1]} ${j.year}';
}
