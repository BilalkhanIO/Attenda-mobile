import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<Map<String, dynamic>> _records = [];
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
      final data = await api.getMyAttendance(days: 186);
      setState(() {
        _records = data.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('My Attendance'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary600,
        backgroundColor: AppColors.bgDark3,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
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
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                gradient: selected
                                    ? const LinearGradient(
                                        colors: [
                                          Color(0xFF00C896),
                                          Color(0xFF00E5FF)
                                        ],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      )
                                    : null, // If not selected, use the color below
                                color: selected ? null : AppColors.glass10,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: selected
                                      ? Colors.transparent
                                      : AppColors.glass20,
                                ),
                              ),
                              child: Text(
                                DateFormat('MMM yyyy').format(m),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? Colors.white
                                      : AppColors.onGlassMuted,
                                ),
                              ),
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
                      child: _StatChip(
                          label: 'Present',
                          value: '${_summary['present']}',
                          color: const Color(0xFF34E0A1))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _StatChip(
                          label: 'Late',
                          value: '${_summary['late']}',
                          color: const Color(0xFFFFBF4D))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _StatChip(
                          label: 'Absent',
                          value: '${_summary['absent']}',
                          color: const Color(0xFFFF6B7D))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _StatChip(
                          label: 'Remote',
                          value: '${_summary['remote']}',
                          color: const Color(0xFF5BD6FF))),
                ]),
                const SizedBox(height: 20),
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
                      child: _RecordTile(record: r),
                    )),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── KPI stat chip with glass tint ──────────────────────
class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: color.withValues(alpha: 0.28), width: 1.0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: color.withValues(alpha: 0.75))),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final Map<String, dynamic> record;
  const _RecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(record['date'] as String);
    final status = record['status'] as String? ?? 'out';
    final checkIn = record['check_in_at'] as String?;
    final checkOut = record['check_out_at'] as String?;
    final hours = _asDouble(record['hours_worked']);

    return GlassCard(
      onTap: () => _showDetail(context, record),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: StatusColors.bg(status),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(DateFormat('d').format(date),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: StatusColors.fg(status))),
            Text(DateFormat('EEE').format(date),
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: StatusColors.fg(status))),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(DateFormat('EEEE, d MMMM').format(date),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (checkIn != null)
                Text(
                    'In: ${DateFormat('hh:mm a').format(DateTime.parse(checkIn).toLocal())}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.onGlassMuted)),
              if (checkIn != null && checkOut != null)
                const Text('·',
                    style:
                        TextStyle(color: AppColors.onGlassDim, fontSize: 12)),
              if (checkOut != null)
                Text(
                    'Out: ${DateFormat('hh:mm a').format(DateTime.parse(checkOut).toLocal())}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.onGlassMuted)),
              if (hours != null) ...[
                const Text('·',
                    style:
                        TextStyle(color: AppColors.onGlassDim, fontSize: 12)),
                Text('${hours.toStringAsFixed(1)}h',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.onGlassMuted)),
              ],
            ],
          ),
        ])),
        StatusBadge(status: status, small: true),
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
          borderRadius: 32,
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
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(
                    DateFormat('EEEE, d MMMM yyyy')
                        .format(DateTime.parse(r['date'] as String)),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                StatusBadge(status: r['status'] as String? ?? 'out'),
              ]),
              const SizedBox(height: 18),
              const Divider(color: AppColors.glass12),
              const SizedBox(height: 10),
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
                return _glassDetailRow('Hours',
                    hours != null ? '${hours.toStringAsFixed(1)}h' : '—');
              }),
              Builder(builder: (_) {
                final net = _asDouble(r['net_hours_worked']);
                return net != null
                    ? _glassDetailRow('Net Hours', '${net.toStringAsFixed(1)}h')
                    : const SizedBox.shrink();
              }),
              Builder(builder: (_) {
                final late = _asInt(r['late_minutes']) ?? 0;
                return late > 0
                    ? _glassDetailRow('Late By', '$late min', highlight: true)
                    : const SizedBox.shrink();
              }),
              Builder(builder: (_) {
                final brk = _asInt(r['break_minutes']) ?? 0;
                return brk > 0
                    ? _glassDetailRow('Breaks', '$brk min')
                    : const SizedBox.shrink();
              }),
              Builder(builder: (_) {
                final ot = _asDouble(r['overtime_hours']) ?? 0;
                return ot > 0
                    ? _glassDetailRow('Overtime', '${ot.toStringAsFixed(1)}h', highlight: true)
                    : const SizedBox.shrink();
              }),
              Builder(builder: (_) {
                final extra = _asInt(r['extra_office_minutes']) ?? 0;
                return extra > 0
                    ? _glassDetailRow('Extra Office Time', '$extra min')
                    : const SizedBox.shrink();
              }),
              _glassDetailRow(
                  'Type',
                  (r['check_in_type'] as String? ?? 'manual')
                      .replaceAll('_', ' ')
                      .toUpperCase()),
              if (r['auto_checked_out'] == true)
                _glassDetailRow('Check Out', 'Auto checked-out by system',
                    highlight: true),
              if (r['ip_detected'] != null)
                _glassDetailRow('IP', r['ip_detected'] as String),
              if (r['is_overridden'] == true)
                _glassDetailRow('Override',
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
                    const SizedBox(height: 14),
                    const Divider(color: AppColors.glass12),
                    const SizedBox(height: 10),
                    const Text('Breaks',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    const SizedBox(height: 8),
                    ...breaks.map((b) => _breakHistoryRow(b)),
                  ],
                );
              }),
              const SizedBox(height: 6),
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
    final autoEnded = (b['auto_ended'] as bool?) ?? false;
    final wifiBack  = (b['wifi_on_at_end'] as bool?) ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        tint: late > 0 ? AppColors.danger500 : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(
              late > 0 ? Icons.running_with_errors : Icons.free_breakfast_outlined,
              size: 14,
              color: late > 0 ? AppColors.danger500 : AppColors.teal100,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(name,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: late > 0 ? AppColors.danger500 : Colors.white)),
            ),
            if (isPaid)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.teal100.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Paid',
                    style: TextStyle(fontSize: 10, color: AppColors.teal100, fontWeight: FontWeight.w600)),
              ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Text('$start → $end',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
            if (duration != null) ...[
              const SizedBox(width: 6),
              Text('· ${duration}m',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
            ],
          ]),
          if (late > 0) ...[
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.warning_amber_rounded, size: 12, color: AppColors.danger500.withValues(alpha: 0.8)),
              const SizedBox(width: 4),
              Text('${late}m late returning',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger500.withValues(alpha: 0.9))),
              if (!wifiBack) ...[
                const SizedBox(width: 4),
                Text('· off WiFi',
                    style: TextStyle(fontSize: 11, color: AppColors.danger500.withValues(alpha: 0.6))),
              ],
            ]),
          ],
          if (autoEnded) ...[
            const SizedBox(height: 2),
            Text('Auto-closed at checkout',
                style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.35))),
          ],
        ]),
      ),
    );
  }

  Widget _glassDetailRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onGlassMuted)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
                    color: highlight ? AppColors.primary : AppColors.onGlass)),
          ),
        ],
      ),
    );
  }
}
