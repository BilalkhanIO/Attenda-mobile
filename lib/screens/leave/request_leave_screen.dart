// Request Leave Screen
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class RequestLeaveScreen extends StatefulWidget {
  const RequestLeaveScreen({super.key});
  @override
  State<RequestLeaveScreen> createState() => _RequestLeaveScreenState();
}

class _RequestLeaveScreenState extends State<RequestLeaveScreen> {
  String _type       = 'annual';
  DateTime? _start;
  DateTime? _end;
  final _reasonCtrl  = TextEditingController();
  bool _loading      = false;

  @override
  void dispose() { _reasonCtrl.dispose(); super.dispose(); }

  int get _workingDays {
    if (_start == null || _end == null) return 0;
    int count = 0;
    var cur = DateTime(_start!.year, _start!.month, _start!.day);
    while (!cur.isAfter(_end!)) {
      if (cur.weekday != DateTime.saturday && cur.weekday != DateTime.sunday) count++;
      cur = cur.add(const Duration(days: 1));
    }
    return count;
  }

  Future<void> _submit() async {
    if (_start == null || _end == null) { _snack('Select start and end dates'); return; }
    if (_start!.isAfter(_end!))         { _snack('End date must be after start date'); return; }

    setState(() => _loading = true);
    try {
      await api.submitLeave({
        'leave_type':    _type,
        'start_date':    DateFormat('yyyy-MM-dd').format(_start!),
        'end_date':      DateFormat('yyyy-MM-dd').format(_end!),
        'reason':        _reasonCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leave request submitted!')));
        context.pop();
      }
    } catch (e) {
      _snack('Failed to submit: ${e.toString().replaceAll('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _start : _end) ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() { if (isStart) _start = picked; else _end = picked; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.gray50,
    appBar: AppBar(title: const Text('Request Leave')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Leave Type
        const Text('Leave Type', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in ['annual', 'sick', 'wfh', 'unpaid', 'emergency'])
            GestureDetector(
              onTap: () => setState(() => _type = t),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _type == t ? AppColors.primary600 : AppColors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _type == t ? AppColors.primary600 : AppColors.gray200),
                ),
                child: Text(t.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _type == t ? Colors.white : AppColors.dark950)),
              ),
            ),
        ]),
        const SizedBox(height: 20),

        // Date range
        Row(children: [
          Expanded(child: _DateTile('Start Date', _start, () => _pickDate(true))),
          const SizedBox(width: 12),
          Expanded(child: _DateTile('End Date', _end, () => _pickDate(false))),
        ]),
        const SizedBox(height: 8),
        if (_start != null && _end != null)
          Text('$_workingDays working day${_workingDays != 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 13, color: AppColors.primary600, fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),

        // Reason
        const Text('Reason (optional)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextFormField(
          controller: _reasonCtrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Brief reason for leave...'),
        ),
        const SizedBox(height: 28),
        AppButton(label: 'Submit Request', onPressed: _submit, loading: _loading),
      ]),
    ),
  );

  Widget _DateTile(String label, DateTime? val, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.gray200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.gray500, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(val != null ? DateFormat('d MMM yyyy').format(val) : 'Select date',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: val != null ? AppColors.dark950 : AppColors.gray500)),
      ]),
    ),
  );
}
