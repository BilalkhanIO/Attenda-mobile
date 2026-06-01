import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:workmanager/workmanager.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/api_service.dart';

// ─── Background task name ─────────────────────────────
const _ipPollTask   = 'com.attenda.ipPoll';
const _gracePeriod  = Duration(minutes: 5);
const _pollInterval = Duration(minutes: 5);

// ─── Hive boxes ──────────────────────────────────────
const _queueBox     = 'offline_queue';
const _stateBox     = 'ip_state';

// State keys
const _kCheckedInViaIp = 'checkedInViaIp';
const _kLastKnownIp    = 'lastKnownIp';
const _kLastKnownSsid  = 'lastKnownSsid';

// ─── Offline event types ─────────────────────────────
enum OfflineEventType { checkIn, checkOut, ipMatch, ipUnmatch }

class OfflineEvent {
  final OfflineEventType type;
  final DateTime timestamp;
  final String? payload; // IP address
  final String? ssid;    // WiFi network name
  OfflineEvent({required this.type, required this.timestamp, this.payload, this.ssid});
  Map<String, dynamic> toJson() => {'type': type.name, 'timestamp': timestamp.toIso8601String(), 'payload': payload, 'ssid': ssid};
  factory OfflineEvent.fromJson(Map<String, dynamic> j) => OfflineEvent(
    type:      OfflineEventType.values.firstWhere((e) => e.name == j['type']),
    timestamp: DateTime.parse(j['timestamp'] as String),
    payload:   j['payload'] as String?,
    ssid:      j['ssid'] as String?,
  );
}

// ─── WiFi / Network Detection Service ────────────────
class WifiAttendanceService {
  static final WifiAttendanceService _instance = WifiAttendanceService._();
  factory WifiAttendanceService() => _instance;
  WifiAttendanceService._();

  final _networkInfo  = NetworkInfo();
  final _connectivity = Connectivity();
  Timer? _graceTimer;

  // In-memory state (also persisted to Hive for background tasks)
  String? _lastKnownIp;
  String? _lastKnownSsid;
  bool   _checkedInViaIp = false;

  // Callback to update UI
  void Function(String status)? onStatusChange;

  // ─── Init on app start ───────────────────────────
  Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isBoxOpen(_queueBox)) await Hive.openBox(_queueBox);
    if (!Hive.isBoxOpen(_stateBox)) await Hive.openBox(_stateBox);

    // Restore persisted state so grace period survives app restart
    _restoreState();

    // Register background worker
    await Workmanager().initialize(_bgCallback, isInDebugMode: kDebugMode);
    await Workmanager().registerPeriodicTask(
      _ipPollTask,
      _ipPollTask,
      frequency:     _pollInterval,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );

    // Listen for connectivity changes in foreground
    _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);

    // Run once immediately on init
    await checkAndReport();

    // Sync any queued offline events
    syncOfflineQueue();
  }

  // ─── Restore persisted state ─────────────────────
  void _restoreState() {
    if (!Hive.isBoxOpen(_stateBox)) return;
    final box = Hive.box(_stateBox);
    _checkedInViaIp = box.get(_kCheckedInViaIp, defaultValue: false) as bool;
    _lastKnownIp    = box.get(_kLastKnownIp)   as String?;
    _lastKnownSsid  = box.get(_kLastKnownSsid) as String?;
  }

  // ─── Persist state so background tasks read it ───
  Future<void> _saveState() async {
    if (!Hive.isBoxOpen(_stateBox)) return;
    final box = Hive.box(_stateBox);
    await box.put(_kCheckedInViaIp, _checkedInViaIp);
    await box.put(_kLastKnownIp,    _lastKnownIp);
    await box.put(_kLastKnownSsid,  _lastKnownSsid);
  }

  // ─── Check current network and report ────────────
  Future<void> checkAndReport() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) return;

      // VPN check
      if (await _isVpnActive()) {
        debugPrint('[WiFi] VPN detected — auto check-in blocked');
        onStatusChange?.call('vpn_detected');
        return;
      }

      final ip   = await _networkInfo.getWifiIP();
      // SSID may be null on iOS without location permission or Android <API 29
      final ssid = await _networkInfo.getWifiName().catchError((_) => null as String?);
      // Strip surrounding quotes iOS adds to SSIDs
      final cleanSsid = ssid?.replaceAll('"', '');

      final hasNetwork = (ip != null && ip.isNotEmpty) || (cleanSsid != null && cleanSsid.isNotEmpty);

      if (!hasNetwork) {
        // Not on WiFi — start grace period if was checked in via network
        if (_checkedInViaIp) _startGracePeriod();
        return;
      }

      // Network obtained — check if anything changed
      final networkChanged = ip != _lastKnownIp || cleanSsid != _lastKnownSsid;
      if (networkChanged) {
        _lastKnownIp   = ip;
        _lastKnownSsid = cleanSsid;
        await _saveState();
        await _cancelGracePeriod();
        await _reportIpEvent(ip: ip, ssid: cleanSsid, connected: true);
      }
    } catch (e) {
      debugPrint('[WiFi] Network check error: $e');
      _queueEvent(OfflineEvent(type: OfflineEventType.ipMatch, timestamp: DateTime.now()));
    }
  }

  // ─── Connectivity change handler ──────────────────
  void _onConnectivityChanged(List<ConnectivityResult> results) async {
    if (results.contains(ConnectivityResult.wifi)) {
      await _cancelGracePeriod();
      await checkAndReport();
    } else if (results.contains(ConnectivityResult.none) || results.contains(ConnectivityResult.mobile)) {
      if (_checkedInViaIp) _startGracePeriod();
    }
  }

  // ─── 5-minute grace period ────────────────────────
  void _startGracePeriod() {
    if (_graceTimer?.isActive ?? false) return;
    debugPrint('[WiFi] Grace period started — checkout in 5 min if not reconnected');
    onStatusChange?.call('grace_period');
    _graceTimer = Timer(_gracePeriod, () => _triggerAutoCheckout());
  }

  Future<void> _cancelGracePeriod() async {
    if (_graceTimer?.isActive ?? false) {
      _graceTimer!.cancel();
      _graceTimer = null;
      debugPrint('[WiFi] Grace period cancelled — reconnected');
      onStatusChange?.call('grace_cancelled');
      // Await the server call so ip_checkout_pending_at is cleared before any
      // subsequent match event could see stale state.
      try {
        await _reportIpEvent(ip: _lastKnownIp, ssid: _lastKnownSsid, connected: true);
      } catch (e) {
        debugPrint('[WiFi] Grace cancel server call failed: $e — queuing');
        _queueEvent(OfflineEvent(type: OfflineEventType.ipMatch, timestamp: DateTime.now(), payload: _lastKnownIp, ssid: _lastKnownSsid));
      }
    }
  }

  Future<void> _triggerAutoCheckout() async {
    debugPrint('[WiFi] Grace period expired — auto check-out');
    try {
      await api.reportIpEvent(_lastKnownIp ?? '', false, ssid: _lastKnownSsid);
      _checkedInViaIp = false;
      _lastKnownIp    = null;
      _lastKnownSsid  = null;
      await _saveState();
      onStatusChange?.call('checked_out');
    } catch (e) {
      _queueEvent(OfflineEvent(
        type:      OfflineEventType.checkOut,
        timestamp: DateTime.now(),
        payload:   _lastKnownIp,
        ssid:      _lastKnownSsid,
      ));
    }
  }

  // ─── Report network event to backend ─────────────
  Future<void> _reportIpEvent({
    required String? ip,
    required String? ssid,
    required bool connected,
  }) async {
    // Need at least one identifier
    if ((ip == null || ip.isEmpty) && (ssid == null || ssid.isEmpty)) return;
    try {
      final result = await api.reportIpEvent(ip ?? '', connected, ssid: ssid);
      final action = result['action'] as String?;
      if (action == 'checked_in') {
        _checkedInViaIp = true;
        await _saveState();
        onStatusChange?.call('checked_in');
        debugPrint('[WiFi] Auto check-in — IP: $ip, SSID: $ssid');
      } else if (action == 'already_in') {
        debugPrint('[WiFi] Already checked in — no state change');
      } else if (action == 'grace_period_cancelled') {
        debugPrint('[WiFi] Server cancelled grace period');
      } else if (action == 'no_networks_configured') {
        debugPrint('[WiFi] Admin has not configured any office networks yet');
        onStatusChange?.call('no_networks');
      }
    } catch (e) {
      debugPrint('[WiFi] Failed to report network event: $e — queuing offline');
      _queueEvent(OfflineEvent(
        type:      connected ? OfflineEventType.ipMatch : OfflineEventType.ipUnmatch,
        timestamp: DateTime.now(),
        payload:   ip,
        ssid:      ssid,
      ));
    }
  }

  // ─── VPN detection ────────────────────────────────
  Future<bool> _isVpnActive() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result.contains(ConnectivityResult.vpn);
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
    final box = Hive.box(_queueBox);
    if (box.isEmpty) return;

    final connectivity = await _connectivity.checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) return;

    debugPrint('[Offline] Syncing ${box.length} queued events...');
    final keys = box.keys.toList();
    for (final key in keys) {
      try {
        final raw = box.get(key) as String?;
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
            if (event.payload != null || event.ssid != null) {
              await api.reportIpEvent(event.payload ?? '', true, ssid: event.ssid);
            }
            break;
          case OfflineEventType.ipUnmatch:
            if (event.payload != null || event.ssid != null) {
              await api.reportIpEvent(event.payload ?? '', false, ssid: event.ssid);
            }
            break;
        }
        await box.delete(key);
        debugPrint('[Offline] Synced event: ${event.type.name}');
      } catch (e) {
        debugPrint('[Offline] Failed to sync event: $e — skipping');
        // Don't break on individual failures; idempotent IP events can be
        // retried on the next sync cycle. Delete the event to prevent a
        // permanently-stuck queue on unrecoverable server errors (e.g. 422).
        final statusCode = (e as dynamic)?.response?.statusCode as int?;
        if (statusCode != null && statusCode >= 400 && statusCode < 500) {
          await box.delete(key);
        }
        // Network errors: leave in queue, skip to next
        continue;
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
        // Background isolate — re-init Hive and restore persisted state
        await Hive.initFlutter();
        if (!Hive.isBoxOpen(_queueBox)) await Hive.openBox(_queueBox);
        if (!Hive.isBoxOpen(_stateBox)) await Hive.openBox(_stateBox);

        final service = WifiAttendanceService();
        // Restore state so background knows if we were previously checked in
        service._restoreState();
        await service.checkAndReport();
      } catch (e) {
        debugPrint('[BG] IP poll failed: $e');
      }
    }
    return Future.value(true);
  });
}
