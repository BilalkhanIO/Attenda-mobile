import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
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
  bool _loading           = true;
  bool _vpnDetected       = false;
  bool _heartbeatLost     = false;
  String?   _disconnectSsid;
  DateTime? _disconnectDeadline; // 10 min from when heartbeat was lost
  bool _noNetworksConfig  = false;
  Timer? _timer;
  Duration _elapsed   = Duration.zero;
  int _unreadNotifs   = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startTimer();

    WifiAttendanceService().onStatusChange = (status, [data]) {
      if (!mounted) return;
      switch (status) {
        case 'checked_in':
          setState(() { _heartbeatLost = false; _disconnectDeadline = null; });
          _load();
          _showSnack('✅ Auto checked in via office WiFi');
          break;
        case 'heartbeat_lost':
          setState(() {
            _heartbeatLost      = true;
            _disconnectSsid     = data;
            _disconnectDeadline = DateTime.now().add(const Duration(minutes: 10));
          });
          break;
        case 'heartbeat_restored':
          setState(() { _heartbeatLost = false; _disconnectDeadline = null; });
          _showSnack('✅ Back on office WiFi');
          break;
        case 'vpn_detected':
          setState(() => _vpnDetected = true);
          break;
        case 'no_networks':
          setState(() => _noNetworksConfig = true);
          break;
      }
    };
  }

  @override
  void dispose() {
    _timer?.cancel();
    WifiAttendanceService().onStatusChange = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
      WifiAttendanceService().checkAndReport();
      WifiAttendanceService().syncOfflineQueue();
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        api.getMyAttendance(days: 1),
        api.getMyShifts(),
        api.getLeaveAndNoticeCheck().catchError((_) => <String, dynamic>{}),
      ]);

      final records   = results[0] as List;
      final shifts    = results[1] as List;
      final leaveInfo = results[2] as Map<String, dynamic>;

      final todayRecord = records.isNotEmpty ? records.first as Map<String, dynamic> : null;
      final status = todayRecord?['status'] as String? ?? 'none';

      Map<String, dynamic>? remoteSession;
      if (status == 'remote') {
        try {
          final sessions = await api.getMyRemoteSessions();
          remoteSession = sessions.isNotEmpty ? sessions.first as Map<String, dynamic> : null;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _todayRecord   = todayRecord;
          _nextShift     = shifts.isNotEmpty ? shifts.first as Map<String, dynamic> : null;
          _remoteSession = remoteSession;
          _todayLeave    = leaveInfo['leave']       as Map<String, dynamic>?;
          _lateNotice    = leaveInfo['late_notice'] as Map<String, dynamic>?;
          _loading       = false;
        });
        _updateElapsed();
      }
    } catch (_) {
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

  void _updateElapsed() {
    final checkIn  = _todayRecord?['check_in_at']  as String?;
    final checkOut = _todayRecord?['check_out_at'] as String?;
    if (checkIn != null && checkOut == null) {
      setState(() => _elapsed = DateTime.now().difference(DateTime.parse(checkIn)));
    }
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

  String get _status   => _todayRecord?['status'] as String? ?? 'none';
  bool get _checkedIn  => _status == 'in' || _status == 'late';
  bool get _checkedOut => _status == 'out';
  bool get _isRemote   => _status == 'remote';

  @override
  Widget build(BuildContext context) {
    final user     = context.watch<AuthProvider>().user!;
    final hour     = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary600,
          backgroundColor: const Color(0xFF2D1952),
          onRefresh: () async {
            await _load();
            await WifiAttendanceService().checkAndReport();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── Header ───────────────────────────────
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$greeting,',
                        style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.55))),
                    Text(user.name.split(' ').first,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
                  ]),
                  Row(children: [
                    // Notification bell
                    GestureDetector(
                      onTap: () async {
                        await context.push('/home/notifications');
                        _load();
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            width: 42, height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.2)),
                            ),
                            child: Stack(alignment: Alignment.center, children: [
                              Icon(Icons.notifications_outlined, size: 20, color: Colors.white.withOpacity(0.8)),
                              if (_unreadNotifs > 0) Positioned(
                                top: 8, right: 8,
                                child: Container(
                                  width: 8, height: 8,
                                  decoration: const BoxDecoration(color: AppColors.primary600, shape: BoxShape.circle),
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
                if (_vpnDetected)        _vpnBanner(),
                if (_heartbeatLost)      _heartbeatLostBanner(),
                if (_noNetworksConfig && !_vpnDetected) _noNetworksBanner(),
                if (!_loading && _todayLeave != null &&
                    _status != 'in' && _status != 'late' && _status != 'out')
                  _leaveTodayBanner(),
                if (!_loading && _lateNotice != null &&
                    _status != 'in' && _status != 'late' && _status != 'out')
                  _lateNoticeBanner(),

                // ─── Status Card ──────────────────────────
                _loading
                    ? SkeletonBox(width: double.infinity, height: 160, radius: 20)
                    : _buildStatusCard(),

                const SizedBox(height: 20),

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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    const Icon(Icons.calendar_today, size: 16, color: AppColors.primary600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                    Icon(Icons.wifi_rounded, size: 15,
                        color: _noNetworksConfig ? Colors.white.withOpacity(0.3) : AppColors.success500),
                    const SizedBox(width: 4),
                    Text(
                      _noNetworksConfig ? 'Auto check-in off' : 'Auto check-in on',
                      style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.45)),
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

  Widget _vpnBanner() => _glassBanner(
    icon: Icons.vpn_lock,
    text: 'VPN detected — auto check-in is disabled. Use QR scan instead.',
    tint: AppColors.warning500,
    action: TextButton(
      onPressed: () => context.push('/attendance/qr'),
      child: const Text('QR Scan', style: TextStyle(color: AppColors.warning500, fontWeight: FontWeight.w700)),
    ),
  );

  Widget _noNetworksBanner() => _glassBanner(
    icon: Icons.wifi_off,
    text: "Auto check-in is off — your admin hasn't added any office networks yet.",
    tint: Colors.white,
  );

  Widget _heartbeatLostBanner() {
    final ssid = _disconnectSsid;
    return _glassBanner(
      icon: Icons.wifi_off,
      text: ssid != null && ssid.isNotEmpty
          ? 'Not on "$ssid" — reconnect within $_disconnectCountdown or you\'ll be checked out'
          : 'Left office WiFi — reconnect within $_disconnectCountdown to stay checked in',
      tint: AppColors.warning500,
    );
  }

  Widget _leaveTodayBanner() {
    final leaveType = (_todayLeave?['leave_type'] as String? ?? 'leave').replaceAll('_', ' ');
    return _glassBanner(
      icon: Icons.beach_access,
      text: 'You have approved $leaveType today. No check-in required.',
      tint: AppColors.primary600,
    );
  }

  Widget _lateNoticeBanner() {
    final expectedTime  = _lateNotice?['expected_time'] as String? ?? '';
    final noticeStatus  = _lateNotice?['status'] as String? ?? 'pending';
    final isAcked       = noticeStatus == 'acknowledged';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        tint: isAcked ? AppColors.success500 : AppColors.warning500,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(isAcked ? Icons.check_circle_outline : Icons.schedule,
              color: isAcked ? AppColors.success500 : AppColors.warning500, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(
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
            child: Icon(Icons.close, size: 16, color: Colors.white.withOpacity(0.4)),
          ),
        ]),
      ),
    );
  }

  Widget _glassBanner({required IconData icon, required String text, required Color tint, Widget? action}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        tint: tint,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(icon, color: tint, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: tint, fontWeight: FontWeight.w500))),
          if (action != null) action,
        ]),
      ),
    );
  }

  // ─── Late Notice Dialog ────────────────────────────────

  Future<void> _showLateNoticeDialog() async {
    final reasonCtrl = TextEditingController();
    TimeOfDay selectedTime = TimeOfDay.now().replacing(
      hour: (TimeOfDay.now().hour + 1).clamp(0, 23),
      minute: 0,
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.schedule, color: AppColors.warning500, size: 22),
            SizedBox(width: 8),
            Text('Report Late Arrival'),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Let your manager know you\'ll be arriving late.',
                style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.55))),
            const SizedBox(height: 16),
            Text('Expected Arrival Time',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.8))),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () async {
                final picked = await showTimePicker(
                  context: ctx,
                  initialTime: selectedTime,
                  builder: (c, child) => Theme(data: AppTheme.glass, child: child!),
                );
                if (picked != null) setDlgState(() => selectedTime = picked);
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.access_time, size: 18, color: AppColors.primary600),
                      const SizedBox(width: 8),
                      Text(selectedTime.format(ctx),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                      const Spacer(),
                      Text('Tap to change', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4))),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Reason',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.8))),
            const SizedBox(height: 6),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              maxLength: 200,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. Medical appointment, traffic delay…',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning500,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final reason = reasonCtrl.text.trim();
                if (reason.length < 5) {
                  _showSnack('Please enter a reason (at least 5 characters)');
                  return;
                }
                try {
                  final today = DateTime.now();
                  final dateStr = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
                  final hh = selectedTime.hour.toString().padLeft(2, '0');
                  final mm = selectedTime.minute.toString().padLeft(2, '0');
                  final notice = await api.submitLateNotice(
                    date: dateStr,
                    expectedTime: '$hh:$mm',
                    reason: reason,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  setState(() => _lateNotice = notice);
                  _showSnack('Late arrival notice submitted ✅');
                } catch (_) {
                  _showSnack('Failed to submit notice. Try again.');
                }
              },
              child: const Text('Submit Notice'),
            ),
          ],
        ),
      ),
    );
    reasonCtrl.dispose();
  }

  // ─── Break Info ────────────────────────────────────────

  Map<String, dynamic>? _computeBreakInfo() {
    final checkInStr = _todayRecord?['check_in_at'] as String?;
    if (checkInStr == null) return null;
    final checkIn = DateTime.parse(checkInStr);

    // Check for active break in break_records
    final breakRecords = (_todayRecord?['break_records'] as List?)
        ?.cast<Map<String, dynamic>>() ?? [];
    final activeBreak = breakRecords.where((b) => b['break_end'] == null).firstOrNull;
    if (activeBreak != null) {
      final startedAt = DateTime.parse(activeBreak['break_start'] as String);
      final durationMins = activeBreak['duration_mins'] as int? ?? 30;
      final endsAt = startedAt.add(Duration(minutes: durationMins));
      final remaining = endsAt.difference(DateTime.now());
      if (remaining.isNegative) {
        return {
          'icon': Icons.free_breakfast,
          'color': AppColors.warning500,
          'text': 'Break running ${(-remaining.inMinutes)}m over',
        };
      }
      final m = remaining.inMinutes;
      final s = remaining.inSeconds % 60;
      return {
        'icon': Icons.free_breakfast,
        'color': AppColors.teal100,
        'text': 'On break — ${m}m ${s}s remaining',
      };
    }

    // Check for upcoming breaks from shift schedule
    final shiftBreaks = (_nextShift?['shift']?['shift_breaks'] as List?)
        ?.cast<Map<String, dynamic>>() ?? [];
    for (final sb in shiftBreaks) {
      final afterMins   = (sb['after_minutes'] as num?)?.toInt() ?? 0;
      final breakMins   = (sb['break_minutes'] as num?)?.toInt() ?? 15;
      final name        = sb['name'] as String? ?? 'Break';
      final breakStart  = checkIn.add(Duration(minutes: afterMins));
      final breakEnd    = breakStart.add(Duration(minutes: breakMins));

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
          'text': '$name in ${untilStart.inMinutes}m ${untilStart.inSeconds % 60}s',
        };
      }
      // More than 10 min away — show next break time
      return {
        'icon': Icons.schedule,
        'color': Colors.white.withOpacity(0.45),
        'text': '$name at ${DateFormat('hh:mm a').format(breakStart)}',
      };
    }
    return null;
  }

  // ─── Status Card ───────────────────────────────────────

  Widget _buildStatusCard() {
    Color cardTint;
    IconData cardIcon;
    String statusTitle;
    String statusSub;
    Color iconColor;

    if (_heartbeatLost) {
      cardTint    = AppColors.warning500;
      cardIcon    = Icons.wifi_off;
      iconColor   = AppColors.warning500;
      statusTitle = 'Not on Office WiFi';
      statusSub   = _disconnectCountdown.isNotEmpty
          ? 'Auto check-out in $_disconnectCountdown — reconnect to stay'
          : 'Reconnect to office WiFi';
    } else if (_vpnDetected) {
      cardTint    = AppColors.warning500;
      cardIcon    = Icons.vpn_lock;
      iconColor   = AppColors.warning500;
      statusTitle = 'VPN Active';
      statusSub   = 'Scan QR code to check in';
    } else if (_isRemote) {
      cardTint    = AppColors.purple500;
      cardIcon    = Icons.home_rounded;
      iconColor   = AppColors.purple500;
      statusTitle = 'Working Remotely 🏠';
      final sessionStatus = _remoteSession?['status'] as String? ?? 'pending';
      statusSub   = sessionStatus == 'approved'
          ? 'Approved — AI will check in with you via WhatsApp'
          : sessionStatus == 'rejected'
              ? 'Rejected by manager — please contact HR'
              : 'Pending manager approval';
    } else if (_checkedOut) {
      cardTint    = Colors.white;
      cardIcon    = Icons.logout;
      iconColor   = Colors.white.withOpacity(0.5);
      statusTitle = 'Checked Out';
      statusSub   = 'Work day complete · ${_todayRecord?['hours_worked'] != null ? '${_todayRecord!['hours_worked']}h worked' : ''}';
    } else if (_checkedIn) {
      final lateMins  = (_todayRecord?['late_minutes'] as num?)?.toInt() ?? 0;
      final isLate    = _status == 'late' || lateMins > 0;
      final hasNotice = _todayRecord?['late_notice_id'] != null;
      cardTint    = isLate ? AppColors.warning500 : AppColors.success500;
      cardIcon    = isLate ? Icons.running_with_errors : Icons.check_circle_rounded;
      iconColor   = isLate ? AppColors.warning500 : AppColors.success500;
      statusTitle = isLate ? 'Checked In (Late)' : 'Checked In ✅';
      statusSub   = lateMins > 0
          ? '$lateMins min late${hasNotice ? ' · pre-announced' : ''} · working for $_elapsedDisplay'
          : 'Working for $_elapsedDisplay';
    } else if (_status == 'leave') {
      cardTint    = AppColors.primary600;
      cardIcon    = Icons.beach_access;
      iconColor   = AppColors.primary600;
      statusTitle = 'On Leave 📅';
      statusSub   = 'Approved leave';
    } else if (_status == 'half_leave') {
      final period   = (_todayLeave?['half_day_period'] as String?) ?? '';
      final expected = period == 'morning' ? 'Afternoon' : 'Morning';
      cardTint    = AppColors.teal700;
      cardIcon    = Icons.calendar_today;
      iconColor   = AppColors.teal100.withOpacity(0.9);
      statusTitle = 'Half-Day Leave';
      statusSub   = period.isNotEmpty ? '$expected half — you may still check in' : 'Approved half-day leave';
    } else {
      cardTint    = Colors.white;
      cardIcon    = Icons.radio_button_unchecked;
      iconColor   = Colors.white.withOpacity(0.4);
      statusTitle = 'Not Checked In';
      statusSub   = _noNetworksConfig
          ? 'Scan QR code to check in — WiFi auto-detection not set up'
          : 'Connect to office WiFi for auto check-in, or scan QR code';
    }

    return GlassCard(
      tint: cardTint,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(cardIcon, size: 28, color: iconColor),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(statusTitle,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
            Text(statusSub,
                style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.6))),
          ])),
        ]),

        if (_checkedIn && _todayRecord?['check_in_at'] != null) ...[
          const SizedBox(height: 12),
          Divider(color: Colors.white.withOpacity(0.15), height: 1),
          const SizedBox(height: 12),
          Row(children: [
            _infoChip(Icons.login, 'In',
                DateFormat('hh:mm a').format(DateTime.parse(_todayRecord!['check_in_at'] as String))),
            const SizedBox(width: 20),
            _infoChip(Icons.timer_outlined, 'Elapsed', _elapsedDisplay),
            if (_todayRecord?['check_in_type'] != null) ...[
              const SizedBox(width: 20),
              _infoChip(Icons.wifi, 'Via', _formatCheckInType(_todayRecord!['check_in_type'] as String)),
            ],
          ]),
          // Break status row (shows upcoming break warning or active break)
          Builder(builder: (context) {
            final breakInfo = _computeBreakInfo();
            if (breakInfo == null) return const SizedBox.shrink();
            return Column(children: [
              const SizedBox(height: 8),
              Divider(color: Colors.white.withOpacity(0.12), height: 1),
              const SizedBox(height: 8),
              Row(children: [
                Icon(breakInfo['icon'] as IconData, size: 14, color: breakInfo['color'] as Color),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  breakInfo['text'] as String,
                  style: TextStyle(fontSize: 12, color: breakInfo['color'] as Color, fontWeight: FontWeight.w600),
                )),
              ]),
            ]);
          }),
        ],

        // Check-in actions
        if (!_checkedIn && !_checkedOut && !_isRemote && _status != 'leave') ...[
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
                side: BorderSide(color: AppColors.warning500.withOpacity(0.6)),
                minimumSize: const Size(double.infinity, 42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
        ],

        // Remote activity button
        if (_isRemote && _remoteSession != null && _remoteSession!['status'] == 'approved') ...[
          const SizedBox(height: 12),
          AppButton(
            label: 'View My Activity',
            icon: Icons.chat_bubble_outline,
            outline: true,
            onPressed: () => context.push('/home/remote/detail?id=${_remoteSession!['id']}'),
          ),
        ],
      ]),
    );
  }

  String _formatCheckInType(String type) {
    switch (type) {
      case 'auto_ip': return 'Auto (WiFi)';
      case 'qr':      return 'QR Code';
      case 'remote':  return 'Remote';
      default:        return 'Manual';
    }
  }

  Widget _infoChip(IconData icon, String label, String value) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: Colors.white.withOpacity(0.4)),
      const SizedBox(width: 4),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.45))),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
      ]),
    ]);
  }

  // ─── Quick Actions ─────────────────────────────────────

  Widget _buildQuickActions(BuildContext context) {
    final actions = [
      _QuickAction(
        icon: Icons.beach_access_outlined,
        label: 'Request\nLeave',
        color: AppColors.primary600,
        onTap: () => context.push('/leave/request'),
      ),
      if (!_checkedIn && !_checkedOut && !_isRemote)
        _QuickAction(
          icon: Icons.home_outlined,
          label: 'Work\nRemote',
          color: AppColors.purple500,
          onTap: () => context.push('/home/remote'),
        ),
      _QuickAction(
        icon: Icons.calendar_today_outlined,
        label: 'My\nSchedule',
        color: AppColors.teal100.withOpacity(0.8),
        onTap: () => context.go('/schedule'),
      ),
      _QuickAction(
        icon: Icons.receipt_long_outlined,
        label: 'My\nPayslips',
        color: AppColors.warning500,
        onTap: () => context.go('/profile'),
      ),
    ];
    return Row(
      children: actions.map((a) => Expanded(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: GestureDetector(
          onTap: a.onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [a.color.withOpacity(0.22), a.color.withOpacity(0.1)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: a.color.withOpacity(0.3)),
                ),
                child: Column(children: [
                  Icon(a.icon, color: a.color, size: 24),
                  const SizedBox(height: 6),
                  Text(a.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: a.color, height: 1.3)),
                ]),
              ),
            ),
          ),
        ),
      ))).toList(),
    );
  }

  // ─── Shift Card ────────────────────────────────────────

  Widget _buildShiftCard() {
    final shift     = (_nextShift!['shift'] as Map?)?.cast<String, dynamic>();
    final dateStr   = _nextShift!['date'] as String?;
    final shiftName = shift?['name'] as String? ?? 'Shift';
    final startTime = shift?['start_time'] as String? ?? '--:--';
    final endTime   = shift?['end_time']   as String? ?? '--:--';
    final colorHex  = shift?['color'] as String? ?? '#f15153';
    final shiftColor = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));

    return GlassCard(
      child: Row(children: [
        Container(
          width: 4, height: 52,
          decoration: BoxDecoration(color: shiftColor, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(shiftName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 3),
          Text('$startTime – $endTime',
              style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.55), fontFamily: 'monospace')),
        ])),
        if (dateStr != null)
          Text(DateFormat('EEE, d MMM').format(DateTime.parse(dateStr)),
              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.55))),
      ]),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});
}
