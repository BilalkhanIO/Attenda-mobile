import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'services/auth_provider.dart';
import 'services/wifi_service.dart';
import 'router.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init WiFi background service (must be before runApp)
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
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        home: const Scaffold(
          backgroundColor: AppColors.dark950,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.wifi_rounded, color: Colors.white, size: 32),
                  SizedBox(width: 12),
                  Text('Attenda', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
                ]),
                SizedBox(height: 32),
                CircularProgressIndicator(color: AppColors.primary600),
              ],
            ),
          ),
        ),
      );
    }

    _router ??= buildRouter(auth);

    return MaterialApp.router(
      title: 'Attenda',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      routerConfig: _router!,
    );
  }
}
