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
  bool _loading    = false;

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      await api.checkIn(type: 'remote', durationType: _duration);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🏠 Remote work request submitted!')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: ${e.toString().replaceAll('Exception: ', '')}')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(title: const Text('Work Remote Today')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Info banner
        const GlassCard(
          tint: AppColors.purple500,
          padding: EdgeInsets.all(16),
          child: Row(children: [
            Icon(Icons.info_outline, color: AppColors.purple500, size: 20),
            SizedBox(width: 12),
            Expanded(child: Text(
              'Your manager will be notified. AI will check in with you via WhatsApp at shift start.',
              style: TextStyle(fontSize: 13, color: AppColors.purple100),
            )),
          ]),
        ),
        const SizedBox(height: 24),

        const Text('Duration', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 12),

        for (final (val, label, desc, icon) in [
          ('full_day',  'Full Day',       'Work remote for the entire shift',  Icons.wb_sunny_outlined),
          ('morning',   'Morning Only',   'Work remote until midday',          Icons.wb_twilight),
          ('afternoon', 'Afternoon Only', 'Work remote from midday',           Icons.nights_stay_outlined),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => setState(() => _duration = val),
              child: GlassCard(
                tint: _duration == val ? AppColors.purple500 : null,
                child: Row(children: [
                  Icon(icon,
                      color: _duration == val ? AppColors.purple500 : Colors.white.withValues(alpha: 0.5),
                      size: 22),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700,
                        color: _duration == val ? Colors.white : Colors.white.withValues(alpha: 0.8))),
                    Text(desc, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
                  ])),
                  if (_duration == val)
                    const Icon(Icons.check_circle, color: AppColors.purple500),
                ]),
              ),
            ),
          ),

        const SizedBox(height: 28),
        AppButton(
            label: 'Request Remote Work',
            icon: Icons.home_rounded,
            onPressed: _submit,
            loading: _loading),
      ]),
    ),
  );
}
