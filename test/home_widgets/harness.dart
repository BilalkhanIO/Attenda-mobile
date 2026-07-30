import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:attenda/services/theme_controller.dart';
import 'package:attenda/utils/theme.dart';

/// Pumps [child] inside the minimal shell shared by all home-widget tests:
/// a [MaterialApp] using the real app theme, with a [ThemeController]
/// provided because shared widgets (e.g. `AppButton`) watch it.
///
/// `SharedPreferences` is mocked so `ThemeController` never touches a
/// platform channel.
Future<void> pumpHomeWidget(WidgetTester tester, Widget child) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => ThemeController(),
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: child),
      ),
    ),
  );
  // Let ThemeController finish loading its (mocked) settings and notify.
  await tester.pump();
}
