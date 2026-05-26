import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> with SingleTickerProviderStateMixin {
  late final _tabCtrl = TabController(length: 2, vsync: this);
  List<Map<String, dynamic>> _shifts = [];
  List<Map<String, dynamic>> _swaps  = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final [s, sw] = await Future.wait([api.getMyShifts(), api.getSwapRequests()]);
      setState(() { _shifts = s.cast<Map<String, dynamic>>(); _swaps = sw.cast<Map<String, dynamic>>(); _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.gray50,
    appBar: AppBar(
      title: const Text('My Schedule'),
      bottom: TabBar(
        controller: _tabCtrl,
        labelColor: AppColors.primary600,
        unselectedLabelColor: AppColors.gray500,
        indicatorColor: AppColors.primary600,
        tabs: [
          const Tab(text: 'Upcoming Shifts'),
          Tab(text: 'Swap Requests${_swaps.where((s) => s['status'] == 'pending').isNotEmpty ? ' (${_swaps.where((s) => s['status'] == 'pending').length})' : ''}'),
        ],
      ),
    ),
    body: TabBarView(controller: _tabCtrl, children: [
      // Shifts
      RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _shifts.isEmpty
                ? const EmptyStateWidget(icon: Icons.calendar_today, title: 'No shifts', description: 'Your upcoming shifts will appear here once published.')
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _shifts.length,
                    itemBuilder: (_, i) {
                      final a     = _shifts[i];
                      final shift = a['shift'] as Map? ?? {};
                      final date  = DateTime.parse(a['date'] as String);
                      final isToday = DateFormat('yyyy-MM-dd').format(date) == DateFormat('yyyy-MM-dd').format(DateTime.now());
                      final color = shift['color'] as String? ?? '#1D4ED8';
                      final c     = Color(int.parse(color.replaceFirst('#', '0xFF')));

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppCard(child: Row(children: [
                          Container(width: 4, height: 56, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(shift['name'] as String? ?? 'Shift',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            Text('${shift['start_time'] ?? '--'} – ${shift['end_time'] ?? '--'}',
                                style: const TextStyle(fontSize: 13, color: AppColors.gray500, fontFamily: 'monospace')),
                          ])),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(DateFormat('EEE, d MMM').format(date),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            if (isToday) Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.primary100, borderRadius: BorderRadius.circular(10)),
                              child: const Text('Today', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary600)),
                            ),
                          ]),
                        ])),
                      );
                    },
                  ),
      ),

      // Swaps
      _loading
          ? const Center(child: CircularProgressIndicator())
          : _swaps.isEmpty
              ? const EmptyStateWidget(icon: Icons.swap_horiz, title: 'No swap requests', description: 'Shift swap requests will appear here.')
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _swaps.length,
                  itemBuilder: (_, i) {
                    final sw = _swaps[i];
                    final status = sw['status'] as String? ?? 'pending';
                    final currentUserId = context.read<AuthProvider>().user?.id;
                    final requesterId = (sw['requester'] as Map?)?['id'] as String? ?? sw['requester_id'] as String?;
                    final isRequester = currentUserId != null && currentUserId == requesterId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(isRequester ? 'You requested a swap' : 'Swap request received',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: status == 'approved' ? AppColors.success100 : status == 'rejected' ? AppColors.danger100 : AppColors.warning100,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                color: status == 'approved' ? AppColors.success700 : status == 'rejected' ? AppColors.danger800 : AppColors.warning800)),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Text('With: ${(sw['target'] as Map?)?['name'] ?? '—'}',
                            style: const TextStyle(fontSize: 13, color: AppColors.gray500)),
                        if (sw['rejection_reason'] != null)
                          Text('Reason: ${sw['rejection_reason']}',
                              style: const TextStyle(fontSize: 12, color: AppColors.danger800)),
                      ])),
                    );
                  },
                ),
    ]),
  );
}
