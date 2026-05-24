import 'dart:async';
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
  bool _loading       = true;
  bool _vpnDetected   = false;
  bool _gracePeriod   = false;
  Timer? _timer;
  Duration _elapsed   = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startTimer();

    // Listen for WiFi status changes
    WifiAttendanceService().onStatusChange = (status) {
      if (!mounted) return;
      switch (status) {
        case 'checked_in':
          _load();
          _showSnack('✅ Auto checked in via office WiFi');
          break;
        case 'checked_out':
          _load();
          _showSnack('🔴 Auto checked out — WiFi disconnected');
          break;
        case 'grace_period':
          setState(() => _gracePeriod = true);
          _showSnack('WiFi signal lost — checking out in 5 min if not reconnected');
          break;
        case 'grace_cancelled':
          setState(() => _gracePeriod = false);
          _showSnack('Welcome back! Check-out cancelled.');
          break;
        case 'vpn_detected':
          setState(() => _vpnDetected = true);
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
      final records = await api.getMyAttendance(days: 1);
      final shifts  = await api.getMyShifts();
      if (mounted) {
        setState(() {
          _todayRecord = records.isNotEmpty ? records.first as Map<String, dynamic> : null;
          _nextShift   = shifts.isNotEmpty  ? shifts.first  as Map<String, dynamic> : null;
          _loading     = false;
        });
        _updateElapsed();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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

  String get _status    => _todayRecord?['status'] as String? ?? 'none';
  bool get _checkedIn   => _status == 'in' || _status == 'late';
  bool get _checkedOut  => _status == 'out';
  bool get _isRemote    => _status == 'remote';

  @override
  Widget build(BuildContext context) {
    final user    = context.watch<AuthProvider>().user!;
    final hour    = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

    return Scaffold(
      backgroundColor: AppColors.gray50,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _load();
            await WifiAttendanceService().checkAndReport();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$greeting,', style: const TextStyle(fontSize: 14, color: AppColors.gray500)),
                    Text(user.name.split(' ').first, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.dark950)),
                  ]),
                  UserAvatar(name: user.name),
                ]),

                const SizedBox(height: 20),

                // VPN warning
                if (_vpnDetected) _vpnBanner(),

                // Grace period warning
                if (_gracePeriod) _graceBanner(),

                // Today's Status Card
                _loading ? const SkeletonBox(width: double.infinity, height: 160, radius: 16) : _buildStatusCard(),

                const SizedBox(height: 20),

                // Quick Actions
                const SectionHeader(title: 'Quick Actions'),
                const SizedBox(height: 12),
                _buildQuickActions(context),

                const SizedBox(height: 20),

                // Today's Shift
                if (_nextShift != null) ...[
                  const SectionHeader(title: 'Your Shift'),
                  const SizedBox(height: 12),
                  _buildShiftCard(),
                ],

                const SizedBox(height: 20),

                // Date + WiFi status
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    const Icon(Icons.calendar_today, size: 16, color: AppColors.primary600),
                    const SizedBox(width: 8),
                    Expanded(child: Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.dark950))),
                    const Icon(Icons.wifi, size: 16, color: AppColors.success500),
                    const SizedBox(width: 4),
                    const Text('Auto check-in active', style: TextStyle(fontSize: 11, color: AppColors.gray500)),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _vpnBanner() => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.warning100, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.warning500)),
    child: Row(children: [
      const Icon(Icons.vpn_lock, color: AppColors.warning800, size: 18),
      const SizedBox(width: 8),
      const Expanded(child: Text('VPN detected — auto check-in is disabled. Use QR scan instead.',
          style: TextStyle(fontSize: 13, color: AppColors.warning800, fontWeight: FontWeight.w500))),
      TextButton(onPressed: () => context.push('/attendance/qr'),
          child: const Text('QR Scan', style: TextStyle(color: AppColors.warning800, fontWeight: FontWeight.w700))),
    ]),
  );

  Widget _graceBanner() => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.primary100, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.primary600)),
    child: const Row(children: [
      Icon(Icons.wifi_off, color: AppColors.primary600, size: 18),
      SizedBox(width: 8),
      Expanded(child: Text('WiFi signal lost — you\'ll be checked out in 5 minutes if not reconnected.',
          style: TextStyle(fontSize: 13, color: AppColors.primary600, fontWeight: FontWeight.w500))),
    ]),
  );

  Widget _buildStatusCard() {
    Color cardColor;
    IconData cardIcon;
    String statusTitle;
    String statusSub;

    if (_gracePeriod) {
      cardColor   = AppColors.warning100;
      cardIcon    = Icons.wifi_off;
      statusTitle = 'WiFi Lost — Grace Period';
      statusSub   = 'Will auto check-out in 5 min';
    } else if (_vpnDetected) {
      cardColor   = AppColors.warning100;
      cardIcon    = Icons.vpn_lock;
      statusTitle = 'VPN Active';
      statusSub   = 'Scan QR code to check in';
    } else if (_isRemote) {
      cardColor   = AppColors.purple100;
      cardIcon    = Icons.home_rounded;
      statusTitle = 'Working Remotely 🏠';
      statusSub   = 'AI will check in with you via WhatsApp';
    } else if (_checkedOut) {
      cardColor   = AppColors.gray100;
      cardIcon    = Icons.logout;
      statusTitle = 'Checked Out';
      statusSub   = 'Work day complete · ${_todayRecord?['hours_worked'] != null ? '${_todayRecord!['hours_worked']}h worked' : ''}';
    } else if (_checkedIn) {
      cardColor   = AppColors.success100;
      cardIcon    = Icons.check_circle_rounded;
      statusTitle = 'Checked In ✅';
      statusSub   = 'Working for $_elapsedDisplay';
    } else if (_status == 'leave') {
      cardColor   = AppColors.primary100;
      cardIcon    = Icons.beach_access;
      statusTitle = 'On Leave 📅';
      statusSub   = 'Approved leave';
    } else {
      cardColor   = AppColors.white;
      cardIcon    = Icons.radio_button_unchecked;
      statusTitle = 'Not Checked In';
      statusSub   = 'Auto check-in active — connect to office WiFi';
    }

    return AppCard(
      color: cardColor,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(cardIcon, size: 28, color: _checkedIn ? AppColors.success700 : _isRemote ? AppColors.purple700 : _gracePeriod ? AppColors.warning800 : AppColors.gray500),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(statusTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.dark950)),
            Text(statusSub, style: const TextStyle(fontSize: 13, color: AppColors.gray500)),
          ])),
        ]),

        if (_checkedIn && _todayRecord?['check_in_at'] != null) ...[
          const SizedBox(height: 12),
          const Divider(color: AppColors.gray200, height: 1),
          const SizedBox(height: 12),
          Row(children: [
            _infoChip(Icons.login, 'In', DateFormat('hh:mm a').format(DateTime.parse(_todayRecord!['check_in_at'] as String))),
            const SizedBox(width: 16),
            _infoChip(Icons.timer_outlined, 'Elapsed', _elapsedDisplay),
            if (_todayRecord?['check_in_type'] != null) ...[
              const SizedBox(width: 16),
              _infoChip(Icons.wifi, 'Via', _formatCheckInType(_todayRecord!['check_in_type'] as String)),
            ],
          ]),
        ],

        // QR Scan button — show if not checked in AND not on leave/remote AND no VPN block
        if (!_checkedIn && !_checkedOut && !_isRemote && _status != 'leave') ...[
          const SizedBox(height: 16),
          AppButton(
            label: 'Scan QR Code',
            icon: Icons.qr_code_scanner,
            onPressed: () => context.push('/attendance/qr'),
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
      Icon(icon, size: 14, color: AppColors.gray500),
      const SizedBox(width: 4),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.gray500)),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.dark950)),
      ]),
    ]);
  }

  Widget _buildQuickActions(BuildContext context) {
    final actions = [
      _QuickAction(icon: Icons.beach_access_outlined, label: 'Request\nLeave', color: AppColors.primary600, bg: AppColors.primary100, onTap: () => context.push('/leave/request')),
      _QuickAction(icon: Icons.home_outlined, label: 'Work\nRemote', color: AppColors.purple700, bg: AppColors.purple100, onTap: () => context.push('/home/remote')),
      _QuickAction(icon: Icons.calendar_today_outlined, label: 'My\nSchedule', color: AppColors.teal700, bg: AppColors.teal100, onTap: () => context.go('/schedule')),
      _QuickAction(icon: Icons.receipt_long_outlined, label: 'My\nPayslips', color: AppColors.warning800, bg: AppColors.warning100, onTap: () => context.go('/profile')),
    ];
    return Row(
      children: actions.map((a) => Expanded(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: AppCard(
          color: a.bg,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          onTap: a.onTap,
          child: Column(children: [
            Icon(a.icon, color: a.color, size: 24),
            const SizedBox(height: 6),
            Text(a.label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: a.color, height: 1.3)),
          ]),
        ),
      ))).toList(),
    );
  }

  Widget _buildShiftCard() {
    final shift     = (_nextShift!['shift'] as Map?)?.cast<String, dynamic>();
    final dateStr   = _nextShift!['date'] as String?;
    final shiftName = shift?['name'] as String? ?? 'Shift';
    final startTime = shift?['start_time'] as String? ?? '--:--';
    final endTime   = shift?['end_time']   as String? ?? '--:--';

    return AppCard(
      child: Row(children: [
        Container(
          width: 4, height: 52,
          decoration: BoxDecoration(
            color: shift?['color'] != null
                ? Color(int.parse((shift!['color'] as String).replaceFirst('#', '0xFF')))
                : AppColors.primary600,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(shiftName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text('$startTime – $endTime', style: const TextStyle(fontSize: 13, color: AppColors.gray500, fontWeight: FontWeight.w500, fontFamily: 'monospace')),
        ])),
        if (dateStr != null)
          Text(DateFormat('EEE, d MMM').format(DateTime.parse(dateStr)),
              style: const TextStyle(fontSize: 12, color: AppColors.gray500)),
      ]),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.color, required this.bg, required this.onTap});
}
