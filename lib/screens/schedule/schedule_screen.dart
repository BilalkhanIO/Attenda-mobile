import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
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

class _ScheduleScreenState extends State<ScheduleScreen>
    with SingleTickerProviderStateMixin {
  late final _tabCtrl = TabController(length: 2, vsync: this);
  List<Map<String, dynamic>> _shifts = [];
  List<Map<String, dynamic>> _swaps = [];
  bool _loading = true;
  // First-load failure — drives the error + Retry state. Reloads with data
  // already on screen fail silently and keep the last good lists.
  String? _error;
  String _shiftSearch = '';
  String _swapSearch = '';
  String? _ackSubmittingId;

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
      final results =
          await Future.wait([api.getMyShifts(), api.getSwapRequests()]);
      if (!mounted) return;
      setState(() {
        _shifts = results[0].cast<Map<String, dynamic>>();
        _swaps = results[1].cast<Map<String, dynamic>>();
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_shifts.isEmpty && _swaps.isEmpty) {
          _error = ApiFailure.fromError(e).userMessage;
        }
        _loading = false;
      });
    }
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

  Future<void> _acknowledgeShift(
    Map<String, dynamic> assignment,
    String status,
  ) async {
    final assignmentId = assignment['id'] as String?;
    if (assignmentId == null || _ackSubmittingId != null) return;
    String? note;
    if (status != 'acknowledged') {
      final controller = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(status == 'conflict'
              ? 'Flag a shift conflict'
              : 'Request shift help'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Tell your manager what you need',
              hintText: 'Add at least 5 characters',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  final value = controller.text.trim();
                  if (value.length < 5) return;
                  Navigator.pop(dialogContext, value);
                },
                child: const Text('Send')),
          ],
        ),
      );
      controller.dispose();
      if (result == null) return;
      note = result;
    }
    setState(() => _ackSubmittingId = assignmentId);
    try {
      await api.acknowledgeMyShift(assignmentId, status: status, note: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(status == 'acknowledged'
            ? 'Shift confirmed'
            : status == 'conflict'
                ? 'Conflict sent to your manager'
                : 'Help request sent to your manager'),
      ));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiFailure.fromError(error).userMessage)));
    } finally {
      if (mounted) setState(() => _ackSubmittingId = null);
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupShifts(
      List<Map<String, dynamic>> shifts) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final groups = <String, List<Map<String, dynamic>>>{
      'Today': [],
      'This Week': [],
      'Later': []
    };
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

  bool _matchesShift(Map<String, dynamic> assignment) {
    final query = _shiftSearch.trim().toLowerCase();
    if (query.isEmpty) return true;
    final shift = (assignment['shift'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return '${shift['name'] ?? ''} ${shift['start_time'] ?? ''} ${shift['end_time'] ?? ''} ${assignment['date'] ?? ''}'
        .toLowerCase()
        .contains(query);
  }

  bool _matchesSwap(Map<String, dynamic> swap) {
    final query = _swapSearch.trim().toLowerCase();
    if (query.isEmpty) return true;
    final requester = (swap['requester'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final target = (swap['target'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return '${requester['name'] ?? ''} ${target['name'] ?? ''} ${swap['status'] ?? ''} ${swap['reason'] ?? ''}'
        .toLowerCase()
        .contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('My Schedule'),
        actions: [
          IconButton(
              tooltip: 'Emergency shifts',
              icon: const Icon(Icons.add_alert_outlined),
              onPressed: () => context.push('/schedule/open-shifts')),
          IconButton(
              tooltip: 'My availability',
              icon: const Icon(Icons.event_available_rounded),
              onPressed: () => context.push('/schedule/availability')),
          if (auth.hasPermission('shifts.assign'))
            IconButton(
                tooltip: 'Team schedule',
                icon: const Icon(Icons.groups_rounded),
                onPressed: () => context.push('/schedule/manage')),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              tooltip: 'Request swap',
              style: IconButton.styleFrom(
                backgroundColor: primary.withValues(alpha: 0.08),
                foregroundColor: primary,
              ),
              icon: const Icon(Icons.swap_horiz_rounded),
              onPressed: _loading ? null : _openSwapSheet,
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            const Tab(text: 'Upcoming Shifts'),
            Tab(
                text:
                    'Swap Requests${_swaps.where((s) => s["status"] == "pending").isNotEmpty ? " (${_swaps.where((s) => s["status"] == "pending").length})" : ""}'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabCtrl, children: [
        // Shifts
        RefreshIndicator(
          color: primary,
          backgroundColor: AppColors.surface,
          onRefresh: _load,
          child: _loading
              ? Center(child: CircularProgressIndicator(color: primary))
              : _error != null
                  ? _errorState()
                  : _shifts.isEmpty
                      ? const EmptyStateWidget(
                          icon: Icons.calendar_today,
                          title: 'No shifts',
                          description:
                              'Your upcoming shifts will appear here once published.',
                        )
                      : Builder(builder: (context) {
                          final matchingShifts =
                              _shifts.where(_matchesShift).toList();
                          final groups = _groupShifts(matchingShifts);
                          final groupOrder = ['Today', 'This Week', 'Later'];
                          final items = <Widget>[];
                          items.add(Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TextField(
                              onChanged: (value) =>
                                  setState(() => _shiftSearch = value),
                              decoration: InputDecoration(
                                hintText: 'Search shifts or dates',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _shiftSearch.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Clear search',
                                        icon: const Icon(Icons.close_rounded),
                                        onPressed: () =>
                                            setState(() => _shiftSearch = ''),
                                      ),
                              ),
                            ),
                          ));
                          if (matchingShifts.isEmpty) {
                            items.add(Padding(
                              padding: const EdgeInsets.only(top: 48),
                              child: EmptyStateWidget(
                                icon: Icons.search_off_rounded,
                                title: 'No matching shifts',
                                description: 'Try another shift name or date.',
                              ),
                            ));
                          }

                          for (final groupName in groupOrder) {
                            final groupShifts = groups[groupName]!;
                            if (groupShifts.isEmpty) continue;

                            items.add(Padding(
                              padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                              child: Text(
                                groupName.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.4,
                                  color: AppColors.gray500,
                                ),
                              ),
                            ));

                            for (final a in groupShifts) {
                              final shift = (a['shift'] as Map?)
                                      ?.cast<String, dynamic>() ??
                                  <String, dynamic>{};
                              final date = DateTime.parse(a['date'] as String);
                              final isToday = groupName == 'Today';
                              final c =
                                  parseHexColor(shift['color'] as String?);
                              final ackStatus =
                                  a['acknowledgement_status'] as String? ??
                                      'not_required';
                              final ackDueAt = DateTime.tryParse(
                                  a['acknowledgement_due_at'] as String? ?? '');

                              items.add(Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: GlassCard(
                                  child: Row(children: [
                                    Container(
                                      width: 4,
                                      height: 56,
                                      decoration: BoxDecoration(
                                          color: c,
                                          borderRadius:
                                              BorderRadius.circular(2)),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(
                                              shift['name'] as String? ??
                                                  'Shift',
                                              style: AppTextStyles.title),
                                          Text(
                                              '${shift["start_time"] ?? "--"} – ${shift["end_time"] ?? "--"}',
                                              style: AppTextStyles.body
                                                  .copyWith(fontFeatures: [
                                                FontFeature.tabularFigures()
                                              ])),
                                          if ((shift['checkpoints'] as List?)
                                                  ?.isNotEmpty ==
                                              true) ...[
                                            const SizedBox(height: 3),
                                            if (isToday)
                                              TextButton.icon(
                                                style: TextButton.styleFrom(
                                                  minimumSize:
                                                      const Size(0, 36),
                                                  padding: EdgeInsets.zero,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                                onPressed: () => context.push(
                                                  '/schedule/rounds?assignmentId=${Uri.encodeComponent(a['id'] as String)}',
                                                ),
                                                icon: const Icon(
                                                    Icons.shield_outlined,
                                                    size: 15),
                                                label: const Text(
                                                    'Safety checkpoints'),
                                              )
                                            else
                                              Text(
                                                date.isAfter(DateTime.now())
                                                    ? 'Available on shift day'
                                                    : 'Shift day has passed',
                                                style: AppTextStyles.caption,
                                              ),
                                          ],
                                          if (a['is_published'] == true &&
                                              ackStatus != 'not_required') ...[
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 4,
                                              runSpacing: 2,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                Text(
                                                  ackStatus == 'pending' &&
                                                          ackDueAt != null &&
                                                          DateTime.now()
                                                              .isAfter(ackDueAt)
                                                      ? 'Response overdue'
                                                      : ackStatus == 'pending'
                                                          ? 'Please respond within 24 hours'
                                                          : ackStatus ==
                                                                  'acknowledged'
                                                              ? 'Shift confirmed'
                                                              : ackStatus ==
                                                                      'conflict'
                                                                  ? 'Conflict reported'
                                                                  : 'Help requested',
                                                  style: AppTextStyles.caption
                                                      .copyWith(
                                                          color: ackStatus ==
                                                                      'conflict' ||
                                                                  ackStatus ==
                                                                      'help_requested'
                                                              ? Colors.orange
                                                                  .shade300
                                                              : primary),
                                                ),
                                                TextButton(
                                                  onPressed: _ackSubmittingId ==
                                                          a['id']
                                                      ? null
                                                      : () => _acknowledgeShift(
                                                          a, 'acknowledged'),
                                                  child: const Text('Confirm'),
                                                ),
                                                TextButton(
                                                  onPressed: _ackSubmittingId ==
                                                          a['id']
                                                      ? null
                                                      : () => _acknowledgeShift(
                                                          a, 'conflict'),
                                                  child: const Text('Conflict'),
                                                ),
                                                TextButton(
                                                  onPressed: _ackSubmittingId ==
                                                          a['id']
                                                      ? null
                                                      : () => _acknowledgeShift(
                                                          a, 'help_requested'),
                                                  child: Text(
                                                      _ackSubmittingId ==
                                                              a['id']
                                                          ? 'Sending…'
                                                          : 'Get help'),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ])),
                                    Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                              DateFormat('EEE, d MMM')
                                                  .format(date),
                                              style: AppTextStyles.bodyStrong),
                                          if (isToday) ...[
                                            const SizedBox(height: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: primary.withValues(
                                                    alpha: 0.10),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text('TODAY',
                                                  style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: primary,
                                                      letterSpacing: 0.8)),
                                            ),
                                          ],
                                        ]),
                                  ]),
                                ),
                              ));
                            }
                          }

                          return ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                            children: items,
                          );
                        }),
        ),

        // Swaps
        _loading
            ? Center(child: CircularProgressIndicator(color: primary))
            : _error != null
                ? _errorState()
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
                    : Builder(builder: (context) {
                        final matchingSwaps =
                            _swaps.where(_matchesSwap).toList();
                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: matchingSwaps.length + 1,
                          itemBuilder: (_, i) {
                            if (i == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: TextField(
                                  onChanged: (value) =>
                                      setState(() => _swapSearch = value),
                                  decoration: InputDecoration(
                                    hintText:
                                        'Search people, status, or reason',
                                    prefixIcon:
                                        const Icon(Icons.search_rounded),
                                    suffixIcon: _swapSearch.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Clear search',
                                            icon:
                                                const Icon(Icons.close_rounded),
                                            onPressed: () => setState(
                                                () => _swapSearch = ''),
                                          ),
                                  ),
                                ),
                              );
                            }
                            if (matchingSwaps.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 48),
                                child: EmptyStateWidget(
                                    icon: Icons.search_off_rounded,
                                    title: 'No matching requests',
                                    description:
                                        'Try another name, status, or reason.'),
                              );
                            }
                            final sw = matchingSwaps[i - 1];
                            final status = sw['status'] as String? ?? 'pending';
                            final currentUserId =
                                context.read<AuthProvider>().user?.id;
                            final requesterId =
                                (sw['requester'] as Map?)?['id'] as String? ??
                                    sw['requester_id'] as String?;
                            final isRequester = currentUserId != null &&
                                currentUserId == requesterId;

                            Color statusColor;
                            Color statusBg;
                            switch (status) {
                              case 'approved':
                                statusColor = AppColors.success500;
                                statusBg = AppColors.success100;
                                break;
                              case 'rejected':
                                statusColor = AppColors.danger500;
                                statusBg = AppColors.danger100;
                                break;
                              default:
                                statusColor = AppColors.warning500;
                                statusBg = AppColors.warning100;
                            }

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: GlassCard(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              isRequester
                                                  ? 'You requested a swap'
                                                  : 'Swap request received',
                                              style: AppTextStyles.bodyStrong,
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                  color: statusBg,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          AppRadius.control)),
                                              child: Text(status,
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: statusColor)),
                                            ),
                                          ]),
                                      const SizedBox(height: 6),
                                      Text(
                                        // Show the OTHER party: target when I requested,
                                        // requester when the request was sent to me.
                                        'With: ${((isRequester ? sw["target"] : sw["requester"]) as Map?)?["name"] ?? "—"}',
                                        style: AppTextStyles.body,
                                      ),
                                      if (sw['rejection_reason'] != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                            'Reason: ${sw["rejection_reason"]}',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                                color: AppColors.danger800)),
                                      ],
                                    ]),
                              ),
                            );
                          },
                        );
                      }),
      ]),
    );
  }
}

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
    _myPickId = widget.myShifts.isNotEmpty
        ? widget.myShifts.first['id'] as String?
        : null;
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
      final results = await Future.wait([
        api.getOrgSchedule(weekStart: fmt.format(today)),
        api.getOrgSchedule(
            weekStart: fmt.format(today.add(const Duration(days: 7)))),
      ]);
      final seen = <String>{};
      final list = <Map<String, dynamic>>[];
      for (final batch in results) {
        for (final raw in batch) {
          final a = (raw as Map).cast<String, dynamic>();
          final id = a['id'] as String?;
          final userId =
              (a['user'] as Map?)?['id'] as String? ?? a['user_id'] as String?;
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
      if (a['id'] == _myPickId) {
        mine = a;
        break;
      }
    }
    Map<String, dynamic>? target;
    for (final a in _candidates) {
      if (a['id'] == _targetPickId) {
        target = a;
        break;
      }
    }
    if (mine == null || target == null) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await api.requestSwap({
        'target_id': (target['user'] as Map?)?['id'] ?? target['user_id'],
        'requester_assign_id': mine['id'],
        'target_assign_id': target['id'],
        if (_reasonCtrl.text.trim().isNotEmpty)
          'reason': _reasonCtrl.text.trim(),
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
    final shift = (a['shift'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final date = DateTime.tryParse(a['date'] as String? ?? "");
    final day = date != null ? DateFormat('EEE, d MMM').format(date) : "—";
    return "$day · ${shift['name'] ?? 'Shift'} (${shift['start_time'] ?? '--'}–${shift['end_time'] ?? '--'})";
  }

  String _candidateLabel(Map<String, dynamic> a) {
    final name = (a['user'] as Map?)?['name'] as String? ?? "Colleague";
    return "$name · ${_myShiftLabel(a)}";
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: AppColors.gray500));

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
      dropdownColor: AppColors.surface,
      style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500),
      hint: Text(hint,
          style: const TextStyle(fontSize: 13, color: AppColors.gray400)),
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
    final primary = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: GlassCard(
        borderRadius: AppRadius.card,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Request a Shift Swap', style: AppTextStyles.headline),
              const SizedBox(height: 6),
              const Text(
                  'Pick your shift and the colleague\'s shift you want to trade. Your manager approves the swap.',
                  style: AppTextStyles.body),
              const SizedBox(height: 18),
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.danger500.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.danger800)),
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
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: primary))),
                )
              else if (_noPermission)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.gray100,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline,
                            size: 16, color: AppColors.warning500),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your account can\'t browse the team schedule, so a colleague can\'t be picked here. '
                            'Ask your manager to arrange the swap — they can set it up from the schedule.',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                height: 1.4,
                                color: AppColors.gray600),
                          ),
                        ),
                      ]),
                )
              else if (_candidates.isEmpty)
                const Text('No teammate shifts found in the next two weeks.',
                    style: AppTextStyles.body)
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
                style:
                    const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: const InputDecoration(
                    hintText: 'Why do you need this swap?', counterText: ''),
              ),
              const SizedBox(height: 16),
              AppButton(
                label: 'Submit Swap Request',
                icon: Icons.swap_horiz_rounded,
                loading: _submitting,
                onPressed:
                    (_myPickId != null && _targetPickId != null && !_submitting)
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
