import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:attenda/screens/attendance/correction_sheet.dart';
import 'package:attenda/services/theme_controller.dart';
import 'package:attenda/utils/theme.dart';

/// Presents [sheet] through a real modal bottom-sheet route (like the app
/// does), so `Navigator.pop` after a successful submit has a route to pop.
Future<void> pumpCorrectionSheet(WidgetTester tester, Widget sheet) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => ThemeController(),
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => sheet,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  final date = DateTime(2026, 7, 1);

  group('CorrectionSheet', () {
    testWidgets('renders date, time tiles, reason field and submit button',
        (tester) async {
      await pumpCorrectionSheet(
        tester,
        CorrectionSheet(
          date: date,
          initialCheckIn: const TimeOfDay(hour: 9, minute: 0),
        ),
      );

      expect(find.text('Request Correction'), findsOneWidget);
      expect(find.text('Wed, 1 Jul 2026'), findsOneWidget);
      expect(find.text('Check In'), findsOneWidget);
      expect(find.text('Check Out'), findsOneWidget);
      // Check-out starts empty; check-in is prefilled from the record.
      expect(find.text('Set time'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Submit Request'), findsOneWidget);
    });

    testWidgets('blocks submission when the reason is empty', (tester) async {
      var submitted = false;
      await pumpCorrectionSheet(
        tester,
        CorrectionSheet(
          date: date,
          initialCheckIn: const TimeOfDay(hour: 9, minute: 0),
          onSubmit: (d, ci, co, r) async => submitted = true,
        ),
      );

      await tester.ensureVisible(find.text('Submit Request'));
      await tester.tap(find.text('Submit Request'));
      await tester.pump();

      expect(find.text('Please enter a reason (5+ chars)'), findsOneWidget);
      expect(submitted, isFalse);
    });

    testWidgets('blocks submission when no corrected time is set',
        (tester) async {
      var submitted = false;
      await pumpCorrectionSheet(
        tester,
        CorrectionSheet(
          date: date,
          onSubmit: (d, ci, co, r) async => submitted = true,
        ),
      );

      await tester.enterText(
          find.byType(TextField), 'Forgot to check out at the end of the day');
      await tester.ensureVisible(find.text('Submit Request'));
      await tester.tap(find.text('Submit Request'));
      await tester.pump();

      expect(find.text('Add a corrected check-in or check-out time.'),
          findsOneWidget);
      expect(submitted, isFalse);
    });

    testWidgets('submits the date, times and reason, then closes',
        (tester) async {
      String? gotDate;
      String? gotCheckIn;
      String? gotCheckOut;
      String? gotReason;
      await pumpCorrectionSheet(
        tester,
        CorrectionSheet(
          date: date,
          initialCheckIn: const TimeOfDay(hour: 9, minute: 0),
          onSubmit: (d, ci, co, r) async {
            gotDate = d;
            gotCheckIn = ci;
            gotCheckOut = co;
            gotReason = r;
          },
        ),
      );

      await tester.enterText(
          find.byType(TextField), 'Forgot to check out at the end of the day');
      await tester.ensureVisible(find.text('Submit Request'));
      await tester.tap(find.text('Submit Request'));
      await tester.pumpAndSettle();

      expect(gotDate, '2026-07-01');
      // ISO 8601 with offset — UTC form ends in Z.
      expect(gotCheckIn, endsWith('Z'));
      expect(gotCheckOut, isNull);
      expect(gotReason, 'Forgot to check out at the end of the day');
      // The sheet popped after a successful submit.
      expect(find.text('Request Correction'), findsNothing);
    });
  });
}
