import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

// Backend serializes Decimal fields (hours_worked, net_hours_worked) as strings
// and Int fields as numbers — parse defensively for either.
double? _asDouble(dynamic v) => v == null
    ? null
    : v is num
        ? v.toDouble()
        : double.tryParse(v.toString());
int? _asInt(dynamic v) => v == null
    ? null
    : v is num
        ? v.toInt()
        : int.tryParse(v.toString());

DateTime? _parseDateTime(dynamic v) {
  if (v == null) return null;
  try {
    return DateTime.parse(v.toString()).toLocal();
  } catch (_) {
    return null;
  }
}

int _totalBreakMinutes(Map<String, dynamic> record) {
  final breaks = (record['break_records'] as List?)
          ?.cast<Map<String, dynamic>>() ??
      const <Map<String, dynamic>>[];
  if (breaks.isEmpty) return _asInt(record['break_minutes']) ?? 0;

  var total = 0;
  final now = DateTime.now();
  for (final b in breaks) {
    final stored = _asInt(b['duration_mins']);
    if (stored != null) {
      total += stored;
      continue;
    }
    final start = _parseDateTime(b['break_start']);
    if (start == null) continue;
    final end = _parseDateTime(b['break_end']) ?? now;
    if (end.isAfter(start)) {
      total += end.difference(start).inMinutes;
    }
  }
  return total;
}

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<Map<String, dynamic>> _records = [];
  // Existing overtime requests keyed by attendance_id, so records show their
  // request status instead of offering a duplicate "Request overtime" action.
  Map<String, Map<String, dynamic>> _overtimeByAttendance = {};
  bool _loading = true;
  DateTime _selectedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 186 days ≈ 6 months, matching the 6-entry month selector below so older
      // months aren't shown empty for lack of fetched data.
      final results = await Future.wait([
        api.getMyAttendance(days: 186),
        // Overtime is optional server-side; ignore failures quietly.
        api.getMyOvertimeRequests().catchError((_) => <dynamic>[]),
      ]);
      if (!mounted) return;
      final overtime = <String, Map<String, dynamic>>{};
      for (final raw in results[1]) {
        final req = (raw as Map).cast<String, dynamic>();
        final attendanceId = req['attendance_id'] as String?;
        if (attendanceId != null) overtime[attendanceId] = req;
      }
      setState(() {
        _records = results[0].cast<Map<String, dynamic>>();
        _overtimeByAttendance = overtime;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestOvertime(Map<String, dynamic> record) async {
    final extra = _asInt(record['extra_office_minutes']) ?? 0;
    final ok = await showConfirmDialog(
      context,
      title: 'Request Overtime',
      message:
          'Ask your manager to approve ${extra}m of extra office time as paid overtime?',
      confirmLabel: 'Request',
    );
    if (ok != true || !mounted) return;
    try {
      await api.requestOvertime(
        attendanceId: record['id'] as String,
        reason: 'Worked ${extra}m beyond shift end',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Overtime request sent for approval')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiFailure.fromError(e).userMessage)));
    }
  }

  List<Map<String, dynamic>> get _monthRecords {
    return _records.where((r) {
      final date = DateTime.parse(r['date'] as String);
      return date.month == _selectedMonth.month &&
          date.year == _selectedMonth.year;
    }).toList()
      ..sort((a, b) => DateTime.parse(b['date'] as String)
          .compareTo(DateTime.parse(a['date'] as String)));
  }

  Map<String, int> get _summary {
    final mr = _monthRecords;
    return {
      'present':
          mr.where((r) => ['in', 'out', 'late'].contains(r['status'])).length,
      'late': mr.where((r) => r['status'] == 'late').length,
      'absent': mr.where((r) => r['status'] == 'absent').length,
      'remote': mr.where((r) => r['status'] == 'remote').length,
    };
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('My Attendance'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)
        ],
      ),
      body: RefreshIndicator(
        color: primary,
        backgroundColor: AppColors.surface,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Month selector
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 6,
                  itemBuilder: (_, i) {
                    final m =
                        DateTime(DateTime.now().year, DateTime.now().month - i);
                    final selected = m.month == _selectedMonth.month &&
                        m.year == _selectedMonth.year;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedMonth = m),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: selected ? primary : AppColors.surface,
                            borderRadius:
                                BorderRadius.circular(AppRadius.control),
                            border: selected
                                ? null
                                : Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            DateFormat('MMM yyyy').format(m),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selected
                                  ? Colors.white
                                  : AppColors.gray600,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Summary chips
              if (!_loading) ...[
                Row(children: [
                  Expanded(
                      child: KpiChip(
                          label: 'Present',
                          value: '${_summary['present']}',
                          color: AppColors.success500,
                          compact: true)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: KpiChip(
                          label: 'Late',
                          value: '${_summary['late']}',
                          color: AppColors.warning500,
                          compact: true)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: KpiChip(
                          label: 'Absent',
                          value: '${_summary['absent']}',
                          color: AppColors.danger500,
                          compact: true)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: KpiChip(
                          label: 'Remote',
                          value: '${_summary['remote']}',
                          color: AppColors.info500,
                          compact: true)),
                ]),
                const SizedBox(height: 24),
              ],

              const SectionHeader(title: 'Records'),
              const SizedBox(height: 12),

              if (_loading)
                ...List.generate(
                    5,
                    (_) => const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: SkeletonBox(
                              width: double.infinity, height: 68, radius: 16),
                        ))
              else if (_monthRecords.isEmpty)
                EmptyStateWidget(
                  icon: Icons.access_time,
                  title: 'No records',
                  description:
                      'No records found for ${DateFormat('MMMM yyyy').format(_selectedMonth)}.',
                )
              else
                ..._monthRecords.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _RecordTile(
                        record: r,
                        overtimeRequest: _overtimeByAttendance[r['id']],
                        onRequestOvertime: () => _requestOvertime(r),
                      ),
                    )),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final Map<String, dynamic> record;
  final Map<String, dynamic>? overtimeRequest;
  final VoidCallback? onRequestOvertime;
  const _RecordTile(
      {required this.record, this.overtimeRequest, this.onRequestOvertime});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(record['date'] as String);
    final status = record['status'] as String? ?? 'out';
    final checkIn = record['check_in_at'] as String?;
    final checkOut = record['check_out_at'] as String?;
    final hours = _asDouble(record['hours_worked']);

    return GlassCard(
      onTap: () => _showDetail(context, record),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: StatusColors.bg(status),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(DateFormat('d').format(date),
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: StatusColors.fg(status))),
            Text(DateFormat('EEE').format(date).toUpperCase(),
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.8,
                    color: StatusColors.fg(status))),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(DateFormat('EEEE, d MMMM').format(date),
              style: AppTextStyles.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(
            children: [
              if (checkIn != null) ...[
                const Icon(Icons.login_rounded,
                    size: 12, color: AppColors.gray400),
                const SizedBox(width: 4),
                Text(DateFormat('hh:mm a').format(DateTime.parse(checkIn).toLocal()),
                    style: AppTextStyles.caption),
              ],
              if (checkOut != null) ...[
                const SizedBox(width: 12),
                const Icon(Icons.logout_rounded,
                    size: 12, color: AppColors.gray400),
                const SizedBox(width: 4),
                Text(DateFormat('hh:mm a').format(DateTime.parse(checkOut).toLocal()),
                    style: AppTextStyles.caption),
              ],
              if (hours != null) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${hours.toStringAsFixed(1)}h',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                ),
              ],
            ],
          ),
        ])),
      ]),
    );
  }

  void _showDetail(BuildContext context, Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true, // Show above the Bottom Navigation Bar
      isScrollControlled: true, // Prevent tall content from being cut off
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: GlassCard(
          borderRadius: AppRadius.card,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: AppColors.gray300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(
                    DateFormat('EEEE, d MMMM yyyy')
                        .format(DateTime.parse(r['date'] as String)),
                    style: AppTextStyles.title),
                StatusBadge(status: r['status'] as String? ?? 'out'),
              ]),
              const SizedBox(height: 18),
              const Divider(height: 32),
              _glassDetailRow(
                  'Check In',
                  r['check_in_at'] != null
                      ? DateFormat('hh:mm a').format(
                          DateTime.parse(r['check_in_at'] as String).toLocal())
                      : '—'),
              _glassDetailRow(
                  'Check Out',
                  r['check_out_at'] != null
                      ? DateFormat('hh:mm a').format(
                          DateTime.parse(r['check_out_at'] as String).toLocal())
                      : '—'),
              Builder(builder: (_) {
                final hours = _asDouble(r['hours_worked']);
                return glassDetailRow('Hours',
                    hours != null ? '${hours.toStringAsFixed(1)}h' : '—');
              }),
              Builder(builder: (_) {
                final net = _asDouble(r['net_hours_worked']);
                return net != null
                    ? glassDetailRow('Net Hours', '${net.toStringAsFixed(1)}h')
                    : const SizedBox.shrink();
              }),
              Builder(builder: (_) {
                final late = _asInt(r['late_minutes']) ?? 0;
                return late > 0
                    ? glassDetailRow('Late By', '$late min', highlight: true, highlightColor: AppColors.warning500)
                    : const SizedBox.shrink();
              }),
              Builder(builder: (_) {
                final brk = _totalBreakMinutes(r);
                return brk > 0
                    ? glassDetailRow('Breaks', '$brk min')
                    : const SizedBox.shrink();
              }),
              Builder(builder: (_) {
                final ot = _asDouble(r['overtime_hours']) ?? 0;
                return ot > 0
                    ? glassDetailRow('Overtime', '${ot.toStringAsFixed(1)}h', highlight: true)
                    : const SizedBox.shrink();
              }),
              Builder(builder: (_) {
                final extra = _asInt(r['extra_office_minutes']) ?? 0;
                return extra > 0
                    ? glassDetailRow('Extra Office Time', '$extra min')
                    : const SizedBox.shrink();
              }),
              // ── Overtime request status / action ───────────────────────
              Builder(builder: (_) {
                final extra = _asInt(r['extra_office_minutes']) ?? 0;
                final ot = _asDouble(r['overtime_hours']) ?? 0;
                if (extra <= 0 || ot > 0 || r['id'] == null) {
                  return const SizedBox.shrink();
                }
                final req = overtimeRequest;
                if (req != null && req['status'] != 'rejected') {
                  final status = (req['status'] as String? ?? 'pending');
                  return glassDetailRow('Overtime Request',
                      status[0].toUpperCase() + status.substring(1),
                      highlight: status == 'pending', highlightColor: AppColors.warning500);
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: AppButton(
                    label: 'Request Overtime (${extra}m)',
                    icon: Icons.more_time,
                    outline: true,
                    onPressed: onRequestOvertime == null
                        ? null
                        : () {
                            Navigator.pop(context);
                            onRequestOvertime!();
                          },
                  ),
                );
              }),
              glassDetailRow(
                  'Type',
                  (r['check_in_type'] as String? ?? 'manual')
                      .replaceAll('_', ' ')
                      .toUpperCase()),
              if (r['auto_checked_out'] == true)
                glassDetailRow('Check Out', 'Auto checked-out by system',
                    highlight: true, highlightColor: AppColors.danger500),
              if (r['ip_detected'] != null)
                glassDetailRow('IP', r['ip_detected'] as String),
              if (r['is_overridden'] == true)
                glassDetailRow('Override',
                    r['override_reason'] as String? ?? 'Overridden by manager',
                    highlight: true),
              // ── Break history ────────────────────────────────────────────
              Builder(builder: (_) {
                final breaks = (r['break_records'] as List?)
                        ?.cast<Map<String, dynamic>>() ??
                    [];
                if (breaks.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    const Divider(height: 1),
                    const SizedBox(height: 20),
                    const SectionHeader(title: 'Breaks'),
                    const SizedBox(height: 12),
                    ...breaks.map((b) => _breakHistoryRow(b)),
                  ],
                );
              }),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _breakHistoryRow(Map<String, dynamic> b) {
    final name     = (b['break_type'] as String? ?? 'Break')
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
    final start    = b['break_start'] != null
        ? DateFormat('hh:mm a').format(DateTime.parse(b['break_start'] as String).toLocal())
        : '—';
    final end      = b['break_end'] != null
        ? DateFormat('hh:mm a').format(DateTime.parse(b['break_end'] as String).toLocal())
        : 'Ongoing';
    final duration = _asInt(b['duration_mins']);
    final late     = _asInt(b['late_return_minutes']) ?? 0;
    final isPaid   = (b['is_paid'] as bool?) ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        tint: late > 0 ? AppColors.danger500 : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(
              late > 0 ? Icons.running_with_errors : Icons.free_breakfast_rounded,
              size: 16,
              color: late > 0 ? AppColors.danger500 : AppColors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: late > 0
                          ? AppColors.danger800
                          : AppColors.textPrimary)),
            ),
            if (isPaid)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('PAID',
                    style: TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Text('$start → $end', style: AppTextStyles.body),
            if (duration != null) ...[
              const SizedBox(width: 8),
              Container(
                width: 4, height: 4,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: AppColors.gray300),
              ),
              const SizedBox(width: 8),
              Text('${duration}m', style: AppTextStyles.bodyStrong),
            ],
          ]),
          if (late > 0) ...[
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.danger500),
              const SizedBox(width: 6),
              Text('${late}m late returning',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger800)),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _glassDetailRow(String label, String value, {bool highlight = false}) {
    return glassDetailRow(label, value, highlight: highlight);
  }
}
