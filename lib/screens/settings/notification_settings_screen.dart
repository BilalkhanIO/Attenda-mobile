import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  Map<String, bool> _prefs = {
    'check_in': true, 'leave_updates': true, 'shift_reminders': true,
    'payroll': true, 'announcements': true, 'late_alerts': true,
  };
  bool _loading = true;
  bool _saving = false;

  static const _labels = {
    'check_in':        ('Check-in Confirmations',   'Get notified when you check in or out',                Icons.login),
    'leave_updates':   ('Leave Updates',             'Approval, rejection and cancellation notices',         Icons.beach_access),
    'shift_reminders': ('Shift Reminders',           'Upcoming shift and swap request alerts',               Icons.calendar_today),
    'payroll':         ('Payroll Notifications',     'When your payslip is ready to download',               Icons.receipt_long),
    'announcements':   ('Team Announcements',        'Organisation-wide notices from HR',                    Icons.campaign),
    'late_alerts':     ('Late Arrival Alerts',       'Warnings when you haven\'t checked in by shift start', Icons.schedule),
  };

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await api.getNotificationPrefs();
      if (mounted) setState(() {
        for (final k in _prefs.keys) {
          if (data[k] is bool) _prefs[k] = data[k] as bool;
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String key, bool val) async {
    setState(() { _prefs[key] = val; _saving = true; });
    try {
      await api.updateNotificationPrefs(Map.from(_prefs).cast<String, bool>());
    } catch (_) {
      if (mounted) setState(() => _prefs[key] = !val); // revert
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Back header
            Row(children: [
              GestureDetector(
                onTap: () => context.pop(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.white.withOpacity(0.18)),
                      ),
                      child: Icon(Icons.arrow_back, color: Colors.white.withOpacity(0.8), size: 20),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Notifications', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                if (_saving) Text('Saving…', style: TextStyle(fontSize: 12, color: AppColors.primary.withOpacity(0.8))),
              ]),
            ]),
            const SizedBox(height: 8),
            Text('Choose which notifications you receive.', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5))),
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator(color: AppColors.primary))
            else
              Expanded(
                child: ListView(
                  children: _labels.entries.map((e) {
                    final key = e.key;
                    final (label, sub, icon) = e.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                            ),
                            child: Icon(icon, color: AppColors.primary, size: 18),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                            Text(sub, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
                          ])),
                          Switch(
                            value: _prefs[key] ?? true,
                            onChanged: (v) => _toggle(key, v),
                            activeColor: AppColors.primary,
                            activeTrackColor: AppColors.primary.withOpacity(0.3),
                          ),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
