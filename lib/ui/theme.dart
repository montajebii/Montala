/// Design tokens: brand colours, spacing, radii and text styles.
///
/// Persian finance apps read best on a warm neutral surface with a single
/// strong accent. The palette below uses a deep teal-gold pair: gold for
/// value/gain, a muted clay red for loss.
library;

import 'package:flutter/material.dart';

class MontalaColors {
  static const brand = Color(0xFF0F766E); // deep teal
  static const brandDark = Color(0xFF0B5A55);
  static const gold = Color(0xFFC08A2E);
  static const goldSoft = Color(0xFFF6EBD6);
  static const gain = Color(0xFF1B7F5A);
  static const gainSoft = Color(0xFFE4F3EC);
  static const loss = Color(0xFFB3261E);
  static const lossSoft = Color(0xFFFBE7E5);
  static const surfaceWarm = Color(0xFFFCFAF7);
  static const surfaceCard = Color(0xFFFFFFFF);
  static const outline = Color(0xFFE5DFD6);
  static const ink = Color(0xFF1E2321);
  static const inkMuted = Color(0xFF6B7370);
}

class Space {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 22.0;
}

ThemeData buildTheme() {
  const seed = MontalaColors.brand;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.light,
    surface: MontalaColors.surfaceWarm,
  ).copyWith(
    primary: MontalaColors.brand,
    onPrimary: Colors.white,
    secondary: MontalaColors.gold,
    outline: MontalaColors.outline,
    surfaceContainerHighest: const Color(0xFFF3EFE9),
  );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Vazirmatn',
    scaffoldBackgroundColor: MontalaColors.surfaceWarm,
    visualDensity: VisualDensity.standard,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: MontalaColors.ink,
      displayColor: MontalaColors.ink,
      fontFamily: 'Vazirmatn',
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: MontalaColors.surfaceWarm,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Vazirmatn',
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: MontalaColors.ink,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: MontalaColors.surfaceCard,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: const BorderSide(color: MontalaColors.outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: const BorderSide(color: MontalaColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: const BorderSide(color: MontalaColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: const BorderSide(color: MontalaColors.brand, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Vazirmatn',
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        side: const BorderSide(color: MontalaColors.outline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Vazirmatn',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: MontalaColors.outline,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      backgroundColor: MontalaColors.ink,
      contentTextStyle: const TextStyle(
        fontFamily: 'Vazirmatn',
        fontSize: 13.5,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: MontalaColors.ink,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      textStyle: const TextStyle(
        fontFamily: 'Vazirmatn',
        fontSize: 12,
        color: Colors.white,
      ),
    ),
  );
}
