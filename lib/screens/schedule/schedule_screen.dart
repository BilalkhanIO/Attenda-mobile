import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/api_failure.dart';
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
      if (!mounted) return;
      setState(() {
        _shifts = s.cast<Map<String, dynamic>>();
        _swaps  = sw.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openSwapSheet() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final myUpcoming = _shifts.where((a) {
      final d = DateTime.tryParse(a['date'] as String? ?? '');
      return d != null && !d.isBefore(today);
    }).toList();

    if (myUpcoming.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('You have no upcoming shifts to swap.')));
      return;
    }

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _SwapRequestSheet(myShifts: myUpcoming),
      ),
    );
    if (submitted == true && mounted) _load();
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
      actions: [
        IconButton(
          tooltip: 'Request swap',
          icon: const Icon(Icons.swap_horiz_rounded),
          onPressed: _loading ? null : _openSwapSheet,
        ),
      ],
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
              ? EmptyStateWidget(
                  icon: Icons.swap_horiz,
                  title: 'No swap requests',
                  description: 'Shift swap requests will appear here.',
                  action: AppButton(
                    label: 'Request Swap',
                    icon: Icons.swap_horiz_rounded,
                    fullWidth: false,
                    onPressed: _openSwapSheet,
                  ),
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
                            // Show the OTHER party: target when I requested,
                            // requester when the request was sent to me.
                            'With: ${((isRequester ? sw['target'] : sw['requester']) as Map?)?['name'] ?? '—'}',
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

// ─── Swap request bottom sheet ──────────────────────────
// Lets the employee pick one of their own upcoming shifts and a colleague's
// shift from the org schedule. Employees without shifts.view get a graceful
// fallback note instead of the colleague picker.
class _SwapRequestSheet extends StatefulWidget {
  final List<Map<String, dynamic>> myShifts;
  const _SwapRequestSheet({required this.myShifts});

  @override
  State<_SwapRequestSheet> createState() => _SwapRequestSheetState();
}

class _SwapRequestSheetState extends State<_SwapRequestSheet> {
  final _reasonCtrl = TextEditingController();
  String? _myPickId;
  String? _targetPickId;
  List<Map<String, dynamic>> _candidates = [];
  bool _loadingCandidates = true;
  bool _noPermission = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _myPickId = widget.myShifts.first['id'] as String?;
    _loadCandidates();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    final myId = context.read<AuthProvider>().user?.id;
    final fmt = DateFormat('yyyy-MM-dd');
    final today = DateTime.now();
    try {
      // Two 7-day windows cover the next fortnight of the org schedule.
      final results = await Future.wait([
        api.getOrgSchedule(weekStart: fmt.format(today)),
        api.getOrgSchedule(weekStart: fmt.format(today.add(const Duration(days: 7)))),
      ]);
      final seen = <String>{};
      final list = <Map<String, dynamic>>[];
      for (final batch in results) {
        for (final raw in batch) {
          final a = (raw as Map).cast<String, dynamic>();
          final id = a['id'] as String?;
          final userId = (a['user'] as Map?)?['id'] as String? ?? a['user_id'] as String?;
          if (id == null || userId == null || userId == myId) continue;
          if (!seen.add(id)) continue;
          list.add(a);
        }
      }
      if (!mounted) return;
      setState(() {
        _candidates = list;
        _loadingCandidates = false;
      });
    } catch (e) {
      if (!mounted) return;
      final failure = ApiFailure.fromError(e);
      setState(() {
        _loadingCandidates = false;
        _noPermission = failure is ForbiddenFailure;
        if (!_noPermission) _error = failure.userMessage;
      });
    }
  }

  Future<void> _submit() async {
    Map<String, dynamic>? mine;
    for (final a in widget.myShifts) {
      if (a['id'] == _myPickId) { mine = a; break; }
    }
    Map<String, dynamic>? target;
    for (final a in _candidates) {
      if (a['id'] == _targetPickId) { target = a; break; }
    }
    if (mine == null || target == null) return;

    setState(() { _submitting = true; _error = null; });
    try {
      await api.requestSwap({
        'target_id': (target['user'] as Map?)?['id'] ?? target['user_id'],
        'requester_assign_id': mine['id'],
        'target_assign_id': target['id'],
        if (_reasonCtrl.text.trim().isNotEmpty) 'reason': _reasonCtrl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Swap request sent for approval')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = ApiFailure.fromError(e).userMessage;
      });
    }
  }

  String _myShiftLabel(Map<String, dynamic> a) {
    final shift = (a['shift'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final date = DateTime.tryParse(a['date'] as String? ?? '');
    final day = date != null ? DateFormat('EEE, d MMM').format(date) : '—';
    return '$day · ${shift['name'] ?? 'Shift'} (${shift['start_time'] ?? '--'}–${shift['end_time'] ?? '--'})';
  }

  String _candidateLabel(Map<String, dynamic> a) {
    final name = (a['user'] as Map?)?['name'] as String? ?? 'Colleague';
    return '$name · ${_myShiftLabel(a)}';
  }

  Widget _sectionLabel(String text) => Text(text,
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
          color: Colors.white.withValues(alpha: 0.45)));

  Widget _dropdown({
    required String? value,
    required List<Map<String, dynamic>> options,
    required String Function(Map<String, dynamic>) label,
    required ValueChanged<String?> onChanged,
    required String hint,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: AppColors.bgDark3,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      hint: Text(hint,
          style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4))),
      items: options
          .map((a) => DropdownMenuItem<String>(
                value: a['id'] as String?,
                child: Text(label(a), overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: _submitting ? null : onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: GlassCard(
        borderRadius: 24,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Request a Shift Swap',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 6),
              Text('Pick your shift and the colleague\'s shift you want to trade. Your manager approves the swap.',
                  style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6))),
              const SizedBox(height: 18),

              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.danger500.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.danger500.withValues(alpha: 0.4)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(fontSize: 13, color: AppColors.danger500)),
                ),
              ],

              _sectionLabel('YOUR SHIFT'),
              const SizedBox(height: 8),
              _dropdown(
                value: _myPickId,
                options: widget.myShifts,
                label: _myShiftLabel,
                onChanged: (v) => setState(() => _myPickId = v),
                hint: 'Select your shift',
              ),
              const SizedBox(height: 18),

              _sectionLabel("COLLEAGUE'S SHIFT"),
              const SizedBox(height: 8),
              if (_loadingCandidates)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                      child: SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary600))),
                )
              else if (_noPermission)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.lock_outline, size: 16, color: AppColors.warning500),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your account can\'t browse the team schedule, so a colleague can\'t be picked here. '
                        'Ask your manager to arrange the swap — they can set it up from the schedule.',
                        style: TextStyle(fontSize: 12, height: 1.4, color: Colors.white.withValues(alpha: 0.65)),
                      ),
                    ),
                  ]),
                )
              else if (_candidates.isEmpty)
                Text('No teammate shifts found in the next two weeks.',
                    style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5)))
              else
                _dropdown(
                  value: _targetPickId,
                  options: _candidates,
                  label: _candidateLabel,
                  onChanged: (v) => setState(() => _targetPickId = v),
                  hint: 'Select a colleague\'s shift',
                ),
              const SizedBox(height: 18),

              _sectionLabel('REASON (OPTIONAL)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _reasonCtrl,
                maxLines: 2,
                maxLength: 200,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                    hintText: 'Why do you need this swap?', counterText: ''),
              ),
              const SizedBox(height: 16),
              AppButton(
                label: 'Submit Swap Request',
                icon: Icons.swap_horiz_rounded,
                loading: _submitting,
                onPressed: (_myPickId != null && _targetPickId != null && !_submitting)
                    ? _submit
                    : null,
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}
