import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attenda/screens/home/widgets/home_banners.dart';
import 'package:attenda/utils/theme.dart';

import 'harness.dart';

void main() {
  group('GlassBanner', () {
    testWidgets('renders icon, text and optional action', (tester) async {
      var actionTapped = false;
      await pumpHomeWidget(
        tester,
        GlassBanner(
          icon: Icons.info_outline,
          text: 'Something informative',
          tint: AppColors.warning500,
          action: TextButton(
            onPressed: () => actionTapped = true,
            child: const Text('Act'),
          ),
        ),
      );

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.text('Something informative'), findsOneWidget);

      await tester.tap(find.text('Act'));
      expect(actionTapped, isTrue);
    });

    testWidgets('renders without an action', (tester) async {
      await pumpHomeWidget(
        tester,
        const GlassBanner(
          icon: Icons.wifi,
          text: 'No action here',
          tint: Colors.white,
        ),
      );

      expect(find.text('No action here'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('FlashBanner', () {
    testWidgets('renders text and fires onDismiss on close tap',
        (tester) async {
      var dismissed = false;
      await pumpHomeWidget(
        tester,
        FlashBanner(
          text: 'Welcome back from your break!',
          tint: AppColors.warning500,
          icon: Icons.celebration_outlined,
          onDismiss: () => dismissed = true,
        ),
      );

      expect(find.text('Welcome back from your break!'), findsOneWidget);
      expect(find.byIcon(Icons.celebration_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      expect(dismissed, isTrue);
    });
  });

  group('OfflineBanner', () {
    testWidgets('renders the offline message', (tester) async {
      await pumpHomeWidget(tester, const OfflineBanner());

      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(
        find.text("You're offline — showing the last synced data."),
        findsOneWidget,
      );
    });
  });

  group('VpnBanner', () {
    testWidgets('renders the VPN warning with a QR Scan action',
        (tester) async {
      await pumpHomeWidget(tester, const VpnBanner());

      expect(find.byIcon(Icons.vpn_lock), findsOneWidget);
      expect(
        find.text(
            'VPN detected — auto check-in is disabled. Use QR scan instead.'),
        findsOneWidget,
      );
      // Navigates via GoRouter, so only assert it is present.
      expect(find.widgetWithText(TextButton, 'QR Scan'), findsOneWidget);
    });
  });

  group('NoNetworksBanner', () {
    testWidgets('renders the no-networks message', (tester) async {
      await pumpHomeWidget(tester, const NoNetworksBanner());

      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      expect(
        find.text(
            "Auto check-in is off — your admin hasn't added any office networks yet."),
        findsOneWidget,
      );
    });
  });

  group('LeaveTodayBanner', () {
    testWidgets('renders the display-ready leave type', (tester) async {
      await pumpHomeWidget(
        tester,
        const LeaveTodayBanner(leaveType: 'annual leave'),
      );

      expect(find.byIcon(Icons.beach_access), findsOneWidget);
      expect(
        find.text('You have approved annual leave today. No check-in required.'),
        findsOneWidget,
      );
    });
  });
}
