import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  final Map<String, List<Map<String, dynamic>>> _items = {};
  final Map<String, String> _errors = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final jobs = <String, Future<dynamic>>{
      if (auth.hasFeature('leave_management')) 'Leave': api.getMyLeaveRequestsPage(limit: 25),
      if (auth.hasFeature('remote_work')) 'Remote work': api.getMyRemoteSessions(),
      if (auth.hasFeature('attendance')) 'Overtime': api.getMyOvertimeRequests(),
      if (auth.hasFeature('shifts')) 'Shift swaps': api.getSwapRequests(),
      if (auth.hasFeature('shifts')) 'Availability': api.getMyShiftAvailability(),
      if (auth.hasFeature('attendance')) 'Time corrections': api.getMyCorrections(),
      'Expenses': api.getMyExpenses(),
    };
    final results = await Future.wait(jobs.entries.map((entry) async {
      try {
        final value = await entry.value;
        final list = value is Map ? (value['items'] as List? ?? const []) : value as List? ?? const [];
        return (entry.key, list.whereType<Map>().map((item) => item.cast<String, dynamic>()).toList(), null as String?);
      } catch (error) {
        return (entry.key, <Map<String, dynamic>>[], ApiFailure.fromError(error).userMessage);
      }
    }));
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addEntries(results.map((item) => MapEntry(item.$1, item.$2)));
      _errors
        ..clear()
        ..addEntries(results.where((item) => item.$3 != null).map((item) => MapEntry(item.$1, item.$3!)));
      _loading = false;
    });
  }

  String _status(Map<String, dynamic> item) =>
      (item['status'] ?? item['decision'] ?? 'submitted').toString().replaceAll('_', ' ');

  bool _pending(Map<String, dynamic> item) =>
      const {'pending', 'submitted', 'in review', 'open'}.contains(_status(item).toLowerCase());

  String _date(Map<String, dynamic> item) {
    final value = item['created_at'] ?? item['date'] ?? item['start_date'] ?? item['expense_date'];
    if (value == null) return 'Date not available';
    final text = value.toString();
    return text.length >= 10 ? text.substring(0, 10) : text;
  }

  String _title(String category, Map<String, dynamic> item) {
    switch (category) {
      case 'Leave': return '${item['leave_type'] ?? 'Leave'} request';
      case 'Remote work': return 'Remote work · ${item['duration_type'] ?? item['status'] ?? 'request'}';
      case 'Overtime': return '${item['requested_minutes'] ?? item['minutes'] ?? 'Overtime'} minutes';
      case 'Shift swaps': return item['reason']?.toString().trim().isNotEmpty == true ? item['reason'].toString() : 'Shift swap request';
      case 'Availability': return item['kind'] == 'unavailable' ? 'Unavailable time' : 'Preferred availability';
      case 'Time corrections': return item['reason']?.toString().trim().isNotEmpty == true ? item['reason'].toString() : 'Attendance correction';
      case 'Expenses': return item['description']?.toString().trim().isNotEmpty == true ? item['description'].toString() : item['category']?.toString() ?? 'Expense claim';
      default: return category;
    }
  }

  String _destination(String category) => switch (category) {
    'Leave' => '/leave',
    'Remote work' => '/home/remote',
    'Overtime' || 'Time corrections' => '/attendance',
    'Shift swaps' => '/schedule',
    'Availability' => '/schedule/availability',
    'Expenses' => '/profile/expenses',
    _ => '/home',
  };

  Color _statusColor(Map<String, dynamic> item) {
    final value = _status(item).toLowerCase();
    if (value.contains('reject') || value.contains('cancel')) return AppColors.danger500;
    if (value.contains('approv') || value == 'completed' || value == 'closed') return AppColors.success500;
    if (_pending(item)) return AppColors.warning500;
    return AppColors.gray500;
  }

  Widget _requestCard(String category, Map<String, dynamic> item) {
    final status = _status(item);
    final color = _statusColor(item);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.control),
          onTap: () => context.push(_destination(category)),
          child: Ink(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              Icon(Icons.description_outlined, color: Theme.of(context).colorScheme.primary, size: 20),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_title(category, item), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyStrong),
                const SizedBox(height: 3),
                Text(_date(item), style: AppTextStyles.caption),
              ])),
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(maxWidth: 100),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(20)),
                child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _section(String category) {
    final list = _items[category] ?? const <Map<String, dynamic>>[];
    final pending = list.where(_pending).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(child: Text(category, style: AppTextStyles.title)),
            if (pending > 0) Text('$pending pending', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
          ]),
        ),
        if (_errors[category] != null)
          Text('Could not load this section: ${_errors[category]}', style: const TextStyle(fontSize: 13, color: AppColors.danger500))
        else if (list.isEmpty)
          Text('No ${category.toLowerCase()} requests yet.', style: AppTextStyles.caption)
        else
          ...list.take(5).map((item) => _requestCard(category, item)),
        if (list.length > 5)
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => context.push(_destination(category)), child: const Text('View all'))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = _items.keys.toList();
    final totalPending = _items.values.expand((items) => items).where(_pending).length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const AppPageTitle(title: 'My requests', subtitle: 'Track decisions and upcoming requests')),
      body: RefreshIndicator(
        color: Theme.of(context).colorScheme.primary,
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                children: [
                  GlassCard(child: Row(children: [
                    Icon(Icons.inbox_outlined, color: Theme.of(context).colorScheme.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Your requests', style: AppTextStyles.title),
                      const SizedBox(height: 3),
                      Text('$totalPending waiting for a decision', style: AppTextStyles.caption),
                    ])),
                  ])),
                  const SizedBox(height: 18),
                  if (_errors.length == categories.length && categories.isNotEmpty)
                    EmptyStateWidget(icon: Icons.cloud_off_outlined, title: 'Requests unavailable', description: 'Check your connection and try again.', action: AppButton(label: 'Retry', onPressed: _load, fullWidth: false))
                  else if (categories.every((category) => (_items[category] ?? []).isEmpty) && _errors.isEmpty)
                    const EmptyStateWidget(icon: Icons.inbox_outlined, title: 'No requests yet', description: 'Requests you submit will appear here with their latest status.')
                  else
                    ...categories.map(_section),
                ],
              ),
      ),
    );
  }
}
