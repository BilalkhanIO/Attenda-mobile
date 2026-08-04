import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../utils/theme.dart';
import '../../../widgets/common.dart';
import 'break_banners.dart' show formatMinutesHours;
import 'shift_ring.dart';

// ─── Status Card variants ──────────────────────────────
//
// The status dispatch (which variant to show, and every value derived from
// today's attendance record) lives in _HomeScreenState._buildStatusCard.
// These widgets only render the data they are given.

/// Small icon + label + value column used inside the status cards.
class InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const InfoChip(
      {super.key,
      required this.icon,
      required this.label,
      required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: AppColors.gray400),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.gray500)),
      ]),
      const SizedBox(height: 2),
      Text(value,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary)),
    ]);
  }
}

/// "Work Day Complete" summary shown after check-out.
class CheckedOutCard extends StatelessWidget {
  final String checkInFmt;
  final String checkOutFmt;
  final String hoursLabel; // '' hides the badge
  final int breakMins;
  final double overtimeHours;
  final int extraOfficeMins;
  final bool wasAutoOut;
  final bool canRequestOvertime;
  final bool actionLoading;
  final VoidCallback onRequestOvertime;

  const CheckedOutCard(
      {super.key,
      required this.checkInFmt,
      required this.checkOutFmt,
      required this.hoursLabel,
      required this.breakMins,
      required this.overtimeHours,
      required this.extraOfficeMins,
      required this.wasAutoOut,
      required this.canRequestOvertime,
      required this.actionLoading,
      required this.onRequestOvertime});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.check_circle_outline,
              size: 28, color: AppColors.success500),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Work Day Complete', style: AppTextStyles.title),
                if (wasAutoOut)
                  const Text('Auto checked-out by system',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.warning800)),
              ])),
          if (hoursLabel.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.gray100,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Text(hoursLabel,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ),
        ]),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 12),
        Row(children: [
          InfoChip(icon: Icons.login, label: 'In', value: checkInFmt),
          const SizedBox(width: 16),
          InfoChip(icon: Icons.logout, label: 'Out', value: checkOutFmt),
          if (breakMins > 0) ...[
            const SizedBox(width: 16),
            InfoChip(
                icon: Icons.free_breakfast,
                label: 'Break',
                value: '${breakMins}m'),
          ],
          if (overtimeHours > 0) ...[
            const SizedBox(width: 16),
            InfoChip(
                icon: Icons.more_time,
                label: 'Overtime',
                value: '${overtimeHours.toStringAsFixed(1)}h'),
          ],
          if (extraOfficeMins > 0) ...[
            const SizedBox(width: 16),
            InfoChip(
                icon: Icons.schedule,
                label: 'Extra',
                value: '${extraOfficeMins}m'),
          ],
        ]),
        if (canRequestOvertime) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: actionLoading ? null : onRequestOvertime,
            icon: const Icon(Icons.more_time, size: 18),
            label: const Text('Request Overtime'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.teal100,
              side: const BorderSide(color: AppColors.border),
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control)),
            ),
          ),
        ],
      ]),
    );
  }
}

/// "Checked In" hero card with the shift progress ring and elapsed timer.
class CheckedInCard extends StatelessWidget {
  final Color ringTint;
  final bool isLate;
  final double shiftPct;
  final String elapsedDisplay;
  final String checkInTime; // formatted, '--:--' when unknown
  final bool hasCheckIn; // whether check_in_at is present
  final String? checkInTypeLabel; // display label, null hides the chip
  final Map<String, dynamic>? breakInfo; // {icon, color, text} or null
  final int lateMins;
  final bool hasNotice;
  final bool actionLoading;
  final VoidCallback onCheckOut;

  const CheckedInCard(
      {super.key,
      required this.ringTint,
      required this.isLate,
      required this.shiftPct,
      required this.elapsedDisplay,
      required this.checkInTime,
      required this.hasCheckIn,
      required this.checkInTypeLabel,
      required this.breakInfo,
      required this.lateMins,
      required this.hasNotice,
      required this.actionLoading,
      required this.onCheckOut});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      tint: ringTint,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Top row: ring on left, info on right ──────────
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          ShiftRing(
            pct: shiftPct,
            center: Icon(
              isLate ? Icons.running_with_errors : Icons.check_circle_rounded,
              color: ringTint,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // Status badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ringTint.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(
                    isLate ? 'Checked In · Late' : 'Checked In',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: ringTint),
                  ),
                ),
                const SizedBox(height: 6),
                // Big elapsed timer
                Text(elapsedDisplay, style: AppTextStyles.timer),
                const SizedBox(height: 2),
                // "Working since HH:MM" subtitle
                Text(
                  'Working since $checkInTime',
                  style: AppTextStyles.body,
                ),
              ])),
        ]),

        // ── Divider + info chips ───────────────────────────
        if (hasCheckIn) ...[
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            InfoChip(icon: Icons.login, label: 'Checked in', value: checkInTime),
            if (checkInTypeLabel != null)
              InfoChip(
                  icon: Icons.wifi, label: 'Method', value: checkInTypeLabel!),
          ]),
        ],

        // ── Break status row ───────────────────────────────
        if (breakInfo != null)
          Column(children: [
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(children: [
              Icon(breakInfo!['icon'] as IconData,
                  size: 14, color: breakInfo!['color'] as Color),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(
                breakInfo!['text'] as String,
                style: TextStyle(
                    fontSize: 13,
                    color: breakInfo!['color'] as Color,
                    fontWeight: FontWeight.w500),
              )),
            ]),
          ]),

        // ── Late info ──────────────────────────────────────
        if (lateMins > 0) ...[
          const SizedBox(height: 8),
          Text(
            '${formatMinutesHours(lateMins)} late${hasNotice ? ' · pre-announced' : ''}',
            style: const TextStyle(
                fontSize: 13,
                color: AppColors.warning800,
                fontWeight: FontWeight.w500),
          ),
        ],

        // ── QR + Check Out buttons ────────────────────────
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: actionLoading
                  ? null
                  : () => context.push('/attendance/qr'),
              icon: const Icon(Icons.qr_code_scanner, size: 16),
              label: const Text('Scan QR'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AppButton(
              label: 'Check Out',
              icon: Icons.logout,
              color: AppColors.danger500,
              loading: actionLoading,
              onPressed: actionLoading ? null : onCheckOut,
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Generic status card for the VPN / remote / leave / not-checked-in states.
class StatusInfoCard extends StatelessWidget {
  final Color tint;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  /// Shows the "Scan QR Code" check-in button block.
  final bool showCheckInActions;

  /// Shows the "Report Late Arrival" button (within the check-in block).
  final bool showReportLate;
  final VoidCallback onReportLate;

  /// Non-null shows the "View My Activity" button for an approved remote
  /// session with this id.
  final String? remoteDetailId;

  const StatusInfoCard(
      {super.key,
      required this.tint,
      required this.icon,
      required this.iconColor,
      required this.title,
      required this.subtitle,
      required this.showCheckInActions,
      required this.showReportLate,
      required this.onReportLate,
      required this.remoteDetailId});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      tint: tint,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 28, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title, style: AppTextStyles.title),
                Text(subtitle, style: AppTextStyles.body),
              ])),
        ]),

        // Check-in actions
        if (showCheckInActions) ...[
          const SizedBox(height: 16),
          AppButton(
            label: 'Scan QR Code',
            icon: Icons.qr_code_scanner,
            onPressed: () => context.push('/attendance/qr'),
          ),
          const SizedBox(height: 8),
          if (showReportLate)
            OutlinedButton.icon(
              onPressed: onReportLate,
              icon: const Icon(Icons.schedule, size: 16),
              label: const Text('Report Late Arrival'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.warning800,
                side: const BorderSide(color: AppColors.border),
                minimumSize: const Size(double.infinity, 42),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control)),
              ),
            ),
        ],

        // Remote activity button
        if (remoteDetailId != null) ...[
          const SizedBox(height: 12),
          AppButton(
            label: 'View My Activity',
            icon: Icons.chat_bubble_outline,
            outline: true,
            onPressed: () =>
                context.push('/home/remote/detail?id=$remoteDetailId'),
          ),
        ],
      ]),
    );
  }
}
