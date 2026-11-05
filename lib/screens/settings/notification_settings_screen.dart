import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final Map<String, bool> _prefs = {
    'attendance': true, 'requests': true, 'shifts': true, 'projects': true,
    'payroll': true, 'announcements': true, 'documents': true, 'security': true,
  };
  final Map<String, bool> _channels = {'in_app': true, 'push': true, 'email': false, 'whatsapp': false};
  bool _loading = true;
  bool _saving = false;
  bool _emailEnabled = false;
  bool _pushEnabled = true;
  bool _whatsappOptedIn = false;
  bool _quietEnabled = false;
  String _quietStart = '22:00';
  String _quietEnd = '08:00';
  String _digest = 'off';
  List<Map<String, dynamic>> _deliveries = [];

  static const _labels = {
    'attendance':      ('Attendance',                'Check-in, check-out, and attendance updates',           Icons.login),
    'requests':        ('Requests and Approvals',     'Leave, remote, overtime, expenses, and corrections',   Icons.approval),
    'shifts':          ('Shifts',                    'Shift reminders, availability, and open shifts',       Icons.calendar_today),
    'projects':        ('Projects',                  'Task assignments, comments, and timesheets',            Icons.work_outline),
    'payroll':         ('Payroll Notifications',     'When your payslip is ready to download',               Icons.receipt_long),
    'announcements':   ('Team Announcements',        'Organisation-wide notices from HR',                    Icons.campaign),
    'documents':       ('Documents and Onboarding',  'Employee documents and onboarding updates',              Icons.folder_outlined),
    'security':        ('Security',                  'Account and integration security alerts',                Icons.security),
  };

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await api.getNotificationPrefs();
      final deliveries = await api.getNotificationDeliveries();
      if (mounted) {
        setState(() {
        final categories = data['categories'] as Map? ?? {};
        final channels = data['channels'] as Map? ?? {};
        for (final k in _prefs.keys) {
          if (categories[k] is bool) _prefs[k] = categories[k] as bool;
        }
        for (final k in _channels.keys) {
          if (channels[k] is bool) _channels[k] = channels[k] as bool;
        }
        _emailEnabled = _channels['email'] == true;
        _pushEnabled = _channels['push'] != false;
        _whatsappOptedIn = data['whatsapp_opted_in'] == true;
        final quiet = data['quiet_hours'] as Map? ?? {};
        _quietEnabled = quiet['enabled'] == true;
        _quietStart = quiet['start'] as String? ?? '22:00';
        _quietEnd = quiet['end'] as String? ?? '08:00';
        _digest = data['digest'] as String? ?? 'off';
        _deliveries = deliveries;
        _loading = false;
      });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String key, bool val) async {
    setState(() { _prefs[key] = val; _saving = true; });
    try {
      await api.updateNotificationPrefs(_payload());
    } catch (e) {
      if (mounted) {
        setState(() => _prefs[key] = !val); // revert
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiFailure.fromError(e).userMessage)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleEmail(bool value) async {
    setState(() { _emailEnabled = value; _channels['email'] = value; _saving = true; });
    try {
      await api.updateNotificationPrefs(_payload());
    } catch (e) {
      if (mounted) {
        setState(() { _emailEnabled = !value; _channels['email'] = !value; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiFailure.fromError(e).userMessage)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _togglePush(bool value) async {
    setState(() { _pushEnabled = value; _channels['push'] = value; _saving = true; });
    try {
      await api.updateNotificationPrefs(_payload());
    } catch (e) {
      if (mounted) {
        setState(() { _pushEnabled = !value; _channels['push'] = !value; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiFailure.fromError(e).userMessage)));
      }
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _toggleWhatsApp(bool value) async {
    if (value) {
      final consent = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('Enable WhatsApp alerts?'),
        content: const Text('Attenda may send your selected alerts to the WhatsApp number on your profile. You can opt out at any time.'),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('I agree'))],
      ));
      if (consent != true || !mounted) return;
    }
    setState(() { _channels['whatsapp'] = value; _saving = true; });
    try {
      final payload = _payload();
      if (value) payload['whatsapp_consent'] = true;
      final response = await api.updateNotificationPrefs(payload);
      if (mounted) setState(() => _whatsappOptedIn = response['whatsapp_opted_in'] == true);
    } catch (e) {
      if (mounted) {
        setState(() => _channels['whatsapp'] = !value);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiFailure.fromError(e).userMessage)));
      }
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Map<String, dynamic> _payload() => {
    'categories': Map.from(_prefs),
    'channels': Map.from(_channels),
    'quiet_hours': {'enabled': _quietEnabled, 'start': _quietStart, 'end': _quietEnd},
    'digest': _digest,
  };

  Future<void> _setQuietTime(bool isStart) async {
    final current = (isStart ? _quietStart : _quietEnd).split(':');
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(current[0]), minute: int.parse(current[1])));
    if (picked == null || !mounted) return;
    setState(() {
      final value = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      if (isStart) { _quietStart = value; } else { _quietEnd = value; }
      _saving = true;
    });
    try { await api.updateNotificationPrefs(_payload()); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiFailure.fromError(e).userMessage))); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _toggleQuiet(bool value) async {
    setState(() { _quietEnabled = value; _saving = true; });
    try { await api.updateNotificationPrefs(_payload()); }
    catch (e) { if (mounted) { setState(() => _quietEnabled = !value); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiFailure.fromError(e).userMessage))); } }
    finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _setDigest(String value) async {
    setState(() { _digest = value; _saving = true; });
    try { await api.updateNotificationPrefs(_payload()); }
    catch (e) { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiFailure.fromError(e).userMessage))); } }
    finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Back header
            Row(children: [
              GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.arrow_back,
                      color: AppColors.gray600, size: 20),
                ),
              ),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Notifications', style: AppTextStyles.headline),
                if (_saving)
                  Text('Saving…',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: primary)),
              ]),
            ]),
            const SizedBox(height: 8),
            const Text('Choose which notifications you receive.',
                style: AppTextStyles.body),
            const SizedBox(height: 20),
            if (_loading)
              Center(child: CircularProgressIndicator(color: primary))
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
                              color: primary.withValues(alpha: 0.08),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.control),
                            ),
                            child: Icon(icon, color: primary, size: 18),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(label, style: AppTextStyles.bodyStrong),
                            Text(sub, style: AppTextStyles.caption),
                          ])),
                          Switch(
                            value: _prefs[key] ?? true,
                            onChanged: (v) => _toggle(key, v),
                          ),
                        ]),
                      ),
                    );
                  }).toList()
                    ..add(Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Column(children: [
                          Row(children: [
                            Container(width: 40, height: 40, decoration: BoxDecoration(color: primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadius.control)), child: Icon(Icons.bedtime_outlined, color: primary, size: 18)),
                            const SizedBox(width: 14),
                            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Quiet hours', style: AppTextStyles.bodyStrong), Text('Delay push and email until quiet hours end', style: AppTextStyles.caption)])),
                            Switch(value: _quietEnabled, onChanged: _toggleQuiet),
                          ]),
                          if (_quietEnabled) Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [
                            Expanded(child: OutlinedButton.icon(onPressed: _saving ? null : () => _setQuietTime(true), icon: const Icon(Icons.nightlight_outlined, size: 16), label: Text('From $_quietStart'))),
                            const SizedBox(width: 10),
                            Expanded(child: OutlinedButton.icon(onPressed: _saving ? null : () => _setQuietTime(false), icon: const Icon(Icons.wb_sunny_outlined, size: 16), label: Text('Until $_quietEnd'))),
                          ])),
                        ]),
                      ),
                    ))
                    ..add(Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(children: [
                          Container(width: 40, height: 40, decoration: BoxDecoration(color: primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadius.control)), child: Icon(Icons.chat_bubble_outline, color: primary, size: 18)),
                          const SizedBox(width: 14),
                          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('WhatsApp alerts', style: AppTextStyles.bodyStrong), Text('Requires your explicit consent and a profile phone number', style: AppTextStyles.caption)])),
                          Switch(value: _channels['whatsapp'] == true && _whatsappOptedIn, onChanged: _toggleWhatsApp),
                        ]),
                      ),
                    ))
                    ..add(Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(children: [
                          Container(width: 40, height: 40, decoration: BoxDecoration(color: primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadius.control)), child: Icon(Icons.mark_email_unread_outlined, color: primary, size: 18)),
                          const SizedBox(width: 14),
                          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Email digest', style: AppTextStyles.bodyStrong), Text('Group email alerts together', style: AppTextStyles.caption)])),
                          DropdownButton<String>(value: _digest, onChanged: _emailEnabled && !_saving ? (value) { if (value != null) _setDigest(value); } : null, items: const [DropdownMenuItem(value: 'off', child: Text('Off')), DropdownMenuItem(value: 'daily', child: Text('Daily')), DropdownMenuItem(value: 'weekly', child: Text('Weekly'))]),
                        ]),
                      ),
                    ))
                    ..add(Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(children: [
                          Container(width: 40, height: 40, decoration: BoxDecoration(color: primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadius.control)), child: Icon(Icons.notifications_active_outlined, color: primary, size: 18)),
                          const SizedBox(width: 14),
                          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Push alerts', style: AppTextStyles.bodyStrong), Text('Send alerts to this signed-in device', style: AppTextStyles.caption)])),
                          Switch(value: _pushEnabled, onChanged: _togglePush),
                        ]),
                      ),
                    ))
                    ..add(Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(AppRadius.control),
                            ),
                            child: Icon(Icons.email_outlined, color: primary, size: 18),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Email delivery', style: AppTextStyles.bodyStrong),
                            Text('Send enabled alerts to your account email', style: AppTextStyles.caption),
                          ])),
                          Switch(value: _emailEnabled, onChanged: _toggleEmail),
                        ]),
                      ),
                    ))
                    ..add(Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Recent delivery activity', style: AppTextStyles.bodyStrong),
                          const SizedBox(height: 8),
                          if (_deliveries.isEmpty) const Text('No channel delivery activity yet.', style: AppTextStyles.caption)
                          else ..._deliveries.take(10).map((item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: Row(children: [
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${item['event_type'] ?? 'Notification'} · ${item['channel'] ?? ''}', style: AppTextStyles.body),
                                Text('${item['status'] ?? ''}${item['last_error'] == null ? '' : ' · ${item['last_error']}'}', style: AppTextStyles.caption),
                              ])),
                              Text(item['created_at'] == null ? '' : DateTime.tryParse(item['created_at'].toString())?.toLocal().toString().substring(0, 16) ?? '', style: AppTextStyles.caption),
                            ]),
                          )),
                        ]),
                      ),
                    )),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
