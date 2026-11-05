import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class ProjectTimeScreen extends StatefulWidget {
  const ProjectTimeScreen({super.key});
  @override
  State<ProjectTimeScreen> createState() => _ProjectTimeScreenState();
}

class _ProjectTimeScreenState extends State<ProjectTimeScreen> {
  Map<String, dynamic>? _timer;
  Map<String, dynamic>? _week;
  List<Map<String, dynamic>> _projects = [];
  List<Map<String, dynamic>> _reviewQueue = [];
  String? _projectId;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String get _weekStart {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return '${monday.year.toString().padLeft(4, '0')}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}T00:00:00.000Z';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final canReview = context.read<AuthProvider>().hasPermission('time.approve');
      final values = await Future.wait([
        api.getRunningProjectTimer(),
        api.getMyTimesheet(_weekStart),
        api.getProjects(),
        if (canReview) api.getTimesheetsToReview(),
      ]);
      if (!mounted) return;
      setState(() {
        _timer = values[0] as Map<String, dynamic>?;
        _week = values[1] as Map<String, dynamic>;
        _projects = (values[2] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _reviewQueue = values.length > 3
            ? (values[3] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : [];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = ApiFailure.fromError(error).userMessage; _loading = false; });
    }
  }

  Future<void> _toggleTimer() async {
    setState(() => _busy = true);
    try {
      if (_timer == null) {
        await api.startProjectTimer(projectId: _projectId);
      } else {
        await api.stopProjectTimer();
      }
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiFailure.fromError(error).userMessage)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await api.submitMyTimesheet(_weekStart);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Timesheet submitted for review')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiFailure.fromError(error).userMessage)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addManualEntry() async {
    final now = DateTime.now();
    final startDate = await showDatePicker(context: context, initialDate: now, firstDate: DateTime(now.year - 2), lastDate: DateTime(now.year + 1));
    if (startDate == null || !mounted) return;
    final startTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now));
    if (startTime == null || !mounted) return;
    final start = DateTime(startDate.year, startDate.month, startDate.day, startTime.hour, startTime.minute);
    final endDate = await showDatePicker(context: context, initialDate: start, firstDate: startDate, lastDate: DateTime(start.year + 1));
    if (endDate == null || !mounted) return;
    final endTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start.add(const Duration(hours: 1))));
    if (endTime == null || !mounted) return;
    final end = DateTime(endDate.year, endDate.month, endDate.day, endTime.hour, endTime.minute);
    if (!end.isAfter(start) || end.difference(start) > const Duration(hours: 24)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose an end time after the start, within 24 hours.')));
      return;
    }
    final controller = TextEditingController();
    final description = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Add time entry'),
      content: TextField(controller: controller, maxLength: 500, decoration: const InputDecoration(labelText: 'Work description (optional)')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Continue'))],
    ));
    if (description == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await api.createManualProjectTime({
        if (_projectId != null) 'project_id': _projectId,
        'started_at': start.toUtc().toIso8601String(),
        'ended_at': end.toUtc().toIso8601String(),
        'description': description,
      });
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiFailure.fromError(error).userMessage)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(Map<String, dynamic> sheet, String decision) async {
    String? note;
    if (decision == 'reject') {
      note = await showDialog<String>(
        context: context,
        builder: (context) {
          final controller = TextEditingController();
          return AlertDialog(
            title: const Text('Return timesheet'),
            content: TextField(controller: controller, maxLines: 3, decoration: const InputDecoration(labelText: 'Reason (required)')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(onPressed: () { final value = controller.text.trim(); if (value.isNotEmpty) Navigator.pop(context, value); }, child: const Text('Return')),
            ],
          );
        },
      );
      if (note == null || note.trim().isEmpty) return;
    }
    setState(() => _busy = true);
    try {
      await api.reviewTimesheet(sheet['id'].toString(), decision: decision, note: note);
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiFailure.fromError(error).userMessage)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = (_week?['entries'] as List? ?? const []).whereType<Map>().toList();
    final totalMinutes = (_week?['total_minutes'] as num?)?.toInt() ?? 0;
    final sheetStatus = (_week?['timesheet'] as Map?)?['status']?.toString() ?? 'draft';
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const AppPageTitle(title: 'Project time', subtitle: 'Timers and weekly timesheets')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: EmptyStateWidget(icon: Icons.error_outline, title: 'Couldn’t load time tracking', description: _error!, action: AppButton(label: 'Try again', onPressed: _load, fullWidth: false)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [Icon(_timer == null ? Icons.timer_outlined : Icons.timer, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 10), Expanded(child: Text(_timer == null ? 'Ready when you are' : 'Timer is running', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))) ]),
                        const SizedBox(height: 12),
                        if (_timer == null)
                          DropdownButtonFormField<String?>(
                            initialValue: _projectId,
                            decoration: const InputDecoration(labelText: 'Project (optional)'),
                            items: [const DropdownMenuItem<String?>(value: null, child: Text('No project selected')), ..._projects.map((project) => DropdownMenuItem<String?>(value: project['id']?.toString(), child: Text(project['name']?.toString() ?? 'Project', overflow: TextOverflow.ellipsis)))],
                            onChanged: (value) => setState(() => _projectId = value),
                          )
                        else
                          Text('${(_timer?['project'] as Map?)?['name'] ?? 'Unassigned project'}${(_timer?['description'] ?? '').toString().isNotEmpty ? ' · ${_timer?['description']}' : ''}', style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 14),
                        AppButton(label: _timer == null ? 'Start timer' : 'Stop and save', icon: _timer == null ? Icons.play_arrow_rounded : Icons.stop_rounded, loading: _busy, onPressed: _toggleTimer),
                        if (_timer == null) Center(child: TextButton.icon(onPressed: _busy ? null : _addManualEntry, icon: const Icon(Icons.edit_calendar_outlined, size: 18), label: const Text('Add time manually'))),
                        const SizedBox(height: 8),
                        Text('Timer uses server time and stops automatically at attendance checkout.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [Expanded(child: Text('This week', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))), Text('${(totalMinutes ~/ 60)}h ${totalMinutes % 60}m', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))]),
                        const SizedBox(height: 4),
                        Text('Status: ${sheetStatus.replaceAll('_', ' ')}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                        const SizedBox(height: 12),
                        if (entries.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text('No time entries yet. Start a timer to log project work.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)))
                        else ...entries.map((entry) {
                          final project = (entry['project'] as Map?)?['name']?.toString() ?? 'Unassigned project';
                          final task = (entry['task'] as Map?)?['title']?.toString();
                          final minutes = (entry['minutes'] as num?)?.toInt() ?? 0;
                          return ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.work_outline_rounded), title: Text(task == null ? project : '$project · $task', maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(entry['description']?.toString() ?? entry['source']?.toString() ?? 'Work'), trailing: Text('${minutes ~/ 60}h ${minutes % 60}m'));
                        }),
                        if (sheetStatus == 'draft' || sheetStatus == 'rejected') ...[
                          const SizedBox(height: 8),
                          AppButton(label: 'Submit timesheet', icon: Icons.send_rounded, loading: _busy, onPressed: entries.isEmpty || _timer != null ? null : _submit),
                        ],
                      ]),
                    ),
                    if (context.watch<AuthProvider>().hasPermission('time.approve')) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Team timesheets', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(_reviewQueue.isEmpty ? 'No submissions waiting for review.' : '${_reviewQueue.length} awaiting review', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                          ..._reviewQueue.map((sheet) => Column(children: [
                            const Divider(height: 20),
                            Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(sheet['user']?['name']?.toString() ?? 'Employee', style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text('Week of ${sheet['week_start']?.toString().split('T').first ?? ''}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary))])),
                              IconButton(tooltip: 'Return with reason', onPressed: _busy ? null : () => _review(sheet, 'reject'), icon: const Icon(Icons.reply_rounded)),
                              IconButton(tooltip: 'Approve and lock', onPressed: _busy ? null : () => _review(sheet, 'approve'), icon: const Icon(Icons.check_circle_outline_rounded, color: AppColors.success500)),
                            ]),
                          ])),
                        ]),
                      ),
                    ],
                  ]),
                ),
    );
  }
}
