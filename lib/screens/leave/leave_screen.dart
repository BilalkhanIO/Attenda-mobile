import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key});
  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen>
    with SingleTickerProviderStateMixin {
  late final _tabCtrl = TabController(length: 2, vsync: this);
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _balances = [];
  String? _nextRequestCursor;
  bool _hasMoreRequests = false;
  bool _loadingMoreRequests = false;
  bool _loading = true;
  // First-load failure — drives the error + Retry state. Reloads with data
  // already on screen fail silently and keep the last good lists.
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final [reqPage, bals] = await Future.wait(
          [api.getMyLeaveRequestsPage(limit: 25), api.getMyLeaveBalance()]);
      if (!mounted) return;
      final page = reqPage as Map<String, dynamic>;
      setState(() {
        _requests = (page['items'] as List? ?? const []).whereType<Map>().map((row) => row.cast<String, dynamic>()).toList();
        _nextRequestCursor = page['next_cursor'] as String?;
        _hasMoreRequests = page['has_more'] == true;
        _balances = (bals as List).cast<Map<String, dynamic>>();
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_requests.isEmpty && _balances.isEmpty) {
          _error = ApiFailure.fromError(e).userMessage;
        }
        _loading = false;
      });
    }
  }

  Future<void> _loadMoreRequests() async {
    if (_loadingMoreRequests || !_hasMoreRequests || _nextRequestCursor == null) return;
    setState(() => _loadingMoreRequests = true);
    try {
      final page = await api.getMyLeaveRequestsPage(cursor: _nextRequestCursor, limit: 25);
      if (!mounted) return;
      final rows = (page['items'] as List? ?? const []).whereType<Map>().map((row) => row.cast<String, dynamic>()).toList();
      setState(() {
        _requests = [..._requests, ...rows];
        _nextRequestCursor = page['next_cursor'] as String?;
        _hasMoreRequests = page['has_more'] == true;
        _loadingMoreRequests = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMoreRequests = false);
    }
  }

  Future<void> _openBalanceHistory() async {
    final future = api.getMyLeaveBalanceLedger(year: DateTime.now().year, limit: 100);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.76,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.gray400, borderRadius: BorderRadius.circular(4)))),
              const SizedBox(height: 18),
              const Text('Leave balance history', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Accruals, leave usage, adjustments and reversals', style: AppTextStyles.caption),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    if (snapshot.hasError) return Center(child: Text('Could not load history. Pull to retry.', style: AppTextStyles.caption));
                    final items = (snapshot.data?['items'] as List? ?? const []).whereType<Map>().map((row) => row.cast<String, dynamic>()).toList();
                    if (items.isEmpty) return Center(child: Text('No balance changes recorded this year.', style: AppTextStyles.caption));
                    return ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final item = items[index];
                        double number(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
                        final totalDelta = number(item['total_delta']);
                        final usedDelta = number(item['used_delta']);
                        final date = DateTime.tryParse('${item['effective_date']}');
                        final detail = totalDelta != 0
                            ? '${totalDelta > 0 ? '+' : ''}${totalDelta.toStringAsFixed(totalDelta % 1 == 0 ? 0 : 2)} days'
                            : '${usedDelta > 0 ? '+' : ''}${usedDelta.toStringAsFixed(usedDelta % 1 == 0 ? 0 : 2)} used';
                        return GlassCard(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(totalDelta < 0 || usedDelta > 0 ? Icons.remove_circle_outline : Icons.add_circle_outline, size: 18, color: totalDelta < 0 || usedDelta > 0 ? AppColors.warning500 : AppColors.success500),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${item['reason'] ?? 'Balance change'}'.replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                              if (item['note'] != null && '${item['note']}'.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text('${item['note']}', style: AppTextStyles.caption),
                              ],
                              const SizedBox(height: 4),
                              Text(date == null ? '' : DateFormat('MMM d, yyyy').format(date), style: AppTextStyles.caption),
                            ])),
                            const SizedBox(width: 8),
                            Text(detail, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          ]),
                        );
                      },
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _errorState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        EmptyStateWidget(
          icon: Icons.error_outline,
          title: 'Couldn\'t load',
          description: _error!,
          action: AppButton(label: 'Retry', onPressed: _load, fullWidth: false),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Leave'),
          actions: [
            IconButton(
              tooltip: 'Leave balance history',
              onPressed: _openBalanceHistory,
              icon: const Icon(Icons.history_rounded),
            ),
            if (context
                .watch<AuthProvider>()
                .hasPermission('analytics.ai_chat'))
              IconButton(
                tooltip: 'Ask AI about leave',
                onPressed: () => context.push('/home/ai', extra: const {
                  'prompt':
                      'Check my live leave balances and recent leave requests. Summarize the available days by leave type and any request that is still pending.',
                }),
                icon: const Icon(Icons.auto_awesome_outlined),
              ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () async {
                await context.push('/leave/request');
                _load();
              },
            ),
          ],
          bottom: TabBar(
            controller: _tabCtrl,
            tabs: const [Tab(text: 'Requests'), Tab(text: 'Balance')],
          ),
        ),
        body: TabBarView(controller: _tabCtrl, children: [
          // Requests tab
          RefreshIndicator(
            color: Theme.of(context).colorScheme.primary,
            backgroundColor: AppColors.surface,
            onRefresh: _load,
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.primary))
                : _error != null
                    ? _errorState()
                    : _requests.isEmpty
                        ? EmptyStateWidget(
                            icon: Icons.beach_access,
                            title: 'No leave requests',
                            description: 'Submit your first leave request.',
                            action: AppButton(
                              label: 'Request Leave',
                              onPressed: () => context.push('/leave/request'),
                              fullWidth: false,
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                            itemCount: _requests.length + (_hasMoreRequests ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i == _requests.length) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Center(child: _loadingMoreRequests
                                      ? const CircularProgressIndicator()
                                      : TextButton(onPressed: _loadMoreRequests, child: const Text('Load more requests'))),
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _LeaveRequestTile(request: _requests[i], onCancel: _load),
                              );
                            },
                          ),
          ),
          // Balance tab
          _loading
              ? Center(
                  child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary))
              : _error != null
                  ? _errorState()
                  : _balances.isEmpty
                      ? const EmptyStateWidget(
                          icon: Icons.account_balance_wallet_outlined,
                          title: 'No leave balances',
                          description:
                              'Your leave allocations will appear here.',
                        )
                      : Builder(builder: (context) {
                          final totalRemaining = _balances.fold(
                              0.0,
                              (s, b) =>
                                  s + ((b['remaining_days'] as num?) ?? 0.0));
                          final totalEntitled = _balances.fold(
                              0.0,
                              (s, b) =>
                                  s + ((b['entitled_days'] as num?) ?? 0.0));
                          final pct = totalEntitled > 0
                              ? (totalRemaining / totalEntitled).clamp(0.0, 1.0)
                              : 0.0;
                          final remainingInt = totalRemaining % 1 == 0
                              ? totalRemaining.toInt().toString()
                              : totalRemaining.toStringAsFixed(1);

                          return ListView(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                            children: [
                              // ── Balance summary glass card ──
                              GlassCard(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 24),
                                child: Row(children: [
                                  _LeaveRing(
                                      pct: pct,
                                      value: remainingInt,
                                      label: 'days'),
                                  const SizedBox(width: 24),
                                  Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('TOTAL REMAINING',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 1.2,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary)),
                                          const SizedBox(height: 8),
                                          Text(
                                            'You have $remainingInt days of leave left for ${DateTime.now().year}.',
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: AppColors.textPrimary,
                                                height: 1.4),
                                          ),
                                        ]),
                                  ),
                                ]),
                              ),
                              const SizedBox(height: 24),
                              const SectionHeader(title: 'Leave Types'),
                              const SizedBox(height: 12),
                              ..._balances.map((b) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _BalanceTile(balance: b),
                                  )),
                            ],
                          );
                        }),
        ]),
      );
}

// The backend serializes `leave_type` either as an embedded object
// (`{name: ...}`) or as a bare string. Branch on the runtime type — a plain
// `as Map?` cast throws on a String before the `??` fallback can catch it.
String _leaveTypeName(dynamic lt) {
  if (lt is Map) return lt['name'] as String? ?? 'Leave';
  if (lt is String) return lt;
  return 'Leave';
}

class _LeaveRequestTile extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback? onCancel;
  const _LeaveRequestTile({required this.request, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final status = request['status'] as String? ?? 'pending';
    final leaveType = _leaveTypeName(request['leave_type']);
    final start = DateTime.parse(request['start_date'] as String);
    final end = DateTime.parse(request['end_date'] as String);
    final days = (request['working_days'] as num?)?.toDouble() ?? 0.0;
    final reason = request['rejection_reason'] as String?;
    final isHalf = request['is_half_day'] as bool? ?? false;

    final statusCfg = <String, (Color, Color)>{
      'pending': (AppColors.warning500, AppColors.warning100),
      'approved': (AppColors.success500, AppColors.success100),
      'rejected': (AppColors.danger500, AppColors.danger100),
      'cancelled': (AppColors.gray400, AppColors.gray100),
    };
    final (fgColor, bgColor) =
        statusCfg[status] ?? (AppColors.gray400, AppColors.gray100);

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Row(children: [
              Text(leaveType.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: AppColors.textPrimary)),
              if (isHalf) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.info100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('HALF-DAY',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.teal700)),
                ),
              ],
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Text(status,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: fgColor)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
            '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, yyyy').format(end)}',
            style: AppTextStyles.title),
        Text(
            '${days == 0.5 ? '½' : days.toInt()} working day${days != 1 ? 's' : ''}',
            style: AppTextStyles.body),
        if (reason != null) ...[
          const SizedBox(height: 6),
          Text('Reason: $reason',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.danger800)),
        ],
        if (status == 'pending') ...[
          const SizedBox(height: 12),
          AppButton(
            label: 'Cancel Request',
            outline: true,
            color: AppColors.danger500,
            onPressed: () async {
              final ok = await showConfirmDialog(
                context,
                title: 'Cancel Leave',
                message: 'Are you sure you want to cancel this leave request?',
                isDanger: true,
                confirmLabel: 'Cancel Request',
              );
              if (ok == true) {
                try {
                  await api.cancelLeave(request['id'] as String);
                  onCancel?.call();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ApiFailure.fromError(e).userMessage)));
                  }
                }
              }
            },
          ),
        ],
      ]),
    );
  }
}

// ─── Leave donut ring ────────────────────────────────────
class _LeaveRing extends StatelessWidget {
  final double pct;
  final String value;
  final String label;
  const _LeaveRing(
      {required this.pct, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      height: 90,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(size: const Size(90, 90), painter: _RingPainter(pct: pct)),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(value, style: AppTextStyles.timer),
          Text(label, style: AppTextStyles.caption),
        ]),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double pct;
  const _RingPainter({required this.pct});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 8;

    // Track
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = AppColors.gray200
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );

    // Arc
    if (pct > 0) {
      final sweep = 2 * math.pi * pct.clamp(0.0, 1.0);
      final arcRect = Rect.fromCircle(center: c, radius: r);
      canvas.drawArc(
        arcRect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..color = AppColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.pct != pct;
}

class _BalanceTile extends StatelessWidget {
  final Map<String, dynamic> balance;
  const _BalanceTile({required this.balance});

  /// Caption shown when the org accrues this balance monthly — the API
  /// annotates the row with `accrual: {monthly, carry_over_max}` only when a
  /// policy exists for the leave type, so absence simply means no caption.
  String? _accrualHint() {
    final accrual = balance['accrual'];
    if (accrual is! Map) return null;
    final monthly = (accrual['monthly'] as num?)?.toDouble() ?? 0;
    if (monthly <= 0) return null;
    final carry = (accrual['carry_over_max'] as num?)?.toDouble() ?? 0;
    String fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();
    final base = 'Accrues +${fmt(monthly)} day${monthly == 1 ? '' : 's'}/month';
    if (carry <= 0) return base;
    return '$base · carries over up to ${fmt(carry)} day${carry == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final leaveType = _leaveTypeName(balance['leave_type']);
    final entitled = (balance['entitled_days'] as num?)?.toDouble() ?? 0.0;
    final used = (balance['used_days'] as num?)?.toDouble() ?? 0.0;
    final remaining =
        (balance['remaining_days'] as num?)?.toDouble() ?? (entitled - used);
    final pct = entitled > 0 ? (used / entitled).clamp(0.0, 1.0) : 0.0;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(leaveType.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: AppColors.textPrimary)),
          Text(
              '${remaining % 1 == 0 ? remaining.toInt() : remaining} days left',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary)),
        ]),
        const SizedBox(height: 14),
        Stack(
          children: [
            Container(
              height: 6,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.gray100,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            AnimatedContainer(
              duration: AppMotion.duration,
              curve: AppMotion.curve,
              height: 6,
              width:
                  MediaQuery.of(context).size.width * 0.7 * pct, // approximate
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${used % 1 == 0 ? used.toInt() : used} used',
              style: AppTextStyles.caption),
          Text('of ${entitled % 1 == 0 ? entitled.toInt() : entitled} total',
              style: AppTextStyles.caption),
        ]),
        if (_accrualHint() != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.autorenew_rounded,
                size: 12, color: AppColors.gray400),
            const SizedBox(width: 4),
            Expanded(
                child: Text(_accrualHint()!, style: AppTextStyles.caption)),
          ]),
        ],
      ]),
    );
  }
}
