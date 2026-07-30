import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

/// Manager approvals hub: pending attendance corrections (approve/reject
/// with an optional note) and the rolling late-arrival summary. Reached from
/// Settings; the entry is gated on the manager/HR capability there.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});
  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen>
    with SingleTickerProviderStateMixin {
  late final _tabCtrl = TabController(length: 2, vsync: this);

  List<Map<String, dynamic>> _corrections = [];
  bool _loadingCorrections = true;
  String? _correctionsError;

  Map<String, dynamic>? _lateSummary;
  bool _loadingLate = true;
  String? _lateError;

  @override
  void initState() {
    super.initState();
    _loadCorrections();
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
  Future<String?> _askNote({required bool approve}) async {
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve Correction' : 'Reject Correction'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            approve
                ? 'The requested times will be applied to the record.'
                : 'The employee will be notified of the rejection.',
            style: AppTextStyles.body,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            maxLines: 2,
            maxLength: 200,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: const InputDecoration(hintText: 'Add a note (optional)'),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancel', style: TextStyle(color: AppColors.gray500)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
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
      ),
    );
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    return confirmed == true ? note : null;
  }

  Future<void> _review(Map<String, dynamic> c, {required bool approve}) async {
    final note = await _askNote(approve: approve);
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

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Team Approvals'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [Tab(text: 'Corrections'), Tab(text: 'Late Arrivals')],
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
                            child: CorrectionApprovalCard(
                              correction: _corrections[i],
                              onApprove: () =>
                                  _review(_corrections[i], approve: true),
                              onReject: () =>
                                  _review(_corrections[i], approve: false),
                            ),
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
          action: AppButton(label: 'Retry', onPressed: onRetry, fullWidth: false),
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
