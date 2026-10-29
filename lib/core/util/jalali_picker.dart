/// Persian (Jalali) date picker dialog.
///
/// Flutter's built-in pickers are Gregorian-only, so this is a small custom
/// grid picker with month/year navigation and Persian digits.
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

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
    _viewYearMonth = gregorianToJalali(widget.initialDate);
  }

  bool _inRange(int y, int m, int d) {
    final g = jalaliToGregorian(JalaliDate(y, m, d));
    return !g.isBefore(widget.firstDate) && !g.isAfter(widget.lastDate);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final jy = _viewYearMonth.year;
    final jm = _viewYearMonth.month;
    final monthLen = jalaliMonthLength(jy, jm);

    // Weekday of the 1st of this Jalali month (Persian week starts Saturday).
    final firstG = jalaliToGregorian(JalaliDate(jy, jm, 1));
    // DateTime.weekday: Mon=1..Sun=7 → Saturday-first offset.
    final leading = (firstG.weekday + 1) % 7;

    final selJ = gregorianToJalali(_selected);

    return AlertDialog(
      title: Text(widget.title, textAlign: TextAlign.right),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      content: SizedBox(
        width: 330,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'ماه بعد',
                ),
                Expanded(
                  child: Text(
                    '${kJalaliMonthNames[jm - 1]} ${toPersianDigits('$jy')}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'ماه قبل',
                ),
              ],
            ),
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

  bool _isTodayJalali(int jy, int jm, int jd) {
    final t = gregorianToJalali(DateTime.now());
    return t.year == jy && t.month == jm && t.day == jd;
  }
}
