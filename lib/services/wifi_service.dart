import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:workmanager/workmanager.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/api_service.dart';

const _heartbeatTask = 'com.attenda.heartbeat';
const _heartbeatInterval = Duration(minutes: 4);
const _heartbeatExpiry   = Duration(minutes: 10);

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

  // Called with (status, [data]) — data carries SSID for 'heartbeat_lost'
  void Function(String status, [String? data])? onStatusChange;

  Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isBoxOpen(_queueBox)) await Hive.openBox(_queueBox);
    if (!Hive.isBoxOpen(_stateBox)) await Hive.openBox(_stateBox);
    _restoreState();

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

  Future<void> checkAndReport() async {
    try {
      final connectivity = await _connectivity.checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        if (_checkedInViaWifi) onStatusChange?.call('heartbeat_lost', _lastKnownSsid);
        return;
      }

      if (await _isVpnActive()) {
        onStatusChange?.call('vpn_detected');
        return;
      }

      final ip   = await _networkInfo.getWifiIP();
      final ssid = (await _networkInfo.getWifiName().catchError((_) => null as String?))
          ?.replaceAll('"', '');

      final hasNetwork = (ip != null && ip.isNotEmpty) || (ssid != null && ssid.isNotEmpty);
      if (!hasNetwork) {
        if (_checkedInViaWifi) onStatusChange?.call('heartbeat_lost', _lastKnownSsid);
        return;
      }

      final networkChanged = ip != _lastKnownIp || ssid != _lastKnownSsid;
      if (networkChanged) {
        _lastKnownIp   = ip;
        _lastKnownSsid = ssid;
        await _saveState();
        await _reportNetworkEvent(ip: ip, ssid: ssid);
      } else if (_checkedInViaWifi) {
        // Same network — send heartbeat
        await _sendHeartbeat(ip: ip, ssid: ssid);
      }
    } catch (e) {
      debugPrint('[WiFi] checkAndReport error: $e');
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) async {
    if (results.contains(ConnectivityResult.wifi)) {
      await checkAndReport();
      if (_checkedInViaWifi) onStatusChange?.call('heartbeat_restored');
    } else if (!results.contains(ConnectivityResult.wifi)) {
      if (_checkedInViaWifi) onStatusChange?.call('heartbeat_lost', _lastKnownSsid);
    }
  }

  Future<void> _sendHeartbeat({String? ip, String? ssid}) async {
    if ((ip == null || ip.isEmpty) && (ssid == null || ssid.isEmpty)) return;
    try {
      final result = await api.sendHeartbeat(ip ?? '', ssid: ssid);
      final action = result['action'] as String?;
      if (action == 'heartbeat_accepted') {
        debugPrint('[WiFi] Heartbeat accepted');
      } else if (action == 'not_checked_in') {
        _checkedInViaWifi = false;
        await _saveState();
      }
    } catch (e) {
      debugPrint('[WiFi] Heartbeat failed: $e — will retry next cycle');
    }
  }

  Future<void> _reportNetworkEvent({String? ip, String? ssid}) async {
    if ((ip == null || ip.isEmpty) && (ssid == null || ssid.isEmpty)) return;
    try {
      final result = await api.reportIpEvent(ip ?? '', ssid: ssid);
      final action = result['action'] as String?;
      if (action == 'checked_in') {
        _checkedInViaWifi = true;
        await _saveState();
        onStatusChange?.call('checked_in');
        debugPrint('[WiFi] Auto check-in — IP: $ip, SSID: $ssid');
      } else if (action == 'already_in') {
        _checkedInViaWifi = true;
        await _saveState();
        // Send heartbeat immediately since we know we're checked in
        await _sendHeartbeat(ip: ip, ssid: ssid);
      } else if (action == 'no_networks_configured') {
        onStatusChange?.call('no_networks');
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
