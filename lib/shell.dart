import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'utils/theme.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabs = [
    (path: '/home',       label: 'Home',       icon: Icons.home_outlined,           activeIcon: Icons.home_rounded),
    (path: '/attendance', label: 'Attendance',  icon: Icons.access_time_outlined,    activeIcon: Icons.access_time_filled_rounded),
    (path: '/leave',      label: 'Leave',       icon: Icons.beach_access_outlined,   activeIcon: Icons.beach_access),
    (path: '/schedule',   label: 'Schedule',    icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today_rounded),
    (path: '/profile',    label: 'Profile',     icon: Icons.person_outline_rounded,  activeIcon: Icons.person_rounded),
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
      backgroundColor: AppColors.bgDark,
      extendBody: true,
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.mesh),
        child: child,
      ),
      bottomNavigationBar: _AuroraNavDock(tabs: _tabs, currentIndex: idx),
    );
  }
}

class _AuroraNavDock extends StatelessWidget {
  final List<({String path, String label, IconData icon, IconData activeIcon})> tabs;
  final int currentIndex;
  const _AuroraNavDock({required this.tabs, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      // Floating dock — 12px margin from screen edges
      padding: EdgeInsets.fromLTRB(16, 0, 16, (bottom > 0 ? bottom : 12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
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
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: active
                                ? BoxDecoration(
                                    gradient: AppGradients.aurora,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withOpacity(0.4),
                                        blurRadius: 12,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  )
                                : null,
                            child: Icon(
                              active ? tab.activeIcon : tab.icon,
                              color: active ? Colors.white : Colors.white.withOpacity(0.45),
                              size: 22,
                            ),
                          ),
                          const SizedBox(height: 3),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 250),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                              color: active ? AppColors.primary : Colors.white.withOpacity(0.4),
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
        ),
      ),
    );
  }
}
