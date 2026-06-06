import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/wifi_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';
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
  bool _loading = true;
  bool _actionLoading = false;
  Timer? _timer;
  Timer? _refreshTimer;
  Timer? _flashTimer;
  Duration _elapsed = Duration.zero;
  int _unreadNotifs = 0;

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
                'You checked in ${_formatMinutesHours(lateMins)} late today',
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
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: isError ? AppColors.danger500 : AppColors.bgDark3,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
        if (_todayStatus == null) _todayStatus = cachedStatus;
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
      ]);

      final records    = results[0] as List;
      final shifts     = results[1] as List;
      final leaveInfo  = results[2] as Map<String, dynamic>;
      final todayStatus = results[3] as Map<String, dynamic>;

      // Never overwrite good in-memory data with an empty offline response.
      if (todayStatus.isEmpty) {
        if (_todayStatus == null) await _loadFromCache();
        if (mounted) setState(() => _loading = false);
        return;
      }

      final todayRecord =
          records.isNotEmpty ? records.first as Map<String, dynamic> : null;
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
          if (todayStatus['attendance'] is Map)
            ...(todayStatus['attendance'] as Map).cast<String, dynamic>(),
        };
        setState(() {
          _todayRecord  = mergedRecord.isNotEmpty ? mergedRecord : _todayRecord;
          _nextShift    = shifts.isNotEmpty ? shifts.first as Map<String, dynamic> : null;
          _remoteSession = remoteSession;
          _todayLeave   = leaveInfo['leave'] as Map<String, dynamic>?;
          _lateNotice   = leaveInfo['late_notice'] as Map<String, dynamic>?;
          _todayStatus  = todayStatus;
          _loading      = false;
        });
        _updateElapsed();
        // Persist for offline use
        _persistCache(todayStatus, mergedRecord.isNotEmpty ? mergedRecord : null);
      }
    } catch (_) {
      // API totally failed — fall back to cache so banners still work offline.
      if (_todayStatus == null) await _loadFromCache();
      if (mounted) setState(() => _loading = false);
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
      setState(
          () => _elapsed = DateTime.now().difference(DateTime.parse(checkIn)));
    } else if (_autoCheckoutRisk) {
      setState(() {}); // keep the disconnect countdown ticking
    }
    // Once the grace window has elapsed the server is closing us out; poll so
    // the UI flips to the checked-out card promptly (instead of waiting up to
    // the 30s refresh).
    if (_autoCheckoutRisk && _graceExpired) _pollForAutoCheckout();
    _checkDeferredReminders();
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

  String _formatMinutesHours(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  int get _livePreCheckinLateMins {
    final shift = (_todayStatus?['shift'] as Map?)?.cast<String, dynamic>();
    final start = _parseLocal(shift?['shift_start_utc']);
    if (start == null || _checkedIn || _checkedOut) return 0;
    final minutes = DateTime.now().difference(start).inMinutes;
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

  // The disconnect/grace UI applies to anyone who was being WiFi-tracked
  // (heartbeatLost is only set when we were). Gated by _checkedIn so it clears
  // the moment the server auto-checks-out (status flips to 'out').
  bool get _autoCheckoutRisk => _heartbeatLost && _checkedIn;
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
    return 'Welcome back — you were ${_formatMinutesHours(maxLate)} late from $breakName';
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary600,
          backgroundColor: AppColors.bgDark3,
          onRefresh: () async {
            await _load(silent: true);
            await WifiAttendanceService().checkAndReport();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
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
                                style: TextStyle(
                                    fontSize: 14,
                                    color:
                                        Colors.white.withValues(alpha: 0.55))),
                            Text(user.name.split(' ').first,
                                style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                          ]),
                      Row(children: [
                        // Notification bell
                        GestureDetector(
                          onTap: () async {
                            await context.push('/home/notifications');
                            _load(silent: true);
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.2)),
                                ),
                                child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Icon(Icons.notifications_outlined,
                                          size: 20,
                                          color: Colors.white
                                              .withValues(alpha: 0.8)),
                                      if (_unreadNotifs > 0)
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: Container(
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                                color: AppColors.primary600,
                                                shape: BoxShape.circle),
                                          ),
                                        ),
                                    ]),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        UserAvatar(name: user.name),
                      ]),
                    ]),

                const SizedBox(height: 20),

                // ─── Banners ──────────────────────────────
                AnimatedSize(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (_vpnDetected) _vpnBanner(),
                    if (_noNetworksConfig && !_vpnDetected) _noNetworksBanner(),
                    if (!_loading &&
                        _todayLeave != null &&
                        _status != 'in' &&
                        _status != 'late' &&
                        _status != 'out')
                      _leaveTodayBanner(),
                    if (!_loading &&
                        _lateNotice != null &&
                        _status != 'in' &&
                        _status != 'late' &&
                        _status != 'out')
                      _lateNoticeBanner(),
                    // ── Break alert banners (from today-status) ──
                    if (!_loading && _checkedIn) ..._breakAlertBanners(),
                    // ── Pre-check-in live late counter ───────────
                    if (!_loading && !_checkedIn && !_checkedOut)
                      _preCheckinLateBanner(),
                    // ── Flash: welcome back from break ───────────
                    if (_breakWelcomeBack != null)
                      _flashBanner(_breakWelcomeBack!, AppColors.warning500,
                          Icons.celebration_outlined),
                    // ── Flash: late arrival notice ────────────────
                    if (_lateArrivalFlash != null)
                      _flashBanner(_lateArrivalFlash!, AppColors.warning500,
                          Icons.access_alarm),
                  ]),
                ),

                // ─── Status Card ──────────────────────────
                _loading
                    ? const SkeletonBox(
                        width: double.infinity, height: 160, radius: 28)
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.05),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
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
                  _buildBreakControl(),
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

                // ─── Date + WiFi status ───────────────────
                GlassCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    const Icon(Icons.calendar_today,
                        size: 16, color: AppColors.primary600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white),
                      ),
                    ),
                    Icon(Icons.wifi_rounded,
                        size: 15,
                        color: _noNetworksConfig
                            ? Colors.white.withValues(alpha: 0.3)
                            : AppColors.success500),
                    const SizedBox(width: 4),
                    Text(
                      _noNetworksConfig
                          ? 'Auto check-in off'
                          : 'Auto check-in on',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.45)),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Banner Widgets ────────────────────────────────────

  // Temporary flash banner shown for 5 s after a WiFi event, then fades out.
  Widget _flashBanner(String text, Color tint, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        tint: tint,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(icon, color: tint, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13, color: tint, fontWeight: FontWeight.w600)),
          ),
          GestureDetector(
            onTap: () => setState(() { _breakWelcomeBack = null; _lateArrivalFlash = null; }),
            child: Icon(Icons.close, size: 16, color: tint.withValues(alpha: 0.5)),
          ),
        ]),
      ),
    );
  }

  Widget _vpnBanner() => _glassBanner(
        icon: Icons.vpn_lock,
        text: 'VPN detected — auto check-in is disabled. Use QR scan instead.',
        tint: AppColors.warning500,
        action: TextButton(
          onPressed: () => context.push('/attendance/qr'),
          child: const Text('QR Scan',
              style: TextStyle(
                  color: AppColors.warning500, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _noNetworksBanner() => _glassBanner(
        icon: Icons.wifi_off,
        text:
            "Auto check-in is off — your admin hasn't added any office networks yet.",
        tint: Colors.white,
      );

  Widget _leaveTodayBanner() {
    final leaveType =
        (_todayLeave?['leave_type'] as String? ?? 'leave').replaceAll('_', ' ');
    return _glassBanner(
      icon: Icons.beach_access,
      text: 'You have approved $leaveType today. No check-in required.',
      tint: AppColors.primary600,
    );
  }

  Widget _lateNoticeBanner() {
    final expectedTime = _lateNotice?['expected_time'] as String? ?? '';
    final noticeStatus = _lateNotice?['status'] as String? ?? 'pending';
    final isAcked = noticeStatus == 'acknowledged';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        tint: isAcked ? AppColors.success500 : AppColors.warning500,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(isAcked ? Icons.check_circle_outline : Icons.schedule,
              color: isAcked ? AppColors.success500 : AppColors.warning500,
              size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
            isAcked
                ? 'Late notice acknowledged — expected by $expectedTime'
                : 'Late arrival notice submitted — expected by $expectedTime',
            style: TextStyle(
              fontSize: 13,
              color: isAcked ? AppColors.success500 : AppColors.warning500,
              fontWeight: FontWeight.w500,
            ),
          )),
          GestureDetector(
            onTap: () async {
              final id = _lateNotice?['id'] as String?;
              if (id == null) return;
              try {
                await api.cancelLateNotice(id);
                setState(() => _lateNotice = null);
                _showSnack('Late notice cancelled');
              } catch (_) {
                _showSnack('Could not cancel notice');
              }
            },
            child: Icon(Icons.close,
                size: 16, color: Colors.white.withValues(alpha: 0.4)),
          ),
        ]),
      ),
    );
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
    } catch (_) {
      _showSnack('Could not defer break', isError: true);
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

    if (_pendingReminderName != null) return [_deferredReminderBanner()];
    if (lateReturningOffWifi != null) return [_overdueOffWifiBanner(lateReturningOffWifi)];
    if (lateReturningOnWifi  != null) return [_overdueOnWifiBanner(lateReturningOnWifi)];
    if (activeBreak          != null) return [_activeBreakBanner(activeBreak)];
    if (windowOpenNotStarted != null) return [_windowOpenBanner(windowOpenNotStarted)];
    if (imminentBreak        != null) return [_imminentBreakBanner(imminentBreak)];
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

  Widget _imminentBreakBanner(Map<String, dynamic> b) {
    final name  = b['name'] as String? ?? 'Break';
    final start = _parseLocal(b['break_start_utc']);
    final label = start != null ? _countdown(start) : '—';
    return _glassBanner(
      icon: Icons.timer_outlined,
      text: '$name starts in $label — wrap up',
      tint: AppColors.primary600,
    );
  }

  // Window is open but the employee hasn't tapped Start Break yet.
  // They are still at their desk — do NOT say "return to office".
  Widget _windowOpenBanner(Map<String, dynamic> b) {
    final name = b['name'] as String? ?? 'Break';
    final end  = _parseLocal(b['break_end_utc']);
    final remaining = end != null ? _countdown(end) : '—';
    return _glassBanner(
      icon: Icons.free_breakfast_outlined,
      text: '$name is now — $remaining left in the window',
      tint: AppColors.warning500,
    );
  }

  Widget _activeBreakBanner(Map<String, dynamic> b) {
    final linked = b['linked_break_record'] as Map<String, dynamic>?;
    final autoStarted = linked?['auto_started'] as bool? ?? false;
    final breakId = linked?['id'] as String?;
    if (autoStarted && breakId != null && !_acknowledgedAutoBreaks.contains(breakId)) {
      return _autoStartedBreakBanner(b, breakId);
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

    final label = breakEnd != null ? _countdown(breakEnd) : '—';
    return _glassBanner(
      icon: Icons.free_breakfast,
      text: '$name — $label remaining',
      tint: AppColors.teal100,
    );
  }

  Widget _overdueOffWifiBanner(Map<String, dynamic> b) {
    final name  = b['name'] as String? ?? 'Break';
    final end   = _parseLocal(b['break_end_utc']);
    final label = end != null ? _countup(end) : '—';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        tint: AppColors.danger500,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          const Icon(Icons.running_with_errors, color: AppColors.danger500, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$name — return to office!',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.danger500, fontWeight: FontWeight.w700)),
              const Text('You are away from the office past your break time',
                  style: TextStyle(fontSize: 12, color: AppColors.danger500)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.danger500.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.danger500.withValues(alpha: 0.5)),
            ),
            child: Text('+$label',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    color: AppColors.danger500, fontFamily: 'monospace')),
          ),
        ]),
      ),
    );
  }

  Widget _overdueOnWifiBanner(Map<String, dynamic> b) {
    final name = b['name'] as String? ?? 'Break';
    return _glassBanner(
      icon: Icons.alarm_on_rounded,
      text: '$name time is up — please tap End Break',
      tint: AppColors.warning500,
    );
  }

  Widget _autoStartedBreakBanner(Map<String, dynamic> b, String breakId) {
    final name = b['name'] as String? ?? 'Break';
    final reminderMins = (b['reminder_after_mins'] as num?)?.toInt() ?? 30;
    final deductIfSkipped = b['deduct_if_skipped'] as bool? ?? true;
    final subtext = deductIfSkipped
        ? 'Deferring will set a ${reminderMins}m reminder; skipping deducts this time'
        : 'Deferring sets a ${reminderMins}m reminder — no pay impact';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        tint: AppColors.teal100,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.free_breakfast, color: AppColors.teal100, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$name has started',
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.teal100,
                        fontWeight: FontWeight.w700)),
                Text(subtext,
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.teal100.withValues(alpha: 0.75))),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _acknowledgedAutoBreaks.add(breakId)),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.teal100.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppColors.teal100.withValues(alpha: 0.4)),
                  ),
                  child: const Text("I'm on it",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.teal100)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: _actionLoading ? null : () => _takeBreakLater(b, breakId),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.warning500.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.warning500.withValues(alpha: 0.4)),
                  ),
                  child: const Text('Take it later',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.warning500)),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _deferredReminderBanner() {
    final name = _pendingReminderName ?? 'your break';
    final deduct = _pendingReminderDeduct;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        tint: AppColors.warning500,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.alarm, color: AppColors.warning500, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Time to take $name',
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.warning500,
                        fontWeight: FontWeight.w700)),
                if (deduct)
                  const Text('Skipping will deduct this time from your pay',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.warning500)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: _actionLoading ? null : _showBreakTypeSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.warning500.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.warning500.withValues(alpha: 0.5)),
                  ),
                  child: const Text('Take it now',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.warning500)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _pendingReminderName = null),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: const Text('Dismiss',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white54)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  // ─── Pre-check-in live late counter ────────────────────

  Widget _preCheckinLateBanner() {
    final lateMin = _livePreCheckinLateMins > 0
        ? _livePreCheckinLateMins
        : ((_todayStatus?['pre_checkin_late_minutes'] as num?)?.toInt() ?? 0);
    if (lateMin <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        tint: AppColors.warning500,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          const Icon(Icons.access_alarm, color: AppColors.warning500, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
            'You are currently ${_formatMinutesHours(lateMin)} late',
            style: const TextStyle(
                fontSize: 13,
                color: AppColors.warning500,
                fontWeight: FontWeight.w600),
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.warning500.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppColors.warning500.withValues(alpha: 0.5)),
            ),
            child: Text('+${_formatMinutesHours(lateMin)}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.warning500,
                    fontFamily: 'monospace')),
          ),
        ]),
      ),
    );
  }

  Widget _glassBanner(
      {required IconData icon,
      required String text,
      required Color tint,
      Widget? action}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        tint: tint,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(icon, color: tint, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 13, color: tint, fontWeight: FontWeight.w500))),
          if (action != null) action,
        ]),
      ),
    );
  }

  Widget _timePickerTile(
    BuildContext ctx, {
    required String label,
    required TimeOfDay value,
    required ValueChanged<TimeOfDay> onPicked,
  }) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: ctx,
          initialTime: value,
          builder: (c, child) => Theme(data: AppTheme.glass, child: child!),
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.45),
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          Flexible(
            child: Text(value.format(ctx),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ]),
      ),
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
          backgroundColor: AppColors.bgDark3,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.assignment_outlined,
                color: AppColors.primary600, size: 22),
            SizedBox(width: 8),
            Flexible(
                child: Text('Report / Request',
                    style: TextStyle(color: Colors.white, fontSize: 16))),
          ]),
          content: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Request type chips ──────────────────────
              Text('Request Type',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.6))),
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
                              ? AppColors.primary600.withValues(alpha: 0.25)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: sel
                                  ? AppColors.primary600
                                  : Colors.white.withValues(alpha: 0.15)),
                        ),
                        child: Text(t['label']!,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: sel
                                    ? AppColors.primary600
                                    : Colors.white.withValues(alpha: 0.7))),
                      ),
                    );
                  }).toList()),
              const SizedBox(height: 16),

              // ── Date picker ──────────────────────────────
              Text('Date',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.6))),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 7)),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                    builder: (c, child) =>
                        Theme(data: AppTheme.glass, child: child!),
                  );
                  if (picked != null) setDlg(() => selectedDate = picked);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calendar_today,
                        size: 15, color: AppColors.primary600),
                    const SizedBox(width: 8),
                    Text(fmtDateDisplay(selectedDate),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                    const Spacer(),
                    Text('Change',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.4))),
                  ]),
                ),
              ),
              const SizedBox(height: 16),

              // ── Leave sub-type (only for 'leave') ────────
              if (requestType == 'leave' || requestType == 'mid_shift_leave')
                ...(() {
                  return [
                    Text('Leave Type',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.6))),
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
                                    ? AppColors.teal700.withValues(alpha: 0.3)
                                    : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: sel
                                        ? AppColors.teal100
                                        : Colors.white.withValues(alpha: 0.15)),
                              ),
                              child: Text(l['label']!,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: sel
                                          ? AppColors.teal100
                                          : Colors.white
                                              .withValues(alpha: 0.6))),
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
                    Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.6))),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: selectedTime,
                          builder: (c, child) =>
                              Theme(data: AppTheme.glass, child: child!),
                        );
                        if (picked != null) setDlg(() => selectedTime = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 11),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.access_time,
                              size: 15, color: AppColors.primary600),
                          const SizedBox(width: 8),
                          Text(selectedTime.format(ctx),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                          const Spacer(),
                          Text('Tap to change',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.4))),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ];
                })(),

              if (requestType == 'mid_shift_leave') ...[
                Text('Leave Window',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.6))),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: _timePickerTile(
                      ctx,
                      label: 'Start',
                      value: selectedTime,
                      onPicked: (picked) => setDlg(() => selectedTime = picked),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _timePickerTile(
                      ctx,
                      label: 'End',
                      value: selectedEndTime,
                      onPicked: (picked) => setDlg(() => selectedEndTime = picked),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
              ],

              // ── Reason ───────────────────────────────────
              Text('Reason',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.6))),
              const SizedBox(height: 6),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                maxLength: 200,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Briefly describe the reason…',
                  hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 13),
                ),
              ),
            ],
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
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
                } catch (_) {
                  _showSnack('Failed to submit. Try again.', isError: true);
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
          'color': AppColors.primary600,
          'text':
              '$name in ${untilStart.inMinutes}m ${untilStart.inSeconds % 60}s',
        };
      }
      // More than 10 min away — show next break time
      return {
        'icon': Icons.schedule,
        'color': Colors.white.withValues(alpha: 0.45),
        'text': '$name at ${DateFormat('hh:mm a').format(breakStart)}',
      };
    }
    return null;
  }

  // ─── Disconnect (left office WiFi) Card ────────────────

  Widget _buildDisconnectCard() {
    final ssid = _disconnectSsid;
    final countdown = _disconnectCountdown;
    final expired = _graceExpired;
    return GlassCard(
      tint: AppColors.warning500,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.wifi_off_rounded,
              size: 28, color: AppColors.warning500),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(expired ? 'Grace Period Ended' : 'Left Office WiFi',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                Text(
                  ssid != null && ssid.isNotEmpty
                      ? 'No longer on "$ssid"'
                      : 'WiFi connection lost',
                  style: TextStyle(
                      fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
                ),
              ])),
        ]),
        const SizedBox(height: 16),
        // Prominent grace countdown
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.warning500.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: AppColors.warning500.withValues(alpha: 0.3)),
          ),
          child: Column(children: [
            Text(
              expired ? '00:00' : (countdown.isNotEmpty ? countdown : '--:--'),
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontFamily: 'monospace',
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              expired ? 'checking you out…' : 'until auto check-out',
              style: TextStyle(
                  fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Text(
          expired
              ? 'You\'ve been checked out. Reconnect to office WiFi and you\'ll be checked back in automatically.'
              : 'Reconnect to office WiFi to stay checked in. If you can\'t, scan the office QR code.',
          style: TextStyle(
              fontSize: 12, color: Colors.white.withValues(alpha: 0.55)),
        ),
        const SizedBox(height: 12),
        AppButton(
          label: 'Scan QR Code',
          icon: Icons.qr_code_scanner,
          onPressed: () => context.push('/attendance/qr'),
        ),
      ]),
    );
  }

  // ─── Status Card ───────────────────────────────────────

  Widget _buildStatusCard() {
    // When the employee is actively on a break and loses WiFi, leaving the
    // office is expected — don't replace the status card with the disconnect
    // card. The break banner handles the "overdue + off WiFi" case instead.
    if (_autoCheckoutRisk && !_isOnBreak) return _buildDisconnectCard();

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
      final breakMins = _asInt(_todayRecord?['break_minutes']) ?? 0;
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

      return GlassCard(
        tint: Colors.white,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.check_circle_outline,
                size: 28, color: Colors.white.withValues(alpha: 0.5)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Work Day Complete',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  if (wasAutoOut)
                    Text('Auto checked-out by system',
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                AppColors.warning500.withValues(alpha: 0.9))),
                ])),
            if (hoursLabel.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(hoursLabel,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
          ]),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.15), height: 1),
          const SizedBox(height: 12),
          Row(children: [
            _infoChip(Icons.login, 'In', checkInFmt),
            const SizedBox(width: 20),
            _infoChip(Icons.logout, 'Out', checkOutFmt),
            if (breakMins > 0) ...[
              const SizedBox(width: 20),
              _infoChip(Icons.free_breakfast, 'Break', '${breakMins}m'),
            ],
            if (overtimeHours > 0) ...[
              const SizedBox(width: 20),
              _infoChip(Icons.more_time, 'Overtime', '${overtimeHours.toStringAsFixed(1)}h'),
            ],
            if (extraOfficeMins > 0) ...[
              const SizedBox(width: 20),
              _infoChip(Icons.schedule, 'Extra', '${extraOfficeMins}m'),
            ],
          ]),
          if (canRequestOvertime) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _actionLoading
                  ? null
                  : () async {
                      setState(() => _actionLoading = true);
                      try {
                        await api.requestOvertime(
                          attendanceId: _todayRecord!['id'] as String,
                          reason: 'Worked ${extraOfficeMins}m after shift end',
                        );
                        _showSnack('Overtime request sent');
                      } catch (_) {
                        _showSnack('Could not request overtime', isError: true);
                      } finally {
                        if (mounted) setState(() => _actionLoading = false);
                      }
                    },
              icon: const Icon(Icons.more_time, size: 18),
              label: const Text('Request Overtime'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.teal100,
                side: BorderSide(color: AppColors.teal100.withValues(alpha: 0.5)),
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ]),
      );
    } else if (_checkedIn) {
      // ── CheckedIn hero: ring layout ───────────────────────
      final lateMins = _asInt(_todayRecord?['late_minutes']) ?? 0;
      final isLate = _status == 'late' || lateMins > 0;
      final hasNotice = _todayRecord?['late_notice_id'] != null;
      final ringTint = isLate ? AppColors.warning500 : const Color(0xFF34E0A1);

      final shiftStart = _getShiftStartMins();
      final shiftEnd = _getShiftEndMins();
      final nowMins = DateTime.now().hour * 60 + DateTime.now().minute;
      final shiftPct =
          ((nowMins - shiftStart) / (shiftEnd - shiftStart)).clamp(0.0, 1.0);

      final checkInStr = _todayRecord?['check_in_at'] as String?;
      final checkInTime = checkInStr != null
          ? DateFormat('hh:mm a').format(DateTime.parse(checkInStr).toLocal())
          : '--:--';
      final checkInType = _todayRecord?['check_in_type'] as String?;

      return GlassCard(
        tint: ringTint,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Top row: ring on left, info on right ──────────
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            _ShiftRing(
              pct: shiftPct,
              center: Icon(
                isLate ? Icons.running_with_errors : Icons.check_circle_rounded,
                color: ringTint,
                size: 30,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Status badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: ringTint.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: ringTint.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      isLate ? 'Checked In · Late' : 'Checked In',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ringTint),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Big elapsed timer
                  Text(
                    _elapsedDisplay,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 2),
                  // "Working since HH:MM" subtitle
                  Text(
                    'Working since $checkInTime',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.55)),
                  ),
                ])),
          ]),

          // ── Divider + info chips ───────────────────────────
          if (checkInStr != null) ...[
            const SizedBox(height: 12),
            Divider(color: Colors.white.withValues(alpha: 0.15), height: 1),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _infoChip(Icons.login, 'Checked in', checkInTime),
              if (checkInType != null)
                _infoChip(
                    Icons.wifi, 'Method', _formatCheckInType(checkInType)),
            ]),
          ],

          // ── Break status row ───────────────────────────────
          Builder(builder: (context) {
            final breakInfo = _computeBreakInfo();
            if (breakInfo == null) return const SizedBox.shrink();
            return Column(children: [
              const SizedBox(height: 8),
              Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
              const SizedBox(height: 8),
              Row(children: [
                Icon(breakInfo['icon'] as IconData,
                    size: 14, color: breakInfo['color'] as Color),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(
                  breakInfo['text'] as String,
                  style: TextStyle(
                      fontSize: 12,
                      color: breakInfo['color'] as Color,
                      fontWeight: FontWeight.w600),
                )),
              ]),
            ]);
          }),

          // ── Late info ──────────────────────────────────────
          if (lateMins > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${_formatMinutesHours(lateMins)} late${hasNotice ? ' · pre-announced' : ''}',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.warning500.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600),
            ),
          ],

          // ── QR + Check Out buttons ────────────────────────
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _actionLoading
                    ? null
                    : () => context.push('/attendance/qr'),
                icon: const Icon(Icons.qr_code_scanner, size: 16),
                label: const Text('Scan QR'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  minimumSize: const Size(0, 42),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppButton(
                label: 'Check Out',
                icon: Icons.logout,
                color: AppColors.danger500,
                loading: _actionLoading,
                onPressed: _actionLoading
                    ? null
                    : () async {
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
                            _showSnack('Failed to check out', isError: true);
                          } finally {
                            if (mounted) setState(() => _actionLoading = false);
                          }
                        }
                      },
              ),
            ),
          ]),
        ]),
      );
    } else if (_status == 'leave') {
      cardTint = AppColors.primary600;
      cardIcon = Icons.beach_access;
      iconColor = AppColors.primary600;
      statusTitle = 'On Leave 📅';
      statusSub = 'Approved leave';
    } else if (_status == 'half_leave') {
      final period = (_todayLeave?['half_day_period'] as String?) ?? '';
      final expected = period == 'morning' ? 'Afternoon' : 'Morning';
      cardTint = AppColors.teal700;
      cardIcon = Icons.calendar_today;
      iconColor = AppColors.teal100.withValues(alpha: 0.9);
      statusTitle = 'Half-Day Leave';
      statusSub = period.isNotEmpty
          ? '$expected half — you may still check in'
          : 'Approved half-day leave';
    } else {
      cardTint = Colors.white;
      cardIcon = Icons.radio_button_unchecked;
      iconColor = Colors.white.withValues(alpha: 0.4);
      statusTitle = 'Not Checked In';
      statusSub = _noNetworksConfig
          ? 'Scan QR code to check in — WiFi auto-detection not set up'
          : 'Connect to office WiFi for auto check-in, or scan QR code';
    }

    return GlassCard(
      tint: cardTint,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(cardIcon, size: 28, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(statusTitle,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                Text(statusSub,
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.6))),
              ])),
        ]),

        // Check-in actions
        if (!_checkedIn &&
            !_checkedOut &&
            !_isRemote &&
            _status != 'leave') ...[
          const SizedBox(height: 16),
          AppButton(
            label: 'Scan QR Code',
            icon: Icons.qr_code_scanner,
            onPressed: () => context.push('/attendance/qr'),
          ),
          const SizedBox(height: 8),
          if (_lateNotice == null || _lateNotice!['status'] == 'cancelled')
            OutlinedButton.icon(
              onPressed: _showLateNoticeDialog,
              icon: const Icon(Icons.schedule, size: 16),
              label: const Text('Report Late Arrival'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.warning500,
                side: BorderSide(
                    color: AppColors.warning500.withValues(alpha: 0.6)),
                minimumSize: const Size(double.infinity, 42),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
        ],

        // Remote activity button
        if (_isRemote &&
            _remoteSession != null &&
            _remoteSession!['status'] == 'approved') ...[
          const SizedBox(height: 12),
          AppButton(
            label: 'View My Activity',
            icon: Icons.chat_bubble_outline,
            outline: true,
            onPressed: () =>
                context.push('/home/remote/detail?id=${_remoteSession!['id']}'),
          ),
        ],
      ]),
    );
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
              final minsLeft  = breakEnd != null
                  ? breakEnd.difference(_now).inMinutes
                  : null;

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
      backgroundColor: AppColors.bgDark3,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Start a Break',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 8),
          ...types.map((t) {
                final state = t['state'] as String? ?? '';
                final isLate = state == 'done' ||
                    (state == 'overdue' &&
                        !(t['subtitle'] as String? ?? '').contains('window open'));
                final isNow  = (t['subtitle'] as String? ?? '').contains('window open');
                final subtitleColor = isLate
                    ? AppColors.warning500
                    : isNow
                        ? AppColors.teal100
                        : Colors.white.withValues(alpha: 0.45);
                return ListTile(
                  leading: Icon(t['icon'] as IconData,
                      color: isLate ? AppColors.warning500 : AppColors.teal100,
                      size: 22),
                  title: Text(t['label'] as String,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: t['subtitle'] != null
                      ? Text(t['subtitle'] as String,
                          style: TextStyle(color: subtitleColor, fontSize: 12))
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
    } catch (_) {
      _showSnack('Could not start break', isError: true);
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
    } catch (_) {
      _showSnack('Could not end break', isError: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  // A standalone break control shown beneath the status card (never inside it).
  Widget _buildBreakControl() {
    if (_isOnBreak) {
      return AppButton(
        label: 'End Break',
        icon: Icons.play_arrow_rounded,
        color: AppColors.teal700,
        loading: _actionLoading,
        onPressed: _actionLoading ? null : _endBreak,
      );
    }
    return OutlinedButton.icon(
      onPressed: _actionLoading ? null : _showBreakTypeSheet,
      icon: const Icon(Icons.free_breakfast_outlined, size: 18),
      label: const Text('Take a Break'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.teal100,
        side: BorderSide(color: AppColors.teal100.withValues(alpha: 0.5)),
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
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

  Widget _infoChip(IconData icon, String label, String value) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.4)),
      const SizedBox(width: 4),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 10, color: Colors.white.withValues(alpha: 0.45))),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      ]),
    ]);
  }

  // ─── Quick Actions ─────────────────────────────────────

  Widget _buildQuickActions(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final actions = [
      _QuickAction(
        icon: Icons.beach_access_outlined,
        label: 'Report /\nRequest',
        color: AppColors.primary600,
        onTap: _showAttendanceRequestDialog,
      ),
      if (auth.hasFeature('remote_work') && !_checkedIn && !_checkedOut && !_isRemote)
        _QuickAction(
          icon: Icons.home_outlined,
          label: 'Work\nRemote',
          color: AppColors.purple500,
          onTap: () => context.push('/home/remote'),
        ),
      if (auth.hasFeature('shifts'))
        _QuickAction(
          icon: Icons.calendar_today_outlined,
          label: 'My\nSchedule',
          color: AppColors.teal100.withValues(alpha: 0.8),
          onTap: () => context.go('/schedule'),
        ),
      if (auth.hasFeature('payroll'))
        _QuickAction(
          icon: Icons.receipt_long_outlined,
          label: 'My\nPayslips',
          color: AppColors.warning500,
          onTap: () => context.go('/profile'),
        ),
    ];
    return Row(
      children: actions
          .map((a) => Expanded(
                  child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: a.onTap,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              a.color.withValues(alpha: 0.22),
                              a.color.withValues(alpha: 0.1)
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: a.color.withValues(alpha: 0.3)),
                        ),
                        child: Column(children: [
                          Icon(a.icon, color: a.color, size: 24),
                          const SizedBox(height: 6),
                          Text(a.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: a.color,
                                  height: 1.3)),
                        ]),
                      ),
                    ),
                  ),
                ),
              )))
          .toList(),
    );
  }

  // ─── Shift Card ────────────────────────────────────────

  Widget _buildShiftCard() {
    final shift = (_nextShift!['shift'] as Map?)?.cast<String, dynamic>();
    final dateStr = _nextShift!['date'] as String?;
    final shiftName = shift?['name'] as String? ?? 'Shift';
    final startTime = shift?['start_time'] as String? ?? '--:--';
    final endTime = shift?['end_time'] as String? ?? '--:--';
    final colorHex = shift?['color'] as String? ?? '#f15153';
    final shiftColor = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));

    return GlassCard(
      child: Row(children: [
        Container(
          width: 4,
          height: 52,
          decoration: BoxDecoration(
              color: shiftColor, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(shiftName,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 3),
          Text('$startTime – $endTime',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.55),
                  fontFamily: 'monospace')),
        ])),
        if (dateStr != null)
          Text(DateFormat('EEE, d MMM').format(DateTime.parse(dateStr)),
              style: TextStyle(
                  fontSize: 12, color: Colors.white.withValues(alpha: 0.55))),
      ]),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
}

// ─── Shift Progress Ring ────────────────────────────────

class _ShiftRing extends StatelessWidget {
  final double pct;
  final Widget center;
  const _ShiftRing({required this.pct, required this.center});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(
          size: const Size(100, 100),
          painter: _RingPainter(pct: pct),
        ),
        center,
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double pct;
  const _RingPainter({required this.pct});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 9;
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (pct > 0) {
      final sweepAngle = 2 * 3.14159265 * pct;
      final rect = Rect.fromCircle(center: center, radius: radius);
      final gradient = SweepGradient(
        startAngle: -3.14159265 / 2,
        endAngle: -3.14159265 / 2 + sweepAngle,
        colors: const [Color(0xFF00C896), Color(0xFF00E5FF)],
      );
      final arcPaint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, -3.14159265 / 2, sweepAngle, false, arcPaint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct;
}
