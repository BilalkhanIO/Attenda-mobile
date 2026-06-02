import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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
      setState(() {
        _requests = reqs.cast<Map<String, dynamic>>();
        _balances = bals.cast<Map<String, dynamic>>();
        _loading  = false;
      });
    } catch (_) { setState(() => _loading = false); }
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
        color: AppColors.primary600,
        backgroundColor: AppColors.bgDark3,
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary600))
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
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                    itemCount: _requests.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _LeaveRequestTile(request: _requests[i], onCancel: _load),
                    ),
                  ),
      ),
      // Balance tab
      _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary600))
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
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                    children: [
                      // ── Balance summary glass card ──
                      GlassCard(
                        tint: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                        child: Row(children: [
                          _LeaveRing(pct: pct, value: remainingInt, label: 'days'),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('TOTAL REMAINING',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Colors.white.withOpacity(0.55))),
                              const SizedBox(height: 6),
                              Text(
                                'You have $remainingInt days of leave left across all types this year.',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white, height: 1.4),
                              ),
                            ]),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      ..._balances.map((b) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _BalanceTile(balance: b),
                      )),
                    ],
                  );
                }),
    ]),
  );
}

class _LeaveRequestTile extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback? onCancel;
  const _LeaveRequestTile({required this.request, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final status = request['status'] as String? ?? 'pending';
    final leaveType = (request['leave_type'] as Map?)?['name'] as String?
        ?? request['leave_type'] as String?
        ?? 'Leave';
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
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: Colors.white)),
              if (isHalf) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.teal100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('HALF-DAY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.teal700)),
                ),
              ],
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
            child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fgColor)),
          ),
        ]),
        const SizedBox(height: 8),
        Text('${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, yyyy').format(end)}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
        Text('${days == 0.5 ? '½' : days.toInt()} working day${days != 1 ? 's' : ''}',
            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.55))),
        if (reason != null) ...[
          const SizedBox(height: 6),
          Text('Reason: $reason', style: const TextStyle(fontSize: 12, color: AppColors.danger500)),
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
                await api.cancelLeave(request['id'] as String);
                onCancel?.call();
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
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
          Text(label, style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.5))),
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
        ..color = Colors.white.withOpacity(0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );

    // Arc
    if (pct > 0) {
      final sweep = 2 * math.pi * pct.clamp(0.0, 1.0);
      final arcRect = Rect.fromCircle(center: c, radius: r);
      final grad = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + sweep,
        colors: const [Color(0xFF00C896), Color(0xFF00E5FF)],
      );
      canvas.drawArc(
        arcRect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..shader = grad.createShader(arcRect)
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

  @override
  Widget build(BuildContext context) {
    final leaveType = (balance['leave_type'] as Map?)?['name'] as String?
        ?? balance['leave_type'] as String?
        ?? 'Leave';
    final entitled  = (balance['entitled_days'] as num?)?.toDouble()  ?? 0.0;
    final used      = (balance['used_days']      as num?)?.toDouble()  ?? 0.0;
    final remaining = (balance['remaining_days'] as num?)?.toDouble()
        ?? (entitled - used);
    final pct       = entitled > 0 ? (used / entitled).clamp(0.0, 1.0) : 0.0;

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(leaveType.toUpperCase(),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: Colors.white)),
          Text('${remaining % 1 == 0 ? remaining.toInt() : remaining} days left',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary600)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: Colors.white.withOpacity(0.12),
            valueColor: AlwaysStoppedAnimation(pct > 0.8 ? AppColors.danger500 : AppColors.primary600),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 6),
        Text('${used % 1 == 0 ? used.toInt() : used} used of ${entitled % 1 == 0 ? entitled.toInt() : entitled} days',
            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.55))),
      ]),
    );
  }
}
