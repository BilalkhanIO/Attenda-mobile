import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class ShiftPlanningScreen extends StatefulWidget {
  const ShiftPlanningScreen({super.key});
  @override
  State<ShiftPlanningScreen> createState() => _ShiftPlanningScreenState();
}

class _ShiftPlanningScreenState extends State<ShiftPlanningScreen> {
  DateTime _week = _monday(DateTime.now());
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _issues = [];
  List<Map<String, dynamic>> _workload = [];
  List<Map<String, dynamic>> _rules = [];
  List<Map<String, dynamic>> _templates = [];
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _locations = [];
  String _search = '';
  String _department = 'all';
  String _locationFilter = 'all';
  String _shiftFilter = 'all';
  String _assignmentFilter = 'all';
  String _publicationFilter = 'all';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static DateTime _monday(DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    return date.subtract(Duration(days: date.weekday - 1));
  }

  String get _weekStart => DateFormat('yyyy-MM-dd').format(_week);
  String _formatDate(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthProvider>();
      final canManageCoverage = auth.hasPermission('shifts.coverage.manage');
      final canViewLocations = auth.hasPermission('org.locations.view') ||
          auth.hasPermission('org.locations.manage');
      final jobs = <Future<dynamic>>[
        api.getOrgSchedule(
            weekStart: _weekStart,
            locationId: canViewLocations ? _locationFilter : null),
        api.getShiftPlanningIssues(_weekStart),
        api.getShiftWorkload(_weekStart),
        api.getShiftTemplates(),
        api.getOrgMembers(),
      ];
      if (canManageCoverage) jobs.add(api.getShiftCoverageRules());
      if (canViewLocations) jobs.add(api.getOrgLocations());
      final results = await Future.wait(jobs);
      if (!mounted) return;
      setState(() {
        _assignments = (results[0] as List).cast<Map<String, dynamic>>();
        _issues =
            ((results[1] as Map<String, dynamic>)['issues'] as List? ?? [])
                .cast<Map<String, dynamic>>();
        _workload = (results[2] as List).cast<Map<String, dynamic>>();
        _templates = (results[3] as List).cast<Map<String, dynamic>>();
        _employees = (results[4] as List).cast<Map<String, dynamic>>();
        var nextIndex = 5;
        _rules = canManageCoverage
            ? (results[nextIndex++] as List).cast<Map<String, dynamic>>()
            : [];
        _locations = canViewLocations
            ? (results[nextIndex] as List)
                .cast<Map<String, dynamic>>()
                .where((location) => location['is_active'] != false)
                .toList()
            : [];
        if (!canViewLocations) _locationFilter = 'all';
        if (_locationFilter != 'all' &&
            _locationFilter != 'unassigned' &&
            !_locations.any((location) => location['id'] == _locationFilter)) {
          _locationFilter = 'all';
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = ApiFailure.fromError(error).userMessage;
        _loading = false;
      });
    }
  }

  Future<void> _assignShift() async {
    if (_templates.isEmpty || _employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Add a shift template and active employee first.'),
      ));
      return;
    }
    var selectedShift = _templates.first['id'] as String;
    var selectedEmployee = _employees.first['id'] as String;
    var selectedDay = _week;
    final assigned = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Assign a shift'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: selectedEmployee,
              decoration: const InputDecoration(labelText: 'Employee'),
              items: _employees
                  .map((person) => DropdownMenuItem(
                        value: person['id'] as String,
                        child: Text(person['name'] as String? ?? 'Employee'),
                      ))
                  .toList(),
              onChanged: (value) => setDialogState(
                  () => selectedEmployee = value ?? selectedEmployee),
            ),
            DropdownButtonFormField<String>(
              initialValue: selectedShift,
              decoration: const InputDecoration(labelText: 'Shift'),
              items: _templates
                  .map((shift) => DropdownMenuItem(
                        value: shift['id'] as String,
                        child: Text(shift['name'] as String? ?? 'Shift'),
                      ))
                  .toList(),
              onChanged: (value) =>
                  setDialogState(() => selectedShift = value ?? selectedShift),
            ),
            DropdownButtonFormField<DateTime>(
              initialValue: selectedDay,
              decoration: const InputDecoration(labelText: 'Date'),
              items: List.generate(7, (index) {
                final date = _week.add(Duration(days: index));
                return DropdownMenuItem(
                  value: date,
                  child: Text(DateFormat('EEEE · MMM d').format(date)),
                );
              }),
              onChanged: (value) =>
                  setDialogState(() => selectedDay = value ?? selectedDay),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final result = await api.assignShift(
                    userId: selectedEmployee,
                    shiftId: selectedShift,
                    date: _formatDate(selectedDay),
                  );
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext, true);
                  final warnings = [
                    if (result['leave_warning'] == true) 'approved leave',
                    if (result['off_day_warning'] == true) 'inactive day',
                    if (result['availability_warning'] == true)
                      'unavailable time',
                  ];
                  if (warnings.isNotEmpty && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content:
                          Text('Assigned with warning: ${warnings.join(', ')}'),
                    ));
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
                      content: Text(ApiFailure.fromError(error).userMessage),
                    ));
                  }
                }
              },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
    if (assigned == true && mounted) _load();
  }

  Future<void> _bulkAssign() async {
    if (_templates.isEmpty || _employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Add a shift template and active employees first.'),
      ));
      return;
    }
    var selectedShift = _templates.first['id'] as String;
    final selectedEmployees = <String>{};
    final selectedDays = <int>{};
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Bulk assign shifts'),
          content: SizedBox(
            width: 440,
            height: 480,
            child: Column(children: [
              DropdownButtonFormField<String>(
                initialValue: selectedShift,
                decoration: const InputDecoration(labelText: 'Shift'),
                items: _templates
                    .map((shift) => DropdownMenuItem(
                          value: shift['id'] as String,
                          child: Text(shift['name'] as String? ?? 'Shift'),
                        ))
                    .toList(),
                onChanged: (value) => setDialogState(
                    () => selectedShift = value ?? selectedShift),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(top: 12, bottom: 6),
                  child: Text('Select days'),
                ),
              ),
              Wrap(
                spacing: 5,
                children: List.generate(7, (index) {
                  final date = _week.add(Duration(days: index));
                  return FilterChip(
                    label: Text(DateFormat('EEE d').format(date)),
                    selected: selectedDays.contains(index),
                    onSelected: (selected) => setDialogState(() {
                      if (selected) {
                        selectedDays.add(index);
                      } else {
                        selectedDays.remove(index);
                      }
                    }),
                  );
                }),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(top: 10, bottom: 4),
                  child: Text('Select employees'),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _employees.length,
                  itemBuilder: (context, index) {
                    final person = _employees[index];
                    final id = person['id'] as String;
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: selectedEmployees.contains(id),
                      title: Text(person['name'] as String? ?? 'Employee'),
                      subtitle: person['department'] == null
                          ? null
                          : Text(person['department'] as String),
                      onChanged: (selected) => setDialogState(() {
                        if (selected == true) {
                          selectedEmployees.add(id);
                        } else {
                          selectedEmployees.remove(id);
                        }
                      }),
                    );
                  },
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedEmployees.isEmpty || selectedDays.isEmpty
                  ? null
                  : () async {
                      final assignments = [
                        for (final day in selectedDays)
                          for (final userId in selectedEmployees)
                            {
                              'user_id': userId,
                              'shift_id': selectedShift,
                              'date':
                                  _formatDate(_week.add(Duration(days: day))),
                            },
                      ];
                      if (assignments.length > 500) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                              content:
                                  Text('Select 500 assignments or fewer.')),
                        );
                        return;
                      }
                      try {
                        final preview = await api.bulkAssignShifts(assignments,
                            dryRun: true);
                        final conflicts = preview['conflicts'] as List? ?? [];
                        final warnings = preview['warnings'] as List? ?? [];
                        if (!dialogContext.mounted) return;
                        final confirm = await showDialog<bool>(
                          context: dialogContext,
                          builder: (confirmContext) => AlertDialog(
                            title: const Text('Review bulk schedule'),
                            content: Text(
                              '${preview['would_create'] ?? 0} assignments can be created. '
                              '${conflicts.length} conflicting entries will be skipped. '
                              '${warnings.length} leave, availability, or active-day warnings need review.',
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(confirmContext, false),
                                  child: const Text('Back')),
                              FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(confirmContext, true),
                                  child: const Text('Create assignments')),
                            ],
                          ),
                        );
                        if (confirm != true || !dialogContext.mounted) return;
                        final result = await api.bulkAssignShifts(assignments);
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext, true);
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${result['created'] ?? 0} assignments created · '
                                '${(result['conflicts'] as List? ?? []).length} skipped',
                              ),
                            ),
                          );
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                                content: Text(
                                    ApiFailure.fromError(error).userMessage)),
                          );
                        }
                      }
                    },
              child: const Text('Review assignments'),
            ),
          ],
        ),
      ),
    );
    if (created == true && mounted) _load();
  }

  List<Map<String, dynamic>> get _visibleAssignments {
    final query = _search.trim().toLowerCase();
    return _assignments.where((item) {
      final user = (item['user'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final shift = (item['shift'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final department = user['department'] as String? ?? '';
      final isPublished = item['is_published'] == true;
      final location = (item['location'] as Map?)?.cast<String, dynamic>();
      final locationId =
          (item['location_id'] as String?) ?? location?['id'] as String?;
      final textMatch = query.isEmpty ||
          '${user['name'] ?? ''} ${user['email'] ?? ''} $department ${shift['name'] ?? ''}'
              .toLowerCase()
              .contains(query);
      return textMatch &&
          (_department == 'all' || department == _department) &&
          (_locationFilter == 'all' ||
              (_locationFilter == 'unassigned'
                  ? locationId == null
                  : locationId == _locationFilter)) &&
          (_shiftFilter == 'all' || shift['id'] == _shiftFilter) &&
          (_assignmentFilter != 'unassigned') &&
          (_publicationFilter == 'all' ||
              isPublished == (_publicationFilter == 'published'));
    }).toList();
  }

  List<String> get _departments => _assignments
      .map((item) => (item['user'] as Map?)?['department'] as String?)
      .whereType<String>()
      .where((value) => value.trim().isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  Future<void> _copyWeek() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _week.subtract(const Duration(days: 7)),
      firstDate: DateTime(2020),
      lastDate: _week.subtract(const Duration(days: 1)),
      helpText: 'Choose any date in the source week',
    );
    if (selectedDate == null || !mounted) return;
    final sourceWeek = _monday(selectedDate);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Repeat this schedule pattern?'),
                content: Text(
                    'Copy assignments from the week of ${_formatDate(sourceWeek)} into the selected week? Existing employee shifts are kept.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Copy week'))
                ]));
    if (confirmed != true) return;
    try {
      final result =
          await api.copyShiftWeek(_formatDate(sourceWeek), _weekStart);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Copied ${result['created']} shifts · skipped ${result['skipped']} conflicts')));
      _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiFailure.fromError(error).userMessage)));
    }
  }

  Future<void> _publish() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Publish schedule?'),
                content: Text(
                    'Employees with shifts in this week will be notified. Week starting $_weekStart.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Publish'))
                ]));
    if (confirmed != true) return;
    try {
      final result = await api.publishShiftWeek(
          _weekStart, _formatDate(_week.add(const Duration(days: 6))));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(result['message'] as String? ?? 'Schedule published')));
        _load();
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiFailure.fromError(error).userMessage)));
    }
  }

  Future<void> _addCoverageRule() async {
    if (_templates.isEmpty) return;
    final shift = _templates.first;
    final rule = <String, dynamic>{
      'shift_id': shift['id'],
      'shift': shift,
      'weekday': 0,
      'required_count': 1,
      'department': ''
    };
    setState(() => _rules = [..._rules, rule]);
  }

  Future<void> _saveCoverage() async {
    setState(() => _saving = true);
    try {
      _rules = await api
          .saveShiftCoverageRules(_rules
              .map((rule) => {
                    'shift_id': rule['shift_id'],
                    'weekday': rule['weekday'],
                    'required_count': rule['required_count'],
                    'department': rule['department'] ?? ''
                  })
              .toList())
          .then((items) => items.cast<Map<String, dynamic>>());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Coverage targets saved')));
        _load();
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiFailure.fromError(error).userMessage)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _scheduleTab() {
    final byDate = <String, List<Map<String, dynamic>>>{};
    for (final item in _visibleAssignments) {
      final date = (item['date'] as String).substring(0, 10);
      byDate.putIfAbsent(date, () => []).add(item);
    }
    final widgets = <Widget>[];
    for (var offset = 0; offset < 7; offset++) {
      final date = _formatDate(_week.add(Duration(days: offset)));
      final items = byDate[date] ?? [];
      widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
          child: Row(children: [
            Text(
                DateFormat('EEEE · MMM d')
                    .format(_week.add(Duration(days: offset)))
                    .toUpperCase(),
                style: const TextStyle(
                    color: AppColors.gray500,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const Spacer(),
            Text('${items.length} shifts',
                style: const TextStyle(color: AppColors.gray500, fontSize: 11))
          ])));
      for (final item in items) {
        final shift = (item['shift'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final user = (item['user'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: GlassCard(
                child: Row(children: [
              Container(
                  width: 4,
                  height: 48,
                  decoration: BoxDecoration(
                      color: parseHexColor(shift['color'] as String?),
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(user['name'] as String? ?? 'Employee',
                        style: AppTextStyles.bodyStrong),
                    Text(
                        '${shift['name'] ?? 'Shift'} · ${shift['start_time'] ?? '--'}–${shift['end_time'] ?? '--'}',
                        style: AppTextStyles.body),
                    if (user['department'] != null)
                      Text(user['department'] as String,
                          style: const TextStyle(
                              color: AppColors.gray500, fontSize: 11))
                  ])),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: item['is_published'] == true
                          ? AppColors.success100
                          : AppColors.warning100,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                      item['is_published'] == true ? 'PUBLISHED' : 'DRAFT',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: item['is_published'] == true
                              ? AppColors.success500
                              : AppColors.warning500)))
            ]))));
      }
      if (items.isEmpty)
        widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('No assigned shifts',
                style: AppTextStyles.body.copyWith(color: AppColors.gray500))));
    }
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          TextField(
              onChanged: (value) => setState(() => _search = value),
              decoration: InputDecoration(
                  hintText: 'Search employee, department or shift',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () => setState(() => _search = ''),
                          icon: const Icon(Icons.close_rounded)))),
          const SizedBox(height: 8),
          if (context
                  .read<AuthProvider>()
                  .hasPermission('org.locations.view') ||
              context
                  .read<AuthProvider>()
                  .hasPermission('org.locations.manage'))
            DropdownButtonFormField<String>(
                initialValue: _locationFilter,
                decoration: const InputDecoration(labelText: 'Location'),
                items: [
                  const DropdownMenuItem(
                      value: 'all', child: Text('All locations')),
                  const DropdownMenuItem(
                      value: 'unassigned', child: Text('No location')),
                  ..._locations.map((location) => DropdownMenuItem(
                      value: location['id'] as String,
                      child: Text(location['name'] as String? ?? 'Location'))),
                ],
                onChanged: (value) {
                  setState(() => _locationFilter = value ?? 'all');
                  _load();
                }),
          if (_departments.isNotEmpty)
            DropdownButtonFormField<String>(
                initialValue: _department,
                decoration: const InputDecoration(labelText: 'Department'),
                items: [
                  const DropdownMenuItem(
                      value: 'all', child: Text('All departments')),
                  ..._departments.map((value) =>
                      DropdownMenuItem(value: value, child: Text(value)))
                ],
                onChanged: (value) =>
                    setState(() => _department = value ?? 'all')),
          DropdownButtonFormField<String>(
              initialValue: _shiftFilter,
              decoration: const InputDecoration(labelText: 'Shift type'),
              items: [
                const DropdownMenuItem(value: 'all', child: Text('All shifts')),
                ..._templates.map((shift) => DropdownMenuItem(
                    value: shift['id'] as String,
                    child: Text(shift['name'] as String? ?? 'Shift'))),
              ],
              onChanged: (value) =>
                  setState(() => _shiftFilter = value ?? 'all')),
          Row(children: [
            Expanded(
                child: DropdownButtonFormField<String>(
                    initialValue: _assignmentFilter,
                    decoration: const InputDecoration(labelText: 'Coverage'),
                    items: const [
                      DropdownMenuItem(
                          value: 'all', child: Text('All coverage')),
                      DropdownMenuItem(
                          value: 'assigned', child: Text('Assigned')),
                      DropdownMenuItem(
                          value: 'unassigned', child: Text('Gaps')),
                    ],
                    onChanged: (value) =>
                        setState(() => _assignmentFilter = value ?? 'all'))),
            const SizedBox(width: 10),
            Expanded(
                child: DropdownButtonFormField<String>(
                    initialValue: _publicationFilter,
                    decoration: const InputDecoration(labelText: 'Schedule'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All states')),
                      DropdownMenuItem(
                          value: 'published', child: Text('Published')),
                      DropdownMenuItem(value: 'draft', child: Text('Draft')),
                    ],
                    onChanged: (value) =>
                        setState(() => _publicationFilter = value ?? 'all'))),
          ]),
          if (_assignmentFilter == 'unassigned')
            ..._issues
                .where((issue) => issue['code'] == 'understaffed')
                .map((issue) => GlassCard(
                        child: Row(children: [
                      const Icon(Icons.person_off_outlined,
                          color: AppColors.warning500),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(issue['message'] as String? ??
                              'Open coverage gap')),
                    ])))
          else
            ...widgets
        ]);
  }

  Widget _issuesTab() => _issues.isEmpty
      ? ListView(children: [
          const SizedBox(height: 130),
          EmptyStateWidget(
              icon: Icons.check_circle_outline,
              title: 'No known schedule issues',
              description:
                  'No conflict or coverage warnings found for this week.')
        ])
      : ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: _issues
              .map((issue) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassCard(
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: AppColors.warning500),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(
                                  issue['message'] as String? ??
                                      'Scheduling issue',
                                  style: AppTextStyles.bodyStrong),
                              Text(
                                  '${issue['code'] ?? ''} · ${issue['date'] ?? ''}',
                                  style: const TextStyle(
                                      color: AppColors.gray500, fontSize: 11))
                            ]))
                      ]))))
              .toList());

  Widget _workloadTab() => _workload.isEmpty
      ? ListView(children: [
          const SizedBox(height: 130),
          EmptyStateWidget(
              icon: Icons.bar_chart_rounded,
              title: 'No scheduled hours',
              description:
                  'Weekly workload will show when shifts are assigned.')
        ])
      : ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: _workload.map((item) {
            final user = (item['user'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
            return Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: GlassCard(
                    child: Row(children: [
                  const CircleAvatar(
                      radius: 18, child: Icon(Icons.person_outline)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(user['name'] as String? ?? 'Employee',
                            style: AppTextStyles.bodyStrong),
                        Text(
                            '${item['assignments']} shifts · ${item['days_worked']} days',
                            style: AppTextStyles.body)
                      ])),
                  Text('${item['scheduled_hours']}h',
                      style: AppTextStyles.title)
                ])));
          }).toList());

  Widget _coverageTab() {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Text('Minimum scheduled people per shift and weekday.',
              style: AppTextStyles.body),
          const SizedBox(height: 12),
          ..._rules.asMap().entries.map((entry) {
            final i = entry.key;
            final rule = entry.value;
            return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassCard(
                    child: Column(children: [
                  DropdownButtonFormField<String>(
                      initialValue: rule['shift_id'] as String?,
                      decoration: const InputDecoration(labelText: 'Shift'),
                      items: _templates
                          .map((shift) => DropdownMenuItem(
                              value: shift['id'] as String,
                              child: Text(shift['name'] as String)))
                          .toList(),
                      onChanged: (value) => setState(() {
                            _rules[i]['shift_id'] = value;
                          })),
                  DropdownButtonFormField<int>(
                      initialValue: rule['weekday'] as int? ?? 0,
                      decoration: const InputDecoration(labelText: 'Weekday'),
                      items: List.generate(
                          7,
                          (day) => DropdownMenuItem(
                              value: day, child: Text(weekdays[day]))),
                      onChanged: (value) =>
                          setState(() => _rules[i]['weekday'] = value ?? 0)),
                  TextFormField(
                      initialValue: '${rule['department'] ?? ''}',
                      decoration: const InputDecoration(
                          labelText: 'Department (optional)'),
                      onChanged: (value) =>
                          _rules[i]['department'] = value.trim()),
                  Row(children: [
                    const Text('People needed'),
                    const Spacer(),
                    IconButton(
                        onPressed: () => setState(() => _rules[i]
                                ['required_count'] =
                            ((_rules[i]['required_count'] as int? ?? 1) - 1)
                                .clamp(0, 100)),
                        icon: const Icon(Icons.remove_circle_outline)),
                    Text('${rule['required_count'] ?? 1}',
                        style: AppTextStyles.bodyStrong),
                    IconButton(
                        onPressed: () => setState(() => _rules[i]
                                ['required_count'] =
                            ((_rules[i]['required_count'] as int? ?? 1) + 1)
                                .clamp(0, 100)),
                        icon: const Icon(Icons.add_circle_outline)),
                    IconButton(
                        tooltip: 'Remove target',
                        onPressed: () => setState(() => _rules.removeAt(i)),
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.redAccent))
                  ])
                ])));
          }),
          OutlinedButton.icon(
              onPressed: _addCoverageRule,
              icon: const Icon(Icons.add),
              label: const Text('Add target')),
          const SizedBox(height: 8),
          FilledButton(
              onPressed: _saving ? null : _saveCoverage,
              child: _saving
                  ? const CircularProgressIndicator()
                  : const Text('Save targets'))
        ]);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canAssign = auth.hasPermission('shifts.assign');
    final canView = auth.hasPermission('shifts.view');
    if (!canAssign || !canView)
      return Scaffold(
          appBar: AppBar(title: const Text('Team schedule')),
          body: const Center(
              child: Text(
                  'You do not have permission to manage team schedules.')));
    final tabs = <Tab>[
      const Tab(text: 'Schedule'),
      Tab(text: 'Issues${_issues.isNotEmpty ? ' (${_issues.length})' : ''}'),
      const Tab(text: 'Workload'),
      if (auth.hasPermission('shifts.coverage.manage'))
        const Tab(text: 'Coverage')
    ];
    final pages = <Widget>[
      _scheduleTab(),
      _issuesTab(),
      _workloadTab(),
      if (auth.hasPermission('shifts.coverage.manage')) _coverageTab()
    ];
    return DefaultTabController(
        length: tabs.length,
        child: Scaffold(
          appBar: AppBar(
              title: const Text('Team schedule'),
              actions: [
                if (canAssign)
                  IconButton(
                    tooltip: 'Assign shift',
                    onPressed: _assignShift,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                  ),
                if (canAssign)
                  IconButton(
                    tooltip: 'Bulk assign shifts',
                    onPressed: _bulkAssign,
                    icon: const Icon(Icons.group_add_rounded),
                  ),
                IconButton(
                    tooltip: 'Previous week',
                    onPressed: () {
                      setState(() =>
                          _week = _week.subtract(const Duration(days: 7)));
                      _load();
                    },
                    icon: const Icon(Icons.chevron_left_rounded)),
                IconButton(
                    tooltip: 'Next week',
                    onPressed: () {
                      setState(
                          () => _week = _week.add(const Duration(days: 7)));
                      _load();
                    },
                    icon: const Icon(Icons.chevron_right_rounded)),
                IconButton(
                    tooltip: 'Schedule history',
                    onPressed: () => context.push('/schedule/history'),
                    icon: const Icon(Icons.history_rounded)),
                IconButton(
                    tooltip: 'Ask Attenda AI about this schedule',
                    onPressed: () => context.push(
                        '/home/ai?prompt=${Uri.encodeComponent('Review the schedule for week starting $_weekStart. Summarize coverage, workload, approved leave conflicts, and unavailable-time issues.')}'),
                    icon: const Icon(Icons.auto_awesome_rounded))
              ],
              bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(94),
                  child: Column(children: [
                    Text(
                        '${DateFormat('MMM d').format(_week)} – ${DateFormat('MMM d, yyyy').format(_week.add(const Duration(days: 6)))}',
                        style: AppTextStyles.bodyStrong),
                    if (canAssign)
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                    onPressed: _copyWeek,
                                    icon: const Icon(Icons.copy_rounded,
                                        size: 17),
                                    label: const Text('Repeat a week')),
                                TextButton.icon(
                                    onPressed: _publish,
                                    icon: const Icon(Icons.publish_rounded,
                                        size: 17),
                                    label: const Text('Publish'))
                              ])),
                    TabBar(tabs: tabs)
                  ]))),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? EmptyStateWidget(
                      icon: Icons.error_outline,
                      title: 'Could not load schedule',
                      description: _error!,
                      action: AppButton(
                          label: 'Retry', onPressed: _load, fullWidth: false))
                  : TabBarView(children: pages),
        ));
  }
}
