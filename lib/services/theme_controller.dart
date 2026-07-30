import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/theme.dart';

// Single-accent palettes: `secondary` always equals `primary` — the minimal
// design uses exactly one accent color (no gradients, no second hue).
enum AppThemePalette {
  emerald(
    name: 'Emerald',
    primary: Color(0xFF059669),
    secondary: Color(0xFF059669),
  ),
  cyber(
    name: 'Cyber',
    primary: Color(0xFF4F46E5),
    secondary: Color(0xFF4F46E5),
  ),
  sunset(
    name: 'Sunset',
    primary: Color(0xFFE11D48),
    secondary: Color(0xFFE11D48),
  ),
  slate(
    name: 'Slate',
    primary: Color(0xFF475569),
    secondary: Color(0xFF475569),
  ),
  aurora(
    name: 'Aurora',
    primary: Color(0xFF2563EB),
    secondary: Color(0xFF2563EB),
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

  /// Legacy `Gradient`-typed accessor — resolves to a flat accent fill so
  /// remaining gradient call sites render solid color (minimal design).
  LinearGradient get primaryGradient => LinearGradient(
    colors: [_palette.primary, _palette.primary],
  );
}
