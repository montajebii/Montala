/// Number and money formatting helpers (Persian digits, Toman/Rial).
library;

const String _kPersianDigits = '۰۱۲۳۴۵۶۷۸۹';
const String _kSep = '٬'; // U+066C arabic thousands separator
const String _kDecimalSep = '٫'; // U+066B arabic decimal separator

String toPersianDigits(String input) {
  final sb = StringBuffer();
  for (final ch in input.codeUnits) {
    if (ch >= 0x30 && ch <= 0x39) {
      sb.write(_kPersianDigits[ch - 0x30]);
    } else {
      sb.writeCharCode(ch);
    }
  }
  return sb.toString();
}

/// Accepts Persian/Arabic digits in user input, returns ASCII.
String normalizeDigits(String input) {
  final sb = StringBuffer();
  for (final ch in input.runes) {
    if (ch >= 0x06F0 && ch <= 0x06F9) {
      sb.write(ch - 0x06F0);
    } else if (ch >= 0x0660 && ch <= 0x0669) {
      sb.write(ch - 0x0660);
    } else {
      sb.writeCharCode(ch);
    }
  }
  return sb.toString();
}

String groupThousands(int n) {
  final neg = n < 0;
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    buf.write(s[i]);
    final remaining = s.length - i - 1;
    if (remaining > 0 && remaining % 3 == 0) buf.write(_kSep);
  }
  final out = buf.toString();
  return neg ? '-$out' : out;
}

/// ۱۲۳۴۵۶۷ → "۱٬۲۳۴٬۵۶۷"
String formatIntFa(int n) => toPersianDigits(groupThousands(n));

/// Formats a double with fixed decimals then Persian digits: 12.4 → "۱۲٫۴"
String formatDoubleFa(double v, int decimals) {
  final s = v.toStringAsFixed(decimals);
  return toPersianDigits(s).replaceAll('.', _kDecimalSep);
}

/// Formats an amount kept internally in Rial for display.
/// [inToman] divides by 10 (Toman = 10 Rial).
String formatMoneyFa(int rial, {required bool inToman}) {
  if (inToman) {
    return formatIntFa(rial ~/ 10);
  }
  return formatIntFa(rial);
}

/// "+۱۲٫۴٪" / "−۳٫۱٪" with Persian percent sign.
String formatPercentFa(double percent, {int decimals = 1}) {
  final sign = percent > 0 ? '+' : percent < 0 ? '\u2212' : '';
  return '$sign${formatDoubleFa(percent.abs(), decimals)}٪';
}

enum UnitDisplay { toman, rial }

String unitLabel(UnitDisplay u) => u == UnitDisplay.toman ? 'تومان' : 'ریال';
