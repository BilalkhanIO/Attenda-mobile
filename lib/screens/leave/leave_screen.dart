import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key});
  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> with SingleTickerProviderStateMixin {
  late final _tabCtrl = TabController(length: 2, vsync: this);
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _balances = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final [reqs, bals] = await Future.wait([api.getMyLeaveRequests(), api.getMyLeaveBalance()]);
      if (!mounted) return;
      setState(() {
        _requests = reqs.cast<Map<String, dynamic>>();
        _balances = bals.cast<Map<String, dynamic>>();
        _loading  = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(
      title: const Text('Leave'),
      actions: [
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
            ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
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
                    itemCount: _requests.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _LeaveRequestTile(request: _requests[i], onCancel: _load),
                    ),
                  ),
      ),
      // Balance tab
      _loading
          ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
          : _balances.isEmpty
              ? const EmptyStateWidget(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'No leave balances',
                  description: 'Your leave allocations will appear here.',
                )
              : Builder(builder: (context) {
                  final totalRemaining = _balances.fold(0.0, (s, b) => s + ((b['remaining_days'] as num?) ?? 0.0));
                  final totalEntitled  = _balances.fold(0.0, (s, b) => s + ((b['entitled_days']  as num?) ?? 0.0));
                  final pct = totalEntitled > 0 ? (totalRemaining / totalEntitled).clamp(0.0, 1.0) : 0.0;
                  final remainingInt = totalRemaining % 1 == 0 ? totalRemaining.toInt().toString() : totalRemaining.toStringAsFixed(1);

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    children: [
                      // ── Balance summary glass card ──
                      GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                        child: Row(children: [
                          _LeaveRing(pct: pct, value: remainingInt, label: 'days'),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('TOTAL REMAINING',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Theme.of(context).colorScheme.primary)),
                              const SizedBox(height: 8),
                              Text(
                                'You have $remainingInt days of leave left for ${DateTime.now().year}.',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary, height: 1.4),
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
    final start  = DateTime.parse(request['start_date'] as String);
    final end    = DateTime.parse(request['end_date']   as String);
    final days   = (request['working_days'] as num?)?.toDouble() ?? 0.0;
    final reason = request['rejection_reason'] as String?;
    final isHalf = request['is_half_day'] as bool? ?? false;

    final statusCfg = <String, (Color, Color)>{
      'pending':   (AppColors.warning500,  AppColors.warning100),
      'approved':  (AppColors.success500,  AppColors.success100),
      'rejected':  (AppColors.danger500,   AppColors.danger100),
      'cancelled': (AppColors.gray400,     AppColors.gray100),
    };
    final (fgColor, bgColor) = statusCfg[status] ?? (AppColors.gray400, AppColors.gray100);

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Row(children: [
              Text(leaveType.toUpperCase(),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.textPrimary)),
              if (isHalf) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.info100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('HALF-DAY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.teal700)),
                ),
              ],
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fgColor)),
          ),
        ]),
        const SizedBox(height: 8),
        Text('${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, yyyy').format(end)}',
            style: AppTextStyles.title),
        Text('${days == 0.5 ? '½' : days.toInt()} working day${days != 1 ? 's' : ''}',
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
  const _LeaveRing({required this.pct, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90, height: 90,
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
      c, r,
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
    final base =
        'Accrues +${fmt(monthly)} day${monthly == 1 ? '' : 's'}/month';
    if (carry <= 0) return base;
    return '$base · carries over up to ${fmt(carry)} day${carry == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final leaveType = _leaveTypeName(balance['leave_type']);
    final entitled  = (balance['entitled_days'] as num?)?.toDouble()  ?? 0.0;
    final used      = (balance['used_days']      as num?)?.toDouble()  ?? 0.0;
    final remaining = (balance['remaining_days'] as num?)?.toDouble()
        ?? (entitled - used);
    final pct       = entitled > 0 ? (used / entitled).clamp(0.0, 1.0) : 0.0;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(leaveType.toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.textPrimary)),
          Text('${remaining % 1 == 0 ? remaining.toInt() : remaining} days left',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
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
              width: MediaQuery.of(context).size.width * 0.7 * pct, // approximate
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
