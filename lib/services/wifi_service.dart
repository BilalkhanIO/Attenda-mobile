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
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/api_service.dart';
import 'attendance_location.dart';
import 'foreground_service.dart'; // shared constants + startForegroundCallback

// ─── Offline-queue models ─────────────────────────────────────────────────────
enum OfflineEventType { checkIn, ipMatch, checkOut, breakStart, breakEnd }

class OfflineEvent {
  final OfflineEventType type;
  final DateTime timestamp;
  final String? payload;
  final String? ssid;
  final String? idempotencyKey;
  final bool requiresReview;
  final AttendanceLocationEvidence? location;
  final Map<String, dynamic>? clockProof;
  final int? sequence;
  final Map<String, dynamic>? actionData;
  OfflineEvent(
      {required this.type,
      required this.timestamp,
      this.payload,
      this.ssid,
      this.idempotencyKey,
      this.requiresReview = false,
      this.location,
      this.clockProof,
      this.sequence,
      this.actionData});
  Map<String, dynamic> toJson() => {
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        'payload': payload,
        'ssid': ssid,
        'idempotency_key': idempotencyKey,
        'requires_review': requiresReview,
        if (sequence != null) 'sequence': sequence,
        if (actionData != null) 'action_data': actionData,
        if (clockProof != null) 'clock_proof': clockProof,
        if (location != null) ...location!.toJson(),
      };
  factory OfflineEvent.fromJson(Map<String, dynamic> j) => OfflineEvent(
        type: OfflineEventType.values.firstWhere((e) => e.name == j['type']),
        timestamp: DateTime.parse(j['timestamp'] as String),
        payload: j['payload'] as String?,
        ssid: j['ssid'] as String?,
        idempotencyKey: j['idempotency_key'] as String?,
        requiresReview: j['requires_review'] as bool? ?? false,
        sequence: (j['sequence'] as num?)?.toInt(),
        actionData: (j['action_data'] as Map?)?.cast<String, dynamic>(),
        clockProof: (j['clock_proof'] as Map?)?.cast<String, dynamic>(),
        location: j['latitude'] is num && j['longitude'] is num
            ? AttendanceLocationEvidence(
                latitude: (j['latitude'] as num).toDouble(),
                longitude: (j['longitude'] as num).toDouble(),
                accuracyM: (j['accuracy_m'] as num?)?.toDouble() ?? 0,
                isMocked: j['is_mocked'] as bool? ?? false,
              )
            : null,
      );
}

// ─── Service singleton ────────────────────────────────────────────────────────
class WifiAttendanceService {
  static final WifiAttendanceService _instance = WifiAttendanceService._();
  factory WifiAttendanceService() => _instance;
  WifiAttendanceService._();

  static String newIdempotencyKey() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  int get pendingOfflineEventCount =>
      _queueEvents.where((event) => !event.requiresReview).length;
  int get parkedOfflineEventCount =>
      _queueEvents.where((event) => event.requiresReview).length;
  bool get hasPendingOfflineCheckout => _queueEvents.any((event) =>
      event.type == OfflineEventType.checkOut && !event.requiresReview);
  List<OfflineEvent> get _queueEvents {
    if (!Hive.isBoxOpen(kQueueBox)) return const [];
    final events = <OfflineEvent>[];
    for (final raw in Hive.box(kQueueBox).values) {
      try {
        if (raw is String) {
          events.add(
              OfflineEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>));
        } else if (raw is Map) {
          events.add(OfflineEvent.fromJson(raw.cast<String, dynamic>()));
        }
      } catch (_) {}
    }
    return events;
  }

  int _nextSequence() =>
      _queueEvents.fold<int>(
          0, (maxValue, event) => max(maxValue, event.sequence ?? 0)) +
      1;

  Future<void> queueOfflineAction(
      {required OfflineEventType type,
      required String idempotencyKey,
      required DateTime timestamp,
      required Map<String, dynamic> clockProof,
      Map<String, dynamic>? actionData}) async {
    if (type == OfflineEventType.checkIn || type == OfflineEventType.ipMatch) {
      throw ArgumentError(
          'Use the dedicated queue method for this event type.');
    }
    if (!Hive.isBoxOpen(kQueueBox)) await Hive.openBox(kQueueBox);
    await Hive.box(kQueueBox).add(jsonEncode(OfflineEvent(
      type: type,
      timestamp: timestamp,
      idempotencyKey: idempotencyKey,
      clockProof: clockProof,
      actionData: actionData,
      sequence: _nextSequence(),
    ).toJson()));
    onStatusChange?.call('offline_queue_changed');
  }

  Future<void> queueManualCheckIn(
      {required String idempotencyKey,
      required DateTime timestamp,
      AttendanceLocationEvidence? location,
      Map<String, dynamic>? clockProof,
      Map<String, dynamic>? deviceProof}) async {
    if (!Hive.isBoxOpen(kQueueBox)) await Hive.openBox(kQueueBox);
    final box = Hive.box(kQueueBox);
    final key = 'checkin:$idempotencyKey';
    await box.put(
        key,
        jsonEncode(OfflineEvent(
          type: OfflineEventType.checkIn,
          timestamp: timestamp,
          idempotencyKey: idempotencyKey,
          location: location,
          clockProof: clockProof,
          actionData:
              deviceProof == null ? null : {'device_proof': deviceProof},
          sequence: _nextSequence(),
        ).toJson()));
    onStatusChange?.call('offline_queue_changed');
  }

  final _networkInfo = NetworkInfo();
  final _connectivity = Connectivity();

  // ── In-memory state (UI isolate) ──────────────────────────────────────────
  String? _lastKnownIp;
  String? _lastKnownSsid;
  bool _checkedInViaWifi = false;
  bool _syncingOfflineQueue = false;

  /// Called with (status, [data]) — data carries extra info (e.g. gap minutes).
  void Function(String status, [String? data])? onStatusChange;

  // ── Grace / disconnect countdown (owned here so it survives tab-switch) ──
  // Server-driven: updated from each heartbeat ack (org heartbeat_grace_mins).
  Duration graceWindow = const Duration(minutes: 20);
  DateTime? disconnectDeadline;
  String? disconnectSsid;
  DateTime? lastHeartbeatAt;
  bool vpnDetected = false;
  bool noNetworksConfigured = false;
  bool get heartbeatLost => disconnectDeadline != null;

  // ── Foreground heartbeat timer ────────────────────────────────────────────
  Timer? _fgHeartbeatTimer;
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
        channelId: 'attenda_wifi',
        channelName: 'Attendance Tracking',
        channelDescription: 'Monitors office WiFi for automatic check-in/out',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Fire every 4 minutes — well within the server's heartbeat grace
        // window (org-configurable, 20 min default)
        eventAction: ForegroundTaskEventAction.repeat(4 * 60 * 1000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    // ── Receive status events from the background task ───────────────────
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);

    // ── Start (or keep) the foreground service ───────────────────────────
    await _startService();

    // ── React to connectivity changes in the foreground ──────────────────
    _connectivitySub =
        _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);

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
      serviceId: _serviceId,
      notificationTitle: 'Attenda',
      notificationText: 'Monitoring office WiFi for attendance…',
      callback: startForegroundCallback,
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
    lastHeartbeatAt = null;
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
      _checkedInViaWifi = true;
      noNetworksConfigured = false;
      vpnDetected = false;
      _markReconnected();
      _saveState();
      _startFgHeartbeat();
      onStatusChange?.call('checked_in');
    } else if (msg.startsWith('re_entered:') ||
        msg.startsWith('re_entered_forgiven:')) {
      _checkedInViaWifi = true;
      noNetworksConfigured = false;
      vpnDetected = false;
      _markReconnected();
      _saveState();
      _startFgHeartbeat();
      final gap = msg.split(':').last;
      onStatusChange?.call(
          msg.startsWith('re_entered_forgiven:')
              ? 're_entered_forgiven'
              : 're_entered',
          gap);
    } else if (msg == 'already_in') {
      _checkedInViaWifi = true;
      noNetworksConfigured = false;
      vpnDetected = false;
      _markReconnected();
      _saveState();
      _startFgHeartbeat();
    } else if (msg == 'heartbeat_accepted') {
      lastHeartbeatAt = DateTime.now();
      vpnDetected = false;
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

      final ip = await _networkInfo.getWifiIP();
      var ssid =
          (await _networkInfo.getWifiName().catchError((_) => null as String?))
              ?.replaceAll('"', '');
      if (ssid == '<unknown ssid>') ssid = null;

      final hasNet =
          (ip != null && ip.isNotEmpty) || (ssid != null && ssid.isNotEmpty);
      if (!hasNet) {
        if (_checkedInViaWifi) _markDisconnected();
        return;
      }

      if (ip != _lastKnownIp || ssid != _lastKnownSsid) {
        _lastKnownIp = ip;
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
          _checkedInViaWifi = true;
          noNetworksConfigured = false;
          await _saveState();
          _markReconnected();
          _startFgHeartbeat();
          onStatusChange?.call('checked_in');
          break;
        case 're_entered':
          _checkedInViaWifi = true;
          noNetworksConfigured = false;
          await _saveState();
          _markReconnected();
          _startFgHeartbeat();
          final gap = result['gap_mins'] as int? ?? 0;
          final forgiven = result['forgiven'] as bool? ?? false;
          onStatusChange?.call(
              forgiven ? 're_entered_forgiven' : 're_entered', '$gap');
          break;
        case 'already_in':
          _checkedInViaWifi = true;
          noNetworksConfigured = false;
          await _saveState();
          _markReconnected();
          _startFgHeartbeat();
          await _fgHeartbeat(ip: ip, ssid: ssid);
          break;
        case 'manual_checkin_required':
          onStatusChange?.call('manual_checkin_required');
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
      await _queueEvent(OfflineEvent(
        type: OfflineEventType.ipMatch,
        timestamp: DateTime.now(),
        payload: ip,
        ssid: ssid,
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
    if (!results.contains(ConnectivityResult.none)) {
      await syncOfflineQueue();
    }
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
    disconnectSsid = null;
    if (notify && wasLost) onStatusChange?.call('heartbeat_restored');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Offline queue — sync queued events when connectivity is restored
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> syncOfflineQueue() async {
    if (_syncingOfflineQueue) return;
    _syncingOfflineQueue = true;
    try {
      if (!Hive.isBoxOpen(kQueueBox)) return;
      final box = Hive.box(kQueueBox);
      if (box.isEmpty) return;
      final conn = await _connectivity.checkConnectivity();
      if (conn.contains(ConnectivityResult.none)) return;

      final queued = <({dynamic key, OfflineEvent event})>[];
      for (final key in box.keys) {
        try {
          final raw = box.get(key);
          if (raw is String) {
            queued.add((
              key: key,
              event:
                  OfflineEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>)
            ));
          } else if (raw is Map) {
            queued.add((
              key: key,
              event: OfflineEvent.fromJson(raw.cast<String, dynamic>())
            ));
          }
        } catch (_) {}
      }
      queued.sort(
          (a, b) => (a.event.sequence ?? 0).compareTo(b.event.sequence ?? 0));
      var sequence = 0;
      for (var i = 0; i < queued.length; i++) {
        sequence = max(sequence + 1, queued[i].event.sequence ?? 0);
        queued[i] = (
          key: queued[i].key,
          event: OfflineEvent(
            type: queued[i].event.type,
            timestamp: queued[i].event.timestamp,
            payload: queued[i].event.payload,
            ssid: queued[i].event.ssid,
            idempotencyKey: queued[i].event.idempotencyKey,
            requiresReview: queued[i].event.requiresReview,
            location: queued[i].event.location,
            clockProof: queued[i].event.clockProof,
            sequence: sequence,
            actionData: queued[i].event.actionData,
          )
        );
      }

      var index = 0;
      while (index < queued.length) {
        final first = queued[index];
        final raw = box.get(first.key);
        if (raw == null) {
          index++;
          continue;
        }
        final event = first.event;
        // A parked action blocks later actions until the user reviews it; sending
        // a checkout without its check-in would corrupt the attendance timeline.
        if (event.requiresReview) break;
        if (DateTime.now().difference(event.timestamp) >
            const Duration(hours: 12)) {
          await box.put(
              first.key,
              jsonEncode(OfflineEvent(
                      type: event.type,
                      timestamp: event.timestamp,
                      payload: event.payload,
                      ssid: event.ssid,
                      idempotencyKey: event.idempotencyKey,
                      requiresReview: true,
                      location: event.location,
                      clockProof: event.clockProof,
                      sequence: event.sequence,
                      actionData: event.actionData)
                  .toJson()));
          onStatusChange?.call('offline_checkin_review');
          break;
        }

        // Wi-Fi observations are sent through their existing endpoint and are
        // never included as attendance actions in an offline batch.
        if (event.type == OfflineEventType.ipMatch) {
          try {
            await api.reportIpEvent(event.payload ?? '', ssid: event.ssid);
            await box.delete(first.key);
            onStatusChange?.call('offline_queue_changed');
            index++;
            continue;
          } catch (_) {
            break;
          }
        }

        final batch =
            <({dynamic key, OfflineEvent event, String idempotencyKey})>[];
        for (var cursor = index;
            cursor < queued.length && batch.length < 20;
            cursor++) {
          final item = queued[cursor];
          final currentRaw = box.get(item.key);
          if (currentRaw == null) continue;
          final current = item.event;
          if (current.requiresReview ||
              current.type == OfflineEventType.ipMatch ||
              DateTime.now().difference(current.timestamp) >
                  const Duration(hours: 12)) {
            break;
          }
          final actionKey =
              current.idempotencyKey ?? ApiService.newIdempotencyKey();
          final saved = OfflineEvent(
              type: current.type,
              timestamp: current.timestamp,
              payload: current.payload,
              ssid: current.ssid,
              idempotencyKey: actionKey,
              requiresReview: false,
              location: current.location,
              clockProof: current.clockProof,
              sequence: current.sequence,
              actionData: current.actionData);
          await box.put(item.key, jsonEncode(saved.toJson()));
          batch.add((key: item.key, event: saved, idempotencyKey: actionKey));
        }
        if (batch.isEmpty) {
          index++;
          continue;
        }

        final requestEvents = batch.map((item) {
          final queuedEvent = item.event;
          final payload = <String, dynamic>{
            'offline': true,
            'idempotency_key': item.idempotencyKey,
            'client_event_at': queuedEvent.timestamp.toUtc().toIso8601String(),
            ...?queuedEvent.clockProof,
          };
          switch (queuedEvent.type) {
            case OfflineEventType.checkIn:
              payload['type'] = 'manual';
              if (queuedEvent.location != null) {
                payload.addAll(queuedEvent.location!.toJson());
              }
              final deviceProof = queuedEvent.actionData?['device_proof'];
              if (deviceProof is Map) {
                payload['device_proof'] = deviceProof.cast<String, dynamic>();
              }
              break;
            case OfflineEventType.checkOut:
              break;
            case OfflineEventType.breakStart:
              payload['break_type'] =
                  queuedEvent.actionData?['break_type'] ?? 'manual';
              if (queuedEvent.actionData?['shift_break_id'] != null) {
                payload['shift_break_id'] =
                    queuedEvent.actionData!['shift_break_id'];
              }
              break;
            case OfflineEventType.breakEnd:
              if (queuedEvent.actionData?['wifi_connected'] != null) {
                payload['wifi_connected'] =
                    queuedEvent.actionData!['wifi_connected'];
              }
              break;
            case OfflineEventType.ipMatch:
              break;
          }
          final type = switch (queuedEvent.type) {
            OfflineEventType.checkIn => 'checkin',
            OfflineEventType.checkOut => 'checkout',
            OfflineEventType.breakStart => 'break_start',
            OfflineEventType.breakEnd => 'break_end',
            OfflineEventType.ipMatch => 'ip_match',
          };
          return {
            'sequence': queuedEvent.sequence,
            'idempotency_key': item.idempotencyKey,
            'type': type,
            'payload': payload
          };
        }).toList();

        List<Map<String, dynamic>> outcomes;
        try {
          outcomes = await api.syncAttendanceEvents(requestEvents);
        } catch (error) {
          final code = (error as dynamic)?.response?.statusCode as int?;
          String? apiCode;
          try {
            final data = (error as dynamic).response?.data;
            if (data is Map) apiCode = data['code'] as String?;
          } catch (_) {}
          final statusCode = code ?? 0;
          final transient = code == null ||
              statusCode == 408 ||
              statusCode == 429 ||
              statusCode >= 500 ||
              apiCode == 'ATTENDANCE_SYNC_IN_PROGRESS' ||
              apiCode == 'SYNC_COORDINATION_UNAVAILABLE' ||
              apiCode == 'IDEMPOTENCY_REQUEST_IN_PROGRESS';
          if (!transient &&
              statusCode >= 400 &&
              statusCode < 500 &&
              statusCode != 401 &&
              statusCode != 403) {
            for (final item in batch) {
              await box.put(
                  item.key,
                  jsonEncode(OfflineEvent(
                          type: item.event.type,
                          timestamp: item.event.timestamp,
                          payload: item.event.payload,
                          ssid: item.event.ssid,
                          idempotencyKey: item.idempotencyKey,
                          requiresReview: true,
                          location: item.event.location,
                          clockProof: item.event.clockProof,
                          sequence: item.event.sequence,
                          actionData: item.event.actionData)
                      .toJson()));
            }
            onStatusChange?.call('offline_checkin_review');
          }
          break;
        }

        var shouldStop = false;
        for (var outcomeIndex = 0;
            outcomeIndex < batch.length;
            outcomeIndex++) {
          final item = batch[outcomeIndex];
          final result = outcomeIndex < outcomes.length
              ? outcomes[outcomeIndex]['result']
              : 'retry';
          if (result == 'applied' || result == 'duplicate') {
            await box.delete(item.key);
          } else if (result == 'parked_for_review' || result == 'rejected') {
            await box.put(
                item.key,
                jsonEncode(OfflineEvent(
                        type: item.event.type,
                        timestamp: item.event.timestamp,
                        payload: item.event.payload,
                        ssid: item.event.ssid,
                        idempotencyKey: item.idempotencyKey,
                        requiresReview: true,
                        location: item.event.location,
                        clockProof: item.event.clockProof,
                        sequence: item.event.sequence,
                        actionData: item.event.actionData)
                    .toJson()));
            onStatusChange?.call('offline_checkin_review');
            shouldStop = true;
            break;
          } else {
            // Unknown or retry outcomes stay in the outbox. The server may have
            // committed an event whose response was lost, so keep its same key.
            shouldStop = true;
            break;
          }
        }
        onStatusChange?.call('offline_queue_changed');
        index += batch.length;
        if (shouldStop || outcomes.length < batch.length) break;
      }
    } finally {
      _syncingOfflineQueue = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Permissions
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> ensureLocationPermission() async {
    try {
      var status = await Permission.locationWhenInUse.status;
      if (!status.isGranted) {
        status = await Permission.locationWhenInUse.request();
      }
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
      final permission =
          await FlutterForegroundTask.checkNotificationPermission();
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
    _lastKnownIp = box.get(kLastKnownIp) as String?;
    _lastKnownSsid = box.get(kLastKnownSsid) as String?;

    // Restart the foreground heartbeat if we were checked in before restart
    if (_checkedInViaWifi) _startFgHeartbeat();
  }

  Future<void> _saveState() async {
    if (!Hive.isBoxOpen(kStateBox)) return;
    final box = Hive.box(kStateBox);
    await box.put(kCheckedInViaWifi, _checkedInViaWifi);
    await box.put(kLastKnownIp, _lastKnownIp);
    await box.put(kLastKnownSsid, _lastKnownSsid);
  }

  Future<void> _queueEvent(OfflineEvent event) async {
    if (!Hive.isBoxOpen(kQueueBox)) return;
    await Hive.box(kQueueBox).add(jsonEncode(OfflineEvent(
      type: event.type,
      timestamp: event.timestamp,
      payload: event.payload,
      ssid: event.ssid,
      idempotencyKey: event.idempotencyKey,
      requiresReview: event.requiresReview,
      location: event.location,
      clockProof: event.clockProof,
      sequence: _nextSequence(),
      actionData: event.actionData,
    ).toJson()));
    onStatusChange?.call('offline_queue_changed');
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
