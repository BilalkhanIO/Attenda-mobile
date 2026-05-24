import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'utils/theme.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabs = [
    (path: '/home',       label: 'Home',       icon: Icons.home_rounded,          activeIcon: Icons.home),
    (path: '/attendance', label: 'Attendance',  icon: Icons.access_time_outlined,  activeIcon: Icons.access_time_filled),
    (path: '/leave',      label: 'Leave',       icon: Icons.beach_access_outlined, activeIcon: Icons.beach_access),
    (path: '/schedule',   label: 'Schedule',    icon: Icons.calendar_today_outlined,activeIcon: Icons.calendar_today),
    (path: '/profile',    label: 'Profile',     icon: Icons.person_outline,        activeIcon: Icons.person),
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
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          border: Border(top: BorderSide(color: AppColors.gray200)),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 60,
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final tab    = _tabs[i];
                final active = idx == i;
                return Expanded(
                  child: InkWell(
                    onTap: () => context.go(tab.path),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          active ? tab.activeIcon : tab.icon,
                          color: active ? AppColors.primary600 : AppColors.gray500,
                          size: 22,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          tab.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                            color: active ? AppColors.primary600 : AppColors.gray500,
                          ),
                        ),
                      ],
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
