import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color _background = Color(0xFF090C10);
  static const Color _surface = Color(0xFF111827);
  static const Color _surfaceRaised = Color(0xFF161E2D);
  static const Color _border = Color(0xFF3B82F6);
  static const Color _selected = Color(0xFF60A5FA);
  static const Color _accent = Color(0xFF4DA3FF);
  static const Color _textPrimary = Color(0xFFE5EEFF);
  static const Color _textSecondary = Color(0xFF9FB3D9);

  static ThemeData get darkMinimal {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _background,
      colorScheme: const ColorScheme.dark(
        primary: _selected,
        secondary: _accent,
        surface: _surface,
        onSurface: _textPrimary,
        onPrimary: _textPrimary,
      ),
      dividerColor: _border,
      iconTheme: const IconThemeData(color: _textPrimary),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: _textPrimary),
        bodyMedium: TextStyle(color: _textPrimary),
        titleMedium: TextStyle(color: _textPrimary),
        labelLarge: TextStyle(color: _textPrimary),
        labelMedium: TextStyle(color: _textSecondary),
      ),
      cardTheme: const CardThemeData(
        color: _surfaceRaised,
        elevation: 0,
        margin: EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: _border, width: 1),
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Color(0xFF0D1420),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: Color(0xFF2D5BBA), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: _selected, width: 1.2),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: Color(0xFF2D5BBA), width: 1),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(color: _surfaceRaised),
    );
  }
}
