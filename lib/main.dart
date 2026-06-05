import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'services/auth_provider.dart';
import 'services/wifi_service.dart';
import 'router.dart';
import 'screens/splash_screen.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Must be called before startService() so the main isolate has a port open
  // to receive events from the background task.
  FlutterForegroundTask.initCommunicationPort();

  // Init WiFi / foreground-service (starts the persistent Android service)
  await WifiAttendanceService().init();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: const AttendaApp(),
    ),
  );
}

class AttendaApp extends StatefulWidget {
  const AttendaApp({super.key});
  @override
  State<AttendaApp> createState() => _AttendaAppState();
}

class _AttendaAppState extends State<AttendaApp> {
  GoRouter? _router;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isLoading) {
      return MaterialApp(
        theme: AppTheme.glass,
        debugShowCheckedModeBanner: false,
        home: const SplashScreen(),
      );
    }

    _router ??= buildRouter(auth);

    return MaterialApp.router(
      title: 'Attenda',
      theme: AppTheme.glass,
      debugShowCheckedModeBanner: false,
      routerConfig: _router!,
    );
  }
}
