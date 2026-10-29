/// Basket valuation screen: quantities of one or more symbols owned at a
/// past date, valued in Rial/Toman at that date.
///
/// Primary use case: pricing a registered mahr (مهریه) at its valuation date.
/// Each symbol is priced on the nearest earlier trading day with the
/// configured price basis, mirroring the profit calculator's rules.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/calc/valuation.dart';
import '../../core/models.dart';
import '../../core/symbols.dart';
import '../../core/util/format.dart';
import '../../core/util/jalali.dart';
import '../../core/util/jalali_picker.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/amount_field.dart';
import '../widgets/common.dart';

class ValuationScreen extends StatefulWidget {
  const ValuationScreen({super.key});

  @override
  State<ValuationScreen> createState() => _ValuationScreenState();
}

class _ValuationScreenState extends State<ValuationScreen> {
  late final Map<String, TextEditingController> _quantityControllers;
  DateTime _date = DateTime.now();
  ValuationResult? _result;
  bool _calculating = false;

  @override
  void initState() {
    super.initState();
    _quantityControllers = {
      for (final s in kSymbols) s.id: TextEditingController(),
    };
  }

  @override
  void dispose() {
    for (final c in _quantityControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<ValuationHolding> _readHoldings() {
    final holdings = <ValuationHolding>[];
    for (final symbol in kSymbols) {
      final qty = parseQuantityFa(_quantityControllers[symbol.id]!.text);
      if (qty > 0) {
        holdings.add(ValuationHolding(symbolId: symbol.id, quantity: qty));
      }
    }
    return holdings;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showJalaliDatePicker(
      context,
      initialDate: _date,
      firstDate: DateTime(2005, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
      title: 'تاریخ ارزش‌گذاری',
    );
    if (picked == null) return;
    setState(() => _date = picked);
  }

  Future<void> _calculate() async {
    final scope = AppScope.of(context);
    final holdings = _readHoldings();

    if (holdings.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تعداد حداقل یک نماد را وارد کنید.')),
        );
      return;
    }

    // Fresh prices first, same policy as the profit calculator.
    try {
      await scope.refreshData();
    } catch (_) {
      // Stale bundled data is still usable; the note below says so.
    }

    final result = valueBasket(
      history: {
        for (final symbol in kSymbols)
          symbol.id: scope.calculator.historyFor(symbol.id),
      },
      holdings: holdings,
      date: _date,
      basis: scope.settings.basis,
    );

    if (!mounted) return;
    setState(() {
      _result = result;
      _calculating = false;
    });
  }

  String _copyText() {
    final result = _result!;
    final scope = AppScope.of(context);
    final inToman = scope.settings.inToman;
    final unit = inToman ? 'تومان' : 'ریال';

    final buf = StringBuffer();
    buf.writeln(
      'ارزش دارایی‌ها در تاریخ ${formatJalali(result.requestedDate)} '
      '(${formatJalaliLong(result.requestedDate)})',
    );
    buf.writeln(
      'مبنای قیمت: ${result.basis == PriceBasis.open ? 'اولین قیمت روز (Open)' : 'آخرین قیمت روز (Close)'}',
    );
    buf.writeln('—');
    for (final line in result.lines) {
      final name = symbolName(line.symbolId);
      if (!line.hasData) {
        buf.writeln('$name: داده‌ای برای این تاریخ موجود نیست');
        continue;
      }
      final qty = formatDoubleFa(
        line.quantity,
        line.quantity >= 100 ? 1 : 3,
      );
      buf.writeln(
        '$name: $qty ${symbolUnit(line.symbolId)} × '
        '${moneyText(line.priceUsed!, inToman: inToman)} = '
        '${formatMoneyFa(line.valueRial!.round(), inToman: inToman)} $unit',
      );
    }
    buf.writeln('—');
    if (result.totalRial != null) {
      buf.writeln('جمع کل: ${formatMoneyFa(result.totalRial!, inToman: inToman)} $unit');
    } else {
      buf.writeln('جمع کل: قابل محاسبه نیست');
    }
    buf.writeln(
      '(بر پایه داده tgju.org؛ نرخ رسمی دادگاه ممکن است متفاوت باشد)',
    );
    return buf.toString();
  }

  Future<void> _copyResult() async {
    await Clipboard.setData(ClipboardData(text: _copyText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('نتیجه کپی شد.')));
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;

    return Scaffold(
      appBar: AppBar(title: const Text('ارزش سبد در یک تاریخ')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Space.l, Space.s, Space.l, Space.m),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تعداد دارایی‌هایی که در آن تاریخ داشته‌اید را وارد '
                          'کنید تا ارزش ریالی همان روز محاسبه شود — مثلاً '
                          'مهریه ثبت‌شده.',
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.7,
                            color: MontalaColors.inkMuted,
                          ),
                        ),
                        const SizedBox(height: Space.m),
                        _HoldingCard(
                          controllers: _quantityControllers,
                          date: _date,
                          onPickDate: _pickDate,
                        ),
                        const SizedBox(height: Space.m),
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
                                : const Icon(Icons.account_balance,
                                    size: 19),
                            label: Text(
                              _calculating
                                  ? 'در حال محاسبه…'
                                  : 'محاسبه ارزش در این تاریخ',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_result != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Space.l, vertical: Space.s),
                      child: _ResultCard(
                        result: _result!,
                        inToman: settings.inToman,
                        basis: settings.basis,
                        onCopy: _copyResult,
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: Space.xxl)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoldingCard extends StatelessWidget {
  final Map<String, TextEditingController> controllers;
  final DateTime date;
  final VoidCallback onPickDate;

  const _HoldingCard({
    required this.controllers,
    required this.date,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DateButton(
              label: 'تاریخ ارزش‌گذاری',
              date: date,
              icon: Icons.event_available,
              onTap: onPickDate,
            ),
            const SizedBox(height: Space.l),
            for (final symbol in kSymbols) ...[
              _QuantityRow(
                symbol: symbol,
                controller: controllers[symbol.id]!,
              ),
              if (symbol != kSymbols.last) const Divider(height: 1),
            ],
            const SizedBox(height: Space.s),
            Text(
              'نمادهایی که تعدادشان خالی است در محاسبه نمی‌آیند. تعداد اعشاری '
              '(مثل ۲٫۵ سکه) مجاز است.',
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.6,
                color: MontalaColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantityRow extends StatelessWidget {
  final AssetSymbol symbol;
  final TextEditingController controller;

  const _QuantityRow({required this.symbol, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SymbolBadge(symbol.id, size: 30),
          const SizedBox(width: Space.s),
          Expanded(
            flex: 3,
            child: Text(
              symbol.nameFa,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: TextField(
              controller: controller,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [QuantityInputFormatter()],
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: '۰',
                suffixText: symbol.unitFa,
                suffixStyle: const TextStyle(
                  fontSize: 10.5,
                  color: MontalaColors.inkMuted,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final ValuationResult result;
  final bool inToman;
  final PriceBasis basis;
  final VoidCallback onCopy;

  const _ResultCard({
    required this.result,
    required this.inToman,
    required this.basis,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final unit = inToman ? 'تومان' : 'ریال';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'ارزش سبد در تاریخ انتخابی',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onCopy,
                  tooltip: 'کپی نتیجه',
                  icon: const Icon(Icons.copy_rounded, size: 17),
                ),
              ],
            ),
            Text(
              '${formatJalaliLong(result.requestedDate)} — مبنای '
              '${basis == PriceBasis.open ? 'Open' : 'Close'}',
              style: const TextStyle(
                fontSize: 10.5,
                color: MontalaColors.inkMuted,
              ),
            ),
            const SizedBox(height: Space.m),
            const Divider(),
            const SizedBox(height: Space.s),
            for (final line in result.lines) ...[
              _ResultLine(line: line, inToman: inToman),
              const SizedBox(height: Space.s),
            ],
            const SizedBox(height: Space.s),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(
                color: MontalaColors.brand.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(Radii.md),
                border:
                    Border.all(color: MontalaColors.brand.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined,
                      size: 17, color: MontalaColors.brand),
                  const SizedBox(width: Space.s),
                  const Text(
                    'جمع کل:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      result.totalRial == null
                          ? '—'
                          : '${formatMoneyFa(result.totalRial!, inToman: inToman)} $unit',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: MontalaColors.brand,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.m),
            const _ValuationDisclaimer(),
          ],
        ),
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  final ValuationLine line;
  final bool inToman;

  const _ResultLine({required this.line, required this.inToman});

  @override
  Widget build(BuildContext context) {
    final qty = formatDoubleFa(line.quantity, line.quantity >= 100 ? 1 : 3);

    return Row(
      children: [
        SymbolBadge(line.symbolId, size: 28),
        const SizedBox(width: Space.s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                symbolName(line.symbolId),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              Text(
                line.hasData
                    ? '$qty ${symbolUnit(line.symbolId)} × '
                        '${moneyText(line.priceUsed!, inToman: inToman)}'
                    : 'برای این تاریخ داده‌ای وجود ندارد',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: MontalaColors.inkMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        Text(
          line.hasData
              ? '${formatMoneyFa(line.valueRial!.round(), inToman: inToman)} '
                  '${inToman ? 'تومان' : 'ریال'}'
              : '—',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _ValuationDisclaimer extends StatelessWidget {
  const _ValuationDisclaimer();

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
              'داده قیمت‌ها روزانه و از tgju.org است؛ اگر تاریخ انتخابی تعطیل '
              'باشد، نزدیک‌ترین روز معاملاتی قبل ملاک می‌شود. نرخ رسمی برای '
              'مهریه را دادگاه بر پایه نرخ اعلامی اتحادیه یا بانک مرکزی '
              'تعیین می‌کند و ممکن است با این اعداد تفاوت داشته باشد.',
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
