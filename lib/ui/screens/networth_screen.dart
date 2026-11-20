/// «ارزش دارایی من» — the personal net-worth tool, port of m0ntIsRich's
/// main.py + rich_dashboard.py.
///
/// Transactions are the source of truth: the user logs backdated buys and
/// sells, and the current value / history / analytics are all derived from
/// those transactions × Montala's daily price archive. Tabs: امروز (current
/// value + allocation), تاریخچه (value chart with trade markers),
/// تراکنش‌ها (log + entry form + CSV export/import), تحلیل (ROI, realized
/// P/L, MA/volatility).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/calc/calculator.dart';
import '../../core/models.dart';
import '../../core/portfolio/portfolio_analytics.dart';
import '../../core/portfolio/portfolio_calc.dart';
import '../../core/portfolio/portfolio_csv.dart';
import '../../core/portfolio/portfolio_models.dart';
import '../../core/portfolio/portfolio_store.dart';
import '../../core/symbols.dart';
import '../../core/util/format.dart';
import '../../core/util/jalali.dart';
import '../../core/util/jalali_picker.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';

class NetWorthScreen extends StatefulWidget {
  const NetWorthScreen({
    super.key,
    @visibleForTesting this.storeOverride,
    @visibleForTesting this.showFab = true,
  });

  /// Test seam: lets widget tests inject a fast, in-memory store instead of
  /// the platform one (real SQLite IO cannot progress under fake-async).
  final PortfolioStore? storeOverride;

  /// Test seam: the store-screenshot goldens hide the FAB — the test
  /// renderer draws a focus-style ring around it that reads as a rendering
  /// bug in stills.
  final bool showFab;

  @override
  State<NetWorthScreen> createState() => _NetWorthScreenState();
}

class _NetWorthScreenState extends State<NetWorthScreen>
    with SingleTickerProviderStateMixin {
  late final PortfolioStore _store;
  late final TabController _tabs;

  List<PortfolioTx> _txs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _store = widget.storeOverride ?? createPortfolioStore();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// The price archive is the app-wide, in-memory copy from [AppScope] — the
  /// calculator keeps it fresh on every data refresh.
  Map<String, List<PriceRow>> get _history =>
      AppScope.of(context).calculator.history;

  Future<void> _load() async {
    final txs = await _store.transactions();
    if (!mounted) return;
    setState(() {
      _txs = txs;
      _loading = false;
    });
  }

  PriceBasis get _basis => AppScope.of(context).settings.basis;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ارزش دارایی من'),
        actions: [
          IconButton(
            tooltip: 'درباره این ابزار',
            icon: const Icon(Icons.info_outline, size: 21),
            onPressed: () => showToolInfo(
              context,
              icon: Icons.savings_outlined,
              iconColor: MontalaColors.gold,
              title: 'ارزش دارایی من',
              paragraphs: const [
                'خرید و فروش دارایی‌ها را با تاریخ و قیمت دلخواه ثبت کنید — '
                    'تاریخ می‌تواند عقب‌تر باشد (پس‌تاریخ) و قیمت پیش‌فرض از '
                    'دیتابیس همان روز پر می‌شود.',
                'از روی تراکنش‌ها و دیتابیس قیمت، ارزش کنونی، تاریخچه کامل '
                    'ارزش، سهم هر دارایی، سود/زیان باز هر دارایی (میانگین '
                    'خرید) و سود/زیان تحقق‌یافته هر فروش ساخته می‌شود.',
                'تب تحلیل، میانگین متحرک، نوسان ۳۰ روزه و نقاط غیرعادی سری '
                    'ارزش را هم نشان می‌دهد. داده فقط روی دستگاه خودتان '
                    'ذخیره می‌شود.',
                'تراکنش‌ها با CSV خروجی/ورودی می‌شوند (دکمه‌های بالای صفحه) — '
                    'برای انتقال بین دستگاه‌ها یا پشتیبان‌گیری.',
              ],
            ),
          ),
          IconButton(
            tooltip: 'خروجی CSV',
            icon: const Icon(Icons.file_upload_outlined, size: 21),
            onPressed: _loading ? null : _exportCsv,
          ),
          IconButton(
            tooltip: 'ورودی CSV',
            icon: const Icon(Icons.file_download_outlined, size: 21),
            onPressed: _loading ? null : _importCsv,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'امروز'),
            Tab(text: 'تاریخچه'),
            Tab(text: 'تراکنش‌ها'),
            Tab(text: 'تحلیل'),
          ],
        ),
      ),
      floatingActionButton: widget.showFab
          ? FloatingActionButton.extended(
            onPressed: _loading ? null : _addTransaction,
            icon: const Icon(Icons.add),
            label: const Text('تراکنش جدید'),
          )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _TodayTab(
                  txs: _txs,
                  history: _history,
                  basis: _basis,
                ),
                _HistoryTab(txs: _txs, history: _history, basis: _basis),
                _TransactionsTab(
                  txs: _txs,
                  history: _history,
                  onChanged: _load,
                  onEdit: _editTransaction,
                ),
                _AnalysisTab(txs: _txs, history: _history, basis: _basis),
              ],
            ),
    );
  }

  // ------------------------------------------------------------- entry form

  Future<void> _addTransaction() => _showTxDialog(null);

  Future<void> _editTransaction(PortfolioTx tx) => _showTxDialog(tx);

  Future<void> _showTxDialog(PortfolioTx? existing) async {
      final saved = await showDialog<_TxDialogResult>(
      context: context,
      builder: (_) => _TxDialog(
        existing: existing,
        txs: _txs,
        history: _history,
      ),
    );
    if (saved == null) return;
    if (saved.deleted) {
      if (existing?.id != null) {
        await _store.deleteTransaction(existing!.id!);
      }
    } else if (existing == null) {
      await _store.addTransaction(saved.tx!);
    } else {
      await _store.updateTransaction(saved.tx!.copyWith(id: existing.id));
    }
    await _load();
  }

  // ------------------------------------------------------------ csv in/out

  Future<void> _exportCsv() async {
    final csv = encodeTxsCsv(_txs);
    try {
      if (kIsWeb) {
        await _showCsvDialog('خروجی تراکنش‌ها', csv);
        return;
      }
      final uri = await FilePicker.saveFile(
        fileName: 'montala_portfolio.csv',
        mimeType: 'text/csv',
        bytes: utf8.encode(csv),
      );
      if (uri == null) {
        // Dialog dismissed (or web download already handled) — fall back to
        // the text dialog so the data is always reachable.
        await _showCsvDialog('خروجی تراکنش‌ها', csv);
      } else {
        _snack('فایل ذخیره شد: $uri');
      }
    } catch (e) {
      await _showCsvDialog('خروجی تراکنش‌ها', csv);
    }
  }

  Future<void> _importCsv() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
      );
      if (picked.isEmpty) return;
      final text = utf8.decode(
        await picked.first.readAsBytes(),
        allowMalformed: true,
      );

      final parsed = parseTxsCsv(text);
      if (parsed.txs.isEmpty && parsed.errors.isNotEmpty) {
        _snack('هیچ ردیف معتبری پیدا نشد:\n${parsed.errors.take(3).join('\n')}');
        return;
      }
      if (!mounted) return;

      final mode = await showDialog<_ImportMode>(
        context: context,
        builder: (context) => _ImportModeDialog(
          parsed: parsed,
          hasExisting: _txs.isNotEmpty,
        ),
      );
      if (mode == null) return;

      if (mode == _ImportMode.replace) {
        await _store.replaceAll(parsed.txs);
      } else {
        for (final tx in parsed.txs) {
          await _store.addTransaction(tx);
        }
      }
      await _load();
      if (!mounted) return;
      _snack(mode == _ImportMode.replace
          ? '${toPersianDigits('${parsed.txs.length}')} تراکنش جایگزین شد'
          : '${toPersianDigits('${parsed.txs.length}')} تراکنش اضافه شد');
    } catch (e) {
      if (!mounted) return;
      _snack('ورود فایل ناموفق بود: $e');
    }
  }

  Future<void> _showCsvDialog(String title, String csv) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: TextEditingController(text: csv),
            maxLines: 12,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
          FilledButton(
            onPressed: () {
              // Clipboard import lives in flutter/services; keep it light.
              Navigator.pop(context);
            },
            child: const Text('کپی دستی متن بالا'),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

enum _ImportMode { merge, replace }

// --------------------------------------------------------------------------
// today

class _TodayTab extends StatelessWidget {
  final List<PortfolioTx> txs;
  final Map<String, List<PriceRow>> history;
  final PriceBasis basis;

  const _TodayTab({
    required this.txs,
    required this.history,
    required this.basis,
  });

  @override
  Widget build(BuildContext context) {
    final point = latestPoint(
      txs: txs,
      history: history,
      basis: basis,
    );

    if (point == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(Space.xl),
          child: Text(
            'هنوز دارایی‌ای ثبت نشده است.\nبا دکمه «تراکنش جدید» اولین خرید را '
            'ثبت کنید — تاریخچه و تحلیل از همان‌جا ساخته می‌شود.',
            textAlign: TextAlign.center,
            style: TextStyle(color: MontalaColors.inkMuted, height: 1.9),
          ),
        ),
      );
    }

    final entries = point.valueByAsset.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(Space.l),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ارزش کنونی دارایی‌ها',
                      style: TextStyle(
                          fontSize: 12, color: MontalaColors.inkMuted),
                    ),
                    const SizedBox(height: Space.s),
                    Text(
                      _fmtCompactToman(point.totalToman),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: MontalaColors.brand,
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      'قیمت پایانی آخرین روز معاملاتی · '
                      '${formatJalaliLong(DateTime.now())}',
                      style: const TextStyle(
                          fontSize: 11, color: MontalaColors.inkMuted),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.m),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.l),
                child: Column(
                  children: [
                    for (var i = 0; i < entries.length; i++)
                      _assetRow(context, entries[i], point, i == 0),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.xxl),
          ],
        ),
      ),
    );
  }

  Widget _assetRow(
    BuildContext context,
    MapEntry<String, double> entry,
    PortfolioPoint point,
    bool isFirst,
  ) {
    final symbol = symbolById(entry.key);
    final units = point.unitsByAsset[entry.key] ?? 0;
    final share =
        point.totalToman > 0 ? entry.value / point.totalToman : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  symbol.nameFa,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '${formatDoubleFa(units, symbol.unitDecimals)} ${symbol.unitFa}',
                  style: const TextStyle(
                      fontSize: 12, color: MontalaColors.inkMuted),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  _fmtCompactToman(entry.value),
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 5,
              backgroundColor: MontalaColors.outline,
              valueColor: const AlwaysStoppedAnimation(MontalaColors.gold),
            ),
          ),
          if (!isFirst) const SizedBox(height: Space.xs),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// history

class _HistoryTab extends StatelessWidget {
  final List<PortfolioTx> txs;
  final Map<String, List<PriceRow>> history;
  final PriceBasis basis;

  const _HistoryTab({
    required this.txs,
    required this.history,
    required this.basis,
  });

  @override
  Widget build(BuildContext context) {
    final start = firstTxDate(txs);
    if (start == null) {
      return const Center(
        child: Text(
          'پس از ثبت اولین تراکنش، تاریخچه ارزش اینجا ساخته می‌شود.',
          style: TextStyle(color: MontalaColors.inkMuted),
        ),
      );
    }
    final series = portfolioSeries(
      txs: txs,
      history: history,
      basis: basis,
      from: start,
      to: DateTime.now(),
    );
    if (series.length < 2) {
      return const Center(
        child: Text(
          'برای رسم تاریخچه حداقل دو روز معاملاتی لازم است.',
          style: TextStyle(color: MontalaColors.inkMuted),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.all(Space.l),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.m, Space.m,
                    Space.m, Space.s),
                child: SizedBox(
                  height: 260,
                  child: CustomPaint(
                    painter: _HistoryChartPainter(
                      points: series,
                      txs: txs,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.s),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.m),
              child: Row(
                children: [
                  const _LegendSwatch(color: MontalaColors.brand),
                  const SizedBox(width: 4),
                  const Text('ارزش کل', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: Space.m),
                  const Icon(Icons.arrow_drop_up, size: 15,
                      color: MontalaColors.gain),
                  const Text('خرید', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: Space.s),
                  const Icon(Icons.arrow_drop_down, size: 15,
                      color: MontalaColors.loss),
                  const Text('فروش', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: Space.xxl),
          ],
        ),
      ),
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  final Color color;
  const _LegendSwatch({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 14,
        height: 3,
        color: color,
      );
}

class _HistoryChartPainter extends CustomPainter {
  final List<PortfolioPoint> points;
  final List<PortfolioTx> txs;

  _HistoryChartPainter({required this.points, required this.txs});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    const padLeft = 8.0, padRight = 8.0, padTop = 14.0, padBottom = 22.0;
    final w = size.width - padLeft - padRight;
    final h = size.height - padTop - padBottom;

    final t0 = points.first.date.millisecondsSinceEpoch.toDouble();
    final t1 = points.last.date.millisecondsSinceEpoch.toDouble();
    final maxV =
        points.map((p) => p.totalToman).reduce(math.max) * 1.08;

    double x(DateTime d) =>
        padLeft +
        w * (d.millisecondsSinceEpoch - t0) / (t1 - t0).clamp(1, 1 << 62);
    double y(double v) => padTop + h * (1 - v / maxV);

    // Horizontal gridlines with compact labels.
    final grid = _TextPainterHelper.gridLabels(maxV, 3);
    final gridPaint = Paint()
      ..color = MontalaColors.outline
      ..strokeWidth = 1;
    // CustomPainter does not inherit the app theme's font — set it
    // explicitly or the labels render in the platform fallback font.
    final labelStyle = const TextStyle(
        fontSize: 9, color: MontalaColors.inkMuted, fontFamily: 'Vazirmatn');
    for (final g in grid) {
      final gy = y(g.value);
      canvas.drawLine(Offset(padLeft, gy), Offset(padLeft + w, gy), gridPaint);
      final tp = _TextPainterHelper.text(g.label, labelStyle);
      tp.paint(canvas, Offset(padLeft, gy - 12));
    }

    // Value line.
    final line = Path();
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final px = x(p.date);
      final py = y(p.totalToman);
      if (i == 0) {
        line.moveTo(px, py);
      } else {
        line.lineTo(px, py);
      }
    }
    final linePaint = Paint()
      ..color = MontalaColors.brand
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(line, linePaint);

    // Buy/sell markers at their nearest series date.
    for (final tx in txs) {
      if (tx.date.isBefore(points.first.date) ||
          tx.date.isAfter(points.last.date)) {
        continue;
      }
      PortfolioPoint nearest = points.first;
      for (final p in points) {
        if (p.date.difference(tx.date).abs() <
            nearest.date.difference(tx.date).abs()) {
          nearest = p;
        }
      }
      final mx = x(tx.date);
      final my = y(nearest.totalToman);
      final paint = Paint()
        ..color = tx.isBuy ? MontalaColors.gain : MontalaColors.loss;
      final path = Path();
      if (tx.isBuy) {
        path.moveTo(mx, my - 7);
        path.lineTo(mx - 5, my + 3);
        path.lineTo(mx + 5, my + 3);
      } else {
        path.moveTo(mx, my + 7);
        path.lineTo(mx - 5, my - 3);
        path.lineTo(mx + 5, my - 3);
      }
      path.close();
      canvas.drawPath(path, paint);
    }

    // First/last date labels.
    final dateStyle = const TextStyle(
        fontSize: 9, color: MontalaColors.inkMuted, fontFamily: 'Vazirmatn');
    _TextPainterHelper.text(formatJalali(points.first.date), dateStyle)
        .paint(canvas, Offset(padLeft, size.height - padBottom + 4));
    final lastTp =
        _TextPainterHelper.text(formatJalali(points.last.date), dateStyle);
    lastTp.paint(
      canvas,
      Offset(padLeft + w - lastTp.width, size.height - padBottom + 4),
    );
  }

  @override
  bool shouldRepaint(covariant _HistoryChartPainter old) =>
      old.points != points || old.txs != txs;
}

/// Small text-painter helpers so the chart painter stays readable.
class _TextPainterHelper {
  static TextPainter text(String s, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.rtl,
    )..layout();
    return tp;
  }

  /// [count]+1 evenly spaced gridline values with compact Toman labels.
  static List<_GridLabel> gridLabels(double maxV, int count) {
    final out = <_GridLabel>[];
    for (var i = 1; i <= count; i++) {
      final v = maxV * i / (count + 1);
      out.add(_GridLabel(v, fmtCompactToman(v)));
    }
    return out;
  }
}

class _GridLabel {
  final double value;
  final String label;
  const _GridLabel(this.value, this.label);
}

/// Compact Toman formatting: «۱۲٫۵ میلیارد» / «۳۴۰ میلیون» / grouped.
String fmtCompactToman(double v) {
  if (v >= 1e9) return '${formatDoubleFa(v / 1e9, 1)} میلیارد';
  if (v >= 1e6) return '${formatDoubleFa(v / 1e6, 1)} میلیون';
  if (v >= 1e3) return toPersianDigits(groupThousands(v.round()));
  return toPersianDigits(v.toStringAsFixed(0));
}

String _fmtCompactToman(double v) => fmtCompactToman(v);

// --------------------------------------------------------------------------
// transactions

class _TransactionsTab extends StatelessWidget {
  final List<PortfolioTx> txs;
  final Map<String, List<PriceRow>> history;
  final VoidCallback onChanged;
  final void Function(PortfolioTx) onEdit;

  const _TransactionsTab({
    required this.txs,
    required this.history,
    required this.onChanged,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (txs.isEmpty) {
      return const Center(
        child: Text(
          'هیچ تراکنشی ثبت نشده است.',
          style: TextStyle(color: MontalaColors.inkMuted),
        ),
      );
    }
    final ordered = [...txs]..sort((a, b) => b.date.compareTo(a.date));

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l,
              88),
          children: [
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < ordered.length; i++)
                    _row(context, ordered[i], i > 0),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, PortfolioTx tx, bool divider) {
    final symbol = symbolById(tx.assetId);
    return InkWell(
      onTap: () => onEdit(tx),
      child: Column(
        children: [
          if (divider) const Divider(height: 1),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
            child: Row(
              children: [
                Icon(
                  tx.isBuy ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 17,
                  color: tx.isBuy ? MontalaColors.gain : MontalaColors.loss,
                ),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${symbol.nameFa} · '
                        '${formatDoubleFa(tx.units, symbol.unitDecimals)} '
                        '${symbol.unitFa}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${formatJalali(tx.date)}'
                        '${tx.note == null || tx.note!.isEmpty ? '' : ' · ${tx.note}'}',
                        style: const TextStyle(
                            fontSize: 11, color: MontalaColors.inkMuted),
                      ),
                    ],
                  ),
                ),
                Text(
                  fmtCompactToman(tx.totalToman),
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// entry dialog

class _TxDialog extends StatefulWidget {
  final PortfolioTx? existing;
  final List<PortfolioTx> txs;
  final Map<String, List<PriceRow>> history;

  const _TxDialog({
    required this.existing,
    required this.txs,
    required this.history,
  });

  @override
  State<_TxDialog> createState() => _TxDialogState();
}

class _TxDialogState extends State<_TxDialog> {
  late String _assetId;
  late bool _isBuy;
  late DateTime _date;
  late final TextEditingController _units;
  late final TextEditingController _price;
  late final TextEditingController _note;
  bool _priceTouched = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _assetId = e?.assetId ?? 'sekee';
    _isBuy = e?.isBuy ?? true;
    _date = e?.date ?? DateTime.now();
    _units = TextEditingController(
      text: e == null ? '' : formatDoubleFa(e.units,
          symbolById(e.assetId).unitDecimals).replaceAll('٫', '.'),
    );
    _price = TextEditingController(
      text: e == null ? '' : _numFa(e.unitPriceToman),
    );
    _note = TextEditingController(text: e?.note ?? '');
    if (e == null) _prefillPrice();
  }

  static String _numFa(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toString();
  }

  double _dbPrice(String assetId, DateTime date) {
    final rows = widget.history[assetId] ?? const <PriceRow>[];
    final row = rowOnOrBefore(rows, date);
    if (row == null) return 0;
    return row.byBasis(PriceBasis.close).toDouble();
  }

  void _prefillPrice() {
    final p = _dbPrice(_assetId, _date);
    if (p > 0) _price.text = _numFa(p);
  }

  Future<void> _pickDate() async {
    final picked = await showJalaliDatePicker(
      context,
      initialDate: _date,
      // Only dates this asset actually has data for are reachable — the
      // floor moves when the user switches asset in the form.
      firstDate: earliestDataDate(widget.history, ids: {_assetId}),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      title: 'تاریخ تراکنش',
    );
    if (picked == null) return;
    setState(() {
      _date = picked;
      if (!_priceTouched) _prefillPrice();
    });
  }

  Future<void> _save() async {
    final units = double.tryParse(
        normalizeDigits(_units.text).replaceAll(',', ''));
    final price = double.tryParse(
        normalizeDigits(_price.text).replaceAll(',', ''));
    if (units == null || units <= 0) {
      _error('تعداد را درست وارد کنید.');
      return;
    }
    if (price == null || price <= 0) {
      _error('قیمت هر واحد را درست وارد کنید.');
      return;
    }
    final tx = PortfolioTx(
      date: _date,
      assetId: _assetId,
      type: _isBuy ? 'BUY' : 'SELL',
      units: units,
      unitPriceToman: price,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    try {
      assertSellAllowed(widget.txs, tx);
    } on PortfolioValidationException {
      _error('فروش بیش از موجودی این دارایی در آن تاریخ ممکن نیست.');
      return;
    }
    if (mounted) Navigator.pop(context, _TxDialogResult(tx: tx));
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final symbol = symbolById(_assetId);
    return AlertDialog(
      title: Text(widget.existing == null ? 'تراکنش جدید' : 'ویرایش تراکنش'),
      contentPadding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _assetId,
                decoration: const InputDecoration(labelText: 'دارایی'),
                items: [
                  for (final s in kSymbols)
                    DropdownMenuItem(value: s.id, child: Text(s.nameFa)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _assetId = v;
                    if (!_priceTouched) _prefillPrice();
                  });
                },
              ),
              const SizedBox(height: Space.m),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('خرید')),
                  ButtonSegment(value: false, label: Text('فروش')),
                ],
                selected: {_isBuy},
                onSelectionChanged: (s) => setState(() => _isBuy = s.first),
              ),
              const SizedBox(height: Space.m),
              InkWell(
                borderRadius: BorderRadius.circular(Radii.md),
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'تاریخ'),
                  child: Text(formatJalaliLong(_date)),
                ),
              ),
              const SizedBox(height: Space.m),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _units,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        labelText: 'تعداد (${symbol.unitFa})',
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: TextField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'قیمت هر واحد (تومان)'),
                      onChanged: (_) => _priceTouched = true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.m),
              TextField(
                controller: _note,
                decoration:
                    const InputDecoration(labelText: 'یادداشت (اختیاری)'),
              ),
              const SizedBox(height: Space.m),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const _TxDialogResult.deleted()),
            child: const Text(
              'حذف',
              style: TextStyle(color: MontalaColors.loss),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        FilledButton(onPressed: _save, child: const Text('ثبت')),
      ],
    );
  }
}

/// What the transaction dialog closed with: a saved tx, or a delete request.
@immutable
class _TxDialogResult {
  final PortfolioTx? tx;
  final bool deleted;

  const _TxDialogResult({this.tx}) : deleted = false;
  const _TxDialogResult.deleted()
      : tx = null,
        deleted = true;
}

// --------------------------------------------------------------------------
// import mode dialog

class _ImportModeDialog extends StatelessWidget {
  final CsvParseResult parsed;
  final bool hasExisting;

  const _ImportModeDialog({required this.parsed, required this.hasExisting});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ورود تراکنش‌ها'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${toPersianDigits('${parsed.txs.length}')} تراکنش معتبر '
              'در فایل پیدا شد.'),
          if (parsed.errors.isNotEmpty) ...[
            const SizedBox(height: Space.s),
            Text('${toPersianDigits('${parsed.errors.length}')} ردیف نامعتبر '
                'رد می‌شود.',
                style: const TextStyle(color: MontalaColors.loss)),
          ],
          const SizedBox(height: Space.m),
          const Text('با تراکنش‌های فعلی چه کندیم؟'),
        ],
      ),
      actions: [
        if (hasExisting)
          TextButton(
            onPressed: () => Navigator.pop(context, _ImportMode.merge),
            child: const Text('ادغام با فعلی‌ها'),
          ),
        if (hasExisting)
          TextButton(
            onPressed: () => Navigator.pop(context, _ImportMode.replace),
            child: const Text('جایگزینی کامل'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ImportMode.merge),
          child: Text(hasExisting ? 'ادغام' : 'ورود'),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------------
// analysis

class _AnalysisTab extends StatelessWidget {
  final List<PortfolioTx> txs;
  final Map<String, List<PriceRow>> history;
  final PriceBasis basis;

  const _AnalysisTab({
    required this.txs,
    required this.history,
    required this.basis,
  });

  @override
  Widget build(BuildContext context) {
    if (txs.isEmpty) {
      return const Center(
        child: Text(
          'تحلیل پس از ثبت تراکنش‌ها ساخته می‌شود.',
          style: TextStyle(color: MontalaColors.inkMuted),
        ),
      );
    }
    final report = portfolioReport(
      txs: txs,
      history: history,
      basis: basis,
    );

    final start = firstTxDate(txs)!;
    final series = portfolioSeries(
      txs: txs,
      history: history,
      basis: basis,
      from: start,
      to: DateTime.now(),
    );
    final totals = [for (final p in series) p.totalToman];
    final ma30 = movingAverage(totals, 30).last;
    final vol = volatilityPct(totals);
    final anomalies = zscoreAnomalies(totals);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(Space.l),
          children: [
            _section('موقعیت دارایی‌ها (سود/زیان باز)'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.m),
                child: report.positions.isEmpty
                    ? const Text('دارایی بازی نگه داشته نشده.',
                        style: TextStyle(
                            fontSize: 12, color: MontalaColors.inkMuted))
                    : Column(
                        children: [
                          for (final p in report.positions)
                            _positionRow(p),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: Space.m),
            _section('سود/زیان تحقق‌یافته فروش‌ها'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.m),
                child: report.realizedSells.isEmpty
                    ? const Text('فروشی ثبت نشده.',
                        style: TextStyle(
                            fontSize: 12, color: MontalaColors.inkMuted))
                    : Column(
                        children: [
                          for (final r in report.realizedSells)
                            _realizedRow(r),
                          const Divider(height: Space.m),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('جمع',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700)),
                              Text(
                                fmtCompactToman(report.realizedPnlToman),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: report.realizedPnlToman >= 0
                                      ? MontalaColors.gain
                                      : MontalaColors.loss,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: Space.m),
            _section('پویایی سری ارزش'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.m),
                child: Column(
                  children: [
                    _metricRow('میانگین متحرک ۳۰ روزه (آخرین)',
                        ma30 == null ? '—' : fmtCompactToman(ma30)),
                    _metricRow('نوسان ۳۰ روزه (انحراف معیار بازده روزانه)',
                        vol == null ? '—' : '${formatDoubleFa(vol, 1)}٪'),
                    _metricRow('نقاط غیرعادی (|z| > ۲)',
                        toPersianDigits('${anomalies.length}')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.xxl),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(left: Space.xs, bottom: Space.s),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: MontalaColors.inkMuted,
          ),
        ),
      );

  Widget _positionRow(AssetPosition p) {
    final symbol = symbolById(p.assetId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(symbol.nameFa,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  '${formatDoubleFa(p.units, symbol.unitDecimals)} '
                  '${symbol.unitFa} · میانگین خرید '
                  '${fmtCompactToman(p.avgCostToman)}',
                  style: const TextStyle(
                      fontSize: 11, color: MontalaColors.inkMuted),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              fmtCompactToman(p.marketValueToman),
              textAlign: TextAlign.left,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          Expanded(
            flex: 2,
            child: DeltaText(p.roiPct, showBackground: true, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _realizedRow(RealizedSell r) {
    final symbol = symbolById(r.tx.assetId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              '${symbol.nameFa} · فروش '
              '${formatDoubleFa(r.tx.units, symbol.unitDecimals)} '
              '${symbol.unitFa} · ${formatJalali(r.tx.date)}',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          Text(
            fmtCompactToman(r.pnlToman),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: r.pnlToman >= 0 ? MontalaColors.gain : MontalaColors.loss,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Text(value,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
