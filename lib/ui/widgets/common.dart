/// Shared presentational widgets.
library;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/symbols.dart';
import '../../core/util/format.dart';
import '../../core/util/jalali.dart';
import '../theme.dart';

/// Small text chip used for units, statuses and labels.
class Chip3d extends StatelessWidget {
  final String label;
  final Color? background;
  final Color? foreground;
  final IconData? icon;

  const Chip3d(
    this.label, {
    super.key,
    this.background,
    this.foreground,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bg = background ?? const Color(0xFFF1EDE7);
    final fg = foreground ?? MontalaColors.inkMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11.5, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Coloured delta text: "+۱۲٪" green / "−۳٪" red.
class DeltaText extends StatelessWidget {
  final double? percent;
  final double fontSize;
  final bool showBackground;

  const DeltaText(
    this.percent, {
    super.key,
    this.fontSize = 13,
    this.showBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = percent;
    if (p == null) {
      return Text(
        '—',
        style: TextStyle(fontSize: fontSize, color: MontalaColors.inkMuted),
      );
    }
    final positive = p >= 0;
    final color = positive ? MontalaColors.gain : MontalaColors.loss;
    final text = Text(
      formatPercentFa(p),
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: color,
        height: 1.3,
      ),
      textDirection: TextDirection.rtl,
    );
    if (!showBackground) return text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: positive ? MontalaColors.gainSoft : MontalaColors.lossSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: text,
    );
  }
}

/// A labelled metric in a summary grid.
class MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Color? valueColor;
  final IconData? icon;

  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.valueColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: MontalaColors.inkMuted),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: MontalaColors.inkMuted,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              color: valueColor ?? MontalaColors.ink,
              height: 1.3,
            ),
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 1),
          Text(
            sub!,
            style: const TextStyle(
              fontSize: 10.5,
              color: MontalaColors.inkMuted,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

/// Symbol avatar: a monogram disc coloured per asset class.
class SymbolBadge extends StatelessWidget {
  final String symbolId;
  final double size;

  const SymbolBadge(this.symbolId, {super.key, this.size = 34});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (symbolId) {
      'dollar' => ('\$', const Color(0xFF2F6D4F)),
      'gold18' => ('۱۸', MontalaColors.gold),
      'gold24' => ('۲۴', const Color(0xFFA97318)),
      'sekee' => ('ت', const Color(0xFF8A5A2B)),
      'sekeb' => ('ب', const Color(0xFF7C5A33)),
      'nim' => ('ن', const Color(0xFF9C6B3C)),
      'rob' => ('ر', const Color(0xFFAD7C4E)),
      'gerami' => ('گ', const Color(0xFFB98F63)),
      _ => ('•', MontalaColors.inkMuted),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.31),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1,
        ),
      ),
    );
  }
}

String symbolName(String id) {
  for (final s in kSymbols) {
    if (s.id == id) return s.nameFa;
  }
  return id;
}

String symbolUnit(String id) {
  for (final s in kSymbols) {
    if (s.id == id) return s.unitFa;
  }
  return '';
}

AssetSymbol? assetOf(String id) {
  for (final s in kSymbols) {
    if (s.id == id) return s;
  }
  return null;
}

/// Tappable date field showing a Jalali date; gold border for future dates.
/// Shared by the profit calculator and the basket valuation screen.
class DateButton extends StatelessWidget {
  final String label;
  final DateTime date;
  final IconData icon;
  final VoidCallback onTap;

  const DateButton({
    super.key,
    required this.label,
    required this.date,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isFuture = date.isAfter(DateTime.now());
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: isFuture ? MontalaColors.gold : MontalaColors.outline,
            width: isFuture ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 11.5, color: MontalaColors.inkMuted),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: MontalaColors.inkMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isFuture) ...[
                  const SizedBox(width: 4),
                  const Chip3d(
                    'آینده',
                    background: MontalaColors.goldSoft,
                    foreground: MontalaColors.gold,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Text(
              formatJalali(date),
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Money text with the unit appended, honouring Toman/Rial display.
String moneyText(int rial, {required bool inToman, bool withUnit = true}) {
  final body = formatMoneyFa(rial, inToman: inToman);
  if (!withUnit) return body;
  return '$body ${inToman ? 'تومان' : 'ریال'}';
}

/// Compact money: ۱٫۲ میلیارد تومان / ۸۵۰ میلیون
String moneyCompact(int rial, {required bool inToman}) {
  final value = inToman ? rial / 10.0 : rial.toDouble();
  final unit = inToman ? 'تومان' : 'ریال';
  final abs = value.abs();
  if (abs >= 1e12) {
    return '${formatDoubleFa(value / 1e12, 1)} همت $unit';
  }
  if (abs >= 1e9) {
    return '${formatDoubleFa(value / 1e9, 1)} میلیارد $unit';
  }
  if (abs >= 1e6) {
    return '${formatDoubleFa(value / 1e6, 1)} میلیون $unit';
  }
  return '${formatIntFa(value.round())} $unit';
}

/// Row "symbol + units" used in the results table.
class SymbolRowLeading extends StatelessWidget {
  final SymbolCalcResult result;

  const SymbolRowLeading(this.result, {super.key});

  @override
  Widget build(BuildContext context) {
    final units = result.units;
    final unitFa = symbolUnit(result.symbolId);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SymbolBadge(result.symbolId),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                symbolName(result.symbolId),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Text(
                units == null
                    ? 'قابل محاسبه نیست'
                    : '${formatDoubleFa(units, units >= 100 ? 1 : 3)} $unitFa',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: MontalaColors.inkMuted,
                  height: 1.35,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
