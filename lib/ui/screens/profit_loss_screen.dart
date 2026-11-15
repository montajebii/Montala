/// Hypothetical profit/loss tool: the query form plus the ranked results.
///
/// Opened from the launcher's tool grid; the price-refresh button lives on
/// the launcher, but a stale dataset still auto-updates before calculating.
library;

import 'package:flutter/material.dart';

import '../../core/calc/calculator.dart';
import '../../core/models.dart';
import '../../core/util/format.dart';
import '../../core/util/jalali_picker.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/amount_field.dart';
import '../widgets/common.dart';
import '../widgets/result_list.dart';

class ProfitLossScreen extends StatefulWidget {
  const ProfitLossScreen({super.key});

  @override
  State<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends State<ProfitLossScreen> {
  final _amountController = TextEditingController();
  DateTime _buyDate = DateTime.now().subtract(const Duration(days: 365));
  DateTime _sellDate = DateTime.now();
  PortfolioResult? _result;
  bool _calculating = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = toPersianDigits(groupThousands(100000000));
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  int get _amountRial {
    final scope = AppScope.of(context);
    final raw = parseAmountFa(_amountController.text);
    return scope.settings.inToman ? raw * 10 : raw;
  }

  Future<void> _pickDate({required bool isBuy}) async {
    final now = DateTime.now();
    final scope = AppScope.of(context);
    final picked = await showJalaliDatePicker(
      context,
      initialDate: isBuy ? _buyDate : _sellDate,
      // The calendar can never show a date before the oldest data of the
      // assets involved (the earliest of all eight series here).
      firstDate: earliestDataDate(scope.calculator.history),
      lastDate: DateTime(now.year + 8, 12, 31),
      title: isBuy ? 'تاریخ خرید' : 'تاریخ فروش / مقایسه',
    );
    if (picked == null) return;
    setState(() {
      if (isBuy) {
        _buyDate = picked;
        if (_sellDate.isBefore(_buyDate)) _sellDate = picked;
      } else {
        _sellDate = picked;
      }
    });
  }

  Future<void> _calculate() async {
    final scope = AppScope.of(context);
    final settings = scope.settings;

    if (_amountRial <= 0) {
      _snack('مبلغ سرمایه‌گذاری را وارد کنید.');
      return;
    }
    if (_sellDate.isBefore(_buyDate)) {
      _snack('تاریخ فروش نمی‌تواند قبل از تاریخ خرید باشد.');
      return;
    }

    setState(() => _calculating = true);

    // Auto-update before calculating when the cached data is stale.
    if (settings.autoUpdate && settings.isStale()) {
      try {
        await scope.refreshData();
      } catch (_) {
        // Quiet: fall back to the stored data, the calculation still runs.
      }
    }

    final result = scope.calculator.run(
      CalcInput(
        amountRial: _amountRial,
        buyDate: _buyDate,
        sellDate: _sellDate,
        basis: settings.basis,
        splitAmount: settings.splitAmount,
      ),
    );

    if (!mounted) return;
    setState(() {
      _result = result;
      _calculating = false;
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سود و زیان فرضی'),
        actions: [
          IconButton(
            tooltip: 'درباره این ابزار',
            icon: const Icon(Icons.info_outline, size: 21),
            onPressed: () => showToolInfo(
              context,
              icon: Icons.trending_up,
              iconColor: MontalaColors.brand,
              title: 'سود و زیان فرضی',
              paragraphs: const [
                'یک مبلغ و دو تاریخ وارد کنید تا ببینید اگر همان روز آن مبلغ '
                    'را در هر دارایی خریده بودید، امروز چه بود؛ نتیجه برای هر '
                    'هشت دارایی به‌صورت رتبه‌بندی‌شده می‌آید.',
                'خروجی هر نماد شامل تعداد واحد قابل خرید، ارزش نهایی، سود یا '
                    'زیان ریالی و درصدی و نمودار رشد ارزش است؛ با زدن هر ردیف '
                    'جزئیات و نمودار کندل ۴۰ روز اخیر باز می‌شود.',
                'تاریخ دوم پیش‌فرض امروز است و می‌تواند آینده باشد — در آن '
                    'صورت قیمت با تخمین روند محاسبه و علامت‌گذاری می‌شود. '
                    'مبنای خرید (Open یا Close) در تنظیمات قابل تغییر است.',
                'داده‌ها از آرشیو tgju.org (۱۳۸۹ تا امروز) می‌آید و پیش از '
                    'محاسبه در صورت کهنگی به‌روزرسانی می‌شود.',
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildForm(context)),
                if (_result != null)
                  SliverToBoxAdapter(
                    child: ResultList(result: _result!, amountRial: _amountRial),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: Space.xxl)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final settings = AppScope.of(context).settings;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'مبلغ سرمایه‌گذاری',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: MontalaColors.inkMuted,
                ),
              ),
              const SizedBox(height: Space.s),
              AmountField(
                controller: _amountController,
                inToman: settings.inToman,
                onUnitToggle: () => settings.setInToman(!settings.inToman),
              ),
              const SizedBox(height: Space.l),
              Row(
                children: [
                  Expanded(
                    child: DateButton(
                      label: 'تاریخ خرید',
                      date: _buyDate,
                      icon: Icons.login,
                      onTap: () => _pickDate(isBuy: true),
                    ),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: DateButton(
                      label: 'تاریخ مقایسه',
                      date: _sellDate,
                      icon: Icons.logout,
                      onTap: () => _pickDate(isBuy: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.m),
              Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _BasisToggle(
                    basis: settings.basis,
                    onChanged: settings.setBasis,
                  ),
                  Chip3d(
                    settings.splitAmount
                        ? 'مبلغ بین همه نمادها تقسیم می‌شود'
                        : 'مبلغ برای هر نماد جداگانه',
                    icon: settings.splitAmount
                        ? Icons.pie_chart_outline
                        : Icons.stacked_bar_chart,
                  ),
                ],
              ),
              const SizedBox(height: Space.l),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _calculating ? null : _calculate,
                  icon: _calculating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.calculate_outlined, size: 19),
                  label: Text(_calculating ? 'در حال محاسبه…' : 'محاسبه سود و زیان'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BasisToggle extends StatelessWidget {
  final PriceBasis basis;
  final ValueChanged<PriceBasis> onChanged;

  const _BasisToggle({required this.basis, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1EDE7),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final b in PriceBasis.values)
            GestureDetector(
              onTap: () => onChanged(b),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                decoration: BoxDecoration(
                  color: basis == b ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: basis == b
                      ? const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          )
                        ]
                      : null,
                ),
                child: Text(
                  b == PriceBasis.open ? 'خرید با Open' : 'خرید با Close',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        basis == b ? FontWeight.w700 : FontWeight.w500,
                    color: basis == b
                        ? MontalaColors.brand
                        : MontalaColors.inkMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
