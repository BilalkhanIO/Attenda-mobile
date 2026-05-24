// Leave Screen
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
  List<Map<String, dynamic>> _requests  = [];
  List<Map<String, dynamic>> _balances  = [];
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
    backgroundColor: AppColors.gray50,
    appBar: AppBar(
      title: const Text('Leave'),
      actions: [
        IconButton(icon: const Icon(Icons.add), onPressed: () async {
          await context.push('/leave/request');
          _load();
        }),
      ],
      bottom: TabBar(
        controller: _tabCtrl,
        labelColor: AppColors.primary600,
        unselectedLabelColor: AppColors.gray500,
        indicatorColor: AppColors.primary600,
        tabs: const [Tab(text: 'Requests'), Tab(text: 'Balance')],
      ),
    ),
    body: TabBarView(controller: _tabCtrl, children: [
      // Requests
      RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _requests.isEmpty
                ? EmptyStateWidget(icon: Icons.beach_access, title: 'No leave requests', description: 'Submit your first leave request.', action: AppButton(label: 'Request Leave', onPressed: () => context.push('/leave/request'), fullWidth: false))
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _requests.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _LeaveRequestTile(request: _requests[i], onCancel: _load),
                    ),
                  ),
      ),
      // Balance
      _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: _balances.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _BalanceTile(balance: b),
              )).toList(),
            ),
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
    final type   = request['leave_type'] as String? ?? 'leave';
    final start  = DateTime.parse(request['start_date'] as String);
    final end    = DateTime.parse(request['end_date']   as String);
    final days   = request['working_days'] as int? ?? 0;
    final reason = request['rejection_reason'] as String?;

    final statusColors = <String, (Color, Color)>{
      'pending':   (AppColors.warning800, AppColors.warning100),
      'approved':  (AppColors.success700, AppColors.success100),
      'rejected':  (AppColors.danger800,  AppColors.danger100),
      'cancelled': (AppColors.gray500,    AppColors.gray100),
    };
    final (fgColor, bgColor) = statusColors[status] ?? (AppColors.gray500, AppColors.gray100);

    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(type.toUpperCase(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
          child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fgColor)),
        ),
      ]),
      const SizedBox(height: 8),
      Text('${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, yyyy').format(end)}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.dark950)),
      Text('$days working day${days != 1 ? 's' : ''}',
          style: const TextStyle(fontSize: 13, color: AppColors.gray500)),
      if (reason != null) ...[
        const SizedBox(height: 6),
        Text('Reason: $reason', style: const TextStyle(fontSize: 12, color: AppColors.danger800)),
      ],
      if (status == 'pending') ...[
        const SizedBox(height: 12),
        AppButton(
          label: 'Cancel Request',
          outline: true,
          color: AppColors.danger500,
          onPressed: () async {
            final ok = await showConfirmDialog(context, title: 'Cancel Leave', message: 'Are you sure you want to cancel this leave request?', isDanger: true, confirmLabel: 'Cancel Request');
            if (ok == true) {
              await api.cancelLeave(request['id'] as String);
              onCancel?.call();
            }
          },
        ),
      ],
    ]));
  }
}

class _BalanceTile extends StatelessWidget {
  final Map<String, dynamic> balance;
  const _BalanceTile({required this.balance});

  @override
  Widget build(BuildContext context) {
    final type      = balance['leave_type'] as String? ?? 'leave';
    final total     = balance['total_days'] as int? ?? 0;
    final used      = balance['used_days']  as int? ?? 0;
    final remaining = total - used;
    final pct       = total > 0 ? used / total : 0.0;

    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(type.replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        Text('$remaining days left', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary600)),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: pct.clamp(0.0, 1.0),
          backgroundColor: AppColors.gray100,
          valueColor: AlwaysStoppedAnimation(pct > 0.8 ? AppColors.danger500 : AppColors.primary600),
          minHeight: 6,
        ),
      ),
      const SizedBox(height: 6),
      Text('$used used of $total days', style: const TextStyle(fontSize: 12, color: AppColors.gray500)),
    ]));
  }
}
