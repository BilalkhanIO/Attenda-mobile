import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attenda/screens/home/widgets/quick_actions.dart';
import 'package:attenda/utils/theme.dart';

import 'harness.dart';

void main() {
  group('QuickActionsRow', () {
    testWidgets('renders a tile per action and fires only the tapped one',
        (tester) async {
      final tapped = <String>[];
      await pumpHomeWidget(
        tester,
        QuickActionsRow(actions: [
          QuickAction(
            icon: Icons.beach_access_outlined,
            label: 'Report /\nRequest',
            color: AppColors.primary,
            onTap: () => tapped.add('request'),
          ),
          QuickAction(
            icon: Icons.home_outlined,
            label: 'Work\nRemote',
            color: AppColors.purple500,
            onTap: () => tapped.add('remote'),
          ),
          QuickAction(
            icon: Icons.calendar_today_outlined,
            label: 'My\nSchedule',
            color: AppColors.teal100,
            onTap: () => tapped.add('schedule'),
          ),
        ]),
      );

      expect(find.text('Report /\nRequest'), findsOneWidget);
      expect(find.text('Work\nRemote'), findsOneWidget);
      expect(find.text('My\nSchedule'), findsOneWidget);
      expect(find.byIcon(Icons.beach_access_outlined), findsOneWidget);
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);

      await tester.tap(find.text('Work\nRemote'));
      expect(tapped, ['remote']);
    });

    testWidgets('renders a single action full-width without exceptions',
        (tester) async {
      var tapped = false;
      await pumpHomeWidget(
        tester,
        QuickActionsRow(actions: [
          QuickAction(
            icon: Icons.receipt_long_outlined,
            label: 'My\nPayslips',
            color: AppColors.warning500,
            onTap: () => tapped = true,
          ),
        ]),
      );

      await tester.tap(find.byIcon(Icons.receipt_long_outlined));
      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
