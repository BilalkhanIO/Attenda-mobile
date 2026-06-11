// foreground_service.dart
//
// Runs inside a persistent Android Foreground Service via flutter_foreground_task.
// Because the package keeps a real FlutterEngine alive, every plugin works here
// — including FlutterSecureStorage and network_info_plus — whether the app is
// open or completely killed.
//
// Lifecycle:
//   onStart       → fires immediately when the service (re)starts
//   onRepeatEvent → fires every 4 minutes
//   onDestroy     → fires when stopService() is called
//   onReceiveData → receives commands from the main isolate

import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:network_info_plus/network_info_plus.dart';

// ─── Constants shared with wifi_service.dart ─────────────────────────────────
const kBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://attenda-api-production.up.railway.app/api/v1',
);
const kCheckedInViaWifi = 'checkedInViaWifi';
const kLastKnownIp = 'lastKnownIp';
const kLastKnownSsid = 'lastKnownSsid';
const kStateBox = 'ip_state';
const kQueueBox = 'offline_queue';

// ─── Entry point (must be top-level + vm:entry-point) ────────────────────────
@pragma('vm:entry-point')
void startForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(AttendaTaskHandler());
}

// ─── Task Handler ─────────────────────────────────────────────────────────────
class AttendaTaskHandler extends TaskHandler {
  final _storage = const FlutterSecureStorage();
  final _networkInfo = NetworkInfo();
  final _connectivity = Connectivity();

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[FG] Service started — reason: $starter');
    await _initHive();
    await _runCycle();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _runCycle();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[FG] Service destroyed');
  }

  /// Receives commands sent from the main isolate via
  /// [WifiAttendanceService.sendCommandToService].
  @override
  void onReceiveData(Object data) {
    if (data == 'manual_checkout') {
      _handleManualCheckout();
    } else if (data == 'force_cycle') {
      _runCycle();
    }
  }

  // ── Core check cycle ───────────────────────────────────────────────────────

  Future<void> _runCycle() async {
    try {
      // 1. Need a valid token — service is a no-op if user is logged out
      final token = await _readToken();
      if (token == null) {
        debugPrint('[FG] No auth token — skipping');
        return;
      }

      // 2. Connectivity gate
      final connResult = await _connectivity.checkConnectivity();
      if (connResult.contains(ConnectivityResult.none)) {
        debugPrint('[FG] No connectivity');
        await _updateNotification(
          title: 'Attenda',
          text: 'No network connection',
        );
        return;
      }
      if (connResult.contains(ConnectivityResult.vpn)) {
        debugPrint('[FG] VPN active — skipping');
        await _updateNotification(
          title: 'Attenda — VPN Active',
          text: 'Auto check-in paused. Use QR scan.',
        );
        FlutterForegroundTask.sendDataToMain('vpn_detected');
        return;
      }

      // 3. WiFi details
      final ip = await _networkInfo.getWifiIP();
      var ssid =
          (await _networkInfo.getWifiName().catchError((_) => null as String?))
              ?.replaceAll('"', '');
      if (ssid == '<unknown ssid>') ssid = null;

      final hasWifi =
          (ip != null && ip.isNotEmpty) || (ssid != null && ssid.isNotEmpty);
      if (!hasWifi) {
        debugPrint('[FG] No WiFi info — no SSID/IP readable');
        await _updateNotification(
          title: 'Attenda',
          text: 'Waiting for readable office WiFi',
        );
        return;
      }

      // 4. Read persisted state
      await _initHive();
      final box = Hive.box(kStateBox);
      final checkedIn = box.get(kCheckedInViaWifi, defaultValue: false) as bool;

      // 5. Heartbeat if already checked in, ip-event to (re)check-in otherwise
      final dio = _buildDio(token);
      if (checkedIn) {
        await _heartbeat(dio: dio, ip: ip ?? '', ssid: ssid, box: box);
      } else {
        await _ipEvent(dio: dio, ip: ip ?? '', ssid: ssid, box: box);
      }
    } catch (e) {
      debugPrint('[FG] Cycle error: $e');
    }
  }

  // ── Heartbeat ──────────────────────────────────────────────────────────────

  Future<void> _heartbeat({
    required Dio dio,
    required String ip,
    String? ssid,
    required Box box,
  }) async {
    try {
      final res = await dio.post('/attendance/heartbeat', data: {
        'ip': ip,
        if (ssid != null && ssid.isNotEmpty) 'ssid': ssid,
      });
      final action = res.data['data']['action'] as String?;
      debugPrint('[FG] Heartbeat → $action');

      switch (action) {
        case 'heartbeat_accepted':
          await _updateNotification(
            title: 'Attenda - Checked In',
            text: 'Office WiFi · Last ping ${_hhmm()}',
          );
          FlutterForegroundTask.sendDataToMain('heartbeat_accepted');
          break;

        case 'not_on_office_network':
          // Left the office — start grace countdown in main isolate
          FlutterForegroundTask.sendDataToMain('heartbeat_lost:${ssid ?? ''}');
          await _updateNotification(
            title: 'Attenda - Left Office WiFi',
            text: 'Reconnect within 10 minutes to stay checked in',
          );
          break;

        case 'not_checked_in':
          // The server auto-checked us out (stale heartbeat) — try re-entry
          await box.put(kCheckedInViaWifi, false);
          await _ipEvent(dio: dio, ip: ip, ssid: ssid, box: box);
          break;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _tryRefreshAndRetry(
            ip: ip, ssid: ssid, box: box, wasSending: 'heartbeat');
      } else {
        debugPrint('[FG] Heartbeat network error: $e');
      }
    }
  }

  // ── IP event (check-in / re-entry) ─────────────────────────────────────────

  Future<void> _ipEvent({
    required Dio dio,
    required String ip,
    String? ssid,
    required Box box,
  }) async {
    try {
      final res = await dio.post('/attendance/ip-event', data: {
        'ip': ip,
        'event': 'match',
        if (ssid != null && ssid.isNotEmpty) 'ssid': ssid,
      });
      final action = res.data['data']['action'] as String?;
      debugPrint('[FG] IP-event → $action');

      switch (action) {
        case 'checked_in':
          await box.put(kCheckedInViaWifi, true);
          await box.put(kLastKnownIp, ip);
          await box.put(kLastKnownSsid, ssid);
          await _updateNotification(
            title: 'Attenda - Checked In',
            text: 'Auto check-in at ${_hhmm()} via office WiFi',
          );
          FlutterForegroundTask.sendDataToMain('checked_in');
          break;

        case 're_entered':
          await box.put(kCheckedInViaWifi, true);
          await box.put(kLastKnownIp, ip);
          await box.put(kLastKnownSsid, ssid);
          final gap = res.data['data']['gap_mins'] as int? ?? 0;
          // Short same-network gaps (screen off / Doze) are forgiven by the
          // server: no break is logged and the day continues uninterrupted.
          final forgiven = res.data['data']['forgiven'] as bool? ?? false;
          await _updateNotification(
            title: forgiven ? 'Attenda - Still Checked In' : 'Attenda - Back at Office',
            text: forgiven
                ? 'Brief signal drop (${gap}m) — no break logged'
                : 'Re-entered · ${gap}m away logged as break',
          );
          FlutterForegroundTask.sendDataToMain(
              forgiven ? 're_entered_forgiven:$gap' : 're_entered:$gap');
          break;

        case 'already_in':
          await box.put(kCheckedInViaWifi, true);
          await _updateNotification(
            title: 'Attenda - Checked In',
            text: 'Office WiFi · Last ping ${_hhmm()}',
          );
          FlutterForegroundTask.sendDataToMain('already_in');
          break;

        case 'no_networks_configured':
          await _updateNotification(
            title: 'Attenda',
            text: 'Auto check-in off — no office networks set up',
          );
          FlutterForegroundTask.sendDataToMain('no_networks');
          break;

        case 'none':
          // On WiFi, but not a registered office network — stay quiet
          await _updateNotification(
            title: 'Attenda',
            text: 'Not on office WiFi',
          );
          break;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _tryRefreshAndRetry(
            ip: ip, ssid: ssid, box: box, wasSending: 'ip_event');
      } else {
        debugPrint('[FG] IP-event network error: $e — queuing');
        await _queueEvent(ip: ip, ssid: ssid);
      }
    }
  }

  // ── Token refresh + retry ──────────────────────────────────────────────────

  Future<void> _tryRefreshAndRetry({
    required String ip,
    String? ssid,
    required Box box,
    required String wasSending,
  }) async {
    try {
      final refresh = await _storage.read(key: 'refresh_token');
      if (refresh == null) return;
      final res = await Dio().post(
        '$kBaseUrl/auth/refresh',
        data: {'refresh_token': refresh},
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      final newToken = res.data['data']['access_token'] as String?;
      if (newToken == null) return;
      await _storage.write(key: 'access_token', value: newToken);

      final newRefresh = res.data['data']['refresh_token'] as String?;
      if (newRefresh != null) {
        await _storage.write(key: 'refresh_token', value: newRefresh);
      }

      // Retry with new token
      final dio = _buildDio(newToken);
      if (wasSending == 'heartbeat') {
        await _heartbeat(dio: dio, ip: ip, ssid: ssid, box: box);
      } else {
        await _ipEvent(dio: dio, ip: ip, ssid: ssid, box: box);
      }
    } catch (e) {
      debugPrint('[FG] Token refresh failed: $e');
      // Do NOT delete tokens here — that causes silent logouts
    }
  }

  // ── Manual checkout command from main isolate ──────────────────────────────

  Future<void> _handleManualCheckout() async {
    try {
      await _initHive();
      final box = Hive.box(kStateBox);
      await box.put(kCheckedInViaWifi, false);
      await _updateNotification(
        title: 'Attenda',
        text: 'Checked out',
      );
    } catch (e) {
      debugPrint('[FG] Manual checkout state update failed: $e');
    }
  }

  // ── Offline queue ──────────────────────────────────────────────────────────

  Future<void> _queueEvent({required String ip, String? ssid}) async {
    try {
      if (!Hive.isBoxOpen(kQueueBox)) await Hive.openBox(kQueueBox);
      await Hive.box(kQueueBox).add(jsonEncode({
        'type': 'ipMatch',
        'timestamp': DateTime.now().toIso8601String(),
        'payload': ip,
        'ssid': ssid,
      }));
    } catch (_) {}
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<void> _initHive() async {
    await Hive.initFlutter();
    if (!Hive.isBoxOpen(kStateBox)) await Hive.openBox(kStateBox);
    if (!Hive.isBoxOpen(kQueueBox)) await Hive.openBox(kQueueBox);
  }

  Future<String?> _readToken() async {
    try {
      return await _storage.read(key: 'access_token');
    } catch (_) {
      return null;
    }
  }

  Dio _buildDio(String token) => Dio(BaseOptions(
        baseUrl: kBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ));

  String _hhmm() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _updateNotification({
    required String title,
    required String text,
  }) async {
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    } catch (_) {}
  }
}
