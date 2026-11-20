/// تابلو زنده — live two-source price board.
///
/// Flutter port of m0ntIsRich's ftgn.py: the estjt.ir and tgju.org readings
/// sit side by side with the percent change against the previous refresh,
/// values carry forward through network failures, and the board auto-refresh
/// every [kRefreshSeconds]. The terminal bidi/reshape tricks of the Python
/// original are gone — Flutter renders RTL natively.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/net/live_quotes.dart';
import '../../core/util/format.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';

const int kRefreshSeconds = 60;

class LiveBoardScreen extends StatefulWidget {
  const LiveBoardScreen({
    super.key,
    @visibleForTesting this.seedTgju,
    @visibleForTesting this.seedEstjt,
    @visibleForTesting this.autoRefresh = true,
  });

  /// Test seam for the store-screenshot goldens: render the board from these
  /// fixed snapshots instead of fetching over the network (golden tests run
  /// under fake async, where real HTTP never progresses). Keys are board row
  /// keys. Null → the normal network path.
  final Map<String, LiveCell>? seedTgju;
  final Map<String, LiveCell>? seedEstjt;

  /// Test seam: disable the 60s auto-refresh ticker (a periodic timer never
  /// lets pumpAndSettle settle).
  final bool autoRefresh;

  @override
  State<LiveBoardScreen> createState() => _LiveBoardScreenState();
}

class _LiveBoardScreenState extends State<LiveBoardScreen> {
  // Merged (carry-forward) display cells per source, keyed by board row key.
  Map<String, LiveCell> _tgjuCells = const {};
  Map<String, LiveCell> _estjtCells = const {};
  // Change vs the previous fetch, same keys.
  Map<String, double?> _tgjuDelta = const {};
  Map<String, double?> _estjtDelta = const {};

  bool _tgjuStale = false;
  bool _estjtStale = false;
  bool _tgjuEverLoaded = false;
  bool _estjtEverLoaded = false;
  String? _tgjuNote;
  String? _estjtNote;

  bool _busy = false;
  int _countdown = kRefreshSeconds;
  Timer? _ticker;
  DateTime? _lastRefresh;

  @override
  void initState() {
    super.initState();
    final seeded = widget.seedTgju != null || widget.seedEstjt != null;
    if (seeded) {
      // Golden-render path: fixed snapshots, no network, no ticker.
      _tgjuCells = widget.seedTgju ?? const {};
      _estjtCells = widget.seedEstjt ?? const {};
      _tgjuEverLoaded = widget.seedTgju != null;
      _estjtEverLoaded = widget.seedEstjt != null;
      _lastRefresh = DateTime.now();
      if (widget.autoRefresh) {
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      }
      return;
    }
    _refresh();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    if (_busy) return;
    setState(() {
      _countdown -= 1;
      if (_countdown <= 0) {
        _countdown = kRefreshSeconds;
        _refresh();
      }
    });
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);

    final prevTgju = _tgjuCells;
    final prevEstjt = _estjtCells;

    // estjt is native-only (no CORS header on the web).
    final wantEstjt = !kIsWeb;
    final results = await Future.wait<Object?>(
        [_fetchTgju(), if (wantEstjt) _fetchEstjt(prevEstjtStale: _estjtStale)]);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _countdown = kRefreshSeconds;
      _lastRefresh = DateTime.now();

      final tgju = results[0] as LiveSnapshot;
      _tgjuCells = mergeCells(previous: prevTgju, fresh: tgju.cells);
      _tgjuDelta = {
        for (final row in kLiveBoardRows)
          row.key: changePct(prevTgju[row.key]?.value,
              _tgjuCells[row.key]?.value),
      };
      _tgjuStale = tgju.stale || _tgjuEverLoaded && tgju.cells.isEmpty;
      _tgjuEverLoaded = _tgjuEverLoaded || tgju.cells.isNotEmpty;
      _tgjuNote = tgju.note;

      if (wantEstjt) {
        final estjt = results[1] as LiveSnapshot;
        _estjtCells = mergeCells(previous: prevEstjt, fresh: estjt.cells);
        _estjtDelta = {
          for (final row in kLiveBoardRows)
            row.key: changePct(prevEstjt[row.key]?.value,
                _estjtCells[row.key]?.value),
        };
        _estjtStale = estjt.stale;
        _estjtEverLoaded = _estjtEverLoaded || estjt.cells.isNotEmpty;
        _estjtNote = estjt.note;
      }
    });
  }

  Future<LiveSnapshot> _fetchTgju() async {
    try {
      return await fetchTgjuLive();
    } catch (e) {
      return LiveSnapshot(
        source: 'tgju',
        fetchedAt: DateTime.now(),
        stale: true,
        cells: const {},
        note: '$e',
      );
    }
  }

  Future<LiveSnapshot> _fetchEstjt({required bool prevEstjtStale}) async {
    try {
      return await fetchEstjtLive();
    } catch (e) {
      return LiveSnapshot(
        source: 'estjt',
        fetchedAt: DateTime.now(),
        stale: true,
        cells: const {},
        note: prevEstjtStale ? '$e' : null,
      );
    }
  }



  @override
  Widget build(BuildContext context) {
    final showEstjt = !kIsWeb;
    final inToman = AppScope.of(context).settings.inToman;
    return Scaffold(
      appBar: AppBar(
        title: const Text('تابلو زنده'),
        actions: [
          IconButton(
            tooltip: 'درباره این ابزار',
            icon: const Icon(Icons.info_outline, size: 21),
            onPressed: () => showToolInfo(
              context,
              icon: Icons.monitor_heart,
              iconColor: MontalaColors.gold,
              title: 'تابلو زنده',
              paragraphs: const [
                'قیمت لحظه‌ای سیزده دارایی (سکه‌ها، طلای ۱۸ و ۲۴، مثقال، انس '
                    'جهانی، آبشده و نقره) را در دو ستون کنار هم از دو منبع '
                    'نشان می‌دهد: estjt و tgju — تا اختلاف منابع دیده شود.',
                'درصد زیر هر عدد، تغییر نسبت به رفرش قبلی است (سبز ▲، قرمز '
                    '▼). صفحه هر ۶۰ ثانیه خودش به‌روزرسانی می‌کند و با دکمه '
                    'پایین‌کشیدن هم می‌توانید فوری تازه کنید.',
                'واحد هر عدد کنارش نوشته شده و با تنظیم «نمایش مبلغ به '
                    'تومان» بین تومان و ریال جابه‌جا می‌شود؛ انس جهانی همیشه '
                    'دلاری است.',
                'در قطعی شبکه، آخرین مقادیر با رنگ کم‌رنگ می‌مانند و بار '
                    'کش/قطع بالا صفحه دیده می‌شود. ستون estjt فقط روی نسخه‌های '
                    'بومی (اندروید/ویندوز/لینوکس) کار می‌کند — آن سایت هدر '
                    'CORS ندارد و نسخه وب فقط tgju را نشان می‌دهد.',
              ],
            ),
          ),
          IconButton(
            onPressed: _busy ? null : _refresh,
            tooltip: 'به‌روزرسانی',
            icon: _busy
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 21),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _statusStrip(showEstjt),
            if (kIsWeb) _webNotice(),
            Expanded(child: _board(showEstjt, inToman)),
          ],
        ),
      ),
    );
  }

  Widget _statusStrip(bool showEstjt) {
    final problems = <String>[];
    if (_tgjuStale) problems.add('tgju قطع — آخرین مقادیر');
    if (showEstjt && _estjtStale) problems.add('estjt قطع — آخرین مقادیر');

    final updated = _lastRefresh == null
        ? 'در حال دریافت…'
        : 'آخرین به‌روزرسانی: ${_clock(_lastRefresh!)} — به‌روزرسانی بعدی تا '
            '${toPersianDigits('$_countdown')} ثانیه';

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule,
                  size: 13, color: MontalaColors.inkMuted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  updated,
                  style: const TextStyle(
                      fontSize: 11, color: MontalaColors.inkMuted),
                ),
              ),
            ],
          ),
          if (problems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off,
                      size: 13, color: MontalaColors.loss),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      problems.join(' · '),
                      style: const TextStyle(
                          fontSize: 11, color: MontalaColors.loss),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _clock(DateTime t) =>
      toPersianDigits('${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}');

  Widget _webNotice() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      child: Container(
        padding: const EdgeInsets.all(Space.s),
        decoration: BoxDecoration(
          color: MontalaColors.goldSoft,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: const Text(
          'ستون estjt فقط روی نسخه‌های بومی (اندروید/ویندوز/لینوکس) در دسترس '
          'است؛ نسخه وب به‌خاطر محدودیت CORS فقط tgju را نشان می‌دهد.',
          style: TextStyle(fontSize: 11, height: 1.7),
        ),
      ),
    );
  }

  Widget _board(bool showEstjt, bool inToman) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Card(
          margin: const EdgeInsets.all(Space.l),
          child: Column(
            children: [
              _headerRow(showEstjt),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: kLiveBoardRows.length,
                  itemBuilder: (context, index) {
                    final row = kLiveBoardRows[index];
                    return _boardRow(row, showEstjt, inToman, index);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerRow(bool showEstjt) {
    TextStyle head() => const TextStyle(
        fontSize: 11.5, fontWeight: FontWeight.w700,
        color: MontalaColors.inkMuted);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.s),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('دارایی', style: head())),
          if (showEstjt)
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  Text('estjt', style: head()),
                  if (_estjtNote != null)
                    Text(
                      _estjtNote!,
                      style: const TextStyle(
                          fontSize: 9, color: MontalaColors.inkMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          // tgju column header follows below (always present).
          _tgjuHeaderCell(head),
        ],
      ),
    );
  }

  Widget _tgjuHeaderCell(TextStyle Function() head) {
    return Expanded(
      flex: 3,
      child: Column(
        children: [
          Text('tgju', style: head()),
          if (_tgjuNote != null)
            Text(
              _tgjuNote!,
              style: const TextStyle(
                  fontSize: 9, color: MontalaColors.inkMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget _boardRow(LiveBoardRow row, bool showEstjt, bool inToman,
      int index) {
    return Column(
      children: [
        if (index > 0) const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Space.m, vertical: Space.s),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  row.labelFa,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              if (showEstjt)
                Expanded(
                  flex: 3,
                  child: _cell(_estjtCells[row.key], _estjtDelta[row.key],
                      _estjtStale, inToman),
                ),
              Expanded(
                flex: 3,
                child: _cell(
                    _tgjuCells[row.key], _tgjuDelta[row.key], _tgjuStale,
                    inToman),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cell(LiveCell? cell, double? delta, bool stale, bool inToman) {
    final (:value, :unit) = formatLiveCell(
      cell ?? const LiveCell(),
      inToman,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cell == null || cell.value == null
                      ? MontalaColors.inkMuted
                      : stale
                          ? MontalaColors.inkMuted
                          : MontalaColors.ink,
                ),
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 3),
              Text(
                unit,
                style: const TextStyle(
                  fontSize: 9,
                  color: MontalaColors.inkMuted,
                ),
              ),
            ],
          ],
        ),
        DeltaText(delta, fontSize: 10.5),
      ],
    );
  }
}
