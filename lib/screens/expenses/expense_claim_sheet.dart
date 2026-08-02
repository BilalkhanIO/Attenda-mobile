import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

/// Signature for submitting an expense claim — injectable in widget tests.
typedef ExpenseSubmit = Future<void> Function(
  double amount,
  String category,
  String description,
  String expenseDate, // yyyy-MM-dd
);

/// Common categories offered as quick picks; free text is still allowed.
const kExpenseQuickCategories = ['Travel', 'Meals', 'Supplies', 'Other'];

/// Opens the new-claim sheet. Resolves to `true` when a claim was submitted
/// successfully.
Future<bool?> showExpenseClaimSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true, // Show above the Bottom Navigation Bar
    isScrollControlled: true, // Keyboard pushes the sheet up
    backgroundColor: Colors.transparent,
    builder: (_) => const ExpenseClaimSheet(),
  );
}

/// Bottom sheet to submit an expense claim: amount, category (free text with
/// quick picks), expense date (today by default, future blocked) and a
/// description. Mirrors the API bounds so most errors surface inline.
class ExpenseClaimSheet extends StatefulWidget {
  /// The initially selected expense date; defaults to today.
  final DateTime? initialDate;

  /// Overrides the API call in tests; defaults to [ApiService.submitExpense].
  final ExpenseSubmit? onSubmit;

  const ExpenseClaimSheet({super.key, this.initialDate, this.onSubmit});

  @override
  State<ExpenseClaimSheet> createState() => _ExpenseClaimSheetState();
}

class _ExpenseClaimSheetState extends State<ExpenseClaimSheet> {
  final _amountCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  late DateTime _date = widget.initialDate ?? DateTime.now();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _categoryCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(now.year - 1),
      lastDate: now, // expense_date cannot be in the future
      builder: (c, child) => Theme(data: AppTheme.light, child: child!),
    );
    if (picked != null) setState(() => _date = picked);
  }

  /// Mirrors the API bounds: amount > 0, category 1–50 chars,
  /// description 5–1000 chars. Returns the first problem found.
  String? _validate() {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      return 'Enter an amount greater than 0.';
    }
    final category = _categoryCtrl.text.trim();
    if (category.isEmpty) return 'Choose or enter a category.';
    if (category.length > 50) return 'Category must be 50 characters or less.';
    final description = _descriptionCtrl.text.trim();
    if (description.length < 5) {
      return 'Please describe the expense (5+ chars)';
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final submit = widget.onSubmit ??
          (double amount, String category, String description, String date) =>
              api.submitExpense(
                amount: amount,
                category: category,
                description: description,
                expenseDate: date,
              );
      await submit(
        double.parse(_amountCtrl.text.trim()),
        _categoryCtrl.text.trim(),
        _descriptionCtrl.text.trim(),
        DateFormat('yyyy-MM-dd').format(_date),
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
                const Text('New Expense Claim', style: AppTextStyles.title),
                const SizedBox(height: 6),
                const Text(
                  'Submit an expense for your manager to review.',
                  style: AppTextStyles.body,
                ),
                const SizedBox(height: 20),

                // ── Amount ────────────────────────────────────
                const Text('Amount', style: AppTextStyles.captionStrong),
                const SizedBox(height: 6),
                TextField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(hintText: '0.00'),
                ),
                const SizedBox(height: 16),

                // ── Category (quick picks + free text) ────────
                const Text('Category', style: AppTextStyles.captionStrong),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in kExpenseQuickCategories)
                      _CategoryChip(
                        label: c,
                        selected: _categoryCtrl.text.trim() == c,
                        onTap: () =>
                            setState(() => _categoryCtrl.text = c),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _categoryCtrl,
                  maxLength: 50,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Travel',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),

                // ── Expense date (future blocked) ─────────────
                const Text('Expense Date', style: AppTextStyles.captionStrong),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(children: [
                      Icon(Icons.calendar_today,
                          size: 15,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('EEE, d MMM yyyy').format(_date),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Description ───────────────────────────────
                const Text('Description', style: AppTextStyles.captionStrong),
                const SizedBox(height: 6),
                TextField(
                  controller: _descriptionCtrl,
                  maxLines: 3,
                  maxLength: 1000,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'What was this expense for?',
                    counterText: '',
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
                  label: 'Submit Claim',
                  icon: Icons.receipt_long_outlined,
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

/// A flat tinted quick-pick chip that fills the category field when tapped.
class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.10)
              : AppColors.gray100,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? primary : AppColors.gray500,
          ),
        ),
      ),
    );
  }
}
