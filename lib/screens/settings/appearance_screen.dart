import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});
  @override State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  int _themeIdx = 0;   // 0=Emerald, 1=Cyber, 2=Sunset, 3=Slate, 4=Aurora
  int _densityIdx = 1; // 0=Compact, 1=Regular, 2=Comfy

  static const _themes = [
    ('Emerald', Color(0xFF00C896), Color(0xFF00E5FF)),
    ('Cyber',   Color(0xFF7B61FF), Color(0xFFFF3CAC)),
    ('Sunset',  Color(0xFFFF6FD8), Color(0xFFFF9671)),
    ('Slate',   Color(0xFF94A3B8), Color(0xFF64748B)),
    ('Aurora',  Color(0xFF6C63FF), Color(0xFF00D4FF)),
  ];

  static const _densities = ['Compact', 'Regular', 'Comfy'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeIdx   = prefs.getInt('appearance_theme')   ?? 0;
      _densityIdx = prefs.getInt('appearance_density') ?? 1;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('appearance_theme',   _themeIdx);
    await prefs.setInt('appearance_density', _densityIdx);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GestureDetector(
                onTap: () => context.pop(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.white.withOpacity(0.18)),
                      ),
                      child: Icon(Icons.arrow_back, color: Colors.white.withOpacity(0.8), size: 20),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Text('Appearance', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
            ]),
            const SizedBox(height: 24),

            const Text('COLOUR THEME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Color(0x66FFFFFF))),
            const SizedBox(height: 10),
            GlassCard(
              child: Column(children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(_themes.length, (i) {
                    final (name, c1, c2) = _themes[i];
                    final selected = _themeIdx == i;
                    return GestureDetector(
                      onTap: () { setState(() => _themeIdx = i); _save(); },
                      child: Column(children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: selected ? 50 : 44,
                          height: selected ? 50 : 44,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [c1, c2], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            shape: BoxShape.circle,
                            boxShadow: selected ? [BoxShadow(color: c1.withOpacity(0.5), blurRadius: 14, spreadRadius: 2)] : null,
                            border: selected ? Border.all(color: Colors.white, width: 2.5) : null,
                          ),
                          child: selected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                        ),
                        const SizedBox(height: 6),
                        Text(name, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w400, color: selected ? Colors.white : Colors.white.withOpacity(0.5))),
                      ]),
                    );
                  }),
                ),
              ]),
            ),

            const SizedBox(height: 24),
            const Text('DENSITY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Color(0x66FFFFFF))),
            const SizedBox(height: 10),
            GlassCard(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: List.generate(_densities.length, (i) {
                  final selected = _densityIdx == i;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () { setState(() => _densityIdx = i); _save(); },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 42,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          gradient: selected ? const LinearGradient(colors: [AppColors.primary, AppColors.secondary]) : null,
                          color: selected ? null : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: selected ? [BoxShadow(color: AppColors.primary.withOpacity(0.35), blurRadius: 10)] : null,
                        ),
                        child: Center(child: Text(_densities[i], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? Colors.white : Colors.white.withOpacity(0.5)))),
                      ),
                    ),
                  );
                }),
              ),
            ),

            const SizedBox(height: 24),
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                const Icon(Icons.info_outline, color: Color(0x66FFFFFF), size: 16),
                const SizedBox(width: 10),
                Expanded(child: Text('Appearance settings are stored locally on this device.', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.4)))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
