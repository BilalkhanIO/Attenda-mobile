import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

/// My onboarding checklist: tasks assigned to me, grouped Pending then
/// Completed. Managers also see manager-side items for their hires — those
/// carry a "For <hire>" chip. Complete works by swipe or button; Skip asks
/// for confirmation. Both update optimistically and revert on failure.
/// Reached from the Professional section of the profile screen.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  List<Map<String, dynamic>> _tasks = [];
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
      final list = await api.getMyOnboardingTasks();
      if (!mounted) return;
      setState(() {
        _tasks = list.cast<Map<String, dynamic>>();
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

  /// Optimistically flips the task to done/skipped, then confirms with the
  /// server. On failure the previous row is restored and the error surfaced.
  Future<void> _close(String id, {required bool skip}) async {
    final index = _tasks.indexWhere((t) => t['id'] == id);
    if (index == -1) return;
    final previous = _tasks[index];
    if (previous['status'] != 'pending') return;

    setState(() {
      _tasks[index] = {
        ...previous,
        'status': skip ? 'skipped' : 'done',
        'completed_at': DateTime.now().toIso8601String(),
      };
    });

    try {
      final updated = skip
          ? await api.skipOnboardingTask(id)
          : await api.completeOnboardingTask(id);
      if (!mounted) return;
      setState(() {
        final i = _tasks.indexWhere((t) => t['id'] == id);
        if (i != -1) _tasks[i] = updated;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final i = _tasks.indexWhere((t) => t['id'] == id);
        if (i != -1) _tasks[i] = previous;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiFailure.fromError(e).userMessage)),
      );
    }
  }

  Future<void> _skipWithConfirm(Map<String, dynamic> task) async {
    final title = task['item_title'] as String? ?? 'this task';
    final confirmed = await showConfirmDialog(
      context,
      title: 'Skip task?',
      message: '"$title" will be marked as skipped. '
          'This can\'t be undone from the app.',
      confirmLabel: 'Skip',
    );
    if (confirmed == true) {
      await _close(task['id'] as String? ?? '', skip: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final myUserId = context.watch<AuthProvider>().user?.id;
    final pending =
        _tasks.where((t) => t['status'] == 'pending').toList(growable: false);
    final completed =
        _tasks.where((t) => t['status'] != 'pending').toList(growable: false);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Onboarding'),
        centerTitle: true,
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
                : _tasks.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 80),
                          EmptyStateWidget(
                            icon: Icons.fact_check_outlined,
                            title: 'No onboarding tasks',
                            description:
                                'Tasks assigned to you will appear here.',
                          ),
                        ],
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        children: [
                          if (pending.isNotEmpty) ...[
                            const SectionHeader(title: 'Pending'),
                            const SizedBox(height: 12),
                            for (final task in pending)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _swipeToComplete(task, myUserId),
                              ),
                          ],
                          if (completed.isNotEmpty) ...[
                            if (pending.isNotEmpty) const SizedBox(height: 16),
                            const SectionHeader(title: 'Completed'),
                            const SizedBox(height: 12),
                            for (final task in completed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: OnboardingTaskCard(
                                    task: task, myUserId: myUserId),
                              ),
                          ],
                        ],
                      ),
      ),
    );
  }

  /// Swipe right to complete: the row never actually dismisses — the status
  /// flip moves it into the Completed group instead.
  Widget _swipeToComplete(Map<String, dynamic> task, String? myUserId) {
    final id = task['id'] as String? ?? '';
    return Dismissible(
      key: ValueKey('onboarding-$id'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        await _close(id, skip: false);
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: AppColors.success100,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: const Icon(Icons.check_circle,
            color: AppColors.success700, size: 22),
      ),
      child: OnboardingTaskCard(
        task: task,
        myUserId: myUserId,
        onComplete: () => _close(id, skip: false),
        onSkip: () => _skipWithConfirm(task),
      ),
    );
  }
}

/// True when the task is still pending and its due date is before today
/// (date-only comparison; a task due today is not overdue yet).
bool isOnboardingTaskOverdue(Map<String, dynamic> task, {DateTime? now}) {
  if (task['status'] != 'pending') return false;
  final raw = task['due_date'] as String?;
  if (raw == null) return false;
  final due = DateTime.tryParse(raw);
  if (due == null) return false;
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  return DateTime(due.year, due.month, due.day).isBefore(today);
}

/// One onboarding task: title, description, due date (tinted red once
/// overdue), a "For <hire>" chip when the task belongs to someone else's
/// onboarding, and Complete/Skip actions while pending. Completed rows show
/// a Done/Skipped chip instead.
class OnboardingTaskCard extends StatelessWidget {
  static const overdueBadgeKey = Key('onboardingOverdueBadge');
  static const hireChipKey = Key('onboardingHireChip');

  final Map<String, dynamic> task;

  /// The signed-in user's id — used to detect tasks done on behalf of a hire.
  final String? myUserId;
  final VoidCallback? onComplete;
  final VoidCallback? onSkip;

  const OnboardingTaskCard({
    super.key,
    required this.task,
    this.myUserId,
    this.onComplete,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final status = task['status'] as String? ?? 'pending';
    final pending = status == 'pending';
    final overdue = isOnboardingTaskOverdue(task);
    final description = task['item_description'] as String? ?? '';
    final hire = task['user'] is Map ? task['user'] as Map : const {};
    final hireId = hire['id'] as String?;
    final forSomeoneElse =
        myUserId != null && hireId != null && hireId != myUserId;

    String? dueLabel;
    final dueRaw = task['due_date'] as String?;
    if (dueRaw != null) {
      final due = DateTime.tryParse(dueRaw);
      if (due != null) dueLabel = DateFormat('EEE, d MMM yyyy').format(due);
    }

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(
              task['item_title'] as String? ?? '',
              style: AppTextStyles.bodyStrong,
            ),
          ),
          if (!pending) ...[
            const SizedBox(width: 8),
            GlassBadge(
              text: status == 'done' ? 'Done' : 'Skipped',
              icon: status == 'done' ? Icons.check_circle : Icons.redo,
              color: status == 'done'
                  ? AppColors.success700
                  : AppColors.gray500,
            ),
          ],
        ]),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(description, style: AppTextStyles.body),
        ],
        if (dueLabel != null || forSomeoneElse) ...[
          const SizedBox(height: 10),
          Row(children: [
            if (dueLabel != null) ...[
              Icon(Icons.calendar_today,
                  size: 12,
                  color:
                      overdue ? AppColors.danger500 : AppColors.gray400),
              const SizedBox(width: 5),
              Text(
                'Due $dueLabel',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: overdue ? FontWeight.w700 : FontWeight.w500,
                  color: overdue
                      ? AppColors.danger500
                      : AppColors.textSecondary,
                ),
              ),
              if (overdue) ...[
                const SizedBox(width: 8),
                const GlassBadge(
                  key: overdueBadgeKey,
                  text: 'Overdue',
                  color: AppColors.danger500,
                ),
              ],
            ],
            const Spacer(),
            if (forSomeoneElse)
              GlassBadge(
                key: hireChipKey,
                text: 'For ${hire['name'] as String? ?? 'hire'}',
                icon: Icons.person_outline,
                color: AppColors.info500,
              ),
          ]),
        ],
        if (pending) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: AppButton(
                label: 'Skip',
                outline: true,
                color: AppColors.gray500,
                onPressed: onSkip,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppButton(
                label: 'Complete',
                icon: Icons.check,
                onPressed: onComplete,
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
