/// Per-symbol detail sheet: OHLC context, growth chart and the buy/sell legs.
library;

import 'package:flutter/material.dart';

import '../../core/calc/forecast.dart';
import '../../core/models.dart';
import '../../core/util/format.dart';
import '../../core/util/jalali.dart';
import '../app_scope.dart';
import '../theme.dart';
import 'charts.dart';
import 'common.dart';

Future<void> showSymbolDetail(
  BuildContext context, {
  required SymbolCalcResult result,
  required int amountRial,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SymbolDetailSheet(result: result, amountRial: amountRial),
  );
}

class _SymbolDetailSheet extends StatelessWidget {
  final SymbolCalcResult result;
  final int amountRial;

  const _SymbolDetailSheet({required this.result, required this.amountRial});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    final inToman = settings.inToman;

    final history = scope.calculator.historyFor(result.symbolId);
    final buyDate = result.buyDateUsed;
    final sellDate = result.sellDateUsed;
    final basis = settings.basis;

    // Value trajectory of this position between the two dates.
    final trajectory = <double>[];
    if (buyDate != null && sellDate != null) {
      final buyPrice = result.buyPrice ?? 1;
      final units = result.units ?? 0;
      for (final row in history) {
        if (row.date.isBefore(buyDate) || row.date.isAfter(sellDate)) continue;
        trajectory.add(row.byBasis(basis) * units);
        if (trajectory.length > 260) break;
      }
      if (trajectory.isEmpty) trajectory.add(amountRial.toDouble());
      // Anchor both ends so the chart always shows the invested amount first.
      if (trajectory.first > 0 && buyPrice > 0) {
        trajectory.insert(0, amountRial.toDouble());
      }
    }

    final growth = dailyGrowthRate(history, basis: basis);
    final annualized = (growth * 365 * 100);

    // Recent candles for context.
    final recent = history.length > 40
        ? history.sublist(history.length - 40)
        : history;

    final profit = result.profitRial;
    final color = profit == null
        ? MontalaColors.inkMuted
        : profit >= 0
            ? MontalaColors.gain
            : MontalaColors.loss;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: MontalaColors.surfaceCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: MontalaColors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(
                      Space.l, Space.m, Space.l, Space.xl),
                  children: [
                    // header
                    Row(
                      children: [
                        SymbolBadge(result.symbolId, size: 42),
                        const SizedBox(width: Space.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                symbolName(result.symbolId),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'واحد: ${symbolUnit(result.symbolId)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: MontalaColors.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (result.estimated)
                          const Chip3d(
                            'قیمت فروش تخمینی',
                            background: MontalaColors.goldSoft,
                            foreground: MontalaColors.gold,
                            icon: Icons.auto_graph,
                          ),
                      ],
                    ),
                    const SizedBox(height: Space.l),

                    // hero profit
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(Space.l),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(Radii.lg),
                        border: Border.all(color: color.withValues(alpha: 0.24)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profit == null
                                ? 'قابل محاسبه نیست'
                                : profit >= 0
                                    ? 'سود فرضی'
                                    : 'زیان فرضی',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                profit == null
                                    ? '—'
                                    : moneyText(profit.abs(), inToman: inToman),
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(width: Space.m),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: DeltaText(
                                  result.profitPercent,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          if (trajectory.length > 2) ...[
                            const SizedBox(height: Space.m),
                            ValueSparkline(
                              trajectory,
                              color: color,
                              height: 58,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.l),

                    // legs
                    _LegCard(
                      title: 'خرید',
                      date: buyDate,
                      price: result.buyPrice,
                      units: result.units,
                      inToman: inToman,
                      symbolId: result.symbolId,
                      icon: Icons.login,
                    ),
                    const SizedBox(height: Space.s),
                    _LegCard(
                      title: 'مقایسه / فروش',
                      date: sellDate,
                      price: result.sellPrice,
                      units: null,
                      inToman: inToman,
                      symbolId: result.symbolId,
                      icon: Icons.logout,
                      note: result.estimated ? 'تخمینی بر پایه روند' : null,
                    ),
                    const SizedBox(height: Space.l),

                    // metrics
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(Space.l),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: MetricTile(
                                    label: 'سرمایه اولیه',
                                    value: moneyCompact(amountRial,
                                        inToman: inToman),
                                    icon: Icons.savings_outlined,
                                  ),
                                ),
                                Expanded(
                                  child: MetricTile(
                                    label: 'ارزش نهایی',
                                    value: result.finalValueRial == null
                                        ? '—'
                                        : moneyCompact(result.finalValueRial!,
                                            inToman: inToman),
                                    icon: Icons.account_balance_wallet_outlined,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: Space.m),
                            const Divider(),
                            const SizedBox(height: Space.m),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: MetricTile(
                                    label: 'درصد بازدهی',
                                    value: result.profitPercent == null
                                        ? '—'
                                        : formatPercentFa(result.profitPercent!),
                                    valueColor: color,
                                    icon: Icons.percent,
                                  ),
                                ),
                                Expanded(
                                  child: MetricTile(
                                    label: 'رشد سالانه‌شده',
                                    value: formatPercentFa(annualized),
                                    sub:
                                        'روند ${toPersianDigits('$kForecastWindow')} روز اخیر — تخمینی',
                                    icon: Icons.show_chart,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.l),

                    // candles
                    if (recent.length > 5) ...[
                      Text(
                        'نمودار ۴۰ روز اخیر',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: Space.s),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(Space.m),
                          child: CandleSpark(
                            opens: recent.map((e) => e.open.toDouble()).toList(),
                            closes:
                                recent.map((e) => e.close.toDouble()).toList(),
                            highs: recent.map((e) => e.high.toDouble()).toList(),
                            lows: recent.map((e) => e.low.toDouble()).toList(),
                            height: 78,
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.m),
                      Row(
                        children: [
                          Text(
                            formatJalali(recent.first.date),
                            style: const TextStyle(
                              fontSize: 10,
                              color: MontalaColors.inkMuted,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            formatJalali(recent.last.date),
                            style: const TextStyle(
                              fontSize: 10,
                              color: MontalaColors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LegCard extends StatelessWidget {
  final String title;
  final DateTime? date;
  final int? price;
  final double? units;
  final bool inToman;
  final String symbolId;
  final IconData icon;
  final String? note;

  const _LegCard({
    required this.title,
    required this.date,
    required this.price,
    required this.units,
    required this.inToman,
    required this.symbolId,
    required this.icon,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: MontalaColors.outline),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: MontalaColors.inkMuted),
          const SizedBox(width: Space.s),
          SizedBox(
            width: 74,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: MontalaColors.inkMuted,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  date == null ? '—' : formatJalaliLong(date!),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                if (date != null)
                  Text(
                    'معادل ${formatJalali(date!)}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: MontalaColors.inkMuted,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                price == null ? '—' : moneyText(price!, inToman: inToman),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              if (units != null)
                Text(
                  '${formatDoubleFa(units!, units! >= 100 ? 1 : 3)} ${symbolUnit(symbolId)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: MontalaColors.inkMuted,
                    height: 1.4,
                  ),
                ),
              if (note != null)
                Text(
                  note!,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: MontalaColors.gold,
                    height: 1.4,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
