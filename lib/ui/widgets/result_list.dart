/// Ranked results: summary metrics, ranking bars, and the detail table.
library;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/util/format.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'symbol_detail_sheet.dart';

class ResultList extends StatelessWidget {
  final PortfolioResult result;
  final int amountRial;

  const ResultList({
    super.key,
    required this.result,
    required this.amountRial,
  });

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final inToman = settings.inToman;

    final usable = result.ranked.where((r) => r.hasResult).toList();
    final best = usable.isNotEmpty ? usable.first : null;
    final worst = usable.isNotEmpty ? usable.last : null;

    final maxAbs = usable.isEmpty
        ? 1.0
        : usable
            .map((r) => (r.profitPercent ?? 0).abs())
            .reduce((a, b) => a > b ? a : b);

    final baseAmount = settings.splitAmount
        ? amountRial ~/ (result.ranked.isEmpty ? 1 : result.ranked.length)
        : amountRial;

    final spanDays = best?.buyDateUsed != null && best?.sellDateUsed != null
        ? best!.sellDateUsed!.difference(best.buyDateUsed!).inDays.abs()
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---------- headline ----------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'خلاصه نتیجه',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (usable.any((r) => r.estimated))
                        const Chip3d(
                          'شامل مقدار تخمینی',
                          background: MontalaColors.goldSoft,
                          foreground: MontalaColors.gold,
                          icon: Icons.help_outline,
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.m),

                  // Best / worst side by side, each in its own half.
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _Highlight(
                            caption: 'بیشترین بازدهی',
                            symbolId: best?.symbolId,
                            percent: best?.profitPercent,
                            icon: Icons.trending_up,
                          ),
                        ),
                        const SizedBox(width: Space.m),
                        Expanded(
                          child: _Highlight(
                            caption: 'کمترین بازدهی',
                            symbolId: worst?.symbolId,
                            percent: worst?.profitPercent,
                            icon: Icons.trending_down,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.m),
                  const Divider(),
                  const SizedBox(height: Space.m),

                  Row(
                    children: [
                      Expanded(
                        child: MetricTile(
                          label: 'سرمایه هر نماد',
                          value: moneyCompact(baseAmount, inToman: inToman),
                          sub: settings.splitAmount
                              ? 'تقسیم بین ${toPersianDigits('${result.ranked.length}')} نماد'
                              : 'مستقل برای هر نماد',
                          icon: Icons.savings_outlined,
                        ),
                      ),
                      Expanded(
                        child: MetricTile(
                          label: 'نمادهای محاسبه‌شده',
                          value:
                              '${toPersianDigits('${usable.length}')} از ${toPersianDigits('${result.ranked.length}')}',
                          icon: Icons.list_alt,
                        ),
                      ),
                      Expanded(
                        child: MetricTile(
                          label: 'بازه مقایسه',
                          value: spanDays == null
                              ? '—'
                              : '${toPersianDigits('$spanDays')} روز',
                          icon: Icons.date_range_outlined,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.l),

          // ---------- ranking bars ----------
          if (usable.isNotEmpty) ...[
            Text(
              'رتبه‌بندی بازدهی',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: Space.s),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.m, vertical: Space.s),
                child: Column(
                  children: [
                    for (final r in usable)
                      RankBar(
                        label: symbolName(r.symbolId),
                        value: r.profitPercent ?? 0,
                        maxAbs: maxAbs,
                        onTap: () => showSymbolDetail(
                          context,
                          result: r,
                          amountRial: settings.splitAmount
                              ? amountRial ~/ result.ranked.length
                              : amountRial,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.l),
          ],

          // ---------- table ----------
          Text(
            'جزئیات هر نماد',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: Space.s),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < result.ranked.length; i++) ...[
                  _ResultRow(
                    index: i + 1,
                    result: result.ranked[i],
                    inToman: inToman,
                    onTap: () => showSymbolDetail(
                      context,
                      result: result.ranked[i],
                      amountRial: baseAmount,
                    ),
                  ),
                  if (i != result.ranked.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.m),
          const _Disclaimer(),
        ],
      ),
    );
  }
}

/// Best/worst callout. Colour follows the sign of the return, never the rank —
/// a positive return must not render in loss-red just because it ranked last.
class _Highlight extends StatelessWidget {
  final String caption;
  final String? symbolId;
  final double? percent;
  final IconData icon;

  const _Highlight({
    required this.caption,
    required this.symbolId,
    required this.percent,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final p = percent ?? 0;
    final positive = p >= 0;
    final color = positive ? MontalaColors.gain : MontalaColors.loss;
    final bg = positive ? MontalaColors.gainSoft : MontalaColors.lossSoft;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 10),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  caption,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: MontalaColors.inkMuted,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            symbolId == null ? '—' : symbolName(symbolId!),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            percent == null ? '—' : formatPercentFa(p),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final int index;
  final SymbolCalcResult result;
  final bool inToman;
  final VoidCallback onTap;

  const _ResultRow({
    required this.index,
    required this.result,
    required this.inToman,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final profit = result.profitRial;
    final color = profit == null
        ? MontalaColors.inkMuted
        : profit >= 0
            ? MontalaColors.gain
            : MontalaColors.loss;

    return InkWell(
      onTap: result.hasResult ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.m, vertical: Space.m),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: Text(
                result.hasResult ? toPersianDigits('$index') : '—',
                style: const TextStyle(
                  fontSize: 11,
                  color: MontalaColors.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(flex: 5, child: SymbolRowLeading(result)),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    result.finalValueRial == null
                        ? '—'
                        : moneyCompact(result.finalValueRial!, inToman: inToman),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    profit == null
                        ? 'نامشخص'
                        : '${profit >= 0 ? 'سود' : 'زیان'} ${moneyCompact(profit.abs(), inToman: inToman)}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: color,
                      height: 1.35,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DeltaText(result.profitPercent, showBackground: true),
                  if (result.estimated) ...[
                    const SizedBox(height: 2),
                    const Text(
                      'تخمینی',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: MontalaColors.gold,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              result.hasResult ? Icons.chevron_left : Icons.remove,
              size: 17,
              color: MontalaColors.outline,
            ),
          ],
        ),
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F3EC),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: MontalaColors.outline),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: MontalaColors.inkMuted),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'این اعداد صرفاً یک شبیه‌سازی بر پایه داده تاریخی قیمت‌هاست و توصیه سرمایه‌گذاری نیست. '
              'برای تاریخ‌های بدون معامله، نزدیک‌ترین روز معاملاتی قبل از آن استفاده شده است.',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.65,
                color: MontalaColors.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
