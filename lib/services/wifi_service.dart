// wifi_service.dart
//
// Owns all WiFi attendance state in the main (UI) isolate.
//
// The actual background polling is done by [AttendaTaskHandler] inside a
// persistent Android Foreground Service (flutter_foreground_task). Events
// bubble back here via [FlutterForegroundTask.addTaskDataCallback], so the
// UI always stays in sync whether the event originated in the foreground or
// background.
//
// Foreground cadence
//   • onStart / resume / tab-switch → checkAndReport() immediately
//   • while checked-in in foreground → Timer every 4 min (closes 15-min gap)
//
// Background cadence
//   • flutter_foreground_task fires every 4 min (no WorkManager 15-min floor)

import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/api_service.dart';
import 'foreground_service.dart'; // shared constants + startForegroundCallback

// ─── Offline-queue models ─────────────────────────────────────────────────────
enum OfflineEventType { checkIn, ipMatch }

class OfflineEvent {
  final OfflineEventType type;
  final DateTime         timestamp;
  final String?          payload;
  final String?          ssid;
  OfflineEvent({required this.type, required this.timestamp, this.payload, this.ssid});
  Map<String, dynamic> toJson() => {
    'type':      type.name,
    'timestamp': timestamp.toIso8601String(),
    'payload':   payload,
    'ssid':      ssid,
  };
  factory OfflineEvent.fromJson(Map<String, dynamic> j) => OfflineEvent(
    type:      OfflineEventType.values.firstWhere((e) => e.name == j['type']),
    timestamp: DateTime.parse(j['timestamp'] as String),
    payload:   j['payload'] as String?,
    ssid:      j['ssid']    as String?,
  );
}

// ─── Service singleton ────────────────────────────────────────────────────────
class WifiAttendanceService {
  static final WifiAttendanceService _instance = WifiAttendanceService._();
  factory WifiAttendanceService() => _instance;
  WifiAttendanceService._();

  final _networkInfo  = NetworkInfo();
  final _connectivity = Connectivity();

  // ── In-memory state (UI isolate) ──────────────────────────────────────────
  String? _lastKnownIp;
  String? _lastKnownSsid;
  bool    _checkedInViaWifi = false;

  /// Called with (status, [data]) — data carries extra info (e.g. gap minutes).
  void Function(String status, [String? data])? onStatusChange;

  // ── Grace / disconnect countdown (owned here so it survives tab-switch) ──
  // Server-driven: updated from each heartbeat ack (org heartbeat_grace_mins).
  Duration graceWindow = const Duration(minutes: 20);
  DateTime? disconnectDeadline;
  String?   disconnectSsid;
  DateTime? lastHeartbeatAt;
  bool      vpnDetected       = false;
  bool      noNetworksConfigured = false;
  bool get heartbeatLost => disconnectDeadline != null;

  // ── Foreground heartbeat timer ────────────────────────────────────────────
  Timer?  _fgHeartbeatTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // ── Foreground service notification ID ───────────────────────────────────
  static const _serviceId = 1001;

  // ─────────────────────────────────────────────────────────────────────────
  // init() — call once from main() before runApp()
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isBoxOpen(kQueueBox)) await Hive.openBox(kQueueBox);
    if (!Hive.isBoxOpen(kStateBox)) await Hive.openBox(kStateBox);
    _restoreState();

    await ensureLocationPermission();
    await _requestNotificationPermission();
    await _requestBatteryOptimisationExemption();

    // ── Configure flutter_foreground_task ────────────────────────────────
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId:          'attenda_wifi',
        channelName:        'Attendance Tracking',
        channelDescription: 'Monitors office WiFi for automatic check-in/out',
        channelImportance:  NotificationChannelImportance.LOW,
        priority:           NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound:        false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Fire every 4 minutes — well within the server's heartbeat grace
        // window (org-configurable, 20 min default)
        eventAction:             ForegroundTaskEventAction.repeat(4 * 60 * 1000),
        autoRunOnBoot:           true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock:           true,
        allowWifiLock:           true,
      ),
    );

    // ── Receive status events from the background task ───────────────────
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);

    // ── Start (or keep) the foreground service ───────────────────────────
    await _startService();

    // ── React to connectivity changes in the foreground ──────────────────
    _connectivitySub = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);

    // ── Immediate foreground check ────────────────────────────────────────
    await checkAndReport();
    syncOfflineQueue();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Start / stop the foreground service
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _startService() async {
    if (await FlutterForegroundTask.isRunningService) return; // already running
    final result = await FlutterForegroundTask.startService(
      serviceId:         _serviceId,
      notificationTitle: 'Attenda',
      notificationText:  'Monitoring office WiFi for attendance…',
      callback:          startForegroundCallback,
    );
    debugPrint('[WiFi] FG service start → $result');
  }

  /// Public hook for the reliability screen: (re)start the service if needed.
  Future<bool> ensureServiceRunning() async {
    await _startService();
    return FlutterForegroundTask.isRunningService;
  }

  /// Tells the background task the user manually checked out.
  Future<void> onManualCheckOut() async {
    _checkedInViaWifi = false;
    lastHeartbeatAt   = null;
    _stopFgHeartbeat();
    _markReconnected();
    await _saveState();
    // Inform the background task so it updates Hive + notification
    FlutterForegroundTask.sendDataToTask('manual_checkout');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Events from the background task → update UI state
  // ─────────────────────────────────────────────────────────────────────────
  void _onTaskData(Object raw) {
    final msg = raw.toString();
    debugPrint('[WiFi] Task → main: $msg');

    if (msg == 'checked_in') {
      _checkedInViaWifi    = true;
      noNetworksConfigured = false;
      vpnDetected          = false;
      _markReconnected();
      _saveState();
      _startFgHeartbeat();
      onStatusChange?.call('checked_in');

    } else if (msg.startsWith('re_entered:') || msg.startsWith('re_entered_forgiven:')) {
      _checkedInViaWifi    = true;
      noNetworksConfigured = false;
      vpnDetected          = false;
      _markReconnected();
      _saveState();
      _startFgHeartbeat();
      final gap = msg.split(':').last;
      onStatusChange?.call(
          msg.startsWith('re_entered_forgiven:') ? 're_entered_forgiven' : 're_entered', gap);

    } else if (msg == 'already_in') {
      _checkedInViaWifi    = true;
      noNetworksConfigured = false;
      vpnDetected          = false;
      _markReconnected();
      _saveState();
      _startFgHeartbeat();

    } else if (msg == 'heartbeat_accepted') {
      lastHeartbeatAt = DateTime.now();
      vpnDetected     = false;
      _markReconnected(notify: true);

    } else if (msg.startsWith('heartbeat_lost:')) {
      _markDisconnected();

    } else if (msg == 'no_networks') {
      noNetworksConfigured = true;
      onStatusChange?.call('no_networks');

    } else if (msg == 'vpn_detected') {
      vpnDetected = true;
      onStatusChange?.call('vpn_detected');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Foreground check (immediate: tab-switch / resume / pull-to-refresh)
  // ─────────────────────────────────────────────────────────────────────────

  // Throttle: don't fire more than once every 30 s (prevents tab-switch spam)
  DateTime? _lastFgCheck;

  Future<void> checkAndReport() async {
    final now = DateTime.now();
    if (_lastFgCheck != null &&
        now.difference(_lastFgCheck!) < const Duration(seconds: 30)) {
      return;
    }
    _lastFgCheck = now;

    try {
      final conn = await _connectivity.checkConnectivity();
      if (conn.contains(ConnectivityResult.none)) {
        if (_checkedInViaWifi) _markDisconnected();
        return;
      }

      if (await _isVpnActive()) {
        vpnDetected = true;
        onStatusChange?.call('vpn_detected');
        return;
      }
      vpnDetected = false;

      final ip   = await _networkInfo.getWifiIP();
      var ssid = (await _networkInfo.getWifiName()
              .catchError((_) => null as String?))
          ?.replaceAll('"', '');
      if (ssid == '<unknown ssid>') ssid = null;

      final hasNet = (ip != null && ip.isNotEmpty) || (ssid != null && ssid.isNotEmpty);
      if (!hasNet) {
        if (_checkedInViaWifi) _markDisconnected();
        return;
      }

      if (ip != _lastKnownIp || ssid != _lastKnownSsid) {
        _lastKnownIp   = ip;
        _lastKnownSsid = ssid;
        await _saveState();
      }

      // Delegate to the background-compatible API calls
      if (_checkedInViaWifi) {
        await _fgHeartbeat(ip: ip, ssid: ssid);
      } else {
        await _fgIpEvent(ip: ip, ssid: ssid);
      }
    } catch (e) {
      debugPrint('[WiFi] checkAndReport error: $e');
    }
  }

  Future<void> _fgHeartbeat({String? ip, String? ssid}) async {
    if ((ip == null || ip.isEmpty) && (ssid == null || ssid.isEmpty)) return;
    try {
      final result = await api.sendHeartbeat(ip ?? '', ssid: ssid);
      final action = result['action'] as String?;
      switch (action) {
        case 'heartbeat_accepted':
          lastHeartbeatAt = DateTime.now();
          final graceMins = result['grace_mins'] as int?;
          if (graceMins != null && graceMins > 0) {
            graceWindow = Duration(minutes: graceMins);
          }
          _markReconnected(notify: true);
          break;
        case 'not_on_office_network':
          _markDisconnected();
          break;
        case 'not_checked_in':
          _checkedInViaWifi = false;
          await _saveState();
          await _fgIpEvent(ip: ip, ssid: ssid);
          break;
      }
    } catch (e) {
      debugPrint('[WiFi] FG heartbeat failed: $e — background will retry');
    }
  }

  Future<void> _fgIpEvent({String? ip, String? ssid}) async {
    if ((ip == null || ip.isEmpty) && (ssid == null || ssid.isEmpty)) return;
    try {
      final result = await api.reportIpEvent(ip ?? '', ssid: ssid);
      final action = result['action'] as String?;
      switch (action) {
        case 'checked_in':
          _checkedInViaWifi    = true;
          noNetworksConfigured = false;
          await _saveState();
          _markReconnected();
          _startFgHeartbeat();
          onStatusChange?.call('checked_in');
          break;
        case 're_entered':
          _checkedInViaWifi    = true;
          noNetworksConfigured = false;
          await _saveState();
          _markReconnected();
          _startFgHeartbeat();
          final gap = result['gap_mins'] as int? ?? 0;
          final forgiven = result['forgiven'] as bool? ?? false;
          onStatusChange?.call(forgiven ? 're_entered_forgiven' : 're_entered', '$gap');
          break;
        case 'already_in':
          _checkedInViaWifi    = true;
          noNetworksConfigured = false;
          await _saveState();
          _markReconnected();
          _startFgHeartbeat();
          await _fgHeartbeat(ip: ip, ssid: ssid);
          break;
        case 'no_networks_configured':
          noNetworksConfigured = true;
          onStatusChange?.call('no_networks');
          break;
        case 'none':
          if (_checkedInViaWifi) _markDisconnected();
          break;
      }
    } catch (e) {
      debugPrint('[WiFi] FG ip-event failed: $e — queuing');
      _queueEvent(OfflineEvent(
        type:      OfflineEventType.ipMatch,
        timestamp: DateTime.now(),
        payload:   ip,
        ssid:      ssid,
      ));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Foreground heartbeat timer (keeps heartbeats < 10 min while app is open)
  // ─────────────────────────────────────────────────────────────────────────
  void _startFgHeartbeat() {
    _fgHeartbeatTimer?.cancel();
    _fgHeartbeatTimer = Timer.periodic(const Duration(minutes: 4), (_) {
      if (_checkedInViaWifi) checkAndReport();
    });
  }

  void _stopFgHeartbeat() {
    _fgHeartbeatTimer?.cancel();
    _fgHeartbeatTimer = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Connectivity listener
  // ─────────────────────────────────────────────────────────────────────────
  void _onConnectivityChanged(List<ConnectivityResult> results) async {
    if (results.contains(ConnectivityResult.wifi)) {
      await checkAndReport();
    } else {
      if (_checkedInViaWifi) _markDisconnected();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Grace / disconnect countdown helpers
  // ─────────────────────────────────────────────────────────────────────────
  void _markDisconnected() {
    disconnectSsid = _lastKnownSsid;
    disconnectDeadline ??= (lastHeartbeatAt ?? DateTime.now()).add(graceWindow);
    onStatusChange?.call('heartbeat_lost', disconnectSsid);
  }

  void _markReconnected({bool notify = false}) {
    final wasLost = heartbeatLost;
    disconnectDeadline = null;
    disconnectSsid     = null;
    if (notify && wasLost) onStatusChange?.call('heartbeat_restored');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Offline queue — sync queued events when connectivity is restored
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> syncOfflineQueue() async {
    if (!Hive.isBoxOpen(kQueueBox)) return;
    final box  = Hive.box(kQueueBox);
    if (box.isEmpty) return;
    final conn = await _connectivity.checkConnectivity();
    if (conn.contains(ConnectivityResult.none)) return;

    for (final key in box.keys.toList()) {
      try {
        final raw = box.get(key) as String?;
        if (raw == null) continue;
        final event = OfflineEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        // Skip and discard events older than a full shift — replaying stale
        // check-ins across days creates wrong records, but same-day events
        // must survive long offline stretches (e.g. doze + poor signal).
        if (DateTime.now().difference(event.timestamp) > const Duration(hours: 12)) {
          await box.delete(key);
          continue;
        }
        if (event.type == OfflineEventType.checkIn) {
          await api.checkIn(type: 'manual');
        } else if (event.type == OfflineEventType.ipMatch &&
            (event.payload != null || event.ssid != null)) {
          await api.reportIpEvent(event.payload ?? '', ssid: event.ssid);
        }
        await box.delete(key);
      } catch (e) {
        final code = (e as dynamic)?.response?.statusCode as int?;
        if (code != null && code >= 400 && code < 500) await box.delete(key);
        continue;
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Permissions
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> ensureLocationPermission() async {
    try {
      var status = await Permission.locationWhenInUse.status;
      if (!status.isGranted) status = await Permission.locationWhenInUse.request();
      return status.isGranted;
    } catch (e) {
      debugPrint('[WiFi] Location permission error: $e');
      return false;
    }
  }

  Future<void> _requestBatteryOptimisationExemption() async {
    try {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (_) {}
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final permission = await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // State persistence (Hive)
  // ─────────────────────────────────────────────────────────────────────────
  void _restoreState() {
    if (!Hive.isBoxOpen(kStateBox)) return;
    final box = Hive.box(kStateBox);
    _checkedInViaWifi = box.get(kCheckedInViaWifi, defaultValue: false) as bool;
    _lastKnownIp      = box.get(kLastKnownIp)   as String?;
    _lastKnownSsid    = box.get(kLastKnownSsid)  as String?;

    // Restart the foreground heartbeat if we were checked in before restart
    if (_checkedInViaWifi) _startFgHeartbeat();
  }

  Future<void> _saveState() async {
    if (!Hive.isBoxOpen(kStateBox)) return;
    final box = Hive.box(kStateBox);
    await box.put(kCheckedInViaWifi, _checkedInViaWifi);
    await box.put(kLastKnownIp,      _lastKnownIp);
    await box.put(kLastKnownSsid,    _lastKnownSsid);
  }

  void _queueEvent(OfflineEvent event) {
    if (!Hive.isBoxOpen(kQueueBox)) return;
    Hive.box(kQueueBox).add(jsonEncode(event.toJson()));
  }

  Future<bool> _isVpnActive() async {
    try {
      return (await _connectivity.checkConnectivity())
          .contains(ConnectivityResult.vpn);
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _stopFgHeartbeat();
    _connectivitySub?.cancel();
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
  }
}
