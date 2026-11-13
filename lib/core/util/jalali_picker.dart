/// Persian (Jalali) date picker dialog.
///
/// Flutter's built-in pickers are Gregorian-only, so this is a small custom
/// grid picker with Persian digits. Navigation:
///  * single chevrons step one month, double chevrons step one year,
///  * tapping the «ماه سال» header switches to a month/year view (12-month
///    grid plus a scrollable year list) for long-distance jumps.
library;

import 'package:flutter/material.dart';

import 'jalali.dart';
import 'format.dart';

Future<DateTime?> showJalaliDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = 'انتخاب تاریخ',
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => _JalaliPickerDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
    ),
  );
}

class _JalaliPickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;

  const _JalaliPickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.title,
  });

  @override
  State<_JalaliPickerDialog> createState() => _JalaliPickerDialogState();
}

class _JalaliPickerDialogState extends State<_JalaliPickerDialog> {
  late JalaliDate _viewYearMonth;
  late DateTime _selected;
  bool _pickingMonthYear = false;
  // Keeps the year list of the month/year view scrolled to the viewed year.
  late final ScrollController _yearScroll;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
    _viewYearMonth = gregorianToJalali(widget.initialDate);
    _yearScroll = ScrollController(
      initialScrollOffset: _yearOffset(_viewYearMonth.year),
    );
  }

  @override
  void dispose() {
    _yearScroll.dispose();
    super.dispose();
  }

  /// Vertical offset of [jy] inside the year list (itemExtent 34).
  double _yearOffset(int jy) {
    final offset = (jy - _minYear) * 34.0;
    return offset > 0 ? offset : 0;
  }

  void _scrollYearList(int jy) {
    if (!_yearScroll.hasClients) return;
    _yearScroll.jumpTo(_yearOffset(jy).clamp(
      0,
      _yearScroll.position.maxScrollExtent,
    ));
  }

  int get _minYear => gregorianToJalali(widget.firstDate).year;
  int get _maxYear => gregorianToJalali(widget.lastDate).year;

  bool _inRange(int y, int m, int d) {
    final g = jalaliToGregorian(JalaliDate(y, m, d));
    return !g.isBefore(widget.firstDate) && !g.isAfter(widget.lastDate);
  }

  /// Whether any day of this Jalali month falls inside the selectable range.
  bool _monthInRange(int y, int m) {
    if (y < _minYear || y > _maxYear) return false;
    final gStart = jalaliToGregorian(JalaliDate(y, m, 1));
    final gEnd = jalaliToGregorian(JalaliDate(y, m, jalaliMonthLength(y, m)));
    return !gEnd.isBefore(widget.firstDate) && !gStart.isAfter(widget.lastDate);
  }

  void _shiftMonth(int delta) {
    var y = _viewYearMonth.year;
    var m = _viewYearMonth.month + delta;
    while (m > 12) {
      m -= 12;
      y += 1;
    }
    while (m < 1) {
      m += 12;
      y -= 1;
    }
    setState(() => _viewYearMonth = JalaliDate(y, m, 1));
  }

  void _shiftYear(int delta) {
    final y = (_viewYearMonth.year + delta).clamp(_minYear, _maxYear);
    setState(() => _viewYearMonth = JalaliDate(y, _viewYearMonth.month, 1));
    _scrollYearList(y);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final jy = _viewYearMonth.year;
    final jm = _viewYearMonth.month;

    return AlertDialog(
      title: Text(widget.title, textAlign: TextAlign.right),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      content: SizedBox(
        width: 330,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(theme, jy, jm),
            if (_pickingMonthYear)
              _buildMonthYearView(theme, jy)
            else
              _buildDayGrid(theme, jy, jm),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, DateTime.now()),
          child: const Text('امروز'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('تأیید'),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ header

  Widget _buildHeader(ThemeData theme, int jy, int jm) {
    if (_pickingMonthYear) {
      // Month/year view: the month chevrons make no sense here; year jumps
      // stay active so the month pane can be flipped quickly.
      return Row(
        children: [
          IconButton(
            onPressed: () => _shiftYear(1),
            icon: const Icon(Icons.keyboard_double_arrow_left),
            tooltip: 'سال بعد',
          ),
          Expanded(
            child: Text(
              'انتخاب ماه و سال',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: () => _shiftYear(-1),
            icon: const Icon(Icons.keyboard_double_arrow_right),
            tooltip: 'سال قبل',
          ),
        ],
      );
    }

    return Row(
      children: [
        IconButton(
          onPressed: () => _shiftYear(1),
          icon: const Icon(Icons.keyboard_double_arrow_left),
          tooltip: 'سال بعد',
        ),
        IconButton(
          onPressed: () => _shiftMonth(1),
          icon: const Icon(Icons.chevron_left),
          tooltip: 'ماه بعد',
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _pickingMonthYear = true),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '${kJalaliMonthNames[jm - 1]} ${toPersianDigits('$jy')}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: () => _shiftMonth(-1),
          icon: const Icon(Icons.chevron_right),
          tooltip: 'ماه قبل',
        ),
        IconButton(
          onPressed: () => _shiftYear(-1),
          icon: const Icon(Icons.keyboard_double_arrow_right),
          tooltip: 'سال قبل',
        ),
      ],
    );
  }

  // ---------------------------------------------------------- month/year view

  Widget _buildMonthYearView(ThemeData theme, int jy) {
    final selJ = gregorianToJalali(_selected);

    return SizedBox(
      height: 236,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Months of the viewed year — first child in RTL, so right side.
          Expanded(
            flex: 5,
            child: GridView.count(
              crossAxisCount: 3,
              padding: const EdgeInsets.only(top: 4),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1.45,
              children: [
                for (var m = 1; m <= 12; m++) _monthCell(theme, jy, m, selJ),
              ],
            ),
          ),
          const VerticalDivider(width: 12),
          // Year list — left side in RTL.
          Expanded(
            flex: 3,
            child: _yearList(theme, jy),
          ),
        ],
      ),
    );
  }

  Widget _monthCell(ThemeData theme, int jy, int m, JalaliDate selJ) {
    final enabled = _monthInRange(jy, m);
    final isSelected = selJ.year == jy && selJ.month == m;
    return Padding(
      padding: const EdgeInsets.all(1),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled
            ? () => setState(() {
                  _viewYearMonth = JalaliDate(jy, m, 1);
                  _pickingMonthYear = false;
                })
            : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isSelected ? theme.colorScheme.primary : null,
          ),
          alignment: Alignment.center,
          child: Text(
            kJalaliMonthNames[m - 1],
            style: TextStyle(
              fontSize: 12,
              color: !enabled
                  ? theme.disabledColor
                  : isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  Widget _yearList(ThemeData theme, int jy) {
    final years = [
      for (var y = _minYear; y <= _maxYear; y++) y,
    ];

    return ListView.builder(
      controller: _yearScroll,
      itemExtent: 34,
      itemCount: years.length,
      itemBuilder: (context, index) {
        final y = years[index];
        final isSelected = y == jy;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _viewYearMonth = JalaliDate(y, 1, 1)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: isSelected ? theme.colorScheme.primaryContainer : null,
              ),
              alignment: Alignment.center,
              child: Text(
                toPersianDigits('$y'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- day grid

  Widget _buildDayGrid(ThemeData theme, int jy, int jm) {
    final monthLen = jalaliMonthLength(jy, jm);

    // Weekday of the 1st of this Jalali month (Persian week starts Saturday).
    final firstG = jalaliToGregorian(JalaliDate(jy, jm, 1));
    // DateTime.weekday: Mon=1..Sun=7 → Saturday-first offset.
    final leading = (firstG.weekday + 1) % 7;

    final selJ = gregorianToJalali(_selected);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (final w in kJalaliWeekdayShort)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    w.length > 2 ? w.substring(0, 2) : w,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const Divider(height: 1),
        SizedBox(
          height: 232,
          child: GridView.builder(
            padding: const EdgeInsets.only(top: 4),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.05,
            ),
            itemCount: leading + monthLen,
            itemBuilder: (context, index) {
              if (index < leading) return const SizedBox.shrink();
              final day = index - leading + 1;
              final enabled = _inRange(jy, jm, day);
              final isSelected = selJ.year == jy &&
                  selJ.month == jm &&
                  selJ.day == day;
              final isToday = _isTodayJalali(jy, jm, day);
              return Padding(
                padding: const EdgeInsets.all(2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: enabled
                      ? () => setState(() {
                            _selected =
                                jalaliToGregorian(JalaliDate(jy, jm, day));
                          })
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      color: isSelected
                          ? theme.colorScheme.primary
                          : isToday
                              ? theme.colorScheme.primaryContainer
                              : null,
                      border: isToday && !isSelected
                          ? Border.all(
                              color: theme.colorScheme.primary, width: 1.2)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      toPersianDigits('$day'),
                      style: TextStyle(
                        fontSize: 13.5,
                        color: !enabled
                            ? theme.disabledColor
                            : isSelected
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            formatJalaliLong(_selected),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  bool _isTodayJalali(int jy, int jm, int jd) {
    final t = gregorianToJalali(DateTime.now());
    return t.year == jy && t.month == jm && t.day == jd;
  }
}
