import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'services/auth_provider.dart';
import 'services/theme_controller.dart';
import 'utils/theme.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  List<({String path, String label, IconData icon, IconData activeIcon})> _getTabs(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return [
      (path: '/home',       label: 'Home',       icon: Icons.home_outlined,           activeIcon: Icons.home_rounded),
      (path: '/attendance', label: 'Attendance',  icon: Icons.access_time_outlined,    activeIcon: Icons.access_time_filled_rounded),
      if (auth.hasFeature('leave_management'))
        (path: '/leave',      label: 'Leave',       icon: Icons.beach_access_outlined,   activeIcon: Icons.beach_access),
      if (auth.hasFeature('shifts'))
        (path: '/schedule',   label: 'Schedule',    icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today_rounded),
      (path: '/profile',    label: 'Profile',     icon: Icons.person_outline_rounded,  activeIcon: Icons.person_rounded),
    ];
  }

  int _currentIndex(BuildContext context, List<({String path, String label, IconData icon, IconData activeIcon})> tabs) {
    final loc = GoRouterState.of(context).matchedLocation;
    for (var i = 0; i < tabs.length; i++) {
      if (loc.startsWith(tabs[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _getTabs(context);
    final idx = _currentIndex(context, tabs);
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: child,
      bottomNavigationBar: _AuroraNavDock(tabs: tabs, currentIndex: idx),
    );
  }
}

class _AuroraNavDock extends StatelessWidget {
  final List<({String path, String label, IconData icon, IconData activeIcon})> tabs;
  final int currentIndex;
  const _AuroraNavDock({required this.tabs, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final palette = themeController.palette;
    final bottom = MediaQuery.of(context).padding.bottom;
    
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, (bottom > 0 ? bottom : 12)),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.gray900.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: List.generate(tabs.length, (i) {
            final tab    = tabs[i];
            final active = currentIndex == i;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.go(tab.path),
                child: Container(
                  color: Colors.transparent, // Ensure full hit area
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: AppMotion.duration,
                        switchInCurve: AppMotion.curve,
                        switchOutCurve: AppMotion.curve,
                        transitionBuilder:
                            (Widget child, Animation<double> animation) {
                          return FadeTransition(opacity: animation, child: child);
                        },
                        child: active
                            ? Icon(
                                tab.activeIcon,
                                key: const ValueKey('active'),
                                color: palette.primary,
                                size: 24,
                              )
                            : Icon(
                                tab.icon,
                                key: const ValueKey('inactive'),
                                color: AppColors.gray400,
                                size: 24,
                              ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedDefaultTextStyle(
                        duration: AppMotion.duration,
                        curve: AppMotion.curve,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          color: active ? palette.primary : AppColors.gray500,
                        ),
                        child: Text(tab.label),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
