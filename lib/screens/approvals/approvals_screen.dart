import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';
import '../expenses/expenses_screen.dart' show formatExpenseAmount;

/// Manager approvals hub: pending attendance corrections, leave requests,
/// expense claims, overtime requests and remote-work sessions
/// (approve/reject), plus the rolling late-arrival summary. Reached from
/// Settings; the entry is gated on the manager/HR capability there, and each
/// queue tab additionally requires its own capability.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});
  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _SelectedApproval {
  const _SelectedApproval(this.type, this.request);
  final String type;
  final Map<String, dynamic> request;
}

class _ApprovalsScreenState extends State<ApprovalsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  late final bool _showLeave;
  late final bool _showExpenses;
  late final bool _showOvertime;
  late final bool _showRemote;

  List<Map<String, dynamic>> _corrections = [];
  bool _loadingCorrections = true;
  String? _correctionsError;

  List<Map<String, dynamic>> _leave = [];
  String? _leaveCursor;
  bool _leaveHasMore = false;
  bool _loadingMoreLeave = false;
  bool _loadingLeave = true;
  String? _leaveError;

  List<Map<String, dynamic>> _expenses = [];
  bool _loadingExpenses = true;
  String? _expensesError;

  List<Map<String, dynamic>> _overtime = [];
  bool _loadingOvertime = true;
  String? _overtimeError;

  List<Map<String, dynamic>> _remote = [];
  bool _loadingRemote = true;
  String? _remoteError;

  Map<String, dynamic>? _lateSummary;
  bool _loadingLate = true;
  String? _lateError;
  bool _selectMode = false;
  bool _bulkWorking = false;
  final Map<String, _SelectedApproval> _selected = {};

  @override
  void initState() {
    super.initState();
    // Same gating pattern as the corrections entry in Settings, but on each
    // queue's capability; the role helper covers a failed capability fetch.
    final auth = context.read<AuthProvider>();
    final managerFallback =
        auth.capabilities == null && (auth.user?.isManager ?? false);
    _showLeave = auth.hasPermission('leave.approve') || managerFallback;
    _showExpenses = auth.hasPermission('expenses.view') ||
        auth.hasPermission('expenses.manage') ||
        managerFallback;
    _showOvertime = auth.hasPermission('overtime.manage') || managerFallback;
    _showRemote = auth.hasPermission('remote.approve') || managerFallback;
    final tabCount = 2 +
        (_showLeave ? 1 : 0) +
        (_showExpenses ? 1 : 0) +
        (_showOvertime ? 1 : 0) +
        (_showRemote ? 1 : 0);
    _tabCtrl = TabController(length: tabCount, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging && _selected.isNotEmpty && mounted) {
        setState(_selected.clear);
      }
    });
    _loadCorrections();
    if (_showLeave) _loadLeave();
    if (_showExpenses) _loadExpenses();
    if (_showOvertime) _loadOvertime();
    if (_showRemote) _loadRemote();
    _loadLateSummary();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCorrections() async {
    setState(() {
      _loadingCorrections = true;
      _correctionsError = null;
    });
    try {
      final list = await api.getCorrections();
      if (!mounted) return;
      setState(() {
        _corrections = list.cast<Map<String, dynamic>>();
        _loadingCorrections = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _correctionsError = ApiFailure.fromError(e).userMessage;
        _loadingCorrections = false;
      });
    }
  }

  Future<void> _loadLeave() async {
    setState(() {
      _loadingLeave = true;
      _leaveError = null;
    });
    try {
      final page = await api.getTeamLeavePage(status: 'pending', limit: 25);
      if (!mounted) return;
      setState(() {
        _leave = (page['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        _leaveCursor = page['next_cursor'] as String?;
        _leaveHasMore = page['has_more'] == true;
        _loadingLeave = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _leaveError = ApiFailure.fromError(e).userMessage;
        _loadingLeave = false;
      });
    }
  }

  Future<void> _loadMoreLeave() async {
    if (_loadingMoreLeave || !_leaveHasMore || _leaveCursor == null) return;
    setState(() => _loadingMoreLeave = true);
    try {
      final page = await api.getTeamLeavePage(
          status: 'pending', limit: 25, cursor: _leaveCursor);
      if (!mounted) return;
      final rows = (page['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      setState(() {
        _leave = [..._leave, ...rows];
        _leaveCursor = page['next_cursor'] as String?;
        _leaveHasMore = page['has_more'] == true;
        _loadingMoreLeave = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMoreLeave = false);
      _showSnack(ApiFailure.fromError(e).userMessage, isError: true);
    }
  }

  Future<void> _loadOvertime() async {
    setState(() {
      _loadingOvertime = true;
      _overtimeError = null;
    });
    try {
      final list = await api.getOvertimeRequests();
      if (!mounted) return;
      setState(() {
        _overtime = list.cast<Map<String, dynamic>>();
        _loadingOvertime = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _overtimeError = ApiFailure.fromError(e).userMessage;
        _loadingOvertime = false;
      });
    }
  }

  Future<void> _loadRemote() async {
    setState(() {
      _loadingRemote = true;
      _remoteError = null;
    });
    try {
      final list = await api.getRemoteSessions();
      if (!mounted) return;
      setState(() {
        _remote = list.cast<Map<String, dynamic>>();
        _loadingRemote = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _remoteError = ApiFailure.fromError(e).userMessage;
        _loadingRemote = false;
      });
    }
  }

  Future<void> _loadExpenses() async {
    setState(() {
      _loadingExpenses = true;
      _expensesError = null;
    });
    try {
      final list = await api.getExpenses();
      if (!mounted) return;
      setState(() {
        _expenses = list.cast<Map<String, dynamic>>();
        _loadingExpenses = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _expensesError = ApiFailure.fromError(e).userMessage;
        _loadingExpenses = false;
      });
    }
  }

  Future<void> _loadLateSummary() async {
    setState(() {
      _loadingLate = true;
      _lateError = null;
    });
    try {
      final summary = await api.getLateSummary();
      if (!mounted) return;
      setState(() {
        _lateSummary = summary;
        _loadingLate = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lateError = ApiFailure.fromError(e).userMessage;
        _loadingLate = false;
      });
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.danger500 : AppColors.gray900,
    ));
  }

  /// Asks for an optional review note. Resolves to null when cancelled,
  /// otherwise the (possibly empty) note text.
  Future<String?> _askNote({
    required bool approve,
    required String title,
    required String message,
  }) async {
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(message, style: AppTextStyles.body),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            maxLines: 2,
            maxLength: 200,
            onChanged: (_) => setDialogState(() {}),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: approve
                  ? 'Add a note (optional)'
                  : 'Reason for rejection (minimum 5 characters)',
              helperText: approve ? null : 'Required to reject this request.',
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.gray500)),
          ),
          ElevatedButton(
            onPressed: !approve && noteCtrl.text.trim().length < 5
                ? null
                : () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: approve
                  ? Theme.of(context).colorScheme.primary
                  : AppColors.danger500,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control)),
            ),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      )),
    );
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    return confirmed == true ? note : null;
  }

  Future<void> _review(Map<String, dynamic> c, {required bool approve}) async {
    final note = await _askNote(
      approve: approve,
      title: approve ? 'Approve Correction' : 'Reject Correction',
      message: approve
          ? 'The requested times will be applied to the record.'
          : 'The employee will be notified of the rejection.',
    );
    if (note == null || !mounted) return;
    try {
      final id = c['id'] as String;
      if (approve) {
        await api.approveCorrection(id, note: note);
      } else {
        await api.rejectCorrection(id, note: note);
      }
      _showSnack(approve ? 'Correction approved' : 'Correction rejected');
      _loadCorrections();
    } catch (e) {
      _showSnack(ApiFailure.fromError(e).userMessage, isError: true);
    }
  }

  Future<void> _reviewExpense(Map<String, dynamic> claim,
      {required bool approve}) async {
    final note = await _askNote(
      approve: approve,
      title: approve ? 'Approve Expense' : 'Reject Expense',
      message: approve
          ? 'The claim will be approved and queued for reimbursement.'
          : 'The employee will be notified of the rejection.',
    );
    if (note == null || !mounted) return;
    try {
      final id = claim['id'] as String;
      if (approve) {
        await api.approveExpense(id, note: note);
      } else {
        await api.rejectExpense(id, note: note);
      }
      _showSnack(approve ? 'Expense approved' : 'Expense rejected');
      _loadExpenses();
    } catch (e) {
      _showSnack(ApiFailure.fromError(e).userMessage, isError: true);
    }
  }

  /// Asks for a required rejection reason. Resolves to null when cancelled
  /// or left empty, otherwise the reason text.
  Future<String?> _askReason({
    required String title,
    required String message,
    int minLength = 3,
  }) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message, style: AppTextStyles.body),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              maxLength: 200,
              onChanged: (_) => setDialogState(() {}),
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: const InputDecoration(hintText: 'Reason (required)'),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.gray500)),
            ),
            ElevatedButton(
              onPressed: reasonCtrl.text.trim().length < minLength
                  ? null
                  : () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger500,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control)),
              ),
              child: const Text('Reject'),
            ),
          ],
        ),
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    return confirmed == true && reason.length >= minLength ? reason : null;
  }

  String _selectionKey(String type, Map<String, dynamic> request) =>
      '$type:${request['id']}';

  Widget _selectableApproval(
      String type, Map<String, dynamic> request, Widget card) {
    if (!_selectMode) return card;
    final key = _selectionKey(type, request);
    final selected = _selected.containsKey(key);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Checkbox(
          value: selected,
          onChanged: (value) {
            if (value == true && _selected.length >= 20) {
              _showSnack('Select up to 20 requests at a time.', isError: true);
              return;
            }
            if (_selected.isNotEmpty &&
                !_selected.values.every((item) => item.type == type)) {
              _showSnack(
                  'Bulk actions can only include one request type at a time.',
                  isError: true);
              return;
            }
            setState(() {
              if (value == true) {
                _selected[key] = _SelectedApproval(type, request);
              } else {
                _selected.remove(key);
              }
            });
          },
        ),
      ),
      Expanded(child: AbsorbPointer(absorbing: true, child: card)),
    ]);
  }

  Future<void> _bulkReview({required bool approve}) async {
    if (_selected.isEmpty || _bulkWorking) return;
    final type = _selected.values.first.type;
    final count = _selected.length;
    String? reason;
    if (approve) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Approve $count requests?',
        message:
            'Each selected $type request will be reviewed separately. Requests that have changed or are no longer eligible will be reported as failures.',
        confirmLabel: 'Approve all',
      );
      if (confirmed != true || !mounted) return;
    } else {
      reason = await _askReason(
        title: 'Reject $count requests?',
        message: 'This reason will be included with every rejection.',
        minLength: 5,
      );
      if (reason == null || !mounted) return;
    }

    setState(() => _bulkWorking = true);
    var succeeded = 0;
    final failed = <String>[];
    for (final selected in _selected.values.toList()) {
      final request = selected.request;
      final id = request['id'] as String;
      try {
        switch (selected.type) {
          case 'correction':
            if (approve) {
              await api.approveCorrection(id);
            } else {
              await api.rejectCorrection(id, note: reason);
            }
            break;
          case 'leave':
            if (approve) {
              await api.approveLeave(id);
            } else {
              await api.rejectLeave(id, reason!);
            }
            break;
          case 'expense':
            if (approve) {
              await api.approveExpense(id);
            } else {
              await api.rejectExpense(id, note: reason!);
            }
            break;
          case 'overtime':
            if (approve) {
              await api.approveOvertime(id);
            } else {
              await api.rejectOvertime(id, reason!);
            }
            break;
          case 'remote':
            if (approve) {
              await api.approveRemoteSession(id);
            } else {
              await api.rejectRemoteSession(id, reason: reason!);
            }
            break;
          default:
            throw StateError('This request type cannot be reviewed in bulk.');
        }
        succeeded++;
      } catch (error) {
        final employee =
            request['user'] is Map ? (request['user'] as Map)['name'] : null;
        final label = employee?.toString().isNotEmpty == true
            ? employee.toString()
            : id.substring(0, id.length < 8 ? id.length : 8);
        failed.add('$label: ${ApiFailure.fromError(error).userMessage}');
      }
    }
    if (!mounted) return;
    setState(() {
      _bulkWorking = false;
      _selected.clear();
      _selectMode = false;
    });
    _showSnack(
      failed.isEmpty
          ? 'All $succeeded selected requests ${approve ? 'were approved' : 'were rejected'}.'
          : '$succeeded of $count requests completed. ${failed.length} need review.',
      isError: failed.isNotEmpty,
    );
    if (failed.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Some requests need review'),
          content: SizedBox(
            width: 440,
            height: 320,
            child: ListView.separated(
              itemCount: failed.length,
              separatorBuilder: (_, __) => const Divider(height: 16),
              itemBuilder: (_, index) =>
                  Text(failed[index], style: AppTextStyles.body),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
    switch (type) {
      case 'correction':
        await _loadCorrections();
        break;
      case 'leave':
        await _loadLeave();
        break;
      case 'expense':
        await _loadExpenses();
        break;
      case 'overtime':
        await _loadOvertime();
        break;
      case 'remote':
        await _loadRemote();
        break;
    }
  }

  Future<void> _reviewLeave(Map<String, dynamic> request,
      {required bool approve}) async {
    final id = request['id'] as String;
    if (approve) {
      final ok = await showConfirmDialog(
        context,
        title: 'Approve Leave',
        message: 'The leave will be approved and deducted from the balance.',
        confirmLabel: 'Approve',
      );
      if (ok != true || !mounted) return;
      try {
        await api.approveLeave(id);
        _showSnack('Leave approved');
        _loadLeave();
      } catch (e) {
        _showSnack(ApiFailure.fromError(e).userMessage, isError: true);
      }
      return;
    }
    final reason = await _askReason(
      title: 'Reject Leave',
      message: 'The employee will be notified with your reason.',
    );
    if (reason == null || !mounted) return;
    try {
      await api.rejectLeave(id, reason);
      _showSnack('Leave rejected');
      _loadLeave();
    } catch (e) {
      _showSnack(ApiFailure.fromError(e).userMessage, isError: true);
    }
  }

  Future<void> _reviewOvertime(Map<String, dynamic> request,
      {required bool approve}) async {
    final id = request['id'] as String;
    if (approve) {
      final ok = await showConfirmDialog(
        context,
        title: 'Approve Overtime',
        message: 'The extra office time will be counted as overtime.',
        confirmLabel: 'Approve',
      );
      if (ok != true || !mounted) return;
      try {
        await api.approveOvertime(id);
        _showSnack('Overtime approved');
        _loadOvertime();
      } catch (e) {
        _showSnack(ApiFailure.fromError(e).userMessage, isError: true);
      }
      return;
    }
    final reason = await _askReason(
      title: 'Reject Overtime',
      message: 'The employee will be notified with your reason.',
    );
    if (reason == null || !mounted) return;
    try {
      await api.rejectOvertime(id, reason);
      _showSnack('Overtime rejected');
      _loadOvertime();
    } catch (e) {
      _showSnack(ApiFailure.fromError(e).userMessage, isError: true);
    }
  }

  Future<void> _reviewRemote(Map<String, dynamic> session,
      {required bool approve}) async {
    final reason = approve
        ? null
        : await _askReason(
            title: 'Reject Remote Work',
            message: 'Give the employee a clear reason for this decision.',
          );
    if (!mounted) return;
    if (!approve && (reason == null || reason.trim().length < 3)) return;
    if (approve) {
      final ok = await showConfirmDialog(
        context,
        title: 'Approve Remote Work',
        message: 'The remote session will be approved.',
        confirmLabel: 'Approve',
      );
      if (ok != true || !mounted) return;
    }
    try {
      final id = session['id'] as String;
      if (approve) {
        await api.approveRemoteSession(id);
      } else {
        await api.rejectRemoteSession(id, reason: reason!.trim());
      }
      _showSnack(
          approve ? 'Remote session approved' : 'Remote session rejected');
      _loadRemote();
    } catch (e) {
      _showSnack(ApiFailure.fromError(e).userMessage, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Team Approvals'),
        actions: [
          if (!_selectMode)
            IconButton(
              tooltip: 'Select requests for bulk review',
              onPressed: () => setState(() => _selectMode = true),
              icon: const Icon(Icons.checklist_rtl_outlined),
            )
          else
            TextButton(
              onPressed: _bulkWorking
                  ? null
                  : () => setState(() {
                        _selectMode = false;
                        _selected.clear();
                      }),
              child: const Text('Cancel selection'),
            ),
          if (context.watch<AuthProvider>().hasPermission('analytics.ai_chat'))
            IconButton(
              tooltip: 'Ask AI about pending approvals',
              onPressed: () => context.push('/home/ai', extra: const {
                'prompt':
                    'List the pending approvals I am allowed to review. Group them by request type and count each group. Do not approve or reject anything.',
              }),
              icon: const Icon(Icons.auto_awesome_outlined),
            ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabs: [
            const Tab(text: 'Corrections'),
            if (_showLeave) const Tab(text: 'Leave'),
            if (_showExpenses) const Tab(text: 'Expenses'),
            if (_showOvertime) const Tab(text: 'Overtime'),
            if (_showRemote) const Tab(text: 'Remote'),
            const Tab(text: 'Late Arrivals'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabCtrl, children: [
        // ── Corrections queue ─────────────────────────────
        RefreshIndicator(
          color: primary,
          backgroundColor: AppColors.surface,
          onRefresh: _loadCorrections,
          child: _loadingCorrections
              ? Center(child: CircularProgressIndicator(color: primary))
              : _correctionsError != null
                  ? _errorState(_correctionsError!, _loadCorrections)
                  : _corrections.isEmpty
                      ? const EmptyStateWidget(
                          icon: Icons.fact_check_outlined,
                          title: 'All caught up',
                          description: 'No pending correction requests.',
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          itemCount: _corrections.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _selectableApproval(
                                'correction',
                                _corrections[i],
                                CorrectionApprovalCard(
                                  correction: _corrections[i],
                                  onApprove: () =>
                                      _review(_corrections[i], approve: true),
                                  onReject: () =>
                                      _review(_corrections[i], approve: false),
                                )),
                          ),
                        ),
        ),

        // ── Leave queue ───────────────────────────────────
        if (_showLeave)
          RefreshIndicator(
            color: primary,
            backgroundColor: AppColors.surface,
            onRefresh: _loadLeave,
            child: _loadingLeave
                ? Center(child: CircularProgressIndicator(color: primary))
                : _leaveError != null
                    ? _errorState(_leaveError!, _loadLeave)
                    : _leave.isEmpty
                        ? const EmptyStateWidget(
                            icon: Icons.beach_access_outlined,
                            title: 'All caught up',
                            description: 'No pending leave requests.',
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                            itemCount: _leave.length + (_leaveHasMore ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i == _leave.length) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    child: _loadingMoreLeave
                                        ? const CircularProgressIndicator()
                                        : TextButton(
                                            onPressed: _loadMoreLeave,
                                            child: const Text(
                                                'Load more requests')),
                                  ),
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _selectableApproval(
                                    'leave',
                                    _leave[i],
                                    LeaveApprovalCard(
                                      request: _leave[i],
                                      onApprove: () => _reviewLeave(_leave[i],
                                          approve: true),
                                      onReject: () => _reviewLeave(_leave[i],
                                          approve: false),
                                    )),
                              );
                            },
                          ),
          ),

        // ── Expenses queue ────────────────────────────────
        if (_showExpenses)
          RefreshIndicator(
            color: primary,
            backgroundColor: AppColors.surface,
            onRefresh: _loadExpenses,
            child: _loadingExpenses
                ? Center(child: CircularProgressIndicator(color: primary))
                : _expensesError != null
                    ? _errorState(_expensesError!, _loadExpenses)
                    : _expenses.isEmpty
                        ? const EmptyStateWidget(
                            icon: Icons.receipt_long_outlined,
                            title: 'All caught up',
                            description: 'No pending expense claims.',
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                            itemCount: _expenses.length,
                            itemBuilder: (_, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _selectableApproval(
                                  'expense',
                                  _expenses[i],
                                  ExpenseApprovalCard(
                                    claim: _expenses[i],
                                    onApprove: () => _reviewExpense(
                                        _expenses[i],
                                        approve: true),
                                    onReject: () => _reviewExpense(_expenses[i],
                                        approve: false),
                                  )),
                            ),
                          ),
          ),

        // ── Overtime queue ────────────────────────────────
        if (_showOvertime)
          RefreshIndicator(
            color: primary,
            backgroundColor: AppColors.surface,
            onRefresh: _loadOvertime,
            child: _loadingOvertime
                ? Center(child: CircularProgressIndicator(color: primary))
                : _overtimeError != null
                    ? _errorState(_overtimeError!, _loadOvertime)
                    : _overtime.isEmpty
                        ? const EmptyStateWidget(
                            icon: Icons.more_time_outlined,
                            title: 'All caught up',
                            description: 'No pending overtime requests.',
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                            itemCount: _overtime.length,
                            itemBuilder: (_, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _selectableApproval(
                                  'overtime',
                                  _overtime[i],
                                  OvertimeApprovalCard(
                                    request: _overtime[i],
                                    onApprove: () => _reviewOvertime(
                                        _overtime[i],
                                        approve: true),
                                    onReject: () => _reviewOvertime(
                                        _overtime[i],
                                        approve: false),
                                  )),
                            ),
                          ),
          ),

        // ── Remote sessions queue ─────────────────────────
        if (_showRemote)
          RefreshIndicator(
            color: primary,
            backgroundColor: AppColors.surface,
            onRefresh: _loadRemote,
            child: _loadingRemote
                ? Center(child: CircularProgressIndicator(color: primary))
                : _remoteError != null
                    ? _errorState(_remoteError!, _loadRemote)
                    : _remote.isEmpty
                        ? const EmptyStateWidget(
                            icon: Icons.home_work_outlined,
                            title: 'All caught up',
                            description: 'No pending remote work requests.',
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                            itemCount: _remote.length,
                            itemBuilder: (_, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _selectableApproval(
                                  'remote',
                                  _remote[i],
                                  RemoteApprovalCard(
                                    session: _remote[i],
                                    onApprove: () => _reviewRemote(_remote[i],
                                        approve: true),
                                    onReject: () => _reviewRemote(_remote[i],
                                        approve: false),
                                  )),
                            ),
                          ),
          ),

        // ── Late summary ──────────────────────────────────
        RefreshIndicator(
          color: primary,
          backgroundColor: AppColors.surface,
          onRefresh: _loadLateSummary,
          child: _loadingLate
              ? Center(child: CircularProgressIndicator(color: primary))
              : _lateError != null
                  ? _errorState(_lateError!, _loadLateSummary)
                  : _buildLateSummary(),
        ),
      ]),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Material(
                color: AppColors.surface,
                elevation: 12,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '${_selected.length} selected · actions apply one request at a time',
                          style: AppTextStyles.caption,
                        ),
                      ),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        TextButton(
                            onPressed: _bulkWorking
                                ? null
                                : () => setState(_selected.clear),
                            child: const Text('Clear')),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _bulkWorking
                              ? null
                              : () => _bulkReview(approve: false),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Reject'),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger500),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _bulkWorking
                              ? null
                              : () => _bulkReview(approve: true),
                          icon: _bulkWorking
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.check, size: 18),
                          label: const Text('Approve'),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _errorState(String message, Future<void> Function() onRetry) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        EmptyStateWidget(
          icon: Icons.error_outline,
          title: 'Couldn\'t load',
          description: message,
          action:
              AppButton(label: 'Retry', onPressed: onRetry, fullWidth: false),
        ),
      ],
    );
  }

  Widget _buildLateSummary() {
    final users = (_lateSummary?['users'] as List?)
            ?.whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList() ??
        const <Map<String, dynamic>>[];
    final windowDays = (_lateSummary?['window_days'] as num?)?.toInt() ?? 30;
    final policyConfigured =
        _lateSummary?['policy_configured'] as bool? ?? false;

    if (users.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          EmptyStateWidget(
            icon: Icons.access_time,
            title: 'No late arrivals',
            description: 'Nobody was late in the last $windowDays days.',
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text('Last $windowDays days, ranked by points',
            style: AppTextStyles.caption),
        if (!policyConfigured) ...[
          const SizedBox(height: 4),
          const Text('No late policy configured — points are not scored.',
              style: AppTextStyles.caption),
        ],
        const SizedBox(height: 12),
        ...users.asMap().entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LateSummaryTile(rank: entry.key + 1, row: entry.value),
            )),
      ],
    );
  }
}

/// One pending correction: who, which day, the requested times and reason,
/// plus Approve / Reject actions.
class CorrectionApprovalCard extends StatelessWidget {
  final Map<String, dynamic> correction;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const CorrectionApprovalCard({
    super.key,
    required this.correction,
    this.onApprove,
    this.onReject,
  });

  String _fmtTime(dynamic iso) {
    if (iso == null) return '—';
    try {
      return DateFormat('hh:mm a')
          .format(DateTime.parse(iso.toString()).toLocal());
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = correction['user'] is Map
        ? (correction['user'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final name = user['name'] as String? ?? 'Employee';
    String dateLabel = '—';
    try {
      dateLabel = DateFormat('EEE, d MMM yyyy')
          .format(DateTime.parse(correction['date'] as String));
    } catch (_) {}

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          UserAvatar(
              name: name, imageUrl: user['avatar_url'] as String?, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: AppTextStyles.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(dateLabel, style: AppTextStyles.caption),
            ]),
          ),
          if (user['department'] != null)
            GlassBadge(
                text: user['department'] as String, color: AppColors.gray500),
        ]),
        const SizedBox(height: 8),
        if (correction['requested_check_in'] != null)
          glassDetailRow(
              'Requested Check In', _fmtTime(correction['requested_check_in'])),
        if (correction['requested_check_out'] != null)
          glassDetailRow('Requested Check Out',
              _fmtTime(correction['requested_check_out'])),
        glassDetailRow('Reason', correction['reason'] as String? ?? '—'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: AppButton(
              label: 'Reject',
              outline: true,
              color: AppColors.danger500,
              onPressed: onReject,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AppButton(label: 'Approve', onPressed: onApprove),
          ),
        ]),
      ]),
    );
  }
}

/// One pending expense claim: who, the amount, category, expense date and
/// description, plus Approve / Reject actions.
class ExpenseApprovalCard extends StatelessWidget {
  final Map<String, dynamic> claim;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const ExpenseApprovalCard({
    super.key,
    required this.claim,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final user = claim['user'] is Map
        ? (claim['user'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final name = user['name'] as String? ?? 'Employee';
    String dateLabel = '—';
    try {
      dateLabel = DateFormat('EEE, d MMM yyyy')
          .format(DateTime.parse(claim['expense_date'] as String));
    } catch (_) {}

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          UserAvatar(
              name: name, imageUrl: user['avatar_url'] as String?, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: AppTextStyles.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(dateLabel, style: AppTextStyles.caption),
            ]),
          ),
          if (user['department'] != null)
            GlassBadge(
                text: user['department'] as String, color: AppColors.gray500),
        ]),
        const SizedBox(height: 8),
        glassDetailRow(
          'Amount',
          formatExpenseAmount(claim['amount'], claim['currency'] as String?),
          highlight: true,
        ),
        glassDetailRow('Category', claim['category'] as String? ?? '—'),
        glassDetailRow('Description', claim['description'] as String? ?? '—'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: AppButton(
              label: 'Reject',
              outline: true,
              color: AppColors.danger500,
              onPressed: onReject,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AppButton(label: 'Approve', onPressed: onApprove),
          ),
        ]),
      ]),
    );
  }
}

/// One pending leave request: who, the type, dates, duration and reason,
/// plus Approve / Reject actions.
class LeaveApprovalCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const LeaveApprovalCard({
    super.key,
    required this.request,
    this.onApprove,
    this.onReject,
  });

  String _fmtDate(dynamic iso) {
    if (iso == null) return '—';
    try {
      return DateFormat('EEE, d MMM yyyy')
          .format(DateTime.parse(iso.toString()).toLocal());
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = request['user'] is Map
        ? (request['user'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final name = user['name'] as String? ?? 'Employee';
    final type = request['leave_type'] as String? ?? 'leave';
    final typeLabel =
        type.isEmpty ? 'Leave' : '${type[0].toUpperCase()}${type.substring(1)}';
    final start = _fmtDate(request['start_date']);
    final end = _fmtDate(request['end_date']);
    final days = (request['working_days'] as num?)?.toDouble();
    final isHalfDay = request['is_half_day'] == true;
    final halfDayPeriod = request['half_day_period'] as String?;
    String duration = days == null
        ? '—'
        : days == days.roundToDouble()
            ? '${days.toInt()} day${days == 1 ? '' : 's'}'
            : '$days days';
    if (isHalfDay && halfDayPeriod != null) {
      duration = 'Half day ($halfDayPeriod)';
    }

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          UserAvatar(
              name: name, imageUrl: user['avatar_url'] as String?, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: AppTextStyles.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(typeLabel, style: AppTextStyles.caption),
            ]),
          ),
          if (user['department'] != null)
            GlassBadge(
                text: user['department'] as String, color: AppColors.gray500),
        ]),
        const SizedBox(height: 8),
        glassDetailRow('Dates', start == end ? start : '$start – $end'),
        glassDetailRow('Duration', duration, highlight: true),
        glassDetailRow('Reason', request['reason'] as String? ?? '—'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: AppButton(
              label: 'Reject',
              outline: true,
              color: AppColors.danger500,
              onPressed: onReject,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AppButton(label: 'Approve', onPressed: onApprove),
          ),
        ]),
      ]),
    );
  }
}

/// One pending overtime request: who, which day, the requested minutes and
/// reason, plus Approve / Reject actions.
class OvertimeApprovalCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const OvertimeApprovalCard({
    super.key,
    required this.request,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final user = request['user'] is Map
        ? (request['user'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final name = user['name'] as String? ?? 'Employee';
    final attendance = request['attendance'] is Map
        ? (request['attendance'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    String dateLabel = '—';
    try {
      dateLabel = DateFormat('EEE, d MMM yyyy')
          .format(DateTime.parse(attendance['date'] as String));
    } catch (_) {}
    final mins = (request['requested_minutes'] as num?)?.toInt() ?? 0;
    final duration = mins >= 60 ? '${mins ~/ 60}h ${mins % 60}m' : '${mins}m';

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          UserAvatar(
              name: name, imageUrl: user['avatar_url'] as String?, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: AppTextStyles.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(dateLabel, style: AppTextStyles.caption),
            ]),
          ),
          if (user['department'] != null)
            GlassBadge(
                text: user['department'] as String, color: AppColors.gray500),
        ]),
        const SizedBox(height: 8),
        glassDetailRow('Requested Overtime', duration, highlight: true),
        glassDetailRow('Reason', request['reason'] as String? ?? '—'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: AppButton(
              label: 'Reject',
              outline: true,
              color: AppColors.danger500,
              onPressed: onReject,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AppButton(label: 'Approve', onPressed: onApprove),
          ),
        ]),
      ]),
    );
  }
}

/// One pending remote-work session: who, which day and the requested
/// duration, plus Approve / Reject actions.
class RemoteApprovalCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const RemoteApprovalCard({
    super.key,
    required this.session,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final user = session['user'] is Map
        ? (session['user'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final name = user['name'] as String? ?? 'Employee';
    final attendance = session['attendance'] is Map
        ? (session['attendance'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    String dateLabel = '—';
    try {
      dateLabel = DateFormat('EEE, d MMM yyyy')
          .format(DateTime.parse(attendance['date'] as String));
    } catch (_) {}
    final durationType = session['duration_type'] as String? ?? 'full_day';
    final durationLabel = durationType == 'half_day' ? 'Half day' : 'Full day';

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          UserAvatar(
              name: name, imageUrl: user['avatar_url'] as String?, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: AppTextStyles.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(dateLabel, style: AppTextStyles.caption),
            ]),
          ),
          if (user['department'] != null)
            GlassBadge(
                text: user['department'] as String, color: AppColors.gray500),
        ]),
        const SizedBox(height: 8),
        glassDetailRow('Working Remotely', durationLabel, highlight: true),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: AppButton(
              label: 'Reject',
              outline: true,
              color: AppColors.danger500,
              onPressed: onReject,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AppButton(label: 'Approve', onPressed: onApprove),
          ),
        ]),
      ]),
    );
  }
}

/// One row of the late summary: rank, name, late count, minutes and points.
class LateSummaryTile extends StatelessWidget {
  final int rank;

  /// A row from /attendance/late-summary `users`:
  /// `{name, department, late_count, total_late_minutes, points}`.
  final Map<String, dynamic> row;

  const LateSummaryTile({super.key, required this.rank, required this.row});

  @override
  Widget build(BuildContext context) {
    final name = row['name'] as String? ?? 'Employee';
    final lateCount = (row['late_count'] as num?)?.toInt() ?? 0;
    final lateMins = (row['total_late_minutes'] as num?)?.toInt() ?? 0;
    final points = (row['points'] as num?)?.toInt() ?? 0;

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.gray100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text('$rank', style: AppTextStyles.captionStrong),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: AppTextStyles.bodyStrong,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('$lateCount× late · ${lateMins}m total',
                style: AppTextStyles.caption),
          ]),
        ),
        const SizedBox(width: 8),
        GlassBadge(
          text: '$points pts',
          color: points > 0 ? AppColors.warning500 : AppColors.gray500,
        ),
      ]),
    );
  }
}
