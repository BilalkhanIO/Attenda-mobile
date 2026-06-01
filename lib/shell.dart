import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'utils/theme.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabs = [
    (path: '/home',       label: 'Home',       icon: Icons.home_outlined,            activeIcon: Icons.home_rounded),
    (path: '/attendance', label: 'Attendance',  icon: Icons.access_time_outlined,     activeIcon: Icons.access_time_filled_rounded),
    (path: '/leave',      label: 'Leave',       icon: Icons.beach_access_outlined,    activeIcon: Icons.beach_access),
    (path: '/schedule',   label: 'Schedule',    icon: Icons.calendar_today_outlined,  activeIcon: Icons.calendar_today_rounded),
    (path: '/profile',    label: 'Profile',     icon: Icons.person_outline_rounded,   activeIcon: Icons.person_rounded),
  ];

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    for (var i = 0; i < _tabs.length; i++) {
      if (loc.startsWith(_tabs[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);
    return Scaffold(
      backgroundColor: AppColors.meshBot,
      extendBody: true,
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.mesh),
        child: child,
      ),
      bottomNavigationBar: _GlassNavBar(tabs: _tabs, currentIndex: idx),
    );
  }
}

class _GlassNavBar extends StatelessWidget {
  final List<({String path, String label, IconData icon, IconData activeIcon})> tabs;
  final int currentIndex;
  const _GlassNavBar({required this.tabs, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.09),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.18), width: 0.5)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 62,
              child: Row(
                children: List.generate(tabs.length, (i) {
                  final tab    = tabs[i];
                  final active = currentIndex == i;
                  return Expanded(
                    child: InkWell(
                      onTap: () => context.go(tab.path),
                      splashColor: Colors.white.withOpacity(0.08),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: EdgeInsets.all(active ? 6 : 0),
                              decoration: active
                                  ? BoxDecoration(
                                      color: AppColors.primary600.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(10),
                                    )
                                  : null,
                              child: Icon(
                                active ? tab.activeIcon : tab.icon,
                                color: active ? AppColors.primary600 : Colors.white.withOpacity(0.45),
                                size: 22,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              tab.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                                color: active ? AppColors.primary600 : Colors.white.withOpacity(0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
