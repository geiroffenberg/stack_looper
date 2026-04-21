import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color _background = Color(0xFF0F1115);
  static const Color _surface = Color(0xFF181B20);
  static const Color _selected = Color(0xFF4B8BFF);
  static const Color _accent = Color(0xFF69D2A9);

  static ThemeData get darkMinimal {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _background,
      colorScheme: const ColorScheme.dark(
        primary: _selected,
        secondary: _accent,
        surface: _surface,
      ),
      cardTheme: const CardThemeData(
        color: _surface,
        elevation: 0,
        margin: EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Color(0xFF111318),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
