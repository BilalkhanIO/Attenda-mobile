import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/wifi_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

/// Tracking Reliability — walks the user through everything Android needs to
/// keep WiFi attendance alive when the screen is off (Doze, OEM battery
/// managers). Surfaces live status for each requirement with a fix action.
class ReliabilityScreen extends StatefulWidget {
  const ReliabilityScreen({super.key});

  @override
  State<ReliabilityScreen> createState() => _ReliabilityScreenState();
}

class _CheckResult {
  final bool ok;
  final String detail;
  const _CheckResult(this.ok, this.detail);
}

class _ReliabilityScreenState extends State<ReliabilityScreen> {
  bool _loading = true;
  _CheckResult _service = const _CheckResult(false, 'Checking…');
  _CheckResult _battery = const _CheckResult(false, 'Checking…');
  _CheckResult _notifications = const _CheckResult(false, 'Checking…');
  _CheckResult _location = const _CheckResult(false, 'Checking…');
  _CheckResult _heartbeat = const _CheckResult(false, 'Checking…');

  @override
  void initState() {
    super.initState();
    _runChecks();
  }

  Future<void> _runChecks() async {
    setState(() => _loading = true);

    final running = await FlutterForegroundTask.isRunningService;

    var batteryOk = true;
    var batteryDetail = 'Not applicable on this platform';
    if (Platform.isAndroid) {
      batteryOk = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      batteryDetail = batteryOk
          ? 'Attenda is exempt from battery optimisation'
          : 'Android may pause tracking when the screen is off';
    }

    final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
    final notifOk = notifPerm == NotificationPermission.granted;

    final locStatus = await Permission.locationWhenInUse.status;
    final locOk = locStatus.isGranted;

    final svc = WifiAttendanceService();
    final hb = svc.lastHeartbeatAt;
    final hbOk = hb != null &&
        DateTime.now().difference(hb) < const Duration(minutes: 6);

    if (!mounted) return;
    setState(() {
      _service = _CheckResult(
        running,
        running
            ? 'Background tracking service is running'
            : 'Service is not running — attendance won\'t track in background',
      );
      _battery = _CheckResult(batteryOk, batteryDetail);
      _notifications = _CheckResult(
        notifOk,
        notifOk
            ? 'Tracking status notifications enabled'
            : 'Android kills silent background services more aggressively',
      );
      _location = _CheckResult(
        locOk,
        locOk
            ? 'Location granted — WiFi network name is readable'
            : 'Without location, Android hides the WiFi name from the app',
      );
      _heartbeat = _CheckResult(
        hbOk,
        hb == null
            ? 'No heartbeat yet this session (normal if not checked in)'
            : 'Last heartbeat ${_timeAgo(hb)}',
      );
      _loading = false;
    });
  }

  String _timeAgo(DateTime t) {
    final mins = DateTime.now().difference(t).inMinutes;
    if (mins < 1) return 'just now';
    if (mins == 1) return '1 minute ago';
    if (mins < 60) return '$mins minutes ago';
    final h = mins ~/ 60;
    return h == 1 ? '1 hour ago' : '$h hours ago';
  }

  Future<void> _fixService() async {
    await WifiAttendanceService().ensureServiceRunning();
    await _runChecks();
  }

  Future<void> _fixBattery() async {
    try {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (_) {}
    await _runChecks();
  }

  Future<void> _fixNotifications() async {
    try {
      await FlutterForegroundTask.requestNotificationPermission();
    } catch (_) {}
    await _runChecks();
  }

  Future<void> _fixLocation() async {
    final granted = await WifiAttendanceService().ensureLocationPermission();
    if (!granted) await openAppSettings();
    await _runChecks();
  }

  Future<void> _fixHeartbeat() async {
    await WifiAttendanceService().checkAndReport();
    await _runChecks();
  }

  @override
  Widget build(BuildContext context) {
    final allOk = _service.ok && _battery.ok && _notifications.ok && _location.ok;
    return Scaffold(
      appBar: AppBar(title: const Text('Tracking Reliability')),
      body: RefreshIndicator(
        onRefresh: _runChecks,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Icon(
                  _loading
                      ? Icons.hourglass_top
                      : allOk
                          ? Icons.verified_outlined
                          : Icons.warning_amber_rounded,
                  size: 32,
                  color: _loading
                      ? Colors.white54
                      : allOk
                          ? AppColors.success500
                          : AppColors.warning500,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _loading
                            ? 'Running checks…'
                            : allOk
                                ? 'Tracking is set up correctly'
                                : 'Tracking may be unreliable',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'These settings keep auto check-in working while your screen is off.',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            _checkTile(Icons.sync, 'Background service', _service, _fixService, 'Restart'),
            _checkTile(Icons.battery_saver_outlined, 'Battery optimisation', _battery,
                _fixBattery, 'Exempt'),
            _checkTile(Icons.notifications_active_outlined, 'Notifications',
                _notifications, _fixNotifications, 'Allow'),
            _checkTile(Icons.location_on_outlined, 'Location (WiFi name)', _location,
                _fixLocation, 'Grant'),
            _checkTile(Icons.favorite_outline, 'Server heartbeat', _heartbeat,
                _fixHeartbeat, 'Ping now'),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.phone_android, size: 16, color: AppColors.primary600),
                    SizedBox(width: 8),
                    Text('Using Samsung, Xiaomi, Huawei or OnePlus?',
                        style: TextStyle(
                            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'These phones have an extra battery manager that can stop Attenda '
                    'even after the checks above pass. In your phone settings, find '
                    'Battery (or Apps → Attenda → Battery) and set Attenda to '
                    '"Unrestricted" / "No restrictions", and disable "Put unused apps '
                    'to sleep" for Attenda.',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6), fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkTile(IconData icon, String title, _CheckResult result,
      Future<void> Function() onFix, String fixLabel) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, size: 20, color: Colors.white.withValues(alpha: 0.6)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Icon(
                    result.ok ? Icons.check_circle : Icons.error_outline,
                    size: 15,
                    color: result.ok ? AppColors.success500 : AppColors.warning500,
                  ),
                ]),
                const SizedBox(height: 3),
                Text(result.detail,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5), fontSize: 11.5)),
              ],
            ),
          ),
          if (!result.ok && !_loading)
            TextButton(
              onPressed: () => onFix(),
              child: Text(fixLabel,
                  style: const TextStyle(
                      color: AppColors.primary600, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}
