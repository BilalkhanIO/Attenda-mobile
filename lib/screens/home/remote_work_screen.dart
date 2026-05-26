// Remote Work Declaration Screen
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class RemoteWorkScreen extends StatefulWidget {
  const RemoteWorkScreen({super.key});
  @override
  State<RemoteWorkScreen> createState() => _RemoteWorkScreenState();
}

class _RemoteWorkScreenState extends State<RemoteWorkScreen> {
  String _duration = 'full_day';
  final _noteCtrl  = TextEditingController();
  bool _loading    = false;

  @override
  void dispose() { _noteCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      await api.checkIn(type: 'remote', durationType: _duration);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🏠 Remote work request submitted!')));
        context.pop();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${e.toString().replaceAll('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.gray50,
    appBar: AppBar(title: const Text('Work Remote Today')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Info card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.purple100, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Icon(Icons.info_outline, color: AppColors.purple700, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text(
              'Your manager will be notified. AI will check in with you via WhatsApp at shift start.',
              style: TextStyle(fontSize: 13, color: AppColors.purple700),
            )),
          ]),
        ),
        const SizedBox(height: 24),

        const Text('Duration', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        for (final (val, label, desc, icon) in [
          ('full_day',  'Full Day',        'Work remote for the entire shift',    Icons.wb_sunny_outlined),
          ('morning',   'Morning Only',    'Work remote until midday',            Icons.wb_twilight),
          ('afternoon', 'Afternoon Only',  'Work remote from midday',             Icons.nights_stay_outlined),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => setState(() => _duration = val),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _duration == val ? AppColors.purple100 : AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _duration == val ? AppColors.purple700 : AppColors.gray200, width: _duration == val ? 2 : 1),
                ),
                child: Row(children: [
                  Icon(icon, color: _duration == val ? AppColors.purple700 : AppColors.gray500, size: 22),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _duration == val ? AppColors.purple700 : AppColors.dark950)),
                    Text(desc,  style: const TextStyle(fontSize: 12, color: AppColors.gray500)),
                  ]),
                  const Spacer(),
                  if (_duration == val) const Icon(Icons.check_circle, color: AppColors.purple700),
                ]),
              ),
            ),
          ),

        const SizedBox(height: 8),
        const Text('Note (optional)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextFormField(
          controller: _noteCtrl,
          decoration: const InputDecoration(hintText: 'e.g. Home — broadband issue at office'),
        ),
        const SizedBox(height: 28),
        AppButton(label: 'Request Remote Work', icon: Icons.home_rounded, onPressed: _submit, loading: _loading),
      ]),
    ),
  );
}
