import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attenda/screens/home/widgets/break_control.dart';
import 'package:attenda/widgets/common.dart';

import 'harness.dart';

void main() {
  group('BreakControl', () {
    testWidgets('on break: shows End Break and fires onEndBreak',
        (tester) async {
      var ended = false;
      await pumpHomeWidget(
        tester,
        BreakControl(
          isOnBreak: true,
          actionLoading: false,
          onEndBreak: () => ended = true,
          onTakeBreak: () {},
        ),
      );

      expect(find.widgetWithText(AppButton, 'End Break'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);

      await tester.tap(find.text('End Break'));
      expect(ended, isTrue);
    });

    testWidgets('on break + loading: shows spinner and blocks taps',
        (tester) async {
      var ended = false;
      await pumpHomeWidget(
        tester,
        BreakControl(
          isOnBreak: true,
          actionLoading: true,
          onEndBreak: () => ended = true,
          onTakeBreak: () {},
        ),
      );

      // AppButton replaces its label with a progress indicator while loading.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('End Break'), findsNothing);

      await tester.tap(find.byType(AppButton));
      expect(ended, isFalse);
    });

    testWidgets('not on break: shows Take a Break and fires onTakeBreak',
        (tester) async {
      var taken = false;
      await pumpHomeWidget(
        tester,
        BreakControl(
          isOnBreak: false,
          actionLoading: false,
          onEndBreak: () {},
          onTakeBreak: () => taken = true,
        ),
      );

      expect(find.widgetWithText(OutlinedButton, 'Take a Break'),
          findsOneWidget);
      expect(find.byIcon(Icons.free_breakfast_outlined), findsOneWidget);

      await tester.tap(find.text('Take a Break'));
      expect(taken, isTrue);
    });

    testWidgets('not on break + loading: button is disabled', (tester) async {
      var taken = false;
      await pumpHomeWidget(
        tester,
        BreakControl(
          isOnBreak: false,
          actionLoading: true,
          onEndBreak: () {},
          onTakeBreak: () => taken = true,
        ),
      );

      final button =
          tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNull);

      await tester.tap(find.text('Take a Break'));
      expect(taken, isFalse);
    });
  });
}
