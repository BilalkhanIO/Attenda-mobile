import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attenda/screens/home/widgets/shift_ring.dart';

import 'harness.dart';

void main() {
  group('ShiftRing', () {
    for (final pct in [0.0, 0.5, 1.0]) {
      testWidgets('builds and paints at pct $pct', (tester) async {
        await pumpHomeWidget(
          tester,
          ShiftRing(
            pct: pct,
            center: const Icon(Icons.check_circle_rounded),
          ),
        );

        expect(find.byType(ShiftRing), findsOneWidget);
        expect(find.byType(CustomPaint), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('renders the provided center widget', (tester) async {
      await pumpHomeWidget(
        tester,
        const ShiftRing(pct: 0.5, center: Text('05:12:33')),
      );

      expect(find.text('05:12:33'), findsOneWidget);
    });

    testWidgets('is sized to 100x100', (tester) async {
      await pumpHomeWidget(
        tester,
        const ShiftRing(pct: 0.25, center: SizedBox.shrink()),
      );

      expect(tester.getSize(find.byType(ShiftRing)), const Size(100, 100));
    });
  });
}
