/// Lightweight CustomPainter charts — no chart package dependency.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/util/format.dart';
import '../theme.dart';

/// Sparkline / area chart of a value series with a shaded gain/loss band.
class ValueSparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double height;
  final bool fill;
  final double strokeWidth;

  const ValueSparkline(
    this.values, {
    super.key,
    required this.color,
    this.height = 46,
    this.fill = true,
    this.strokeWidth = 1.8,
  });

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(height: height);
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparkPainter(
          values: values,
          color: color,
          fill: fill,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final bool fill;
  final double strokeWidth;

  _SparkPainter({
    required this.values,
    required this.color,
    required this.fill,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var minV = values.first, maxV = values.first;
    for (final v in values) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final span = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
    final dx = size.width / (values.length - 1);

    Offset pointAt(int i) {
      final x = dx * i;
      final y = size.height - ((values[i] - minV) / span) * (size.height - 4) - 2;
      return Offset(x, y);
    }

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p = pointAt(i);
      path.lineTo(p.dx, p.dy);
    }

    if (fill) {
      final area = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.26),
              color.withValues(alpha: 0.02),
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // End dot
    final end = pointAt(values.length - 1);
    canvas.drawCircle(end, 2.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.color != color;
}

/// Horizontal comparison bar used to rank symbols by profit percent.
/// The bar grows from the left edge and the signed value is printed at the
/// far end, so magnitude and sign read without consulting a legend.
class RankBar extends StatelessWidget {
  final String label;
  final double value; // percent
  final double maxAbs;
  final bool selected;
  final VoidCallback? onTap;

  const RankBar({
    super.key,
    required this.label,
    required this.value,
    required this.maxAbs,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final positive = value >= 0;
    final color = positive ? MontalaColors.gain : MontalaColors.loss;
    final ratio = maxAbs <= 0 ? 0.0 : (value.abs() / maxAbs).clamp(0.0, 1.0);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? MontalaColors.brand : MontalaColors.ink,
                  height: 1.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  // Percent-based so a 0.3% bar is still visible.
                  final w = (c.maxWidth * ratio).clamp(4.0, c.maxWidth);
                  return Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      width: w,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: selected ? 0.92 : 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 54,
              child: Text(
                formatPercentFa(value, decimals: 0),
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tiny OHLC candle painter for the detail sheet header.
class CandleSpark extends StatelessWidget {
  final List<double> opens;
  final List<double> closes;
  final List<double> highs;
  final List<double> lows;
  final double height;

  const CandleSpark({
    super.key,
    required this.opens,
    required this.closes,
    required this.highs,
    required this.lows,
    this.height = 64,
  });

  @override
  Widget build(BuildContext context) {
    if (opens.isEmpty) return SizedBox(height: height);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _CandlePainter(
          opens: opens,
          closes: closes,
          highs: highs,
          lows: lows,
        ),
      ),
    );
  }
}

class _CandlePainter extends CustomPainter {
  final List<double> opens;
  final List<double> closes;
  final List<double> highs;
  final List<double> lows;

  _CandlePainter({
    required this.opens,
    required this.closes,
    required this.highs,
    required this.lows,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var minV = lows.first, maxV = highs.first;
    for (final v in lows) {
      if (v < minV) minV = v;
    }
    for (final v in highs) {
      if (v > maxV) maxV = v;
    }
    final span = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
    double y(double v) => size.height - ((v - minV) / span) * (size.height - 6) - 3;

    final n = opens.length;
    final slot = size.width / n;
    final bodyW = math.max(1.4, slot * 0.62);

    for (var i = 0; i < n; i++) {
      final up = closes[i] >= opens[i];
      final color = up ? MontalaColors.gain : MontalaColors.loss;
      final x = slot * i + slot / 2;
      final paint = Paint()
        ..color = color.withValues(alpha: 0.85)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(x, y(highs[i])), Offset(x, y(lows[i])), paint);

      final top = y(math.max(opens[i], closes[i]));
      final bottom = y(math.min(opens[i], closes[i]));
      canvas.drawRect(
        Rect.fromLTRB(
          x - bodyW / 2,
          top,
          x + bodyW / 2,
          math.max(bottom, top + 1),
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_CandlePainter old) => old.closes != closes;
}
