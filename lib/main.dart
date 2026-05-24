import 'package:flutter/material.dart';
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

class AttendaApp extends StatelessWidget {
  const AttendaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth   = context.watch<AuthProvider>();
    final router = buildRouter(auth);

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

    return MaterialApp.router(
      title: 'Attenda',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}
