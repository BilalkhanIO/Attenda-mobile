import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:workmanager/workmanager.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/api_service.dart';

const _heartbeatTask = 'com.attenda.heartbeat';
// Android clamps periodic WorkManager tasks to a 15-minute minimum, so anything
// shorter is silently rounded up. Keep this at the floor for the tightest cadence.
const _heartbeatInterval = Duration(minutes: 15);

const _queueBox = 'offline_queue';
const _stateBox = 'ip_state';

const _kCheckedInViaWifi = 'checkedInViaWifi';
const _kLastKnownIp      = 'lastKnownIp';
const _kLastKnownSsid    = 'lastKnownSsid';

enum OfflineEventType { checkIn, ipMatch }

class OfflineEvent {
  final OfflineEventType type;
  final DateTime timestamp;
  final String? payload;
  final String? ssid;
  OfflineEvent({required this.type, required this.timestamp, this.payload, this.ssid});
  Map<String, dynamic> toJson() => {'type': type.name, 'timestamp': timestamp.toIso8601String(), 'payload': payload, 'ssid': ssid};
  factory OfflineEvent.fromJson(Map<String, dynamic> j) => OfflineEvent(
    type:      OfflineEventType.values.firstWhere((e) => e.name == j['type']),
    timestamp: DateTime.parse(j['timestamp'] as String),
    payload:   j['payload'] as String?,
    ssid:      j['ssid'] as String?,
  );
}

class WifiAttendanceService {
  static final WifiAttendanceService _instance = WifiAttendanceService._();
  factory WifiAttendanceService() => _instance;
  WifiAttendanceService._();

  final _networkInfo  = NetworkInfo();
  final _connectivity = Connectivity();

  String? _lastKnownIp;
  String? _lastKnownSsid;
  bool    _checkedInViaWifi = false;

  // ─── Live connection status (owned here, not in the UI) ─────────────
  // These live in the singleton so they survive HomeScreen rebuilds (every
  // tab switch recreates the screen). The grace deadline is set ONCE, when the
  // device first leaves office WiFi, and is never bumped afterwards — so the
  // countdown keeps running across navigation instead of restarting at 10:00.
  static const graceWindow = Duration(minutes: 10);
  DateTime? disconnectDeadline;
  String?   disconnectSsid;
  DateTime? lastHeartbeatAt; // time of the last accepted heartbeat
  bool      vpnDetected = false;
  bool      noNetworksConfigured = false;
  bool get heartbeatLost => disconnectDeadline != null;

  // Called with (status, [data]) — data carries SSID for 'heartbeat_lost'
  void Function(String status, [String? data])? onStatusChange;

  void _markDisconnected() {
    disconnectSsid = _lastKnownSsid;
    // Grace runs from the LAST accepted heartbeat (matching the server's
    // heartbeat-expiry window), not from when we noticed the drop. Set once.
    disconnectDeadline ??= (lastHeartbeatAt ?? DateTime.now()).add(graceWindow);
    onStatusChange?.call('heartbeat_lost', disconnectSsid);
  }

  void _markReconnected({bool notify = false}) {
    final wasLost = heartbeatLost;
    disconnectDeadline = null;
    disconnectSsid = null;
    if (notify && wasLost) onStatusChange?.call('heartbeat_restored');
  }

  Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isBoxOpen(_queueBox)) await Hive.openBox(_queueBox);
    if (!Hive.isBoxOpen(_stateBox)) await Hive.openBox(_stateBox);
    _restoreState();

    // Reading the WiFi SSID/IP requires location permission on Android 8.1+.
    // Without it getWifiName()/getWifiIP() return null and auto check-in never fires.
    await ensureLocationPermission();

    await Workmanager().initialize(_bgCallback);
    await Workmanager().registerPeriodicTask(
      _heartbeatTask, _heartbeatTask,
      frequency: _heartbeatInterval,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );

    _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    await checkAndReport();
    syncOfflineQueue();
  }

  void _restoreState() {
    if (!Hive.isBoxOpen(_stateBox)) return;
    final box = Hive.box(_stateBox);
    _checkedInViaWifi = box.get(_kCheckedInViaWifi, defaultValue: false) as bool;
    _lastKnownIp      = box.get(_kLastKnownIp)  as String?;
    _lastKnownSsid    = box.get(_kLastKnownSsid) as String?;
  }

  Future<void> _saveState() async {
    if (!Hive.isBoxOpen(_stateBox)) return;
    final box = Hive.box(_stateBox);
    await box.put(_kCheckedInViaWifi, _checkedInViaWifi);
    await box.put(_kLastKnownIp,      _lastKnownIp);
    await box.put(_kLastKnownSsid,    _lastKnownSsid);
  }

  /// Requests location permission (needed to read the WiFi SSID/IP).
  /// Safe to call repeatedly — returns true once granted.
  Future<bool> ensureLocationPermission() async {
    try {
      var status = await Permission.locationWhenInUse.status;
      if (!status.isGranted) {
        status = await Permission.locationWhenInUse.request();
      }
      return status.isGranted;
    } catch (e) {
      debugPrint('[WiFi] Location permission request failed: $e');
      return false;
    }
  }

  /// Call when the user checks out manually so we stop sending heartbeats and
  /// the state stays consistent (otherwise heartbeats keep firing until the
  /// backend rejects them with `not_checked_in`).
  Future<void> onManualCheckOut() async {
    _checkedInViaWifi = false;
    lastHeartbeatAt   = null;
    _markReconnected(); // clear any disconnect countdown
    await _saveState();
  }

  Future<void> checkAndReport() async {
    try {
      final connectivity = await _connectivity.checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
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
      final ssid = (await _networkInfo.getWifiName().catchError((_) => null as String?))
          ?.replaceAll('"', '');

      final hasNetwork = (ip != null && ip.isNotEmpty) || (ssid != null && ssid.isNotEmpty);
      if (!hasNetwork) {
        if (_checkedInViaWifi) _markDisconnected();
        return;
      }

      final networkChanged = ip != _lastKnownIp || ssid != _lastKnownSsid;
      if (networkChanged) {
        _lastKnownIp   = ip;
        _lastKnownSsid = ssid;
        await _saveState();
      }

      if (_checkedInViaWifi) {
        // Already checked in — keep the session alive with a heartbeat.
        final action = await _sendHeartbeat(ip: ip, ssid: ssid);
        switch (action) {
          case 'heartbeat_accepted':
            // Still on office WiFi — clear any pending disconnect countdown.
            _markReconnected(notify: true);
            break;
          case 'not_on_office_network':
            // Left the office network (moved to another WiFi) — start the
            // grace countdown so the user can reconnect before auto-checkout.
            _markDisconnected();
            break;
          case 'not_checked_in':
            // The heartbeat-expiry job auto-checked us out during a WiFi gap.
            // We're back on office WiFi now, so recover: the ip-event handler
            // reopens the auto-closed record ('re_entered') or checks in fresh.
            await _reportNetworkEvent(ip: ip, ssid: ssid);
            break;
        }
      } else {
        // Not checked in yet — attempt an auto check-in. The backend is
        // idempotent (returns `already_in` if we already are), so it's safe to
        // call even when the network hasn't changed. This is what lets check-in
        // recover after a restart or manual check-out on the same network.
        await _reportNetworkEvent(ip: ip, ssid: ssid);
      }
    } catch (e) {
      debugPrint('[WiFi] checkAndReport error: $e');
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) async {
    if (results.contains(ConnectivityResult.wifi)) {
      // checkAndReport() clears the disconnect state (and fires
      // 'heartbeat_restored') if we're back on the office network.
      await checkAndReport();
    } else {
      if (_checkedInViaWifi) _markDisconnected();
    }
  }

  Future<String?> _sendHeartbeat({String? ip, String? ssid}) async {
    if ((ip == null || ip.isEmpty) && (ssid == null || ssid.isEmpty)) return null;
    try {
      final result = await api.sendHeartbeat(ip ?? '', ssid: ssid);
      final action = result['action'] as String?;
      if (action == 'heartbeat_accepted') {
        lastHeartbeatAt = DateTime.now();
        debugPrint('[WiFi] Heartbeat accepted');
      } else if (action == 'not_checked_in') {
        _checkedInViaWifi = false;
        await _saveState();
      }
      return action;
    } catch (e) {
      debugPrint('[WiFi] Heartbeat failed: $e — will retry next cycle');
      return null;
    }
  }

  Future<void> _reportNetworkEvent({String? ip, String? ssid}) async {
    if ((ip == null || ip.isEmpty) && (ssid == null || ssid.isEmpty)) return;
    try {
      final result = await api.reportIpEvent(ip ?? '', ssid: ssid);
      final action = result['action'] as String?;
      if (action == 'checked_in') {
        _checkedInViaWifi = true;
        noNetworksConfigured = false;
        await _saveState();
        _markReconnected();
        onStatusChange?.call('checked_in');
        debugPrint('[WiFi] Auto check-in — IP: $ip, SSID: $ssid');
      } else if (action == 're_entered') {
        _checkedInViaWifi = true;
        noNetworksConfigured = false;
        await _saveState();
        _markReconnected();
        final gapMins = result['gap_mins'] as int? ?? 0;
        onStatusChange?.call('re_entered', '$gapMins');
        debugPrint('[WiFi] Re-entry after auto-checkout — gap: ${gapMins}m');
      } else if (action == 'already_in') {
        _checkedInViaWifi = true;
        noNetworksConfigured = false;
        await _saveState();
        _markReconnected();
        // Send heartbeat immediately since we know we're checked in
        await _sendHeartbeat(ip: ip, ssid: ssid);
      } else if (action == 'no_networks_configured') {
        noNetworksConfigured = true;
        onStatusChange?.call('no_networks');
      } else if (action == 'none') {
        // On a network, but not a registered office one.
        if (_checkedInViaWifi) _markDisconnected();
      }
    } catch (e) {
      debugPrint('[WiFi] Network event failed: $e — queuing');
      _queueEvent(OfflineEvent(
        type: OfflineEventType.ipMatch,
        timestamp: DateTime.now(),
        payload: ip,
        ssid: ssid,
      ));
    }
  }

  Future<bool> _isVpnActive() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result.contains(ConnectivityResult.vpn);
    } catch (_) { return false; }
  }

  void _queueEvent(OfflineEvent event) {
    if (!Hive.isBoxOpen(_queueBox)) return;
    Hive.box(_queueBox).add(jsonEncode(event.toJson()));
  }

  Future<void> syncOfflineQueue() async {
    if (!Hive.isBoxOpen(_queueBox)) return;
    final box = Hive.box(_queueBox);
    if (box.isEmpty) return;
    final connectivity = await _connectivity.checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) return;

    for (final key in box.keys.toList()) {
      try {
        final raw = box.get(key) as String?;
        if (raw == null) continue;
        final event = OfflineEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (event.type == OfflineEventType.checkIn) {
          await api.checkIn(type: 'manual');
        } else if (event.type == OfflineEventType.ipMatch && (event.payload != null || event.ssid != null)) {
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

  void dispose() {}
}

@pragma('vm:entry-point')
void _bgCallback() {
  Workmanager().executeTask((task, inputData) async {
    if (task == _heartbeatTask) {
      try {
        await Hive.initFlutter();
        if (!Hive.isBoxOpen('offline_queue')) await Hive.openBox('offline_queue');
        if (!Hive.isBoxOpen('ip_state'))      await Hive.openBox('ip_state');
        final service = WifiAttendanceService();
        service._restoreState();
        await service.checkAndReport();
      } catch (e) {
        debugPrint('[BG] Heartbeat task failed: $e');
      }
    }
    return Future.value(true);
  });
}
