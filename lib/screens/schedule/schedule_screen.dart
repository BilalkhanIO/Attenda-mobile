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
      setState(() {
        _shifts = s.cast<Map<String, dynamic>>();
        _swaps  = sw.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  Map<String, List<Map<String, dynamic>>> _groupShifts(List<Map<String, dynamic>> shifts) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final groups = <String, List<Map<String, dynamic>>>{'Today': [], 'This Week': [], 'Later': []};
    for (final s in shifts) {
      final date = DateTime.parse(s['date'] as String);
      final diff = date.difference(today).inDays;
      if (diff <= 0) {
        groups['Today']!.add(s);
      } else if (diff <= 7) {
        groups['This Week']!.add(s);
      } else {
        groups['Later']!.add(s);
      }
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(
      title: const Text('My Schedule'),
      bottom: TabBar(
        controller: _tabCtrl,
        tabs: [
          const Tab(text: 'Upcoming Shifts'),
          Tab(text: 'Swap Requests${_swaps.where((s) => s['status'] == 'pending').isNotEmpty ? ' (${_swaps.where((s) => s['status'] == 'pending').length})' : ''}'),
        ],
      ),
    ),
    body: TabBarView(controller: _tabCtrl, children: [
      // Shifts
      RefreshIndicator(
        color: AppColors.primary600,
        backgroundColor: AppColors.bgDark3,
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary600))
            : _shifts.isEmpty
                ? const EmptyStateWidget(
                    icon: Icons.calendar_today,
                    title: 'No shifts',
                    description: 'Your upcoming shifts will appear here once published.',
                  )
                : Builder(builder: (context) {
                    final groups = _groupShifts(_shifts);
                    final groupOrder = ['Today', 'This Week', 'Later'];
                    final items = <Widget>[];

                    for (final groupName in groupOrder) {
                      final groupShifts = groups[groupName]!;
                      if (groupShifts.isEmpty) continue;

                      items.add(Padding(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                        child: Text(
                          groupName.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                        ),
                      ));

                      for (final a in groupShifts) {
                        final shift    = (a['shift'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
                        final date     = DateTime.parse(a['date'] as String);
                        final isToday  = groupName == 'Today';
                        final c = parseHexColor(shift['color'] as String?,
                            fallback: const Color(0xFF00C896));

                        items.add(Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            child: Row(children: [
                              Container(
                                width: 4, height: 56,
                                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(shift['name'] as String? ?? 'Shift',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                                Text('${shift['start_time'] ?? '--'} – ${shift['end_time'] ?? '--'}',
                                    style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.55), fontFamily: 'monospace')),
                              ])),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text(DateFormat('EEE, d MMM').format(date),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                                if (isToday) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary600.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.primary600.withValues(alpha: 0.4)),
                                    ),
                                    child: const Text('TODAY',
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.primary600, letterSpacing: 0.8)),
                                  ),
                                ],
                              ]),
                            ]),
                          ),
                        ));
                      }
                    }

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                      children: items,
                    );
                  }),
      ),

      // Swaps
      _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary600))
          : _swaps.isEmpty
              ? const EmptyStateWidget(
                  icon: Icons.swap_horiz,
                  title: 'No swap requests',
                  description: 'Shift swap requests will appear here.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                  itemCount: _swaps.length,
                  itemBuilder: (_, i) {
                    final sw     = _swaps[i];
                    final status = sw['status'] as String? ?? 'pending';
                    final currentUserId = context.read<AuthProvider>().user?.id;
                    final requesterId = (sw['requester'] as Map?)?['id'] as String?
                        ?? sw['requester_id'] as String?;
                    final isRequester = currentUserId != null && currentUserId == requesterId;

                    Color statusColor;
                    Color statusBg;
                    switch (status) {
                      case 'approved': statusColor = AppColors.success500; statusBg = AppColors.success100; break;
                      case 'rejected': statusColor = AppColors.danger500;  statusBg = AppColors.danger100;  break;
                      default:         statusColor = AppColors.warning500; statusBg = AppColors.warning100;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text(
                              isRequester ? 'You requested a swap' : 'Swap request received',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(20)),
                              child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          Text(
                            'With: ${(sw['target'] as Map?)?['name'] ?? '—'}',
                            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.55)),
                          ),
                          if (sw['rejection_reason'] != null) ...[
                            const SizedBox(height: 4),
                            Text('Reason: ${sw['rejection_reason']}',
                                style: const TextStyle(fontSize: 12, color: AppColors.danger500)),
                          ],
                        ]),
                      ),
                    );
                  },
                ),
    ]),
  );
}
