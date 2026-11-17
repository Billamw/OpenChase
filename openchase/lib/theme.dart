import 'package:flutter/material.dart';

/// OpenChase house style — dark slate with felt-green + gold accent.
/// Tokens from the project design system (ui-ux-pro-max, "OpenChase").
class OcColors {
  static const bg = Color(0xFF0F172A); // slate-900
  static const card = Color(0xFF192134);
  static const field = Color(0xFF1E293B); // slate-800 input fill
  static const border = Color(0x14FFFFFF); // white 8%
  static const fg = Color(0xFFF8FAFC);
  static const mutedFg = Color(0xFF94A3B8);
  static const primary = Color(0xFF22C55E); // green 500 (AA on dark)
  static const onPrimary = Color(0xFF052E16);
  static const deepGreen = Color(0xFF15803D);
  static const gold = Color(0xFFF59E0B); // accent / CTA highlight
  static const danger = Color(0xFFEF4444);

  static const radius = 14.0;
}

ThemeData ocTheme() {
  final scheme = ColorScheme.dark(
    primary: OcColors.primary,
    onPrimary: OcColors.onPrimary,
    secondary: OcColors.gold,
    onSecondary: Color(0xFF1C1200),
    surface: OcColors.card,
    onSurface: OcColors.fg,
    error: OcColors.danger,
    onError: Colors.white,
    outline: OcColors.mutedFg,
  );

  final base = ThemeData(
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: 'Inter',
  );
  final text = base.textTheme;

  final input = InputDecorationTheme(
    filled: true,
    fillColor: OcColors.field,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    hintStyle: TextStyle(color: OcColors.mutedFg),
    helperStyle: TextStyle(color: OcColors.mutedFg),
    labelStyle: TextStyle(color: OcColors.mutedFg),
    floatingLabelStyle: TextStyle(color: OcColors.primary),
    errorStyle: TextStyle(color: OcColors.danger),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(OcColors.radius),
      borderSide: const BorderSide(color: OcColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(OcColors.radius),
      borderSide: const BorderSide(color: OcColors.primary, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(OcColors.radius),
      borderSide: const BorderSide(color: OcColors.danger),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(OcColors.radius),
      borderSide: const BorderSide(color: OcColors.danger, width: 2),
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: OcColors.bg,
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: OcColors.card,
      foregroundColor: OcColors.fg,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: input,
    cardTheme: CardThemeData(
      color: OcColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OcColors.radius),
        side: const BorderSide(color: OcColors.border),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: OcColors.primary,
        foregroundColor: OcColors.onPrimary,
        minimumSize: const Size(160, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OcColors.radius),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: OcColors.fg,
        minimumSize: const Size(160, 52),
        side: const BorderSide(color: OcColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OcColors.radius),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: OcColors.deepGreen,
        foregroundColor: Colors.white,
        minimumSize: const Size(140, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OcColors.radius),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: OcColors.primary),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: OcColors.card,
      contentTextStyle: const TextStyle(color: OcColors.fg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OcColors.radius),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: OcColors.field,
      selectedColor: OcColors.deepGreen,
      labelStyle: const TextStyle(color: OcColors.fg),
      side: const BorderSide(color: OcColors.border),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: OcColors.primary,
      thumbColor: OcColors.primary,
      inactiveTrackColor: OcColors.field,
    ),
    dividerTheme: const DividerThemeData(color: OcColors.border),
  );
}
