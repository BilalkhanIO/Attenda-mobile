import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attenda/screens/home/widgets/shift_ring.dart';
import 'package:attenda/screens/home/widgets/status_card.dart';
import 'package:attenda/utils/theme.dart';
import 'package:attenda/widgets/common.dart';

import 'harness.dart';

void main() {
  group('InfoChip', () {
    testWidgets('renders icon, label and value', (tester) async {
      await pumpHomeWidget(
        tester,
        const InfoChip(icon: Icons.login, label: 'In', value: '09:02 AM'),
      );

      expect(find.byIcon(Icons.login), findsOneWidget);
      expect(find.text('In'), findsOneWidget);
      expect(find.text('09:02 AM'), findsOneWidget);
    });
  });

  group('CheckedOutCard', () {
    testWidgets('renders the full day summary and fires onRequestOvertime',
        (tester) async {
      var requested = false;
      await pumpHomeWidget(
        tester,
        CheckedOutCard(
          checkInFmt: '09:02 AM',
          checkOutFmt: '05:30 PM',
          hoursLabel: '8h 28m',
          breakMins: 30,
          overtimeHours: 1.5,
          extraOfficeMins: 20,
          wasAutoOut: true,
          canRequestOvertime: true,
          actionLoading: false,
          onRequestOvertime: () => requested = true,
        ),
      );

      expect(find.text('Work Day Complete'), findsOneWidget);
      expect(find.text('Auto checked-out by system'), findsOneWidget);
      expect(find.text('8h 28m'), findsOneWidget);
      expect(find.text('09:02 AM'), findsOneWidget);
      expect(find.text('05:30 PM'), findsOneWidget);
      expect(find.text('30m'), findsOneWidget);
      expect(find.text('1.5h'), findsOneWidget);
      expect(find.text('20m'), findsOneWidget);

      await tester.tap(find.text('Request Overtime'));
      expect(requested, isTrue);
    });

    testWidgets('hides optional chips, badge and overtime button',
        (tester) async {
      await pumpHomeWidget(
        tester,
        CheckedOutCard(
          checkInFmt: '09:02 AM',
          checkOutFmt: '05:30 PM',
          hoursLabel: '',
          breakMins: 0,
          overtimeHours: 0,
          extraOfficeMins: 0,
          wasAutoOut: false,
          canRequestOvertime: false,
          actionLoading: false,
          onRequestOvertime: () {},
        ),
      );

      expect(find.text('Work Day Complete'), findsOneWidget);
      expect(find.text('Auto checked-out by system'), findsNothing);
      expect(find.text('Break'), findsNothing);
      expect(find.text('Overtime'), findsNothing);
      expect(find.text('Extra'), findsNothing);
      expect(find.text('Request Overtime'), findsNothing);
    });
  });

  group('CheckedInCard', () {
    testWidgets('renders the on-time hero and fires onCheckOut',
        (tester) async {
      var checkedOut = false;
      await pumpHomeWidget(
        tester,
        CheckedInCard(
          ringTint: const Color(0xFF34E0A1),
          isLate: false,
          shiftPct: 0.5,
          elapsedDisplay: '04:32:10',
          checkInTime: '09:02 AM',
          hasCheckIn: true,
          checkInTypeLabel: 'Auto (WiFi)',
          breakInfo: const {
            'icon': Icons.free_breakfast,
            'color': AppColors.teal100,
            'text': 'Lunch Break — 12m elapsed',
          },
          lateMins: 0,
          hasNotice: false,
          actionLoading: false,
          onCheckOut: () => checkedOut = true,
        ),
      );

      expect(find.byType(ShiftRing), findsOneWidget);
      expect(find.text('Checked In'), findsOneWidget);
      expect(find.text('04:32:10'), findsOneWidget);
      expect(find.text('Working since 09:02 AM'), findsOneWidget);
      expect(find.text('Auto (WiFi)'), findsOneWidget);
      expect(find.text('Lunch Break — 12m elapsed'), findsOneWidget);
      expect(find.textContaining('late'), findsNothing);
      // The QR button navigates via GoRouter, so only assert it is present.
      expect(find.text('Scan QR'), findsOneWidget);

      await tester.tap(find.text('Check Out'));
      expect(checkedOut, isTrue);
    });

    testWidgets('renders the late variant with a pre-announced notice',
        (tester) async {
      await pumpHomeWidget(
        tester,
        CheckedInCard(
          ringTint: AppColors.warning500,
          isLate: true,
          shiftPct: 0.25,
          elapsedDisplay: '01:05:00',
          checkInTime: '10:15 AM',
          hasCheckIn: true,
          checkInTypeLabel: 'QR Code',
          breakInfo: null,
          lateMins: 15,
          hasNotice: true,
          actionLoading: false,
          onCheckOut: () {},
        ),
      );

      expect(find.text('Checked In · Late'), findsOneWidget);
      expect(find.byIcon(Icons.running_with_errors), findsOneWidget);
      expect(find.text('15m late · pre-announced'), findsOneWidget);
    });

    testWidgets('hides chips and subtitle details without a check-in time',
        (tester) async {
      await pumpHomeWidget(
        tester,
        CheckedInCard(
          ringTint: const Color(0xFF34E0A1),
          isLate: false,
          shiftPct: 0.0,
          elapsedDisplay: '--:--',
          checkInTime: '--:--',
          hasCheckIn: false,
          checkInTypeLabel: null,
          breakInfo: null,
          lateMins: 0,
          hasNotice: false,
          actionLoading: false,
          onCheckOut: () {},
        ),
      );

      expect(find.text('Working since --:--'), findsOneWidget);
      expect(find.text('Checked in'), findsNothing);
      expect(find.text('Method'), findsNothing);
    });
  });

  group('StatusInfoCard', () {
    testWidgets('renders check-in actions and fires onReportLate',
        (tester) async {
      var reported = false;
      await pumpHomeWidget(
        tester,
        StatusInfoCard(
          tint: Colors.white,
          icon: Icons.radio_button_unchecked,
          iconColor: Colors.white,
          title: 'Not Checked In',
          subtitle: 'Connect to office WiFi for auto check-in, or scan QR code',
          showCheckInActions: true,
          showReportLate: true,
          onReportLate: () => reported = true,
          remoteDetailId: null,
        ),
      );

      expect(find.text('Not Checked In'), findsOneWidget);
      expect(
        find.text('Connect to office WiFi for auto check-in, or scan QR code'),
        findsOneWidget,
      );
      expect(find.widgetWithText(AppButton, 'Scan QR Code'), findsOneWidget);

      await tester.tap(find.text('Report Late Arrival'));
      expect(reported, isTrue);
    });

    testWidgets('shows the remote activity button without check-in actions',
        (tester) async {
      await pumpHomeWidget(
        tester,
        StatusInfoCard(
          tint: AppColors.primary,
          icon: Icons.home_rounded,
          iconColor: AppColors.primary,
          title: 'Working Remotely',
          subtitle: 'Approved remote session',
          showCheckInActions: false,
          showReportLate: false,
          onReportLate: () {},
          remoteDetailId: 'rs-123',
        ),
      );

      expect(find.text('Working Remotely'), findsOneWidget);
      expect(find.text('Scan QR Code'), findsNothing);
      expect(find.text('Report Late Arrival'), findsNothing);
      // Navigates via GoRouter, so only assert it is present.
      expect(
          find.widgetWithText(AppButton, 'View My Activity'), findsOneWidget);
    });
  });
}
