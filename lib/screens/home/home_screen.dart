import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_provider.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../services/wifi_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';
import 'widgets/break_banners.dart';
import 'widgets/break_control.dart';
import 'widgets/disconnect_card.dart';
import 'widgets/home_banners.dart';
import 'widgets/quick_actions.dart';
import 'widgets/shift_card.dart';
import 'widgets/status_card.dart';
import 'widgets/whos_out_card.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _todayRecord;
  Map<String, dynamic>? _nextShift;
  Map<String, dynamic>? _remoteSession;
  Map<String, dynamic>? _todayLeave;
  Map<String, dynamic>? _lateNotice;
  Map<String, dynamic>? _todayStatus; // from /attendance/today-status
  Map<String, dynamic>? _whosOut; // from /org/whos-out (today)
  bool _loading = true;
  // First-load failure with nothing cached — drives the error + Retry state.
  // Background/silent refresh failures never set this; the last good data
  // stays on screen instead.
  String? _loadError;
  bool _actionLoading = false;
  Timer? _timer;
  Timer? _refreshTimer;
  Timer? _flashTimer;
  Duration _elapsed = Duration.zero;
  int _unreadNotifs = 0;

  // Offline indicator — fed by connectivity_plus, shown as a thin banner.
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _offline = false;

  // Auto-started break acknowledgement + deferred reminder state.
  final Set<String> _acknowledgedAutoBreaks = {};
  List<Map<String, dynamic>> _deferredReminders = [];
  String? _pendingReminderName;
  bool _pendingReminderDeduct = true;

  // Clock offset = serverTime - deviceTime, corrects for device clock skew.
  Duration _clockOffset = Duration.zero;

  // Flash messages shown briefly after a WiFi event, then auto-dismissed.
  String? _breakWelcomeBack;   // "Welcome back — you were X late from Lunch"
  String? _lateArrivalFlash;  // "You checked in X late today"

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _initialSync();

    _startTimer();
    _startAutoRefresh();

    // Offline banner: connectivity_plus reports [none] when fully offline.
    Connectivity().checkConnectivity().then((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (mounted && offline != _offline) setState(() => _offline = offline);
    }).catchError((_) {});
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (mounted && offline != _offline) setState(() => _offline = offline);
    });

    // The service owns the connection state; the callback only refreshes the
    // UI and runs side effects (snack / data reload). Reading state via getters
    // means a freshly-rebuilt HomeScreen shows the correct status immediately.
    WifiAttendanceService().onStatusChange = (status, [data]) {
      if (!mounted) return;
      switch (status) {
        case 'checked_in':
          // Reload first, then check whether the check-in was late.
          _load(silent: true).then((_) {
            if (!mounted) return;
            final lateMins = (_todayRecord?['late_minutes'] as num?)?.toInt() ?? 0;
            if (lateMins > 0) {
              _showFlash(
                'You checked in ${formatMinutesHours(lateMins)} late today',
                isBreak: false,
              );
            } else {
              _showSnack('✅ Auto checked in via office WiFi');
            }
          });
          break;
        case 're_entered':
          _load(silent: true);
          final gap = int.tryParse(data ?? '0') ?? 0;
          _showSnack('✅ Returned to office — ${gap}m away logged as break');
          break;
        case 're_entered_forgiven':
          _load(silent: true);
          _showSnack('✅ Reconnected — brief signal drop, no break logged');
          break;
        case 'heartbeat_restored':
          // Capture overdue state BEFORE reload wipes it, then show after.
          final welcomeMsg = _overdueBreakWelcomeBack();
          _load(silent: true).then((_) {
            if (!mounted) return;
            if (welcomeMsg != null) {
              _showFlash(welcomeMsg, isBreak: true);
            } else {
              _showSnack('✅ Back on office WiFi');
            }
          });
          setState(() {});
          break;
        case 'heartbeat_lost':
        case 'vpn_detected':
        case 'no_networks':
          setState(() {});
          break;
      }
    };
  }

  Future<void> _initialSync() async {
    setState(() => _loading = true);
    try {
      await WifiAttendanceService().checkAndReport();
    } catch (_) {}
    await _loadDeferredReminders();
    if (mounted) await _load(silent: true);
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _refreshTimer?.cancel();
    _flashTimer?.cancel();
    _connSub?.cancel();
    WifiAttendanceService().onStatusChange = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startAutoRefresh();
      _resumeSync();
      WifiAttendanceService().syncOfflineQueue();
    } else if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel(); // stop UI polling while backgrounded
      // Foreground heartbeat timer is stopped; background service keeps running
    }
  }

  Future<void> _resumeSync() async {
    try {
      await WifiAttendanceService().checkAndReport();
    } catch (_) {}
    if (mounted) await _load(silent: true);
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w500)),
      backgroundColor: isError ? AppColors.danger500 : AppColors.gray900,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
      duration: const Duration(seconds: 3),
    ));
  }

  // ── SharedPreferences cache keys ──────────────────────
  static const _kCachedStatus = 'attenda_today_status';
  static const _kCachedRecord = 'attenda_today_record';
  static const _kCacheDate    = 'attenda_cache_date';

  Future<void> _persistCache(Map<String, dynamic> todayStatus, Map<String, dynamic>? todayRecord) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await prefs.setString(_kCachedStatus, jsonEncode(todayStatus));
      await prefs.setString(_kCachedRecord, jsonEncode(todayRecord ?? {}));
      await prefs.setString(_kCacheDate, dateStr);
    } catch (_) {}
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (prefs.getString(_kCacheDate) != dateStr) return; // stale day — ignore
      final statusJson = prefs.getString(_kCachedStatus);
      final recordJson = prefs.getString(_kCachedRecord);
      if (statusJson == null || !mounted) return;
      final cachedStatus = jsonDecode(statusJson) as Map<String, dynamic>;
      final cachedRecord = recordJson != null
          ? (jsonDecode(recordJson) as Map<String, dynamic>)
          : null;
      setState(() {
        _todayStatus ??= cachedStatus;
        if (_todayRecord == null && cachedRecord != null && cachedRecord.isNotEmpty) {
          _todayRecord = cachedRecord;
        }
      });
    } catch (_) {}
  }

  Future<void> _load({bool silent = false}) async {
    // Silent refreshes (the 30s poll, resume, pull-to-refresh) skip the loading
    // flag so the status card doesn't flash its skeleton or re-run entry
    // animations. Only the very first load shows the skeleton.
    if (!silent) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        api.getMyAttendance(days: 1),
        api.getMyShifts(),
        api.getLeaveAndNoticeCheck().catchError((_) => <String, dynamic>{}),
        api.getTodayStatus().catchError((_) => <String, dynamic>{}),
        // Who's out + holidays are additive UI — fail silently and keep the
        // last good data when the fetch doesn't come back.
        api.getWhosOut().catchError((_) => <String, dynamic>{}),
      ]);

      final records    = results[0] as List;
      final shifts     = results[1] as List;
      final leaveInfo  = results[2] as Map<String, dynamic>;
      final todayStatus = results[3] as Map<String, dynamic>;
      final whosOut    = results[4] as Map<String, dynamic>;

      // Never overwrite good in-memory data with an empty offline response.
      if (todayStatus.isEmpty) {
        if (_todayStatus == null) await _loadFromCache();
        if (mounted) {
          setState(() {
            if (_todayStatus == null) {
              _loadError = 'Could not reach the server. Check your connection.';
            }
            _loading = false;
          });
        }
        return;
      }

      final statusAttendance = todayStatus['attendance'] is Map
          ? (todayStatus['attendance'] as Map).cast<String, dynamic>()
          : null;
      final statusDate = todayStatus['date'] as String?;
      final fallbackDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final todayDate = statusDate ?? fallbackDate;
      Map<String, dynamic>? todayRecord;
      for (final raw in records) {
        if (raw is! Map) continue;
        final record = raw.cast<String, dynamic>();
        final recordDate = (record['date'] ?? '').toString();
        if (recordDate.startsWith(todayDate)) {
          todayRecord = record;
          break;
        }
      }
      todayRecord ??= statusAttendance;
      final status = todayRecord?['status'] as String? ?? 'none';

      // Compute clock offset once per successful fetch.
      final serverTimeStr = todayStatus['server_time'] as String?;
      if (serverTimeStr != null) {
        final serverTime = DateTime.parse(serverTimeStr);
        _clockOffset = serverTime.difference(DateTime.now());
      }

      Map<String, dynamic>? remoteSession;
      if (status == 'remote') {
        try {
          final sessions = await api.getMyRemoteSessions();
          remoteSession = sessions.isNotEmpty
              ? sessions.first as Map<String, dynamic>
              : null;
        } catch (_) {}
      }

      if (mounted) {
        final mergedRecord = {
          if (todayRecord != null) ...todayRecord,
          if (statusAttendance != null) ...statusAttendance,
        };
        setState(() {
          _todayRecord  = mergedRecord.isNotEmpty ? mergedRecord : _todayRecord;
          _nextShift    = shifts.isNotEmpty ? shifts.first as Map<String, dynamic> : null;
          _remoteSession = remoteSession;
          _todayLeave   = leaveInfo['leave'] as Map<String, dynamic>?;
          _lateNotice   = leaveInfo['late_notice'] as Map<String, dynamic>?;
          _todayStatus  = todayStatus;
          if (whosOut.isNotEmpty) _whosOut = whosOut;
          _loadError    = null;
          _loading      = false;
        });
        _updateElapsed();
        // Persist for offline use
        _persistCache(todayStatus, mergedRecord.isNotEmpty ? mergedRecord : null);
      }
    } catch (e) {
      // API totally failed — fall back to cache so banners still work offline.
      if (_todayStatus == null) await _loadFromCache();
      if (mounted) {
        setState(() {
          if (_todayStatus == null) {
            _loadError = ApiFailure.fromError(e).userMessage;
          }
          _loading = false;
        });
      }
    }

    try {
      final count = await api.getNotificationCount();
      if (mounted) setState(() => _unreadNotifs = count);
    } catch (_) {}
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateElapsed();
    });
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_loading) _load(silent: true);
    });
  }

  void _updateElapsed() {
    final checkIn = _todayRecord?['check_in_at'] as String?;
    final checkOut = _todayRecord?['check_out_at'] as String?;
    if (checkIn != null && checkOut == null) {
      setState(() => _elapsed = _liveWorkedDuration());
    } else if (_autoCheckoutRisk) {
      setState(() {}); // keep the disconnect countdown ticking
    }
    // Once the grace window has elapsed the server is closing us out; poll so
    // the UI flips to the checked-out card promptly (instead of waiting up to
    // the 30s refresh).
    if (_autoCheckoutRisk && _graceExpired) _pollForAutoCheckout();
    _checkDeferredReminders();
  }

  Duration _liveWorkedDuration() {
    final checkIn = _parseLocal(_todayRecord?['check_in_at']);
    if (checkIn == null) return Duration.zero;
    final checkOut = _parseLocal(_todayRecord?['check_out_at']);
    final end = checkOut ?? _now;
    var worked = end.difference(checkIn);

    final breakRecords = (_todayRecord?['break_records'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    for (final b in breakRecords) {
      if (b['is_paid'] == true) continue;
      final breakStart = _parseLocal(b['break_start']);
      if (breakStart == null) continue;
      final breakEnd = _parseLocal(b['break_end']) ?? end;
      if (!breakEnd.isAfter(breakStart)) continue;
      worked -= breakEnd.difference(breakStart);
    }

    return worked.isNegative ? Duration.zero : worked;
  }

  int _totalBreakMinutes(Map<String, dynamic>? record) {
    if (record == null) return 0;
    final breakRecords = (record['break_records'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    if (breakRecords.isEmpty) return _asInt(record['break_minutes']) ?? 0;

    var total = 0;
    final endOfWork = _parseLocal(record['check_out_at']) ?? _now;
    for (final b in breakRecords) {
      final stored = _asInt(b['duration_mins']);
      if (stored != null) {
        total += stored;
        continue;
      }
      final start = _parseLocal(b['break_start']);
      if (start == null) continue;
      final end = _parseLocal(b['break_end']) ?? endOfWork;
      if (end.isAfter(start)) {
        total += end.difference(start).inMinutes;
      }
    }
    return total;
  }

  DateTime? _lastExpiryPoll;
  void _pollForAutoCheckout() {
    if (_loading) return;
    final now = DateTime.now();
    if (_lastExpiryPoll != null &&
        now.difference(_lastExpiryPoll!) < const Duration(seconds: 10)) {
      return;
    }
    _lastExpiryPoll = now;
    _load(silent: true);
  }

  String get _elapsedDisplay {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes % 60;
    final s = _elapsed.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String get _disconnectCountdown {
    if (_disconnectDeadline == null) return '';
    final remaining = _disconnectDeadline!.difference(DateTime.now());
    if (remaining.isNegative) return '00:00';
    final m = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  DateTime? _parseLocal(dynamic value) {
    if (value == null) return null;
    try {
      return DateTime.parse(value.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  int get _livePreCheckinLateMins {
    final shift = (_todayStatus?['shift'] as Map?)?.cast<String, dynamic>();
    final start = _parseLocal(shift?['shift_start_utc']);
    if (start == null || _checkedIn || _checkedOut) return 0;
    // Use server-corrected _now (not device DateTime.now()) so this matches the
    // break countdowns and the server's pre_checkin_late_minutes under clock skew.
    final minutes = _now.difference(start).inMinutes;
    return minutes > 0 ? minutes : 0;
  }

  String get _status => _todayRecord?['status'] as String? ?? 'none';
  bool get _checkedIn => _status == 'in' || _status == 'late';
  bool get _checkedOut => _status == 'out';
  bool get _isRemote => _status == 'remote';

  // WiFi/connection state is owned by the singleton so it survives the
  // HomeScreen being recreated on every tab switch (the disconnect countdown
  // therefore keeps running instead of restarting).
  WifiAttendanceService get _wifi => WifiAttendanceService();
  bool get _heartbeatLost => _wifi.heartbeatLost;
  bool get _vpnDetected => _wifi.vpnDetected;
  bool get _noNetworksConfig => _wifi.noNetworksConfigured;
  String? get _disconnectSsid => _wifi.disconnectSsid;
  DateTime? get _disconnectDeadline => _wifi.disconnectDeadline;

  // The disconnect/grace UI applies to unexpected WiFi loss while actively
  // working. During a break, the break timer owns the state; the backend also
  // defers heartbeat checkout until the break is overdue plus grace.
  bool get _autoCheckoutRisk => _heartbeatLost && _checkedIn && !_isOnBreak;
  // True once the grace window has elapsed — the server is closing us out.
  bool get _graceExpired =>
      _disconnectDeadline != null &&
      !DateTime.now().isBefore(_disconnectDeadline!);

  bool get _isOnBreak =>
      (_todayRecord?['break_records'] as List?)
          ?.cast<Map<String, dynamic>>()
          .any((b) => b['break_end'] == null) ??
      false;

  // Current time corrected for any device/server clock drift.
  DateTime get _now => DateTime.now().add(_clockOffset);

  // ── Who's out / holidays (from /org/whos-out) ──────────
  List<Map<String, dynamic>> get _whosOutLeave =>
      (_whosOut?['on_leave'] as List?)
          ?.whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList() ??
      const [];
  List<Map<String, dynamic>> get _whosOutRemote =>
      (_whosOut?['remote'] as List?)
          ?.whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList() ??
      const [];
  bool get _todayIsHoliday =>
      ((_whosOut?['holidays'] as List?)?.whereType<String>() ??
              const <String>[])
          .contains(DateFormat('yyyy-MM-dd').format(DateTime.now()));

  void _showFlash(String msg, {required bool isBreak}) {
    _flashTimer?.cancel();
    setState(() {
      if (isBreak) {
        _breakWelcomeBack = msg;
        _lateArrivalFlash = null;
      } else {
        _lateArrivalFlash = msg;
        _breakWelcomeBack = null;
      }
    });
    _flashTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() { _breakWelcomeBack = null; _lateArrivalFlash = null; });
    });
  }

  // Returns the overdue welcome-back message if any shift break was overdue
  // at the time the device reconnected to office WiFi. Called before reload.
  String? _overdueBreakWelcomeBack() {
    final breaks = (_todayStatus?['shift']?['breaks'] as List?)
        ?.cast<Map<String, dynamic>>() ?? [];
    int maxLate = 0;
    String? breakName;
    for (final b in breaks) {
      if (b['break_state'] != 'overdue') continue;
      final endUtc = _parseLocal(b['break_end_utc']);
      if (endUtc == null) continue;
      final late = _now.difference(endUtc).inMinutes;
      if (late > maxLate) { maxLate = late; breakName = b['name'] as String?; }
    }
    if (maxLate <= 0 || breakName == null) return null;
    return 'Welcome back — you were ${formatMinutesHours(maxLate)} late from $breakName';
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user!;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: primary,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            await _load(silent: true);
            await WifiAttendanceService().checkAndReport();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── Header ───────────────────────────────
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$greeting,',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.gray500)),
                            const SizedBox(height: 2),
                            Text(user.name.split(' ').first,
                                style: AppTextStyles.display),
                          ]),
                      Row(children: [
                        // Notification bell
                        GestureDetector(
                          onTap: () async {
                            await context.push('/home/notifications');
                            _load(silent: true);
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.control),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  const Icon(Icons.notifications_none_rounded,
                                      size: 22, color: AppColors.gray600),
                                  if (_unreadNotifs > 0)
                                    Positioned(
                                      top: 12,
                                      right: 12,
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: AppColors.surface,
                                                width: 1.5)),
                                      ),
                                    ),
                                ]),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => context.go('/profile'),
                          child: UserAvatar(
                            name: user.name,
                            imageUrl: _todayStatus?['user']?['avatar_url'] as String?,
                            size: 40,
                          ),
                        ),
                      ]),
                    ]),

                const SizedBox(height: 20),

                // ─── Banners ──────────────────────────────
                AnimatedSize(
                  duration: AppMotion.duration,
                  curve: AppMotion.curve,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (_offline) const OfflineBanner(),
                    if (_vpnDetected) const VpnBanner(),
                    if (_noNetworksConfig && !_vpnDetected)
                      const NoNetworksBanner(),
                    if (_todayIsHoliday) const HolidayBanner(),
                    if (!_loading &&
                        _todayLeave != null &&
                        _status != 'in' &&
                        _status != 'late' &&
                        _status != 'out')
                      LeaveTodayBanner(
                          leaveType:
                              (_todayLeave?['leave_type'] as String? ?? 'leave')
                                  .replaceAll('_', ' ')),
                    if (!_loading &&
                        _lateNotice != null &&
                        _status != 'in' &&
                        _status != 'late' &&
                        _status != 'out')
                      LateNoticeBanner(
                          expectedTime:
                              _lateNotice?['expected_time'] as String? ?? '',
                          isAcknowledged:
                              (_lateNotice?['status'] as String? ?? 'pending') ==
                                  'acknowledged',
                          onCancel: _cancelLateNotice),
                    // ── Break alert banners (from today-status) ──
                    if (!_loading && _checkedIn) ..._breakAlertBanners(),
                    // ── Pre-check-in live late counter ───────────
                    if (!_loading && !_checkedIn && !_checkedOut)
                      PreCheckinLateBanner(
                          lateMinutes: _livePreCheckinLateMins > 0
                              ? _livePreCheckinLateMins
                              : ((_todayStatus?['pre_checkin_late_minutes']
                                          as num?)
                                      ?.toInt() ??
                                  0)),
                    // ── Flash: welcome back from break ───────────
                    if (_breakWelcomeBack != null)
                      FlashBanner(
                          text: _breakWelcomeBack!,
                          tint: AppColors.warning500,
                          icon: Icons.celebration_outlined,
                          onDismiss: _dismissFlash),
                    // ── Flash: late arrival notice ────────────────
                    if (_lateArrivalFlash != null)
                      FlashBanner(
                          text: _lateArrivalFlash!,
                          tint: AppColors.warning500,
                          icon: Icons.access_alarm,
                          onDismiss: _dismissFlash),
                  ]),
                ),

                // ─── First-load failure (nothing cached) ──
                if (!_loading && _loadError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: EmptyStateWidget(
                      icon: Icons.error_outline,
                      title: 'Couldn\'t load',
                      description: _loadError!,
                      action: AppButton(
                          label: 'Retry',
                          onPressed: () => _load(),
                          fullWidth: false),
                    ),
                  )
                else ...[
                // ─── Status Card ──────────────────────────
                _loading
                    ? const SkeletonBox(
                        width: double.infinity, height: 160, radius: 16)
                    : AnimatedSwitcher(
                        duration: AppMotion.duration,
                        switchInCurve: AppMotion.curve,
                        switchOutCurve: AppMotion.curve,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: child,
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(
                              _status + (_autoCheckoutRisk ? '_hl' : '')),
                          child: _buildStatusCard(),
                        ),
                      ),

                const SizedBox(height: 20),

                // ─── Break control ─────────────────────────────────
                // Always show when checked in. When WiFi is lost mid-break
                // (_autoCheckoutRisk) we still show End Break so the employee
                // can close the break record before the grace window expires.
                // Hide "Take a Break" during the disconnect countdown (they
                // shouldn't start a new break while the session is at risk).
                if (!_loading && _checkedIn &&
                    (!_autoCheckoutRisk || _isOnBreak)) ...[
                  BreakControl(
                    isOnBreak: _isOnBreak,
                    actionLoading: _actionLoading,
                    onEndBreak: _endBreak,
                    onTakeBreak: _showBreakTypeSheet,
                  ),
                  const SizedBox(height: 20),
                ],

                // ─── Quick Actions ────────────────────────
                const SectionHeader(title: 'Quick Actions'),
                const SizedBox(height: 12),
                _buildQuickActions(context),

                const SizedBox(height: 20),

                // ─── Today's Shift ────────────────────────
                if (_nextShift != null) ...[
                  const SectionHeader(title: 'Your Shift'),
                  const SizedBox(height: 12),
                  _buildShiftCard(),
                  const SizedBox(height: 20),
                ],

                // ─── Who's out today ──────────────────────
                if (_whosOutLeave.isNotEmpty || _whosOutRemote.isNotEmpty) ...[
                  const SectionHeader(title: "Who's out today"),
                  const SizedBox(height: 12),
                  WhosOutCard(onLeave: _whosOutLeave, remote: _whosOutRemote),
                  const SizedBox(height: 20),
                ],

                // ─── Date + WiFi status ───────────────────
                GlassCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Icon(Icons.calendar_today,
                        size: 16, color: primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary),
                      ),
                    ),
                    Icon(Icons.wifi_rounded,
                        size: 15,
                        color: _noNetworksConfig
                            ? AppColors.gray300
                            : AppColors.success500),
                    const SizedBox(width: 4),
                    Text(
                      _noNetworksConfig
                          ? 'Auto check-in off'
                          : 'Auto check-in on',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.gray500),
                    ),
                  ]),
                ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Banner Widgets ────────────────────────────────────

  void _dismissFlash() =>
      setState(() { _breakWelcomeBack = null; _lateArrivalFlash = null; });

  Future<void> _cancelLateNotice() async {
    final id = _lateNotice?['id'] as String?;
    if (id == null) return;
    try {
      await api.cancelLateNotice(id);
      if (!mounted) return;
      setState(() => _lateNotice = null);
      _showSnack('Late notice cancelled');
    } catch (e) {
      _showSnack(ApiFailure.fromError(e).userMessage, isError: true);
    }
  }

  // ─── Break alert banners from today-status ─────────────────
  //
  // Priority (highest → lowest): overdue+offWifi > overdue+onWifi > active > imminent
  // Only ONE banner shown at a time. All times computed live from UTC timestamps
  // ── Deferred break reminder helpers ───────────────────
  static const _kDeferredBreaks = 'attenda_deferred_breaks';

  Future<void> _saveDeferredReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDeferredBreaks, jsonEncode(_deferredReminders));
    } catch (_) {}
  }

  Future<void> _loadDeferredReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kDeferredBreaks);
      if (raw == null || !mounted) return;
      final list = jsonDecode(raw) as List;
      setState(() => _deferredReminders = list.cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  void _checkDeferredReminders() {
    if (_deferredReminders.isEmpty) return;
    final now = _now;
    final fired = _deferredReminders.where((r) {
      final t = DateTime.tryParse(r['remindAt'] as String? ?? '');
      return t != null && now.isAfter(t);
    }).toList();
    if (fired.isEmpty) return;
    final first = fired.first;
    setState(() {
      _deferredReminders = _deferredReminders.where((r) => r != first).toList();
      _pendingReminderName = first['name'] as String?;
      _pendingReminderDeduct = first['deductIfSkipped'] as bool? ?? true;
    });
    _saveDeferredReminders();
  }

  Future<void> _takeBreakLater(Map<String, dynamic> b, String breakId) async {
    final reminderMins = (b['reminder_after_mins'] as num?)?.toInt() ?? 30;
    final deductIfSkipped = b['deduct_if_skipped'] as bool? ?? true;
    setState(() => _actionLoading = true);
    try {
      await api.endBreak(wifiConnected: !_wifi.heartbeatLost);
      final remindAt = _now.add(Duration(minutes: reminderMins));
      final reminder = {
        'id': breakId,
        'name': b['name'] as String? ?? 'Break',
        'remindAt': remindAt.toIso8601String(),
        'deductIfSkipped': deductIfSkipped,
      };
      if (mounted) {
        setState(() {
          _deferredReminders = [
            ..._deferredReminders.where((r) => r['id'] != breakId),
            reminder,
          ];
          _acknowledgedAutoBreaks.add(breakId);
        });
      }
      await _saveDeferredReminders();
      _showSnack(
          'Reminder set — you\'ll be notified in ${reminderMins}m to take ${b['name'] ?? 'your break'}');
      await _load(silent: true);
    } catch (e) {
      _showSnack(ApiFailure.fromError(e).userMessage, isError: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  // + _now so the 1-second _updateElapsed setState() drives mm:ss ticking.
  List<Widget> _breakAlertBanners() {
    final breaks = (_todayStatus?['shift']?['breaks'] as List?)
            ?.cast<Map<String, dynamic>>() ?? [];
    final offWifi = _wifi.heartbeatLost;

    // "overdue" from the backend covers two very different situations:
    //   A) Window is still open but employee hasn't started the break yet
    //      (_now < break_end_utc) — they're busy, gentle nudge
    //   B) Window has passed AND employee is still on break
    //      (_now >= break_end_utc) — they're late returning, urgent
    // We distinguish them locally so each gets the right banner.
    Map<String, dynamic>? lateReturningOffWifi;   // B + off WiFi
    Map<String, dynamic>? lateReturningOnWifi;    // B + on WiFi
    Map<String, dynamic>? windowOpenNotStarted;   // A (regardless of WiFi)
    Map<String, dynamic>? activeBreak;
    Map<String, dynamic>? imminentBreak;

    for (final b in breaks) {
      final state    = b['break_state'] as String? ?? 'upcoming';
      final breakEnd = _parseLocal(b['break_end_utc']);

      if (state == 'overdue') {
        final windowStillOpen = breakEnd != null && _now.isBefore(breakEnd);
        if (windowStillOpen) {
          windowOpenNotStarted ??= b;
        } else if (offWifi) {
          final prev = lateReturningOffWifi;
          if (prev == null || _liveOverdueSecs(b) > _liveOverdueSecs(prev)) {
            lateReturningOffWifi = b;
          }
        } else {
          lateReturningOnWifi ??= b;
        }
      } else if (state == 'active') {
        activeBreak ??= b;
      } else if (state == 'imminent') {
        imminentBreak ??= b;
      }
    }

    if (_pendingReminderName != null) {
      return [
        DeferredReminderBanner(
          name: _pendingReminderName ?? 'your break',
          deduct: _pendingReminderDeduct,
          onTakeNow: _actionLoading ? null : _showBreakTypeSheet,
          onDismiss: () => setState(() => _pendingReminderName = null),
        )
      ];
    }
    if (lateReturningOffWifi != null) {
      final end = _parseLocal(lateReturningOffWifi['break_end_utc']);
      return [
        OverdueOffWifiBanner(
          name: lateReturningOffWifi['name'] as String? ?? 'Break',
          overdueLabel: end != null ? _countup(end) : '—',
        )
      ];
    }
    if (lateReturningOnWifi != null) {
      return [
        OverdueOnWifiBanner(
            name: lateReturningOnWifi['name'] as String? ?? 'Break')
      ];
    }
    if (activeBreak != null) return [_activeBreakBanner(activeBreak)];
    if (windowOpenNotStarted != null) {
      final end = _parseLocal(windowOpenNotStarted['break_end_utc']);
      return [
        WindowOpenBanner(
          name: windowOpenNotStarted['name'] as String? ?? 'Break',
          remaining: end != null ? _countdown(end) : '—',
        )
      ];
    }
    if (imminentBreak != null) {
      final start = _parseLocal(imminentBreak['break_start_utc']);
      return [
        ImminentBreakBanner(
          name: imminentBreak['name'] as String? ?? 'Break',
          countdown: start != null ? _countdown(start) : '—',
        )
      ];
    }
    return [];
  }

  int _liveOverdueSecs(Map<String, dynamic> b) {
    final end = _parseLocal(b['break_end_utc']);
    if (end == null) return (b['overdue_minutes'] as num?)?.toInt() ?? 0;
    return _now.difference(end).inSeconds.clamp(0, 999999);
  }

  // Live mm:ss countdown string until a future DateTime.
  String _countdown(DateTime target) {
    final diff = target.difference(_now);
    if (diff.isNegative) return '00:00';
    final m = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // Live mm:ss count-up string since a past DateTime.
  String _countup(DateTime since) {
    final diff = _now.difference(since);
    if (diff.isNegative) return '00:00';
    final m = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // Dispatches an active policy break to the right banner: an auto-started
  // break the employee hasn't acknowledged yet gets the actionable banner,
  // everything else gets the plain countdown banner.
  Widget _activeBreakBanner(Map<String, dynamic> b) {
    final linked = b['linked_break_record'] as Map<String, dynamic>?;
    final autoStarted = linked?['auto_started'] as bool? ?? false;
    final breakId = linked?['id'] as String?;
    if (autoStarted && breakId != null && !_acknowledgedAutoBreaks.contains(breakId)) {
      return AutoStartedBreakBanner(
        name: b['name'] as String? ?? 'Break',
        reminderMins: (b['reminder_after_mins'] as num?)?.toInt() ?? 30,
        deductIfSkipped: b['deduct_if_skipped'] as bool? ?? true,
        onAcknowledge: () =>
            setState(() => _acknowledgedAutoBreaks.add(breakId)),
        onTakeLater: _actionLoading ? null : () => _takeBreakLater(b, breakId),
      );
    }

    final name = b['name'] as String? ?? 'Break';
    final kind = b['break_kind'] as String? ?? 'fixed';
    DateTime? breakEnd;

    if (kind == 'fixed') {
      breakEnd = _parseLocal(b['break_end_utc']);
    } else {
      // Flexible: end = actual break_start + allowed break_minutes.
      // Use linked_break_record.break_start so the timer reflects when the
      // employee actually started the break, not the scheduled window.
      final linked  = b['linked_break_record'] as Map<String, dynamic>?;
      final startStr = linked?['break_start'] as String?;
      final mins    = (b['break_minutes'] as num?)?.toInt();
      if (startStr != null && mins != null) {
        breakEnd = DateTime.parse(startStr).toLocal().add(Duration(minutes: mins));
      } else {
        breakEnd = _parseLocal(b['break_end_utc']);
      }
    }

    return ActiveBreakBanner(
      name: name,
      remaining: breakEnd != null ? _countdown(breakEnd) : '—',
    );
  }

  // ─── Attendance Request Dialog (Late Arrival / Leave / Early Departure) ───

  Future<void> _showAttendanceRequestDialog() async {
    String requestType = 'late_arrival';
    String leaveType = 'annual';
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now().replacing(
      hour: (TimeOfDay.now().hour + 1).clamp(0, 23),
      minute: 0,
    );
    TimeOfDay selectedEndTime = TimeOfDay.now().replacing(
      hour: (TimeOfDay.now().hour + 2).clamp(0, 23),
      minute: 0,
    );
    final reasonCtrl = TextEditingController();

    const typeOptions = [
      {'value': 'late_arrival', 'label': 'Late Arrival'},
      {'value': 'leave', 'label': 'Day Leave'},
      {'value': 'mid_shift_leave', 'label': 'Mid-Shift Leave'},
      {'value': 'early_departure', 'label': 'Early Departure'},
    ];
    const leaveOptions = [
      {'value': 'annual', 'label': 'Annual'},
      {'value': 'sick', 'label': 'Sick'},
      {'value': 'unpaid', 'label': 'Unpaid'},
      {'value': 'other', 'label': 'Other'},
    ];

    String fmtDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    String fmtDateDisplay(DateTime d) =>
        DateFormat('EEE, d MMM yyyy').format(d);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Row(children: [
            Icon(Icons.assignment_outlined,
                color: Theme.of(context).colorScheme.primary, size: 22),
            const SizedBox(width: 8),
            const Flexible(
                child: Text('Report / Request', style: AppTextStyles.title)),
          ]),
          content: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Request type chips ──────────────────────
              const Text('Request Type', style: AppTextStyles.captionStrong),
              const SizedBox(height: 8),
              Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: typeOptions.map((t) {
                    final sel = requestType == t['value'];
                    return GestureDetector(
                      onTap: () => setDlg(() => requestType = t['value']!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: sel
                              ? Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.10)
                              : AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(AppRadius.control),
                          border: Border.all(
                              color: sel
                                  ? Theme.of(context).colorScheme.primary
                                  : AppColors.border),
                        ),
                        child: Text(t['label']!,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    sel ? FontWeight.w700 : FontWeight.w500,
                                color: sel
                                    ? Theme.of(context).colorScheme.primary
                                    : AppColors.gray600)),
                      ),
                    );
                  }).toList()),
              const SizedBox(height: 16),

              // ── Date picker ──────────────────────────────
              const Text('Date', style: AppTextStyles.captionStrong),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 7)),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (picked != null) setDlg(() => selectedDate = picked);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_today,
                        size: 15, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(fmtDateDisplay(selectedDate),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const Spacer(),
                    const Text('Change', style: AppTextStyles.caption),
                  ]),
                ),
              ),
              const SizedBox(height: 16),

              // ── Leave sub-type (only for 'leave') ────────
              if (requestType == 'leave' || requestType == 'mid_shift_leave')
                ...(() {
                  return [
                    const Text('Leave Type', style: AppTextStyles.captionStrong),
                    const SizedBox(height: 6),
                    Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: leaveOptions.map((l) {
                          final sel = leaveType == l['value'];
                          return GestureDetector(
                            onTap: () => setDlg(() => leaveType = l['value']!),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: sel
                                    ? AppColors.teal100.withValues(alpha: 0.10)
                                    : AppColors.surface,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.control),
                                border: Border.all(
                                    color: sel
                                        ? AppColors.teal100
                                        : AppColors.border),
                              ),
                              child: Text(l['label']!,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: sel
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: sel
                                          ? AppColors.teal700
                                          : AppColors.gray600)),
                            ),
                          );
                        }).toList()),
                    const SizedBox(height: 16),
                  ];
                })(),

              // ── Expected time (late/early only) ──────────
              if (requestType != 'leave' && requestType != 'mid_shift_leave')
                ...(() {
                  final label = requestType == 'late_arrival'
                      ? 'Expected Arrival Time'
                      : 'Expected Departure Time';
                  return [
                    Text(label, style: AppTextStyles.captionStrong),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: selectedTime,
                        );
                        if (picked != null) setDlg(() => selectedTime = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 11),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(AppRadius.control),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(children: [
                          Icon(Icons.access_time,
                              size: 15, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(selectedTime.format(ctx),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                          const Spacer(),
                          const Text('Tap to change',
                              style: AppTextStyles.caption),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ];
                })(),

              if (requestType == 'mid_shift_leave') ...[
                const Text('Leave Window', style: AppTextStyles.captionStrong),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: TimePickerTile(
                      label: 'Start',
                      value: selectedTime,
                      onPicked: (picked) => setDlg(() => selectedTime = picked),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TimePickerTile(
                      label: 'End',
                      value: selectedEndTime,
                      onPicked: (picked) => setDlg(() => selectedEndTime = picked),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
              ],

              // ── Reason ───────────────────────────────────
              const Text('Reason', style: AppTextStyles.captionStrong),
              const SizedBox(height: 6),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                maxLength: 200,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Briefly describe the reason…',
                ),
              ),
            ],
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.gray500)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control)),
              ),
              onPressed: () async {
                final reason = reasonCtrl.text.trim();
                if (reason.length < 5) {
                  _showSnack('Please enter a reason (5+ chars)');
                  return;
                }
                try {
                  final hh = selectedTime.hour.toString().padLeft(2, '0');
                  final mm = selectedTime.minute.toString().padLeft(2, '0');
                  final eh = selectedEndTime.hour.toString().padLeft(2, '0');
                  final em = selectedEndTime.minute.toString().padLeft(2, '0');
                  if (requestType == 'mid_shift_leave') {
                    final startMins = selectedTime.hour * 60 + selectedTime.minute;
                    final endMins = selectedEndTime.hour * 60 + selectedEndTime.minute;
                    if (endMins <= startMins) {
                      _showSnack('End time must be after start time');
                      return;
                    }
                  }
                  await api.submitAttendanceRequest(
                    type: requestType == 'mid_shift_leave' ? 'leave' : requestType,
                    date: fmtDate(selectedDate),
                    reason: reason,
                    expectedTime: '$hh:$mm',
                    leaveType: leaveType,
                    leaveStartTime: requestType == 'mid_shift_leave' ? '$hh:$mm' : null,
                    leaveEndTime: requestType == 'mid_shift_leave' ? '$eh:$em' : null,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  _showSnack('Request submitted ✅');
                  _load(silent: true);
                } catch (e) {
                  _showSnack(ApiFailure.fromError(e).userMessage,
                      isError: true);
                }
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    reasonCtrl.dispose();
  }

  /// Alias kept for the "Not checked in" card button.
  Future<void> _showLateNoticeDialog() => _showAttendanceRequestDialog();

  // ─── Numeric parsing helpers ───────────────────────────
  // The backend sometimes serializes numeric fields as strings
  // (e.g. "8.5", "30"). Cast defensively instead of `as num?`.
  static double? _asDouble(dynamic v) => v == null
      ? null
      : v is num
          ? v.toDouble()
          : double.tryParse(v.toString());
  static int? _asInt(dynamic v) => v == null
      ? null
      : v is num
          ? v.toInt()
          : int.tryParse(v.toString());

  // ─── Break Info ────────────────────────────────────────

  // A local-time DateTime for today at "HH:mm" (used for wall-clock breaks).
  DateTime _todayAt(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, h, m);
  }

  Map<String, dynamic>? _computeBreakInfo() {
    final checkInStr = _todayRecord?['check_in_at'] as String?;
    if (checkInStr == null) return null;
    final checkIn = DateTime.parse(checkInStr).toLocal();

    // Check for active break in break_records
    final breakRecords = (_todayRecord?['break_records'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    Map<String, dynamic>? activeBreak;
    for (final b in breakRecords) {
      if (b['break_end'] == null) {
        activeBreak = b;
        break;
      }
    }
    if (activeBreak != null) {
      final startedAt = DateTime.parse(activeBreak['break_start'] as String);
      final elapsed = DateTime.now().difference(startedAt);
      final m = elapsed.inMinutes;
      final s = elapsed.inSeconds % 60;
      final breakType = activeBreak['break_type'] as String? ?? 'break';
      final label = _formatBreakType(breakType);
      return {
        'icon': Icons.free_breakfast,
        'color': AppColors.teal100,
        'text': '$label — ${m}m ${s}s elapsed',
      };
    }

    // Check for upcoming breaks from shift schedule
    final shiftBreaks = (_nextShift?['shift']?['breaks'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    for (final sb in shiftBreaks) {
      final name = sb['name'] as String? ?? 'Break';
      final startTime = sb['break_start_time'] as String?;
      final endTime = sb['break_end_time'] as String?;

      // Prefer the wall-clock window (this is what the backend auto-starts on);
      // fall back to the relative `after_minutes` offset from check-in.
      late final DateTime breakStart;
      late final DateTime breakEnd;
      if (startTime != null &&
          startTime.contains(':') &&
          endTime != null &&
          endTime.contains(':')) {
        breakStart = _todayAt(startTime);
        breakEnd = _todayAt(endTime);
      } else {
        final afterMins = _asInt(sb['after_minutes']) ?? 0;
        final breakMins = _asInt(sb['break_minutes']) ?? 15;
        breakStart = checkIn.add(Duration(minutes: afterMins));
        breakEnd = breakStart.add(Duration(minutes: breakMins));
      }

      // Already past this break? Skip.
      if (DateTime.now().isAfter(breakEnd)) continue;

      final untilStart = breakStart.difference(DateTime.now());
      if (untilStart.isNegative) {
        // Should be on break but no active record yet
        return {
          'icon': Icons.free_breakfast,
          'color': AppColors.warning500,
          'text': '$name started — take your break',
        };
      }
      if (untilStart.inMinutes <= 10) {
        return {
          'icon': Icons.schedule,
        'color': Theme.of(context).colorScheme.primary,
          'text':
              '$name in ${untilStart.inMinutes}m ${untilStart.inSeconds % 60}s',
        };
      }
      // More than 10 min away — show next break time
      return {
        'icon': Icons.schedule,
        'color': AppColors.gray500,
        'text': '$name at ${DateFormat('hh:mm a').format(breakStart)}',
      };
    }
    return null;
  }

  // ─── Status Card ───────────────────────────────────────

  Widget _buildStatusCard() {
    // When the employee is actively on a break and loses WiFi, leaving the
    // office is expected — don't replace the status card with the disconnect
    // card. The break banner handles the "overdue + off WiFi" case instead.
    if (_autoCheckoutRisk && !_isOnBreak) {
      return DisconnectCard(
        ssid: _disconnectSsid,
        countdown: _disconnectCountdown,
        expired: _graceExpired,
      );
    }

    Color cardTint;
    IconData cardIcon;
    String statusTitle;
    String statusSub;
    Color iconColor;

    if (_vpnDetected) {
      cardTint = AppColors.warning500;
      cardIcon = Icons.vpn_lock;
      iconColor = AppColors.warning500;
      statusTitle = 'VPN Active';
      statusSub = 'Scan QR code to check in';
    } else if (_isRemote) {
      cardTint = AppColors.purple500;
      cardIcon = Icons.home_rounded;
      iconColor = AppColors.purple500;
      statusTitle = 'Working Remotely 🏠';
      final sessionStatus = _remoteSession?['status'] as String? ?? 'pending';
      statusSub = sessionStatus == 'approved'
          ? 'Approved — AI will check in with you via WhatsApp'
          : sessionStatus == 'rejected'
              ? 'Rejected by manager — please contact HR'
              : 'Pending manager approval';
    } else if (_checkedOut) {
      // ── CheckedOut summary card ────────────────────────────
      final checkInStr = _todayRecord?['check_in_at'] as String?;
      final checkOutStr = _todayRecord?['check_out_at'] as String?;
      final hoursWorked = _asDouble(_todayRecord?['hours_worked']);
      final netHours = _asDouble(_todayRecord?['net_hours_worked']);
      final breakMins = _totalBreakMinutes(_todayRecord);
      final overtimeHours = _asDouble(_todayRecord?['overtime_hours']) ?? 0;
      final extraOfficeMins = _asInt(_todayRecord?['extra_office_minutes']) ?? 0;
      final wasAutoOut = (_todayRecord?['auto_checked_out'] as bool?) ?? false;
      final shift = (_todayStatus?['shift'] as Map?)?.cast<String, dynamic>();
      final canRequestOvertime = extraOfficeMins > 0 &&
          shift?['overtime_enabled'] == true &&
          shift?['overtime_requires_approval'] == true &&
          _todayRecord?['id'] != null;

      final checkInFmt = checkInStr != null
          ? DateFormat('hh:mm a').format(DateTime.parse(checkInStr).toLocal())
          : '--:--';
      final checkOutFmt = checkOutStr != null
          ? DateFormat('hh:mm a').format(DateTime.parse(checkOutStr).toLocal())
          : '--:--';

      String hoursLabel = '';
      if (netHours != null) {
        hoursLabel = '${netHours.toStringAsFixed(1)}h net';
      } else if (hoursWorked != null) {
        hoursLabel = '${hoursWorked.toStringAsFixed(1)}h worked';
      }

      return CheckedOutCard(
        checkInFmt: checkInFmt,
        checkOutFmt: checkOutFmt,
        hoursLabel: hoursLabel,
        breakMins: breakMins,
        overtimeHours: overtimeHours,
        extraOfficeMins: extraOfficeMins,
        wasAutoOut: wasAutoOut,
        canRequestOvertime: canRequestOvertime,
        actionLoading: _actionLoading,
        onRequestOvertime: () => _requestOvertime(extraOfficeMins),
      );
    } else if (_checkedIn) {
      // ── CheckedIn hero: ring layout ───────────────────────
      final lateMins = _asInt(_todayRecord?['late_minutes']) ?? 0;
      final isLate = _status == 'late' || lateMins > 0;
      final hasNotice = _todayRecord?['late_notice_id'] != null;
      final ringTint = isLate ? AppColors.warning500 : AppColors.success500;

      final shiftStart = _getShiftStartMins();
      final shiftEnd = _getShiftEndMins();
      // Server-corrected _now keeps the progress ring in sync with the elapsed
      // timer and break countdowns (which all use _now) under device clock skew.
      final nowMins = _now.hour * 60 + _now.minute;
      final shiftPct =
          ((nowMins - shiftStart) / (shiftEnd - shiftStart)).clamp(0.0, 1.0);

      final checkInStr = _todayRecord?['check_in_at'] as String?;
      final checkInTime = checkInStr != null
          ? DateFormat('hh:mm a').format(DateTime.parse(checkInStr).toLocal())
          : '--:--';
      final checkInType = _todayRecord?['check_in_type'] as String?;

      return CheckedInCard(
        ringTint: ringTint,
        isLate: isLate,
        shiftPct: shiftPct,
        elapsedDisplay: _elapsedDisplay,
        checkInTime: checkInTime,
        hasCheckIn: checkInStr != null,
        checkInTypeLabel:
            checkInType != null ? _formatCheckInType(checkInType) : null,
        breakInfo: _computeBreakInfo(),
        lateMins: lateMins,
        hasNotice: hasNotice,
        actionLoading: _actionLoading,
        onCheckOut: _confirmCheckOut,
      );
    } else if (_status == 'leave') {
      cardTint = Theme.of(context).colorScheme.primary;
      cardIcon = Icons.beach_access;
      iconColor = Theme.of(context).colorScheme.primary;
      statusTitle = 'On Leave 📅';
      statusSub = 'Approved leave';
    } else if (_status == 'half_leave') {
      final period = (_todayLeave?['half_day_period'] as String?) ?? '';
      final expected = period == 'morning' ? 'Afternoon' : 'Morning';
      cardTint = AppColors.teal700;
      cardIcon = Icons.calendar_today;
      iconColor = AppColors.teal100;
      statusTitle = 'Half-Day Leave';
      statusSub = period.isNotEmpty
          ? '$expected half — you may still check in'
          : 'Approved half-day leave';
    } else {
      cardTint = Colors.white;
      cardIcon = Icons.radio_button_unchecked;
      iconColor = AppColors.gray400;
      statusTitle = 'Not Checked In';
      statusSub = _noNetworksConfig
          ? 'Scan QR code to check in — WiFi auto-detection not set up'
          : 'Connect to office WiFi for auto check-in, or scan QR code';
    }

    return StatusInfoCard(
      tint: cardTint,
      icon: cardIcon,
      iconColor: iconColor,
      title: statusTitle,
      subtitle: statusSub,
      showCheckInActions:
          !_checkedIn && !_checkedOut && !_isRemote && _status != 'leave',
      showReportLate:
          _lateNotice == null || _lateNotice!['status'] == 'cancelled',
      onReportLate: _showLateNoticeDialog,
      remoteDetailId: _isRemote &&
              _remoteSession != null &&
              _remoteSession!['status'] == 'approved'
          ? _remoteSession!['id']?.toString()
          : null,
    );
  }

  Future<void> _confirmCheckOut() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Check Out?',
      message: 'Are you sure you want to check out?',
      confirmLabel: 'Check Out',
      isDanger: true,
    );
    if (confirmed == true) {
      setState(() => _actionLoading = true);
      try {
        await api.checkOut();
        // Notifies both main isolate and background service
        await WifiAttendanceService().onManualCheckOut();
        await _load();
        _showSnack('Checked out ✅');
      } catch (e) {
        _showSnack(ApiFailure.fromError(e).userMessage, isError: true);
      } finally {
        if (mounted) setState(() => _actionLoading = false);
      }
    }
  }

  Future<void> _requestOvertime(int extraOfficeMins) async {
    setState(() => _actionLoading = true);
    try {
      await api.requestOvertime(
        attendanceId: _todayRecord!['id'] as String,
        reason: 'Worked ${extraOfficeMins}m after shift end',
      );
      _showSnack('Overtime request sent');
    } catch (e) {
      _showSnack(ApiFailure.fromError(e).userMessage, isError: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  String _formatCheckInType(String type) {
    switch (type) {
      case 'auto_ip':
        return 'Auto (WiFi)';
      case 'qr':
        return 'QR Code';
      case 'remote':
        return 'Remote';
      default:
        return 'Manual';
    }
  }

  String _formatBreakType(String type) {
    switch (type) {
      case 'lunch':
        return 'Lunch Break';
      case 'prayer':
        return 'Prayer Break';
      case 'short':
        return 'Short Break';
      case 'away':
        return 'Away';
      default:
        return 'Break';
    }
  }

  // ─── Break request (ad-hoc) ────────────────────────────

  Future<void> _showBreakTypeSheet() async {
    final policyBreaks = (_todayStatus?['shift']?['breaks'] as List?)
            ?.whereType<Map>()
            .map((b) => b.cast<String, dynamic>())
            .toList() ??
        const <Map<String, dynamic>>[];
    // Build the break options list.
    // Policy breaks retain their break_state so we can show timing badges.
    // "done" (missed window) breaks are still included — employee can take
    // them late; the backend accepts shift_break_id at any time.
    final List<Map<String, dynamic>> types = policyBreaks.isNotEmpty
        ? policyBreaks
            .where((b) => b['break_state'] != 'active') // hide if already active
            .map<Map<String, dynamic>>((b) {
              final state     = b['break_state'] as String? ?? 'upcoming';
              final breakEnd  = _parseLocal(b['break_end_utc']);
              final minsLeft  = breakEnd?.difference(_now).inMinutes;

              // State badge shown as suffix in the subtitle
              String badge = '';
              if (state == 'overdue' && breakEnd != null && _now.isBefore(breakEnd)) {
                badge = ' · window open';
              } else if (state == 'done' || (state == 'overdue' && (breakEnd == null || !_now.isBefore(breakEnd)))) {
                badge = ' · take late';
              } else if (state == 'imminent' && minsLeft != null) {
                badge = ' · in ${minsLeft}m';
              }

              return {
                'id': b['id'],
                'type': b['name'] ?? 'break',
                'label': b['name'] ?? 'Break',
                'subtitle':
                    "${b['break_minutes'] ?? 0}m${b['allowed_count_per_shift'] != null ? " × ${b['allowed_count_per_shift']}" : ''}$badge",
                'icon': Icons.coffee,
                'state': state,
              };
            })
            .toList()
        : [
            {'type': 'short', 'label': 'Quick Break', 'icon': Icons.coffee},
            {'type': 'lunch', 'label': 'Lunch', 'icon': Icons.lunch_dining},
            {'type': 'prayer', 'label': 'Prayer', 'icon': Icons.self_improvement},
            {'type': 'manual', 'label': 'Other', 'icon': Icons.more_horiz},
          ];

    final chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.gray300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Start a Break', style: AppTextStyles.title),
          const SizedBox(height: 8),
          ...types.map((t) {
                final state = t['state'] as String? ?? '';
                final isLate = state == 'done' ||
                    (state == 'overdue' &&
                        !(t['subtitle'] as String? ?? '').contains('window open'));
                final isNow  = (t['subtitle'] as String? ?? '').contains('window open');
                final subtitleColor = isLate
                    ? AppColors.warning800
                    : isNow
                        ? AppColors.teal700
                        : AppColors.gray500;
                return ListTile(
                  leading: Icon(t['icon'] as IconData,
                      color: isLate ? AppColors.warning500 : AppColors.teal100,
                      size: 22),
                  title: Text(t['label'] as String,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700)),
                  subtitle: t['subtitle'] != null
                      ? Text(t['subtitle'] as String,
                          style: TextStyle(color: subtitleColor, fontSize: 11))
                      : null,
                  onTap: () => Navigator.pop(context, t),
                );
              }),
          const SizedBox(height: 8),
        ]),
      ),
    );

    if (chosen == null || !mounted) return;
    setState(() => _actionLoading = true);
    try {
      await api.startBreak(
        breakType: chosen['type'] as String? ?? 'manual',
        shiftBreakId: chosen['id'] as String?,
      );
      await _load();
      _showSnack('Break started ☕');
    } catch (e) {
      _showSnack(ApiFailure.fromError(e).userMessage, isError: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _endBreak() async {
    setState(() => _actionLoading = true);
    try {
      // wifiConnected = true when the device is still on the office network at
      // the moment the employee taps End Break. heartbeatLost means the device
      // has left the office WiFi, so the inverse gives us the connected state.
      final wifiConnected = !_wifi.heartbeatLost;
      await api.endBreak(wifiConnected: wifiConnected);
      await _load();
      _showSnack('Break ended — welcome back!');
    } catch (e) {
      _showSnack(ApiFailure.fromError(e).userMessage, isError: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  // ─── Shift time helpers ────────────────────────────────

  int _getShiftStartMins() {
    final startTime = (_nextShift?['shift'] as Map?)?['start_time'] as String?;
    if (startTime != null && startTime.contains(':')) {
      final parts = startTime.split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]) ?? 9;
        final m = int.tryParse(parts[1]) ?? 0;
        return h * 60 + m;
      }
    }
    return 9 * 60; // default 09:00
  }

  int _getShiftEndMins() {
    final endTime = (_nextShift?['shift'] as Map?)?['end_time'] as String?;
    if (endTime != null && endTime.contains(':')) {
      final parts = endTime.split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]) ?? 17;
        final m = int.tryParse(parts[1]) ?? 30;
        return h * 60 + m;
      }
    }
    return 17 * 60 + 30; // default 17:30
  }

  // ─── Quick Actions ─────────────────────────────────────

  Widget _buildQuickActions(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final actions = [
      QuickAction(
        icon: Icons.beach_access_outlined,
        label: 'Report /\nRequest',
        color: Theme.of(context).colorScheme.primary,
        onTap: _showAttendanceRequestDialog,
      ),
      if (auth.hasFeature('remote_work') && !_checkedIn && !_checkedOut && !_isRemote)
        QuickAction(
          icon: Icons.home_outlined,
          label: 'Work\nRemote',
          color: AppColors.purple500,
          onTap: () => context.push('/home/remote'),
        ),
      if (auth.hasFeature('shifts'))
        QuickAction(
          icon: Icons.calendar_today_outlined,
          label: 'My\nSchedule',
          color: AppColors.teal100,
          onTap: () => context.go('/schedule'),
        ),
      if (auth.hasFeature('payroll'))
        QuickAction(
          icon: Icons.receipt_long_outlined,
          label: 'My\nPayslips',
          color: AppColors.warning500,
          onTap: () => context.go('/profile'),
        ),
    ];
    return QuickActionsRow(actions: actions);
  }

  // ─── Shift Card ────────────────────────────────────────

  Widget _buildShiftCard() {
    final shift = (_nextShift!['shift'] as Map?)?.cast<String, dynamic>();
    return ShiftCard(
      shiftName: shift?['name'] as String? ?? 'Shift',
      startTime: shift?['start_time'] as String? ?? '--:--',
      endTime: shift?['end_time'] as String? ?? '--:--',
      shiftColor: parseHexColor(shift?['color'] as String?,
          fallback: const Color(0xFFF15153)),
      dateStr: _nextShift!['date'] as String?,
    );
  }
}
