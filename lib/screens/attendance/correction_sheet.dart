import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

/// Signature for submitting a correction — injectable in widget tests.
typedef CorrectionSubmit = Future<void> Function(
  String date, // yyyy-MM-dd
  String? requestedCheckIn, // ISO 8601 with offset
  String? requestedCheckOut, // ISO 8601 with offset
  String reason,
);

/// Opens the correction request sheet for [date]. Resolves to `true` when a
/// request was submitted successfully.
Future<bool?> showCorrectionSheet(
  BuildContext context, {
  required DateTime date,
  DateTime? initialCheckIn,
  DateTime? initialCheckOut,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true, // Show above the Bottom Navigation Bar
    isScrollControlled: true, // Keyboard pushes the sheet up
    backgroundColor: Colors.transparent,
    builder: (_) => CorrectionSheet(
      date: date,
      initialCheckIn:
          initialCheckIn != null ? TimeOfDay.fromDateTime(initialCheckIn) : null,
      initialCheckOut: initialCheckOut != null
          ? TimeOfDay.fromDateTime(initialCheckOut)
          : null,
    ),
  );
}

/// Bottom sheet to request an attendance correction for a single day:
/// optional corrected check-in / check-out times plus a required reason.
class CorrectionSheet extends StatefulWidget {
  final DateTime date;
  final TimeOfDay? initialCheckIn;
  final TimeOfDay? initialCheckOut;

  /// Overrides the API call in tests; defaults to [ApiService.submitCorrection].
  final CorrectionSubmit? onSubmit;

  const CorrectionSheet({
    super.key,
    required this.date,
    this.initialCheckIn,
    this.initialCheckOut,
    this.onSubmit,
  });

  @override
  State<CorrectionSheet> createState() => _CorrectionSheetState();
}

class _CorrectionSheetState extends State<CorrectionSheet> {
  late TimeOfDay? _checkIn = widget.initialCheckIn;
  late TimeOfDay? _checkOut = widget.initialCheckOut;
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  String? _toIso(TimeOfDay? t) {
    if (t == null) return null;
    final d = widget.date;
    // Local wall-clock time converted to UTC — ISO 8601 with offset ("Z").
    return DateTime(d.year, d.month, d.day, t.hour, t.minute)
        .toUtc()
        .toIso8601String();
  }

  Future<void> _submit() async {
    final reason = _reasonCtrl.text.trim();
    if (_checkIn == null && _checkOut == null) {
      setState(() => _error = 'Add a corrected check-in or check-out time.');
      return;
    }
    if (reason.length < 5) {
      setState(() => _error = 'Please enter a reason (5+ chars)');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final submit = widget.onSubmit ??
          (String date, String? checkIn, String? checkOut, String r) =>
              api.submitCorrection(
                date: date,
                requestedCheckIn: checkIn,
                requestedCheckOut: checkOut,
                reason: r,
              );
      await submit(
        DateFormat('yyyy-MM-dd').format(widget.date),
        _toIso(_checkIn),
        _toIso(_checkOut),
        reason,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiFailure.fromError(e).userMessage;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          child: GlassCard(
            borderRadius: AppRadius.card,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: AppColors.gray300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text('Request Correction', style: AppTextStyles.title),
                const SizedBox(height: 6),
                const Text(
                  'Ask your manager to fix the recorded times for this day.',
                  style: AppTextStyles.body,
                ),
                const SizedBox(height: 20),

                // ── Date (prefilled from the record) ──────────
                const Text('Date', style: AppTextStyles.captionStrong),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.gray100,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_today,
                        size: 15, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('EEE, d MMM yyyy').format(widget.date),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Corrected times (both optional) ───────────
                const Text('Corrected Times', style: AppTextStyles.captionStrong),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: _OptionalTimeTile(
                      label: 'Check In',
                      value: _checkIn,
                      onPicked: (t) => setState(() => _checkIn = t),
                      onCleared: () => setState(() => _checkIn = null),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _OptionalTimeTile(
                      label: 'Check Out',
                      value: _checkOut,
                      onPicked: (t) => setState(() => _checkOut = t),
                      onCleared: () => setState(() => _checkOut = null),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                const Text('Set at least one — leave the other unchanged.',
                    style: AppTextStyles.caption),
                const SizedBox(height: 16),

                // ── Reason ────────────────────────────────────
                const Text('Reason', style: AppTextStyles.captionStrong),
                const SizedBox(height: 6),
                TextField(
                  controller: _reasonCtrl,
                  maxLines: 3,
                  maxLength: 200,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Briefly describe the reason…',
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.danger500)),
                ],
                const SizedBox(height: 16),
                AppButton(
                  label: 'Submit Request',
                  icon: Icons.edit_calendar_outlined,
                  loading: _submitting,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tappable time tile that starts empty ("Set time") and can be cleared.
class _OptionalTimeTile extends StatelessWidget {
  final String label;
  final TimeOfDay? value;
  final ValueChanged<TimeOfDay> onPicked;
  final VoidCallback onCleared;

  const _OptionalTimeTile({
    required this.label,
    required this.value,
    required this.onPicked,
    required this.onCleared,
  });

  @override
  Widget build(BuildContext context) {
    final v = value;
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: v ?? TimeOfDay.now(),
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
            child: Text(
              v != null ? v.format(context) : 'Set time',
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: v != null ? FontWeight.w700 : FontWeight.w500,
                color: v != null ? AppColors.textPrimary : AppColors.gray400,
              ),
            ),
          ),
          if (v != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onCleared,
              child:
                  const Icon(Icons.close, size: 14, color: AppColors.gray400),
            ),
          ],
        ]),
      ),
    );
  }
}
