import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/theme_controller.dart';
import '../../utils/theme.dart';
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.arrow_back,
                      color: AppColors.gray600, size: 20),
                ),
              ),
              const SizedBox(width: 14),
              const Text('Appearance', style: AppTextStyles.headline),
            ]),
            const SizedBox(height: 24),

            const Text('COLOUR THEME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppColors.gray500)),
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
                          duration: AppMotion.duration,
                          curve: AppMotion.curve,
                          width: selected ? 50 : 44,
                          height: selected ? 50 : 44,
                          decoration: BoxDecoration(
                            color: palette.primary,
                            shape: BoxShape.circle,
                            border: selected
                                ? Border.all(
                                    color: AppColors.surface, width: 2.5)
                                : null,
                          ),
                          child: selected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                        ),
                        const SizedBox(height: 6),
                        Text(palette.name, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? AppColors.textPrimary : AppColors.gray500)),
                      ]),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 24),
            const Text('DENSITY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppColors.gray500)),
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
                        duration: AppMotion.duration,
                        curve: AppMotion.curve,
                        height: 42,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: selected
                              ? themeController.palette.primary
                              : Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(AppRadius.control),
                        ),
                        child: Center(child: Text(densities[i], style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? Colors.white : AppColors.gray500))),
                      ),
                    ),
                  );
                }),
              ),
            ),

            const SizedBox(height: 24),
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: const Row(children: [
                Icon(Icons.info_outline, color: AppColors.gray400, size: 16),
                SizedBox(width: 10),
                Expanded(child: Text('Appearance settings are applied instantly and stored locally.', style: AppTextStyles.body)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
