import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_theme.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _kPaletteKey = 'selected_palette';

  AppPalette _palette = AppPalette.neonBlue;

  ThemeProvider() {
    _load();
  }

  AppPalette get palette => _palette;

  ThemeData get themeData => AppTheme.themeFor(_palette);

  Future<void> setPalette(AppPalette p) async {
    if (_palette == p) return;
    _palette = p;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPaletteKey, p.toString());
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kPaletteKey);
    if (s == null) return;
    try {
      _palette = AppPalette.values.firstWhere((e) => e.toString() == s);
      notifyListeners();
    } catch (_) {
      // ignore
    }
  }
}
