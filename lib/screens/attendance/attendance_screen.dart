import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

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
      final data = await api.getMyAttendance(days: 90);
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
      return date.month == _selectedMonth.month && date.year == _selectedMonth.year;
    }).toList()
      ..sort((a, b) => DateTime.parse(b['date'] as String).compareTo(DateTime.parse(a['date'] as String)));
  }

  Map<String, int> get _summary {
    final mr = _monthRecords;
    return {
      'present': mr.where((r) => ['in','out','late'].contains(r['status'])).length,
      'late':    mr.where((r) => r['status'] == 'late').length,
      'absent':  mr.where((r) => r['status'] == 'absent').length,
      'remote':  mr.where((r) => r['status'] == 'remote').length,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(title: const Text('My Attendance'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
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
                    final m = DateTime(DateTime.now().year, DateTime.now().month - i);
                    final selected = m.month == _selectedMonth.month && m.year == _selectedMonth.year;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedMonth = m),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.primary600 : AppColors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: selected ? AppColors.primary600 : AppColors.gray200),
                          ),
                          child: Text(DateFormat('MMM yyyy').format(m),
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                  color: selected ? Colors.white : AppColors.dark950)),
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
                  Expanded(child: KpiChip(label: 'Present', value: '${_summary['present']}', color: AppColors.success700, bg: AppColors.success100)),
                  const SizedBox(width: 8),
                  Expanded(child: KpiChip(label: 'Late',    value: '${_summary['late']}',    color: AppColors.warning800, bg: AppColors.warning100)),
                  const SizedBox(width: 8),
                  Expanded(child: KpiChip(label: 'Absent',  value: '${_summary['absent']}',  color: AppColors.danger800,  bg: AppColors.danger100)),
                  const SizedBox(width: 8),
                  Expanded(child: KpiChip(label: 'Remote',  value: '${_summary['remote']}',  color: AppColors.purple700,  bg: AppColors.purple100)),
                ]),
                const SizedBox(height: 20),
              ],

              // Records list
              const SectionHeader(title: 'Attendance Records'),
              const SizedBox(height: 12),

              if (_loading)
                ...List.generate(5, (_) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SkeletonBox(width: double.infinity, height: 68, radius: 12),
                ))
              else if (_monthRecords.isEmpty)
                EmptyStateWidget(
                  icon: Icons.access_time,
                  title: 'No records',
                  description: 'No attendance records found for ${DateFormat('MMMM yyyy').format(_selectedMonth)}.',
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

class _RecordTile extends StatelessWidget {
  final Map<String, dynamic> record;
  const _RecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final date     = DateTime.parse(record['date'] as String);
    final status   = record['status'] as String? ?? 'out';
    final checkIn  = record['check_in_at']  as String?;
    final checkOut = record['check_out_at'] as String?;
    final hours    = record['hours_worked'];

    return AppCard(
      onTap: () => _showDetail(context, record),
      child: Row(children: [
        // Date column
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: StatusColors.bg(status), borderRadius: BorderRadius.circular(10)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(DateFormat('d').format(date), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: StatusColors.fg(status))),
            Text(DateFormat('EEE').format(date), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: StatusColors.fg(status))),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(DateFormat('EEEE, d MMMM').format(date), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.dark950)),
          const SizedBox(height: 3),
          Row(children: [
            if (checkIn != null) Text('In: ${DateFormat('HH:mm').format(DateTime.parse(checkIn))}', style: const TextStyle(fontSize: 12, color: AppColors.gray500)),
            if (checkIn != null && checkOut != null) const Text('  ·  ', style: TextStyle(color: AppColors.gray200)),
            if (checkOut != null) Text('Out: ${DateFormat('HH:mm').format(DateTime.parse(checkOut))}', style: const TextStyle(fontSize: 12, color: AppColors.gray500)),
            if (hours != null) Text('  ·  ${hours}h', style: const TextStyle(fontSize: 12, color: AppColors.gray500)),
          ]),
        ])),
        StatusBadge(status: status, small: true),
      ]),
    );
  }

  void _showDetail(BuildContext context, Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.parse(r['date'] as String)),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              StatusBadge(status: r['status'] as String? ?? 'out'),
            ]),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            _detailRow('Check In',   r['check_in_at']  != null ? DateFormat('hh:mm a').format(DateTime.parse(r['check_in_at']  as String)) : '—'),
            _detailRow('Check Out',  r['check_out_at'] != null ? DateFormat('hh:mm a').format(DateTime.parse(r['check_out_at'] as String)) : '—'),
            _detailRow('Hours',      r['hours_worked'] != null ? '${r['hours_worked']}h' : '—'),
            _detailRow('Type',       (r['check_in_type'] as String? ?? 'manual').replaceAll('_', ' ').toUpperCase()),
            if (r['ip_detected'] != null)
              _detailRow('IP', r['ip_detected'] as String),
            if (r['is_overridden'] == true)
              _detailRow('Override', r['override_reason'] as String? ?? 'Overridden by manager', highlight: true),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 14, color: AppColors.gray500)),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
            color: highlight ? AppColors.warning800 : AppColors.dark950)),
      ]),
    );
  }
}
