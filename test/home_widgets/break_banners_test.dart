import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attenda/screens/home/widgets/break_banners.dart';
import 'package:attenda/widgets/common.dart';

import 'harness.dart';

void main() {
  group('formatMinutesHours', () {
    test('formats minutes under an hour', () {
      expect(formatMinutesHours(0), '0m');
      expect(formatMinutesHours(12), '12m');
      expect(formatMinutesHours(59), '59m');
    });

    test('formats whole and mixed hours', () {
      expect(formatMinutesHours(60), '1h');
      expect(formatMinutesHours(65), '1h 5m');
      expect(formatMinutesHours(120), '2h');
    });
  });

  group('ImminentBreakBanner', () {
    testWidgets('renders name and countdown', (tester) async {
      await pumpHomeWidget(
        tester,
        const ImminentBreakBanner(name: 'Lunch Break', countdown: '04:59'),
      );

      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      expect(
          find.text('Lunch Break starts in 04:59 — wrap up'), findsOneWidget);
    });
  });

  group('WindowOpenBanner', () {
    testWidgets('renders name and remaining window time', (tester) async {
      await pumpHomeWidget(
        tester,
        const WindowOpenBanner(name: 'Lunch Break', remaining: '10:00'),
      );

      expect(find.text('Lunch Break is now — 10:00 left in the window'),
          findsOneWidget);
    });
  });

  group('ActiveBreakBanner', () {
    testWidgets('renders name and remaining time', (tester) async {
      await pumpHomeWidget(
        tester,
        const ActiveBreakBanner(name: 'Lunch Break', remaining: '25:00'),
      );

      expect(find.text('Lunch Break — 25:00 remaining'), findsOneWidget);
    });
  });

  group('OverdueOffWifiBanner', () {
    testWidgets('renders warning text and overdue badge', (tester) async {
      await pumpHomeWidget(
        tester,
        const OverdueOffWifiBanner(name: 'Lunch Break', overdueLabel: '02:15'),
      );

      expect(find.text('Lunch Break — return to office!'), findsOneWidget);
      expect(find.text('You are away from the office past your break time'),
          findsOneWidget);
      expect(find.text('+02:15'), findsOneWidget);
    });
  });

  group('OverdueOnWifiBanner', () {
    testWidgets('renders the end-break reminder', (tester) async {
      await pumpHomeWidget(
        tester,
        const OverdueOnWifiBanner(name: 'Lunch Break'),
      );

      expect(find.text('Lunch Break time is up — please tap End Break'),
          findsOneWidget);
    });
  });

  group('AutoStartedBreakBanner', () {
    testWidgets('shows deduct subtext and fires both actions', (tester) async {
      var acknowledged = false;
      var takeLater = false;
      await pumpHomeWidget(
        tester,
        AutoStartedBreakBanner(
          name: 'Lunch Break',
          reminderMins: 30,
          deductIfSkipped: true,
          onAcknowledge: () => acknowledged = true,
          onTakeLater: () => takeLater = true,
        ),
      );

      expect(find.text('Lunch Break has started'), findsOneWidget);
      expect(
        find.text(
            'Deferring will set a 30m reminder; skipping deducts this time'),
        findsOneWidget,
      );

      await tester.tap(find.text("I'm on it"));
      expect(acknowledged, isTrue);

      await tester.tap(find.text('Take it later'));
      expect(takeLater, isTrue);
    });

    testWidgets('shows no-pay-impact subtext and builds with null onTakeLater',
        (tester) async {
      await pumpHomeWidget(
        tester,
        AutoStartedBreakBanner(
          name: 'Tea Break',
          reminderMins: 15,
          deductIfSkipped: false,
          onAcknowledge: () {},
          onTakeLater: null,
        ),
      );

      expect(find.text('Tea Break has started'), findsOneWidget);
      expect(find.text('Deferring sets a 15m reminder — no pay impact'),
          findsOneWidget);
    });
  });

  group('DeferredReminderBanner', () {
    testWidgets('renders deduct warning and fires actions', (tester) async {
      var takeNow = false;
      var dismissed = false;
      await pumpHomeWidget(
        tester,
        DeferredReminderBanner(
          name: 'Lunch Break',
          deduct: true,
          onTakeNow: () => takeNow = true,
          onDismiss: () => dismissed = true,
        ),
      );

      expect(find.text('Time to take Lunch Break'), findsOneWidget);
      expect(find.text('Skipping will deduct this time from your pay'),
          findsOneWidget);

      await tester.tap(find.text('Take it now'));
      expect(takeNow, isTrue);

      await tester.tap(find.text('Dismiss'));
      expect(dismissed, isTrue);
    });

    testWidgets('hides the deduct warning when deduct is false',
        (tester) async {
      await pumpHomeWidget(
        tester,
        DeferredReminderBanner(
          name: 'Tea Break',
          deduct: false,
          onTakeNow: null,
          onDismiss: () {},
        ),
      );

      expect(find.text('Time to take Tea Break'), findsOneWidget);
      expect(find.text('Skipping will deduct this time from your pay'),
          findsNothing);
    });
  });

  group('PreCheckinLateBanner', () {
    testWidgets('renders nothing when not late', (tester) async {
      await pumpHomeWidget(
        tester,
        const PreCheckinLateBanner(lateMinutes: 0),
      );

      expect(find.byType(GlassCard), findsNothing);
      expect(find.textContaining('late'), findsNothing);
    });

    testWidgets('renders the live late counter', (tester) async {
      await pumpHomeWidget(
        tester,
        const PreCheckinLateBanner(lateMinutes: 75),
      );

      expect(find.text('You are currently 1h 15m late'), findsOneWidget);
      expect(find.text('+1h 15m'), findsOneWidget);
    });
  });

  group('LateNoticeBanner', () {
    testWidgets('renders submitted state and fires onCancel', (tester) async {
      var cancelled = false;
      await pumpHomeWidget(
        tester,
        LateNoticeBanner(
          expectedTime: '10:30',
          isAcknowledged: false,
          onCancel: () => cancelled = true,
        ),
      );

      expect(find.text('Late arrival notice submitted — expected by 10:30'),
          findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      expect(cancelled, isTrue);
    });

    testWidgets('renders acknowledged state', (tester) async {
      await pumpHomeWidget(
        tester,
        LateNoticeBanner(
          expectedTime: '10:30',
          isAcknowledged: true,
          onCancel: () {},
        ),
      );

      expect(find.text('Late notice acknowledged — expected by 10:30'),
          findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });
  });

  group('TimePickerTile', () {
    testWidgets('renders the label and formatted time', (tester) async {
      await pumpHomeWidget(
        tester,
        TimePickerTile(
          label: 'Start',
          value: const TimeOfDay(hour: 9, minute: 30),
          onPicked: (_) {},
        ),
      );

      expect(find.text('Start'), findsOneWidget);
      expect(find.text('9:30 AM'), findsOneWidget);
    });
  });
}
