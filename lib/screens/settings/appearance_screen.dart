import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/theme_controller.dart';
import '../../widgets/common.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final densities = ['Compact', 'Regular', 'Comfy'];

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
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      child: Icon(Icons.arrow_back, color: Colors.white.withValues(alpha: 0.8), size: 20),
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
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: AppThemePalette.values.map((palette) {
                    final selected = themeController.palette == palette;
                    return GestureDetector(
                      onTap: () => themeController.setPalette(palette),
                      child: Column(children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: selected ? 50 : 44,
                          height: selected ? 50 : 44,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [palette.primary, palette.secondary], 
                              begin: Alignment.topLeft, 
                              end: Alignment.bottomRight
                            ),
                            shape: BoxShape.circle,
                            boxShadow: selected ? [BoxShadow(color: palette.primary.withValues(alpha: 0.5), blurRadius: 14, spreadRadius: 2)] : null,
                            border: selected ? Border.all(color: Colors.white, width: 2.5) : null,
                          ),
                          child: selected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                        ),
                        const SizedBox(height: 6),
                        Text(palette.name, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w400, color: selected ? Colors.white : Colors.white.withValues(alpha: 0.5))),
                      ]),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 24),
            const Text('DENSITY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Color(0x66FFFFFF))),
            const SizedBox(height: 10),
            GlassCard(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: List.generate(densities.length, (i) {
                  final selected = themeController.densityIndex == i;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => themeController.setDensity(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 42,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          gradient: selected ? themeController.primaryGradient : null,
                          color: selected ? null : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: selected ? [BoxShadow(color: themeController.palette.primary.withValues(alpha: 0.35), blurRadius: 10)] : null,
                        ),
                        child: Center(child: Text(densities[i], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? Colors.white : Colors.white.withValues(alpha: 0.5)))),
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
                Expanded(child: Text('Appearance settings are applied instantly and stored locally.', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4)))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
