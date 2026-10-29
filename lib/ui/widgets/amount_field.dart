/// Amount input that accepts Persian digits and groups thousands while typing.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/util/format.dart';

class ThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = normalizeDigits(newValue.text).replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    // Guard against absurd lengths overflowing int64.
    final clipped = digits.length > 15 ? digits.substring(0, 15) : digits;
    final n = int.parse(clipped);
    final formatted = toPersianDigits(groupThousands(n));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

int parseAmountFa(String text) {
  final digits = normalizeDigits(text).replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return 0;
  return int.tryParse(digits) ?? 0;
}

/// Quantity input (e.g. 2.5 coins): Persian digits with a single decimal
/// separator, no thousands grouping.
class QuantityInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text =
        normalizeDigits(newValue.text).replaceAll('٫', '.');
    text = text.replaceAll(RegExp(r'[^0-9.]'), '');

    // Keep only the first decimal separator.
    final firstDot = text.indexOf('.');
    if (firstDot != -1) {
      text = text.substring(0, firstDot + 1) +
          text.substring(firstDot + 1).replaceAll('.', '');
    }
    if (text.length > 15) text = text.substring(0, 15);
    if (text.isEmpty || text == '.') {
      return const TextEditingValue(text: '');
    }

    final formatted = toPersianDigits(text).replaceAll('.', '٫');
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Parses a quantity field edited by [QuantityInputFormatter]; 0 when empty.
double parseQuantityFa(String text) {
  var t = normalizeDigits(text).replaceAll('٫', '.');
  t = t.replaceAll(RegExp(r'[^0-9.]'), '');
  if (t.endsWith('.')) t = t.substring(0, t.length - 1);
  final v = double.tryParse(t);
  return (v == null || v.isNaN || v.isInfinite || v <= 0) ? 0 : v;
}

class AmountField extends StatelessWidget {
  final TextEditingController controller;
  final bool inToman;
  final VoidCallback onUnitToggle;
  final ValueChanged<String>? onChanged;

  const AmountField({
    super.key,
    required this.controller,
    required this.inToman,
    required this.onUnitToggle,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textAlign: TextAlign.right,
            textDirection: TextDirection.rtl,
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandsInputFormatter()],
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
            decoration: InputDecoration(
              hintText: 'مثلاً ۱۰۰٬۰۰۰٬۰۰۰',
              hintStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w400,
                color: Color(0xFFB6B0A8),
              ),
              prefixIcon: Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, end: 2),
                child: TextButton(
                  onPressed: onUnitToggle,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        inToman ? 'تومان' : 'ریال',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Icon(Icons.swap_horiz, size: 15),
                    ],
                  ),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
