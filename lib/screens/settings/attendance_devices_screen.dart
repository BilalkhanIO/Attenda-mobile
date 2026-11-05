import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../services/attendance_device_keys.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class AttendanceDevicesScreen extends StatefulWidget {
  const AttendanceDevicesScreen({super.key});

  @override
  State<AttendanceDevicesScreen> createState() =>
      _AttendanceDevicesScreenState();
}

class _AttendanceDevicesScreenState extends State<AttendanceDevicesScreen> {
  final _label = TextEditingController();
  final _keys = AttendanceDeviceKeys();
  List<Map<String, dynamic>> _devices = [];
  bool _loading = true;
  bool _enrolling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final devices = await api.getMyAttendanceDevices();
      if (mounted) setState(() => _devices = devices);
    } catch (e) {
      if (mounted) {
        setState(() => _error = ApiFailure.fromError(e).userMessage);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _enroll() async {
    final userId = context.read<AuthProvider>().user?.id;
    final label = _label.text.trim();
    if (userId == null || label.length < 2) {
      setState(
          () => _error = 'Enter a device name with at least 2 characters.');
      return;
    }
    setState(() {
      _enrolling = true;
      _error = null;
    });
    try {
      final keyPair = await _keys.createKey();
      final enrollment = await api.startAttendanceDeviceEnrollment(
          label: label, publicKey: keyPair.publicKey);
      final device = Map<String, dynamic>.from(enrollment['device'] as Map);
      final challenge = enrollment['challenge'] as String;
      final signature = await _keys.signChallenge(keyPair.alias, challenge);
      await api.confirmAttendanceDeviceEnrollment(
        id: device['id'] as String,
        challenge: challenge,
        signature: signature,
      );
      await _keys.rememberEnrollment(
          userId, device['id'] as String, keyPair.alias);
      _label.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Device verified. An organization administrator must approve it.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiFailure.fromError(e).userMessage);
    } finally {
      if (mounted) setState(() => _enrolling = false);
    }
  }

  Future<void> _revoke(Map<String, dynamic> device) async {
    final id = device['id'] as String?;
    final userId = context.read<AuthProvider>().user?.id;
    if (id == null || userId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke this device?'),
        content: const Text(
            'It will no longer be trusted for attendance. You can enroll it again later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep device')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Revoke')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await api.revokeMyAttendanceDevice(id);
      await _keys.clearIfRevoked(userId, id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiFailure.fromError(e).userMessage)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEnrollOnPlatform = defaultTargetPlatform == TargetPlatform.android;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Trusted attendance devices')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            const GlassCard(
              tint: AppColors.info500,
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.verified_user_outlined, color: AppColors.info700),
                SizedBox(width: 12),
                Expanded(
                    child: Text(
                        'Enroll this Android device with a secure key. Your private key stays on the device. Enrollment requires administrator approval and does not change attendance check-in rules.',
                        style: AppTextStyles.body)),
              ]),
            ),
            if (!canEnrollOnPlatform) ...[
              const SizedBox(height: 16),
              const GlassCard(
                tint: AppColors.warning500,
                child: Text(
                    'Enrollment is currently supported on Android. You can still review and revoke devices here.',
                    style: AppTextStyles.body),
              ),
            ],
            const SizedBox(height: 20),
            Text('Add this device', style: AppTextStyles.headline),
            const SizedBox(height: 10),
            TextField(
              controller: _label,
              maxLength: 100,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Device name',
                hintText: 'e.g. My Android phone',
                prefixIcon: Icon(Icons.phone_android),
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _enrolling || !canEnrollOnPlatform ? null : _enroll,
                icon: _enrolling
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_moderator_outlined),
                label: Text(_enrolling ? 'Verifying device…' : 'Enroll device'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: const TextStyle(
                      color: AppColors.danger500, fontSize: 13)),
            ],
            const SizedBox(height: 28),
            Row(children: [
              Expanded(
                  child: Text('Your devices', style: AppTextStyles.headline)),
              IconButton(
                  onPressed: _loading ? null : _load,
                  tooltip: 'Refresh devices',
                  icon: const Icon(Icons.refresh)),
            ]),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()))
            else if (_devices.isEmpty)
              const GlassCard(
                  child: Text('No attendance devices enrolled yet.',
                      style: AppTextStyles.body))
            else
              ..._devices.map(_deviceCard),
          ],
        ),
      ),
    );
  }

  Widget _deviceCard(Map<String, dynamic> device) {
    final status = (device['status'] as String? ?? 'pending').toLowerCase();
    final color = switch (status) {
      'approved' => AppColors.success700,
      'revoked' => AppColors.gray500,
      _ => AppColors.warning800,
    };
    final date =
        DateTime.tryParse(device['created_at']?.toString() ?? '')?.toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.phone_android, color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(device['label']?.toString() ?? 'Android device',
                    style: AppTextStyles.bodyStrong),
                const SizedBox(height: 4),
                Text(
                    date == null
                        ? 'Added device'
                        : 'Added ${date.day}/${date.month}/${date.year}',
                    style: AppTextStyles.caption),
                const SizedBox(height: 8),
                GlassBadge(
                    text: status[0].toUpperCase() + status.substring(1),
                    color: color),
              ])),
          if (status != 'revoked')
            IconButton(
                onPressed: () => _revoke(device),
                tooltip: 'Revoke device',
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.danger500)),
        ]),
      ),
    );
  }
}
