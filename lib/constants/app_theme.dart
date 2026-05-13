import 'package:flutter/material.dart';

enum AppPalette { neonBlue, neonGreen, neonYellow, neonRed, light }

class AppTheme {
  AppTheme._();

  static ThemeData themeFor(AppPalette palette) {
    switch (palette) {
      case AppPalette.neonGreen:
        return _darkBase(
          border: const Color(0xFF16A34A),
          selected: const Color(0xFF4ADE80),
          accent: const Color(0xFF34D399),
          textPrimary: const Color(0xFFEFFAF0),
          textSecondary: const Color(0xFFBFEED1),
        );
      case AppPalette.neonYellow:
        return _darkBase(
          border: const Color(0xFFF59E0B),
          selected: const Color(0xFFFDE68A),
          accent: const Color(0xFFFCD34D),
          textPrimary: const Color(0xFFFFFBEB),
          textSecondary: const Color(0xFFF7E8A9),
        );
      case AppPalette.neonRed:
        return _darkBase(
          border: const Color(0xFFEF4444),
          selected: const Color(0xFFFCA5A5),
          accent: const Color(0xFFF87171),
          textPrimary: const Color(0xFFFFF1F1),
          textSecondary: const Color(0xFFF7C7C7),
        );
      case AppPalette.light:
        return _lightBase(
          primary: const Color(0xFF0F172A),
          secondary: const Color(0xFF111827),
          surface: const Color(0xFFFFFFFF),
          onSurface: const Color(0xFF0B1220),
          border: const Color(0xFF60A5FA),
        );
      case AppPalette.neonBlue:
      default:
        return _darkBase(
          border: const Color(0xFF3B82F6),
          selected: const Color(0xFF60A5FA),
          accent: const Color(0xFF4DA3FF),
          textPrimary: const Color(0xFFE5EEFF),
          textSecondary: const Color(0xFF9FB3D9),
        );
    }
  }

  static ThemeData _darkBase({
    required Color border,
    required Color selected,
    required Color accent,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    const Color background = Color(0xFF090C10);
    const Color surface = Color(0xFF111827);
    const Color surfaceRaised = Color(0xFF161E2D);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.dark(
        primary: selected,
        secondary: accent,
        surface: surface,
        onSurface: textPrimary,
        onPrimary: textPrimary,
      ),
      dividerColor: border,
      iconTheme: IconThemeData(color: textPrimary),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: textPrimary),
        bodyMedium: TextStyle(color: textPrimary),
        titleMedium: TextStyle(color: textPrimary),
        labelLarge: TextStyle(color: textPrimary),
        labelMedium: TextStyle(color: textSecondary),
      ),
      cardTheme: CardThemeData(
        color: surfaceRaised,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border, width: 1),
          borderRadius: const BorderRadius.all(Radius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: const Color(0xFF0D1420),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: border.withOpacity(0.9), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: selected, width: 1.2),
        ),
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: border.withOpacity(0.9), width: 1),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(color: surfaceRaised),
    );
  }

  static ThemeData _lightBase({
    required Color primary,
    required Color secondary,
    required Color surface,
    required Color onSurface,
    required Color border,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: surface,
      colorScheme: ColorScheme.light(
        primary: primary,
        secondary: secondary,
        surface: surface,
        onSurface: onSurface,
        onPrimary: onSurface,
      ),
      dividerColor: border,
      iconTheme: IconThemeData(color: onSurface),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: onSurface),
        bodyMedium: TextStyle(color: onSurface),
        titleMedium: TextStyle(color: onSurface),
        labelLarge: TextStyle(color: onSurface),
        labelMedium: TextStyle(color: onSurface.withOpacity(0.7)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border, width: 1),
          borderRadius: const BorderRadius.all(Radius.circular(14)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(color: surface),
    );
  }
}
