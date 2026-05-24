import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:workmanager/workmanager.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

// ─── Background task name ─────────────────────────────
const _ipPollTask   = 'com.attenda.ipPoll';
const _gracePeriod  = Duration(minutes: 5);
const _pollInterval = Duration(minutes: 5);

// ─── Hive boxes ──────────────────────────────────────
const _queueBox     = 'offline_queue';
const _stateBox     = 'ip_state';

// ─── Offline event types ─────────────────────────────
enum OfflineEventType { checkIn, checkOut, ipMatch, ipUnmatch }

class OfflineEvent {
  final OfflineEventType type;
  final DateTime timestamp;
  final String? payload;
  OfflineEvent({required this.type, required this.timestamp, this.payload});
  Map<String, dynamic> toJson() => {'type': type.name, 'timestamp': timestamp.toIso8601String(), 'payload': payload};
  factory OfflineEvent.fromJson(Map<String, dynamic> j) => OfflineEvent(
    type:      OfflineEventType.values.firstWhere((e) => e.name == j['type']),
    timestamp: DateTime.parse(j['timestamp'] as String),
    payload:   j['payload'] as String?,
  );
}

// ─── WiFi IP Detection Service ────────────────────────
class WifiAttendanceService {
  static final WifiAttendanceService _instance = WifiAttendanceService._();
  factory WifiAttendanceService() => _instance;
  WifiAttendanceService._();

  final _networkInfo  = NetworkInfo();
  final _connectivity = Connectivity();
  Timer? _graceTimer;
  String? _lastKnownIp;
  bool   _checkedInViaIp = false;

  // Callback to update UI
  void Function(String status)? onStatusChange;

  // ─── Init on app start ───────────────────────────
  Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isBoxOpen(_queueBox))  await Hive.openBox(_queueBox);
    if (!Hive.isBoxOpen(_stateBox))  await Hive.openBox(_stateBox);

    // Register background worker
    await Workmanager().initialize(_bgCallback, isInDebugMode: kDebugMode);
    await Workmanager().registerPeriodicTask(
      _ipPollTask,
      _ipPollTask,
      frequency:     _pollInterval,
      existingWorkPolicy: ExistingWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );

    // Listen for connectivity changes in foreground
    _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);

    // Run once immediately on init
    await checkAndReport();

    // Sync any queued offline events
    syncOfflineQueue();
  }

  // ─── Check current IP and report ─────────────────
  Future<void> checkAndReport() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return; // No internet — skip
      }

      // VPN check
      if (await _isVpnActive()) {
        debugPrint('[WiFi] VPN detected — auto check-in blocked');
        onStatusChange?.call('vpn_detected');
        return;
      }

      final ip = await _networkInfo.getWifiIP();

      if (ip == null || ip.isEmpty) {
        // Not on WiFi — start grace period if was checked in via IP
        if (_checkedInViaIp && _lastKnownIp != null) {
          _startGracePeriod();
        }
        return;
      }

      // IP obtained
      if (ip != _lastKnownIp) {
        _lastKnownIp = ip;
        _cancelGracePeriod();
        await _reportIpEvent(ip: ip, connected: true);
      }
    } catch (e) {
      debugPrint('[WiFi] IP check error: $e');
      _queueEvent(OfflineEvent(type: OfflineEventType.ipMatch, timestamp: DateTime.now()));
    }
  }

  // ─── Connectivity change handler ──────────────────
  void _onConnectivityChanged(ConnectivityResult result) async {
    if (result == ConnectivityResult.wifi) {
      // Reconnected to WiFi
      _cancelGracePeriod();
      await checkAndReport();
    } else if (result == ConnectivityResult.none || result == ConnectivityResult.mobile) {
      // Left WiFi
      if (_checkedInViaIp) {
        _startGracePeriod();
      }
    }
  }

  // ─── 5-minute grace period ────────────────────────
  void _startGracePeriod() {
    if (_graceTimer?.isActive ?? false) return; // Already running
    debugPrint('[WiFi] Grace period started — checkout in 5 min if not reconnected');
    onStatusChange?.call('grace_period');
    _graceTimer = Timer(_gracePeriod, () => _triggerAutoCheckout());
  }

  void _cancelGracePeriod() {
    if (_graceTimer?.isActive ?? false) {
      _graceTimer!.cancel();
      _graceTimer = null;
      debugPrint('[WiFi] Grace period cancelled — reconnected');
      onStatusChange?.call('grace_cancelled');
      // Tell server to cancel pending checkout
      _reportIpEvent(ip: _lastKnownIp ?? '', connected: true).catchError((e) {});
    }
  }

  Future<void> _triggerAutoCheckout() async {
    debugPrint('[WiFi] Grace period expired — auto check-out');
    try {
      await api.reportIpEvent(_lastKnownIp ?? '', false);
      _checkedInViaIp = false;
      _lastKnownIp    = null;
      onStatusChange?.call('checked_out');
    } catch (e) {
      // Offline — queue the checkout
      _queueEvent(OfflineEvent(
        type:      OfflineEventType.checkOut,
        timestamp: DateTime.now(),
        payload:   _lastKnownIp,
      ));
    }
  }

  // ─── Report IP event to backend ───────────────────
  Future<void> _reportIpEvent({required String ip, required bool connected}) async {
    try {
      final result = await api.reportIpEvent(ip, connected);
      final action = result['action'] as String?;
      if (action == 'checked_in') {
        _checkedInViaIp = true;
        onStatusChange?.call('checked_in');
        debugPrint('[WiFi] Auto check-in via IP $ip');
      } else if (action == 'grace_period_cancelled') {
        debugPrint('[WiFi] Server cancelled grace period');
      }
    } catch (e) {
      debugPrint('[WiFi] Failed to report IP event: $e — queuing offline');
      _queueEvent(OfflineEvent(
        type:      connected ? OfflineEventType.ipMatch : OfflineEventType.ipUnmatch,
        timestamp: DateTime.now(),
        payload:   ip,
      ));
    }
  }

  // ─── VPN detection ────────────────────────────────
  Future<bool> _isVpnActive() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      return connectivityResult == ConnectivityResult.vpn;
    } catch (_) {
      return false;
    }
  }

  // ─── Offline queue ────────────────────────────────
  void _queueEvent(OfflineEvent event) {
    if (!Hive.isBoxOpen(_queueBox)) return;
    final box = Hive.box(_queueBox);
    box.add(jsonEncode(event.toJson()));
    debugPrint('[Offline] Queued event: ${event.type.name}');
  }

  Future<void> syncOfflineQueue() async {
    if (!Hive.isBoxOpen(_queueBox)) return;
    final box    = Hive.box(_queueBox);
    if (box.isEmpty) return;

    final connectivity = await _connectivity.checkConnectivity();
    if (connectivity == ConnectivityResult.none) return;

    debugPrint('[Offline] Syncing ${box.length} queued events...');
    final keys = box.keys.toList();
    for (final key in keys) {
      try {
        final raw   = box.get(key) as String?;
        if (raw == null) continue;
        final event = OfflineEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>);

        switch (event.type) {
          case OfflineEventType.checkIn:
            await api.checkIn(type: 'manual');
            break;
          case OfflineEventType.checkOut:
            await api.checkOut();
            break;
          case OfflineEventType.ipMatch:
            if (event.payload != null) await api.reportIpEvent(event.payload!, true);
            break;
          case OfflineEventType.ipUnmatch:
            if (event.payload != null) await api.reportIpEvent(event.payload!, false);
            break;
        }
        await box.delete(key);
        debugPrint('[Offline] Synced event: ${event.type.name}');
      } catch (e) {
        debugPrint('[Offline] Failed to sync event: $e');
        break; // Stop on first failure — try again next time
      }
    }
  }

  void dispose() {
    _graceTimer?.cancel();
  }
}

// ─── Background callback (top-level function) ─────────
@pragma('vm:entry-point')
void _bgCallback() {
  Workmanager().executeTask((task, inputData) async {
    if (task == _ipPollTask) {
      try {
        await WifiAttendanceService().checkAndReport();
      } catch (e) {
        debugPrint('[BG] IP poll failed: $e');
      }
    }
    return Future.value(true);
  });
}
