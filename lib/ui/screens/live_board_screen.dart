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
import '../theme.dart';
import '../widgets/common.dart';

const int kRefreshSeconds = 60;

class LiveBoardScreen extends StatefulWidget {
  const LiveBoardScreen({super.key});

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

  String _fmtCell(LiveCell cell) {
    final v = cell.value;
    if (v == null) return '—';
    final grouped = toPersianDigits(groupThousands(v.round()));
    return cell.isUsd ? '\$$grouped' : grouped;
  }

  @override
  Widget build(BuildContext context) {
    final showEstjt = !kIsWeb;
    return Scaffold(
      appBar: AppBar(
        title: const Text('تابلو زنده'),
        actions: [
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
            Expanded(child: _board(showEstjt)),
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

  Widget _board(bool showEstjt) {
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
                    return _boardRow(row, showEstjt, index);
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

  Widget _boardRow(LiveBoardRow row, bool showEstjt, int index) {
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
                      _estjtStale),
                ),
              Expanded(
                flex: 3,
                child:
                    _cell(_tgjuCells[row.key], _tgjuDelta[row.key], _tgjuStale),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cell(LiveCell? cell, double? delta, bool stale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          cell == null ? '—' : _fmtCell(cell),
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
        DeltaText(delta, fontSize: 10.5),
      ],
    );
  }
}
