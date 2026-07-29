import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../utils/theme.dart';
import '../../../widgets/common.dart';

// ─── Banner Widgets ────────────────────────────────────

/// Thin glass banner row: icon + text + optional trailing action.
class GlassBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color tint;
  final Widget? action;
  const GlassBanner(
      {super.key,
      required this.icon,
      required this.text,
      required this.tint,
      this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        tint: tint,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(icon, color: tint, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 13, color: tint, fontWeight: FontWeight.w500))),
          if (action != null) action!,
        ]),
      ),
    );
  }
}

/// Temporary flash banner shown for 5 s after a WiFi event, then fades out.
class FlashBanner extends StatelessWidget {
  final String text;
  final Color tint;
  final IconData icon;
  final VoidCallback onDismiss;
  const FlashBanner(
      {super.key,
      required this.text,
      required this.tint,
      required this.icon,
      required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        tint: tint,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(icon, color: tint, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13, color: tint, fontWeight: FontWeight.w600)),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close, size: 16, color: tint.withValues(alpha: 0.5)),
          ),
        ]),
      ),
    );
  }
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) => const GlassBanner(
        icon: Icons.cloud_off_rounded,
        text: "You're offline — showing the last synced data.",
        tint: AppColors.warning500,
      );
}

class VpnBanner extends StatelessWidget {
  const VpnBanner({super.key});

  @override
  Widget build(BuildContext context) => GlassBanner(
        icon: Icons.vpn_lock,
        text: 'VPN detected — auto check-in is disabled. Use QR scan instead.',
        tint: AppColors.warning500,
        action: TextButton(
          onPressed: () => context.push('/attendance/qr'),
          child: const Text('QR Scan',
              style: TextStyle(
                  color: AppColors.warning500, fontWeight: FontWeight.w700)),
        ),
      );
}

class NoNetworksBanner extends StatelessWidget {
  const NoNetworksBanner({super.key});

  @override
  Widget build(BuildContext context) => const GlassBanner(
        icon: Icons.wifi_off,
        text:
            "Auto check-in is off — your admin hasn't added any office networks yet.",
        tint: Colors.white,
      );
}

class LeaveTodayBanner extends StatelessWidget {
  /// Display-ready leave type (underscores already replaced with spaces).
  final String leaveType;
  const LeaveTodayBanner({super.key, required this.leaveType});

  @override
  Widget build(BuildContext context) {
    return GlassBanner(
      icon: Icons.beach_access,
      text: 'You have approved $leaveType today. No check-in required.',
      tint: Theme.of(context).colorScheme.primary,
    );
  }
}
