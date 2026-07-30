import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attenda/screens/home/widgets/shift_card.dart';

import 'harness.dart';

void main() {
  group('ShiftCard', () {
    testWidgets('renders shift name, time range and date', (tester) async {
      await pumpHomeWidget(
        tester,
        const ShiftCard(
          shiftName: 'Morning Shift',
          startTime: '09:00',
          endTime: '17:00',
          shiftColor: Color(0xFFF15153),
          dateStr: '2026-01-01', // a Thursday
        ),
      );

      expect(find.text('Morning Shift'), findsOneWidget);
      expect(find.text('09:00 – 17:00'), findsOneWidget);
      expect(find.text('Thu, 1 Jan'), findsOneWidget);
    });

    testWidgets('hides the date label when dateStr is null', (tester) async {
      await pumpHomeWidget(
        tester,
        const ShiftCard(
          shiftName: 'Night Shift',
          startTime: '22:00',
          endTime: '06:00',
          shiftColor: Color(0xFF00C896),
          dateStr: null,
        ),
      );

      expect(find.text('Night Shift'), findsOneWidget);
      expect(find.text('22:00 – 06:00'), findsOneWidget);
      // Only the name and the time range are rendered.
      expect(find.byType(Text), findsNWidgets(2));
    });
  });
}
