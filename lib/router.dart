import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/attendance/attendance_screen.dart';
import '../screens/attendance/qr_scanner_screen.dart';
import '../screens/leave/leave_screen.dart';
import '../screens/leave/request_leave_screen.dart';
import '../screens/schedule/schedule_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/home/remote_work_screen.dart';
import '../screens/home/remote_detail_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/settings/notification_settings_screen.dart';
import '../screens/settings/security_screen.dart';
import '../screens/settings/appearance_screen.dart';
import '../screens/settings/edit_profile_screen.dart';
import 'shell.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

GoRouter buildRouter(AuthProvider auth) => GoRouter(
  navigatorKey: _rootKey,
  refreshListenable: auth,
  initialLocation: '/home',
  redirect: (context, state) {
    final loggedIn = auth.isAuthenticated;
    final loggingIn = state.matchedLocation == '/login';
    if (!loggedIn && !loggingIn) return '/login';
    if (loggedIn && loggingIn) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),

    ShellRoute(
      navigatorKey: _shellKey,
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, __) => const HomeScreen(),
          routes: [
            GoRoute(path: 'remote', builder: (_, __) => const RemoteWorkScreen()),
            GoRoute(
              path: 'remote/detail',
              builder: (_, state) => RemoteDetailScreen(
                sessionId: state.uri.queryParameters['id'] ?? '',
              ),
            ),
            GoRoute(path: 'notifications', builder: (_, __) => const NotificationsScreen()),
          ],
        ),
        GoRoute(
          path: '/attendance',
          builder: (_, __) => const AttendanceScreen(),
          routes: [
            GoRoute(path: 'qr', parentNavigatorKey: _rootKey, builder: (_, __) => const QrScannerScreen()),
          ],
        ),
        GoRoute(
          path: '/leave',
          builder: (_, __) => const LeaveScreen(),
          routes: [
            GoRoute(path: 'request', parentNavigatorKey: _rootKey, builder: (_, __) => const RequestLeaveScreen()),
          ],
        ),
        GoRoute(path: '/schedule', builder: (_, __) => const ScheduleScreen()),
        GoRoute(
          path: '/profile',
          builder: (_, __) => const ProfileScreen(),
          routes: [
            GoRoute(path: 'edit', parentNavigatorKey: _rootKey, builder: (_, __) => const EditProfileScreen()),
            GoRoute(path: 'settings/notifications', parentNavigatorKey: _rootKey, builder: (_, __) => const NotificationSettingsScreen()),
            GoRoute(path: 'settings/security', parentNavigatorKey: _rootKey, builder: (_, __) => const SecurityScreen()),
            GoRoute(path: 'settings/appearance', parentNavigatorKey: _rootKey, builder: (_, __) => const AppearanceScreen()),
          ],
        ),
      ],
    ),
  ],
);
