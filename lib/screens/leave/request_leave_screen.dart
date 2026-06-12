import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class RequestLeaveScreen extends StatefulWidget {
  const RequestLeaveScreen({super.key});
  @override
  State<RequestLeaveScreen> createState() => _RequestLeaveScreenState();
}

class _RequestLeaveScreenState extends State<RequestLeaveScreen> {
  String _type         = 'annual';
  DateTime? _start;
  DateTime? _end;
  bool _isHalfDay      = false;
  String _halfPeriod   = 'morning';
  final _reasonCtrl    = TextEditingController();
  bool _loading        = false;

  @override
  void dispose() { _reasonCtrl.dispose(); super.dispose(); }

  double get _workingDays {
    if (_isHalfDay) return 0.5;
    if (_start == null || _end == null) return 0;
    int count = 0;
    var cur = DateTime(_start!.year, _start!.month, _start!.day);
    while (!cur.isAfter(_end!)) {
      if (cur.weekday != DateTime.saturday && cur.weekday != DateTime.sunday) count++;
      cur = cur.add(const Duration(days: 1));
    }
    return count.toDouble();
  }

  Future<void> _submit() async {
    if (_start == null) { _snack('Select a start date'); return; }
    if (!_isHalfDay && _end == null) { _snack('Select an end date'); return; }
    if (!_isHalfDay && _start!.isAfter(_end!)) { _snack('End date must be after start date'); return; }

    setState(() => _loading = true);
    try {
      await api.submitLeave({
        'leave_type':    _type,
        'start_date':    DateFormat('yyyy-MM-dd').format(_start!),
        'end_date':      DateFormat('yyyy-MM-dd').format(_isHalfDay ? _start! : _end!),
        'reason':        _reasonCtrl.text.trim(),
        'is_half_day':   _isHalfDay,
        if (_isHalfDay) 'half_day_period': _halfPeriod,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Leave request submitted!')));
        context.pop();
      }
    } catch (e) {
      _snack(ApiFailure.fromError(e).userMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _start : _end) ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(data: AppTheme.glass, child: child!),
    );
    if (picked == null) return;
    setState(() { if (isStart) {
      _start = picked;
    } else {
      _end = picked;
    } });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.meshBot,
    body: Container(
      decoration: const BoxDecoration(gradient: AppGradients.mesh),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
                const Text('Request Leave',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
            ),
            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Leave Type
                  _sectionLabel('Leave Type'),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final t in ['annual', 'sick', 'wfh', 'unpaid', 'emergency'])
                      GestureDetector(
                        onTap: () => setState(() => _type = t),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: _type == t
                                    ? AppColors.primary600
                                    : Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _type == t ? AppColors.primary600 : Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Text(
                                t.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _type == t ? Colors.white : Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 20),

                  // Half-day toggle
                  GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(children: [
                      const Icon(Icons.calendar_view_day_outlined, color: AppColors.teal700, size: 20),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Half-Day Leave',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                      Switch(
                        value: _isHalfDay,
                        onChanged: (v) => setState(() => _isHalfDay = v),
                        activeThumbColor: AppColors.primary600,
                      ),
                    ]),
                  ),

                  if (_isHalfDay) ...[
                    const SizedBox(height: 10),
                    GlassCard(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        for (final (val, label) in [('morning', 'Morning'), ('afternoon', 'Afternoon')])
                          Expanded(child: GestureDetector(
                            onTap: () => setState(() => _halfPeriod = val),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _halfPeriod == val
                                    ? AppColors.primary600
                                    : Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _halfPeriod == val ? AppColors.primary600 : Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Center(
                                child: Text(label, style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _halfPeriod == val ? Colors.white : Colors.white.withValues(alpha: 0.6),
                                )),
                              ),
                            ),
                          )),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Date range
                  _sectionLabel('Date${_isHalfDay ? '' : ' Range'}'),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _dateTile('Start Date', _start, () => _pickDate(true))),
                    if (!_isHalfDay) ...[
                      const SizedBox(width: 12),
                      Expanded(child: _dateTile('End Date', _end, () => _pickDate(false))),
                    ],
                  ]),
                  if (_workingDays > 0) ...[
                    const SizedBox(height: 8),
                    Text('${_isHalfDay ? '½' : _workingDays.toInt()} working day${!_isHalfDay && _workingDays != 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 13, color: AppColors.primary600, fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 20),

                  // Reason
                  _sectionLabel('Reason (optional)'),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _reasonCtrl,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(hintText: 'Brief reason for leave...'),
                  ),
                  const SizedBox(height: 28),
                  AppButton(label: 'Submit Request', onPressed: _submit, loading: _loading),
                ]),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _sectionLabel(String text) =>
      Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white));

  Widget _dateTile(String label, DateTime? val, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.55), fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(
              val != null ? DateFormat('d MMM yyyy').format(val) : 'Select date',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: val != null ? Colors.white : Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}
