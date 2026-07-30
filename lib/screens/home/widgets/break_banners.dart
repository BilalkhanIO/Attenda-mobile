import 'package:flutter/material.dart';
import '../../../utils/theme.dart';
import '../../../widgets/common.dart';
import 'home_banners.dart';

// ─── Break alert banners from today-status ─────────────────

/// "12m" under an hour, "1h 5m" above (used by banners and the status card).
String formatMinutesHours(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

class ImminentBreakBanner extends StatelessWidget {
  final String name;
  final String countdown; // live mm:ss until the break starts
  const ImminentBreakBanner(
      {super.key, required this.name, required this.countdown});

  @override
  Widget build(BuildContext context) {
    return GlassBanner(
      icon: Icons.timer_outlined,
      text: '$name starts in $countdown — wrap up',
      tint: Theme.of(context).colorScheme.primary,
    );
  }
}

/// Window is open but the employee hasn't tapped Start Break yet.
/// They are still at their desk — do NOT say "return to office".
class WindowOpenBanner extends StatelessWidget {
  final String name;
  final String remaining; // live mm:ss left in the window
  const WindowOpenBanner(
      {super.key, required this.name, required this.remaining});

  @override
  Widget build(BuildContext context) {
    return GlassBanner(
      icon: Icons.free_breakfast_outlined,
      text: '$name is now — $remaining left in the window',
      tint: AppColors.warning500,
    );
  }
}

class ActiveBreakBanner extends StatelessWidget {
  final String name;
  final String remaining; // live mm:ss until the break ends
  const ActiveBreakBanner(
      {super.key, required this.name, required this.remaining});

  @override
  Widget build(BuildContext context) {
    return GlassBanner(
      icon: Icons.free_breakfast,
      text: '$name — $remaining remaining',
      tint: AppColors.teal100,
    );
  }
}

class OverdueOffWifiBanner extends StatelessWidget {
  final String name;
  final String overdueLabel; // live mm:ss since the break window closed
  const OverdueOffWifiBanner(
      {super.key, required this.name, required this.overdueLabel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        tint: AppColors.danger500,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          const Icon(Icons.running_with_errors, color: AppColors.danger500, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$name — return to office!',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.danger800, fontWeight: FontWeight.w700)),
              const Text('You are away from the office past your break time',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.danger800)),
            ]),
          ),
          Text('+$overdueLabel',
              style: AppTextStyles.timer
                  .copyWith(fontSize: 13, color: AppColors.danger800)),
        ]),
      ),
    );
  }
}

class OverdueOnWifiBanner extends StatelessWidget {
  final String name;
  const OverdueOnWifiBanner({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return GlassBanner(
      icon: Icons.alarm_on_rounded,
      text: '$name time is up — please tap End Break',
      tint: AppColors.warning500,
    );
  }
}

class AutoStartedBreakBanner extends StatelessWidget {
  final String name;
  final int reminderMins;
  final bool deductIfSkipped;
  final VoidCallback onAcknowledge;

  /// Pass null while an action is already in flight to disable the button.
  final VoidCallback? onTakeLater;

  const AutoStartedBreakBanner(
      {super.key,
      required this.name,
      required this.reminderMins,
      required this.deductIfSkipped,
      required this.onAcknowledge,
      required this.onTakeLater});

  @override
  Widget build(BuildContext context) {
    final subtext = deductIfSkipped
        ? 'Deferring will set a ${reminderMins}m reminder; skipping deducts this time'
        : 'Deferring sets a ${reminderMins}m reminder — no pay impact';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        tint: AppColors.teal100,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.free_breakfast, color: AppColors.teal100, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$name has started',
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.teal700,
                        fontWeight: FontWeight.w700)),
                Text(subtext,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.teal700)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: onAcknowledge,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.teal100.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: const Text("I'm on it",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.teal700)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: onTakeLater,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.warning500.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: const Text('Take it later',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.warning800)),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class DeferredReminderBanner extends StatelessWidget {
  final String name;
  final bool deduct;

  /// Pass null while an action is already in flight to disable the button.
  final VoidCallback? onTakeNow;
  final VoidCallback onDismiss;

  const DeferredReminderBanner(
      {super.key,
      required this.name,
      required this.deduct,
      required this.onTakeNow,
      required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        tint: AppColors.warning500,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.alarm, color: AppColors.warning500, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Time to take $name',
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.warning800,
                        fontWeight: FontWeight.w700)),
                if (deduct)
                  const Text('Skipping will deduct this time from your pay',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.warning800)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: onTakeNow,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.warning500.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: const Text('Take it now',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.warning800)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDismiss,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.gray100,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: const Text('Dismiss',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.gray500)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ─── Pre-check-in live late counter ────────────────────

class PreCheckinLateBanner extends StatelessWidget {
  final int lateMinutes;
  const PreCheckinLateBanner({super.key, required this.lateMinutes});

  @override
  Widget build(BuildContext context) {
    if (lateMinutes <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        tint: AppColors.warning500,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          const Icon(Icons.access_alarm, color: AppColors.warning500, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
            'You are currently ${formatMinutesHours(lateMinutes)} late',
            style: const TextStyle(
                fontSize: 13,
                color: AppColors.warning800,
                fontWeight: FontWeight.w500),
          )),
          Text('+${formatMinutesHours(lateMinutes)}',
              style: AppTextStyles.timer
                  .copyWith(fontSize: 13, color: AppColors.warning800)),
        ]),
      ),
    );
  }
}

class LateNoticeBanner extends StatelessWidget {
  final String expectedTime;
  final bool isAcknowledged;
  final VoidCallback onCancel;
  const LateNoticeBanner(
      {super.key,
      required this.expectedTime,
      required this.isAcknowledged,
      required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final isAcked = isAcknowledged;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        tint: isAcked ? AppColors.success500 : AppColors.warning500,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(isAcked ? Icons.check_circle_outline : Icons.schedule,
              color: isAcked ? AppColors.success500 : AppColors.warning500,
              size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
            isAcked
                ? 'Late notice acknowledged — expected by $expectedTime'
                : 'Late arrival notice submitted — expected by $expectedTime',
            style: TextStyle(
              fontSize: 13,
              color: isAcked ? AppColors.success700 : AppColors.warning800,
              fontWeight: FontWeight.w500,
            ),
          )),
          GestureDetector(
            onTap: onCancel,
            child: const Icon(Icons.close, size: 16, color: AppColors.gray400),
          ),
        ]),
      ),
    );
  }
}

class TimePickerTile extends StatelessWidget {
  final String label;
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onPicked;
  const TimePickerTile(
      {super.key,
      required this.label,
      required this.value,
      required this.onPicked});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: value,
          builder: (c, child) => Theme(data: AppTheme.light, child: child!),
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.gray500,
                  fontWeight: FontWeight.w500)),
          const Spacer(),
          Flexible(
            child: Text(value.format(context),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ),
        ]),
      ),
    );
  }
}
