import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attenda/screens/home/widgets/disconnect_card.dart';
import 'package:attenda/widgets/common.dart';

import 'harness.dart';

void main() {
  group('DisconnectCard', () {
    testWidgets('renders the grace countdown with the lost SSID',
        (tester) async {
      await pumpHomeWidget(
        tester,
        const DisconnectCard(
          ssid: 'Office-WiFi',
          countdown: '09:45',
          expired: false,
        ),
      );

      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.text('Left Office WiFi'), findsOneWidget);
      expect(find.text('No longer on "Office-WiFi"'), findsOneWidget);
      expect(find.text('09:45'), findsOneWidget);
      expect(find.text('until auto check-out'), findsOneWidget);
      // Navigates via GoRouter, so only assert it is present.
      expect(find.widgetWithText(AppButton, 'Scan QR Code'), findsOneWidget);
    });

    testWidgets('falls back when the SSID is unknown and no deadline is set',
        (tester) async {
      await pumpHomeWidget(
        tester,
        const DisconnectCard(ssid: null, countdown: '', expired: false),
      );

      expect(find.text('WiFi connection lost'), findsOneWidget);
      expect(find.text('--:--'), findsOneWidget);
    });

    testWidgets('renders the expired state', (tester) async {
      await pumpHomeWidget(
        tester,
        const DisconnectCard(
          ssid: 'Office-WiFi',
          countdown: '',
          expired: true,
        ),
      );

      expect(find.text('Grace Period Ended'), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('checking you out…'), findsOneWidget);
    });
  });
}
