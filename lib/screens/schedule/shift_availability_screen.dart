import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class ShiftAvailabilityScreen extends StatefulWidget {
  const ShiftAvailabilityScreen({super.key});
  @override
  State<ShiftAvailabilityScreen> createState() =>
      _ShiftAvailabilityScreenState();
}

class _ShiftAvailabilityScreenState extends State<ShiftAvailabilityScreen> {
  List<Map<String, dynamic>> _mine = [];
  List<Map<String, dynamic>> _team = [];
  bool _loading = true;
  String? _error;
  String _status = 'pending';

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
      final canReview = context
          .read<AuthProvider>()
          .hasPermission('shifts.availability.manage');
      final results = await Future.wait([
        api.getMyShiftAvailability(),
        if (canReview) api.getTeamShiftAvailability(status: _status),
      ]);
      if (!mounted) return;
      setState(() {
        _mine = results.first.cast<Map<String, dynamic>>();
        _team =
            results.length > 1 ? results[1].cast<Map<String, dynamic>>() : [];
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

  Future<void> _request() async {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AvailabilityRequestSheet(),
    );
    if (submitted == true && mounted) _load();
  }

  Future<void> _review(Map<String, dynamic> item, String status) async {
    String? reason;
    if (status == 'rejected') {
      reason = await showDialog<String>(
          context: context,
          builder: (dialogContext) {
            final controller = TextEditingController();
            return AlertDialog(
              title: const Text('Decline availability'),
              content: TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 500,
                  decoration:
                      const InputDecoration(labelText: 'Reason required')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () {
                      final value = controller.text.trim();
                      if (value.isNotEmpty) Navigator.pop(dialogContext, value);
                    },
                    child: const Text('Decline'))
              ],
            );
          });
      if (reason == null || reason.trim().isEmpty) return;
    }
    try {
      await api.reviewShiftAvailability(item['id'] as String,
          status: status, reason: reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Availability $status')));
      _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiFailure.fromError(error).userMessage)));
    }
  }

  Future<void> _cancel(Map<String, dynamic> item) async {
    try {
      await api.cancelShiftAvailability(item['id'] as String);
      if (mounted) _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiFailure.fromError(error).userMessage)));
    }
  }

  String _scheduleLabel(Map<String, dynamic> item) {
    final time = item['start_time'] != null
        ? '${item['start_time']}–${item['end_time']}'
        : 'All day';
    final date = item['date'] as String?;
    if (date != null) return '${date.substring(0, 10)} · $time';
    final days = const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    final weekday = (item['weekday'] as int?) ?? 0;
    final from = item['starts_on'] == null
        ? ''
        : ' from ${item['starts_on'].toString().substring(0, 10)}';
    final until = item['ends_on'] == null
        ? ''
        : ' to ${item['ends_on'].toString().substring(0, 10)}';
    return 'Every ${days[weekday]}$from$until · $time';
  }

  Widget _itemCard(Map<String, dynamic> item, {bool team = false}) {
    final primary = Theme.of(context).colorScheme.primary;
    final status = item['status'] as String? ?? 'pending';
    final color = status == 'approved'
        ? AppColors.success500
        : status == 'rejected'
            ? AppColors.danger500
            : AppColors.warning500;
    final user = (item['user'] as Map?)?.cast<String, dynamic>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(
                  '${item['kind'] == 'preferred' ? 'Prefers to work' : 'Unavailable'} · ${_scheduleLabel(item)}',
                  style: AppTextStyles.bodyStrong)),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10)),
              child: Text(status.toUpperCase(),
                  style: TextStyle(
                      color: color, fontSize: 10, fontWeight: FontWeight.w700)))
        ]),
        if (team && user != null)
          Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                  '${user['name'] ?? 'Employee'}${user['department'] == null ? '' : ' · ${user['department']}'}',
                  style: AppTextStyles.body)),
        if ((item['note'] as String?)?.isNotEmpty == true)
          Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(item['note'] as String, style: AppTextStyles.body)),
        if ((item['review_note'] as String?)?.isNotEmpty == true)
          Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text('Decision: ${item['review_note']}',
                  style: AppTextStyles.body)),
        if (team && status == 'pending')
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton.icon(
                    onPressed: () => _review(item, 'rejected'),
                    icon: const Icon(Icons.close_rounded, size: 17),
                    label: const Text('Decline')),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                    onPressed: () => _review(item, 'approved'),
                    icon: const Icon(Icons.check_rounded, size: 17),
                    label: const Text('Approve'))
              ])),
        if (!team && status == 'pending')
          Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: () => _cancel(item),
                  child: Text('Cancel request',
                      style: TextStyle(color: primary)))),
      ])),
    );
  }

  Widget _myRequests() => _loading
      ? const Center(child: CircularProgressIndicator())
      : _error != null
          ? Center(child: Text(_error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: _mine.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      EmptyStateWidget(
                          icon: Icons.event_available_outlined,
                          title: 'No availability requests',
                          description:
                              'Add your preferred work times or unavailable dates.')
                    ])
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      children: _mine.map(_itemCard).toList()));

  Widget _teamRequests() => Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Request status'),
                items: const [
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'approved', child: Text('Approved')),
                  DropdownMenuItem(value: 'rejected', child: Text('Declined')),
                  DropdownMenuItem(value: 'all', child: Text('All'))
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                  _load();
                })),
        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _team.isEmpty
                            ? ListView(children: [
                                const SizedBox(height: 100),
                                EmptyStateWidget(
                                    icon: Icons.inbox_outlined,
                                    title: 'No requests in this view',
                                    description:
                                        'Team availability requests appear here.')
                              ])
                            : ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 100),
                                children: _team
                                    .map((item) => _itemCard(item, team: true))
                                    .toList())))
      ]);

  @override
  Widget build(BuildContext context) {
    final canReview = context
        .watch<AuthProvider>()
        .hasPermission('shifts.availability.manage');
    return DefaultTabController(
        length: canReview ? 2 : 1,
        child: Scaffold(
          appBar: AppBar(
              title: const Text('Availability'),
              actions: [
                IconButton(
                    tooltip: 'Add availability',
                    onPressed: _request,
                    icon: const Icon(Icons.add_circle_outline_rounded))
              ],
              bottom: canReview
                  ? const TabBar(tabs: [
                      Tab(text: 'My requests'),
                      Tab(text: 'Team requests')
                    ])
                  : null),
          body: canReview
              ? TabBarView(children: [_myRequests(), _teamRequests()])
              : _myRequests(),
        ));
  }
}

class _AvailabilityRequestSheet extends StatefulWidget {
  @override
  State<_AvailabilityRequestSheet> createState() =>
      _AvailabilityRequestSheetState();
}

class _AvailabilityRequestSheetState extends State<_AvailabilityRequestSheet> {
  final _note = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _startsOn = TextEditingController();
  final _endsOn = TextEditingController();
  String _kind = 'unavailable';
  String _mode = 'date';
  String _date = '';
  int _weekday = 0;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _note.dispose();
    _start.dispose();
    _end.dispose();
    _startsOn.dispose();
    _endsOn.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final picked = await showDatePicker(
        context: context,
        firstDate: DateTime.now().subtract(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 730)),
        initialDate: DateTime.now());
    if (picked != null)
      controller.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickTime(TextEditingController controller) async {
    final time =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time != null)
      controller.text =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _submit() async {
    if (_mode == 'date' && _date.isEmpty ||
        _mode == 'recurring' && _startsOn.text.isEmpty) {
      setState(() => _error = 'Choose a date or recurring start date.');
      return;
    }
    if (_start.text.isNotEmpty != _end.text.isNotEmpty) {
      setState(
          () => _error = 'Enter both times, or leave both empty for all day.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await api.requestShiftAvailability({
        'kind': _kind,
        if (_mode == 'date') 'date': _date else 'weekday': _weekday,
        if (_mode == 'recurring') 'starts_on': _startsOn.text,
        if (_endsOn.text.isNotEmpty) 'ends_on': _endsOn.text,
        if (_start.text.isNotEmpty) 'start_time': _start.text,
        if (_end.text.isNotEmpty) 'end_time': _end.text,
        'note': _note.text.trim()
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        setState(() {
          _error = ApiFailure.fromError(error).userMessage;
          _saving = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add availability', style: AppTextStyles.title),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _kind,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(
                          value: 'unavailable', child: Text('Unavailable')),
                      DropdownMenuItem(
                          value: 'preferred', child: Text('Prefer to work')),
                    ],
                    onChanged: (value) =>
                        setState(() => _kind = value ?? 'unavailable'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _mode,
                    decoration: const InputDecoration(labelText: 'Repeats'),
                    items: const [
                      DropdownMenuItem(value: 'date', child: Text('One date')),
                      DropdownMenuItem(
                          value: 'recurring', child: Text('Weekly')),
                    ],
                    onChanged: (value) =>
                        setState(() => _mode = value ?? 'date'),
                  ),
                  const SizedBox(height: 12),
                  if (_mode == 'date')
                    OutlinedButton.icon(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          firstDate:
                              DateTime.now().subtract(const Duration(days: 1)),
                          lastDate:
                              DateTime.now().add(const Duration(days: 730)),
                          initialDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() => _date =
                              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}');
                        }
                      },
                      icon: const Icon(Icons.calendar_today),
                      label: Text(_date.isEmpty ? 'Choose date' : _date),
                    )
                  else ...[
                    DropdownButtonFormField<int>(
                      initialValue: _weekday,
                      decoration: const InputDecoration(labelText: 'Weekday'),
                      items: List.generate(
                          7,
                          (i) => DropdownMenuItem(
                                value: i,
                                child: Text(const [
                                  'Monday',
                                  'Tuesday',
                                  'Wednesday',
                                  'Thursday',
                                  'Friday',
                                  'Saturday',
                                  'Sunday'
                                ][i]),
                              )),
                      onChanged: (value) =>
                          setState(() => _weekday = value ?? 0),
                    ),
                    TextField(
                        controller: _startsOn,
                        readOnly: true,
                        decoration: InputDecoration(
                            labelText: 'Starts on',
                            suffixIcon: IconButton(
                                icon: const Icon(Icons.calendar_month),
                                onPressed: () => _pickDate(_startsOn))),
                        onTap: () => _pickDate(_startsOn)),
                    TextField(
                        controller: _endsOn,
                        readOnly: true,
                        decoration: InputDecoration(
                            labelText: 'Ends on (optional)',
                            suffixIcon: IconButton(
                                icon: const Icon(Icons.calendar_month),
                                onPressed: () => _pickDate(_endsOn))),
                        onTap: () => _pickDate(_endsOn)),
                  ],
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: _start,
                            readOnly: true,
                            decoration: InputDecoration(
                                labelText: 'From',
                                suffixIcon: IconButton(
                                    icon: const Icon(Icons.access_time),
                                    onPressed: () => _pickTime(_start))),
                            onTap: () => _pickTime(_start))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TextField(
                            controller: _end,
                            readOnly: true,
                            decoration: InputDecoration(
                                labelText: 'Until',
                                suffixIcon: IconButton(
                                    icon: const Icon(Icons.access_time),
                                    onPressed: () => _pickTime(_end))),
                            onTap: () => _pickTime(_end))),
                  ]),
                  TextField(
                      controller: _note,
                      maxLength: 500,
                      decoration:
                          const InputDecoration(labelText: 'Note (optional)')),
                  if (_error != null)
                    Text(_error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const CircularProgressIndicator()
                          : const Text('Submit request')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
