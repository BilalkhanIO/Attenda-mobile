import 'package:flutter/material.dart';
import '../../../utils/theme.dart';
import '../../../widgets/common.dart';

// A standalone break control shown beneath the status card (never inside it).
class BreakControl extends StatelessWidget {
  final bool isOnBreak;
  final bool actionLoading;
  final VoidCallback onEndBreak;
  final VoidCallback onTakeBreak;

  const BreakControl(
      {super.key,
      required this.isOnBreak,
      required this.actionLoading,
      required this.onEndBreak,
      required this.onTakeBreak});

  @override
  Widget build(BuildContext context) {
    if (isOnBreak) {
      return AppButton(
        label: 'End Break',
        icon: Icons.play_arrow_rounded,
        color: AppColors.teal700,
        loading: actionLoading,
        onPressed: actionLoading ? null : onEndBreak,
      );
    }
    return OutlinedButton.icon(
      onPressed: actionLoading ? null : onTakeBreak,
      icon: const Icon(Icons.free_breakfast_outlined, size: 18),
      label: const Text('Take a Break'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.teal100,
        side: const BorderSide(color: AppColors.border),
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
    );
  }
}
