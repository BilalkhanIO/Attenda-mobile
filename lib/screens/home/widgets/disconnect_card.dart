import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../utils/theme.dart';
import '../../../widgets/common.dart';

// ─── Disconnect (left office WiFi) Card ────────────────

class DisconnectCard extends StatelessWidget {
  /// SSID of the office network that was lost (may be null/empty).
  final String? ssid;

  /// Live mm:ss grace countdown ('' when no deadline is known).
  final String countdown;

  /// True once the grace window has elapsed — the server is closing us out.
  final bool expired;

  const DisconnectCard(
      {super.key,
      required this.ssid,
      required this.countdown,
      required this.expired});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      tint: AppColors.warning500,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.wifi_off_rounded,
              size: 28, color: AppColors.warning500),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(expired ? 'Grace Period Ended' : 'Left Office WiFi',
                    style: AppTextStyles.title),
                Text(
                  ssid != null && ssid!.isNotEmpty
                      ? 'No longer on "$ssid"'
                      : 'WiFi connection lost',
                  style: AppTextStyles.body,
                ),
              ])),
        ]),
        const SizedBox(height: 16),
        // Prominent grace countdown
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.warning500.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Column(children: [
            Text(
              expired ? '00:00' : (countdown.isNotEmpty ? countdown : '--:--'),
              style: AppTextStyles.timer,
            ),
            const SizedBox(height: 2),
            Text(
              expired ? 'checking you out…' : 'until auto check-out',
              style: AppTextStyles.caption,
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Text(
          expired
              ? 'You\'ve been checked out. Reconnect to office WiFi and you\'ll be checked back in automatically.'
              : 'Reconnect to office WiFi to stay checked in. If you can\'t, scan the office QR code.',
          style: AppTextStyles.body,
        ),
        const SizedBox(height: 12),
        AppButton(
          label: 'Scan QR Code',
          icon: Icons.qr_code_scanner,
          onPressed: () => context.push('/attendance/qr'),
        ),
      ]),
    );
  }
}
