import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/theme.dart';

enum AppThemePalette {
  emerald(
    name: 'Emerald',
    primary: Color(0xFF00C896),
    secondary: Color(0xFF00E5FF),
  ),
  cyber(
    name: 'Cyber',
    primary: Color(0xFF7B61FF),
    secondary: Color(0xFFFF3CAC),
  ),
  sunset(
    name: 'Sunset',
    primary: Color(0xFFFF6FD8),
    secondary: Color(0xFFFF9671),
  ),
  slate(
    name: 'Slate',
    primary: Color(0xFF94A3B8),
    secondary: Color(0xFF64748B),
  ),
  aurora(
    name: 'Aurora',
    primary: Color(0xFF6C63FF),
    secondary: Color(0xFF00D4FF),
  );

  final String name;
  final Color primary;
  final Color secondary;

  const AppThemePalette({
    required this.name,
    required this.primary,
    required this.secondary,
  });
}

class ThemeController extends ChangeNotifier {
  static const String _themeKey = 'appearance_theme';
  static const String _densityKey = 'appearance_density';

  AppThemePalette _palette = AppThemePalette.emerald;
  VisualDensity _visualDensity = VisualDensity.standard;

  AppThemePalette get palette => _palette;
  VisualDensity get visualDensity => _visualDensity;

  ThemeController() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    final themeIndex = prefs.getInt(_themeKey) ?? 0;
    if (themeIndex >= 0 && themeIndex < AppThemePalette.values.length) {
      _palette = AppThemePalette.values[themeIndex];
    }

    final densityIndex = prefs.getInt(_densityKey) ?? 1; // Default to Regular
    _visualDensity = _indexToDensity(densityIndex);
    
    notifyListeners();
  }

  Future<void> setPalette(AppThemePalette palette) async {
    if (_palette == palette) return;
    _palette = palette;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, palette.index);
  }

  Future<void> setDensity(int index) async {
    final density = _indexToDensity(index);
    if (_visualDensity == density) return;
    _visualDensity = density;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_densityKey, index);
  }

  VisualDensity _indexToDensity(int index) {
    switch (index) {
      case 0: return VisualDensity.compact;
      case 2: return VisualDensity.comfortable;
      default: return VisualDensity.standard;
    }
  }

  int get densityIndex {
    if (_visualDensity == VisualDensity.compact) return 0;
    if (_visualDensity == VisualDensity.comfortable) return 2;
    return 1;
  }

  ThemeData get themeData => AppTheme.build(
    primary: _palette.primary,
    secondary: _palette.secondary,
    visualDensity: _visualDensity,
  );

  LinearGradient get primaryGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_palette.primary, _palette.secondary],
  );
}
