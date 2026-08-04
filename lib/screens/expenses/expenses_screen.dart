import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';
import 'expense_claim_sheet.dart';

/// My expense claims: newest-first list with a "New Claim" bottom-sheet form.
/// Reached from the Professional section of the profile screen.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<Map<String, dynamic>> _claims = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await api.getMyExpenses();
      if (!mounted) return;
      setState(() {
        _claims = list.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiFailure.fromError(e).userMessage;
        _loading = false;
      });
    }
  }

  Future<void> _newClaim() async {
    final submitted = await showExpenseClaimSheet(context);
    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense claim submitted')),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('My Expenses'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _newClaim,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: primary,
        backgroundColor: AppColors.surface,
        onRefresh: _load,
        child: _loading
            ? Center(child: CircularProgressIndicator(color: primary))
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      EmptyStateWidget(
                        icon: Icons.error_outline,
                        title: 'Couldn\'t load',
                        description: _error!,
                        action: AppButton(
                            label: 'Retry', onPressed: _load, fullWidth: false),
                      ),
                    ],
                  )
                : _claims.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 80),
                          EmptyStateWidget(
                            icon: Icons.receipt_long_outlined,
                            title: 'No expense claims',
                            description:
                                'Submit your first expense claim for reimbursement.',
                            action: AppButton(
                              label: 'New Claim',
                              onPressed: _newClaim,
                              fullWidth: false,
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        itemCount: _claims.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ExpenseClaimCard(claim: _claims[i]),
                        ),
                      ),
      ),
    );
  }
}

/// Formats "1234.5" + "USD" as "USD 1,234.50"; tolerates string amounts.
String formatExpenseAmount(dynamic amount, String? currency) {
  final value = amount is num ? amount : num.tryParse('$amount') ?? 0;
  final formatted = NumberFormat('#,##0.00').format(value);
  return currency == null || currency.isEmpty
      ? formatted
      : '$currency $formatted';
}

/// Status chip for expense claims, in the app's status-chip style
/// (flat tinted background, small icon + bold label).
class ExpenseStatusChip extends StatelessWidget {
  final String status;
  const ExpenseStatusChip({super.key, required this.status});

  Color get _bg => switch (status) {
        'approved' => AppColors.success100,
        'rejected' => AppColors.danger100,
        'reimbursed' => AppColors.primary100,
        _ => AppColors.warning100, // pending
      };

  Color get _fg => switch (status) {
        'approved' => AppColors.success700,
        'rejected' => AppColors.danger800,
        'reimbursed' => AppColors.primary900,
        _ => AppColors.warning800, // pending
      };

  String get _label => switch (status) {
        'approved' => 'Approved',
        'rejected' => 'Rejected',
        'reimbursed' => 'Reimbursed',
        'pending' => 'Pending',
        _ => status,
      };

  IconData get _icon => switch (status) {
        'approved' => Icons.check_circle,
        'rejected' => Icons.cancel,
        'reimbursed' => Icons.paid,
        _ => Icons.hourglass_empty, // pending
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_icon, size: 12, color: _fg),
        const SizedBox(width: 4),
        Text(_label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: _fg)),
      ]),
    );
  }
}

/// One of my claims: amount + status, category chip, expense date,
/// description, and the reviewer's note when present.
class ExpenseClaimCard extends StatelessWidget {
  final Map<String, dynamic> claim;
  const ExpenseClaimCard({super.key, required this.claim});

  @override
  Widget build(BuildContext context) {
    final status = claim['status'] as String? ?? 'pending';
    final category = claim['category'] as String? ?? '—';
    final description = claim['description'] as String? ?? '';
    final note = claim['review_note'] as String?;
    final reviewer = claim['reviewer'] is Map
        ? (claim['reviewer'] as Map)['name'] as String?
        : null;

    String dateLabel = '—';
    try {
      dateLabel = DateFormat('EEE, d MMM yyyy')
          .format(DateTime.parse(claim['expense_date'] as String));
    } catch (_) {}

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatExpenseAmount(
                        claim['amount'], claim['currency'] as String?),
                    style: AppTextStyles.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(dateLabel, style: AppTextStyles.caption),
                ]),
          ),
          const SizedBox(width: 8),
          ExpenseStatusChip(status: status),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          GlassBadge(text: category, color: AppColors.gray500),
        ]),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(description, style: AppTextStyles.body),
        ],
        if (note != null && note.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.gray100,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reviewer != null && reviewer.isNotEmpty
                        ? 'Note from $reviewer'
                        : 'Reviewer note',
                    style: AppTextStyles.captionStrong,
                  ),
                  const SizedBox(height: 2),
                  Text(note, style: AppTextStyles.body),
                ]),
          ),
        ],
      ]),
    );
  }
}
