import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://attenda-api-production.up.railway.app/api/v1');
const _storage = FlutterSecureStorage();

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  late final Dio _dio = _buildDio();

  Dio _buildDio() {
    final dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    // Request interceptor — attach JWT
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'access_token');
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          try {
            final refresh = await _storage.read(key: 'refresh_token');
            if (refresh != null) {
              final res = await Dio().post('$_baseUrl/auth/refresh', data: {'refresh_token': refresh});
              final newToken = res.data['data']['access_token'] as String;
              await _storage.write(key: 'access_token', value: newToken);
              error.requestOptions.headers['Authorization'] = 'Bearer $newToken';
              final retry = await dio.fetch(error.requestOptions);
              return handler.resolve(retry);
            }
          } catch (_) {
            await _storage.deleteAll();
          }
        }
        handler.next(error);
      },
    ));

    return dio;
  }

  // ─── Auth ─────────────────────────────────────────
  Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await _dio.post('/auth/login', data: {'email': email, 'password': password});
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<void> logout() async {
    try { await _dio.post('/auth/logout'); } catch (_) {}
    await _storage.deleteAll();
  }

  Future<void> forgotPassword(String email) async {
    await _dio.post('/auth/forgot-password', data: {'email': email});
  }

  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    final res = await Dio().post('$_baseUrl/auth/refresh', data: {'refresh_token': refreshToken});
    return res.data['data'] as Map<String, dynamic>;
  }

  // ─── Users ────────────────────────────────────────
  Future<Map<String, dynamic>> getMe() async {
    final res = await _dio.get('/users/me');
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateMe(Map<String, dynamic> data) async {
    final res = await _dio.put('/users/me', data: data);
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMyCapabilities() async {
    final res = await _dio.get('/users/me/capabilities');
    return res.data['data'] as Map<String, dynamic>;
  }

  // ─── Attendance ───────────────────────────────────
  Future<List<dynamic>> getTodayAttendance() async {
    final res = await _dio.get('/attendance/today');
    return res.data['data'] as List;
  }

  Future<List<dynamic>> getMyAttendance({int days = 30}) async {
    final res = await _dio.get('/attendance/me', queryParameters: {'days': days});
    return res.data['data'] as List;
  }

  Future<Map<String, dynamic>> checkIn({String type = 'manual', String? qrCode, String? durationType}) async {
    final res = await _dio.post('/attendance/checkin', data: {
      'type': type,
      if (qrCode != null) 'qr_code': qrCode,
      if (type == 'remote' && durationType != null) 'duration_type': durationType,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> checkOut() async {
    final res = await _dio.post('/attendance/checkout');
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> startBreak({String breakType = 'manual', String? shiftBreakId}) async {
    final res = await _dio.post('/attendance/break/start', data: {
      'break_type': breakType,
      if (shiftBreakId != null) 'shift_break_id': shiftBreakId,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> endBreak({bool wifiConnected = false}) async {
    final res = await _dio.post('/attendance/break/end',
        data: {'wifi_connected': wifiConnected});
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> getMyRemoteSessions() async {
    final res = await _dio.get('/attendance/remote/sessions/me');
    return res.data['data'] as List;
  }

  Future<Map<String, dynamic>> getRemoteSessionLogs(String sessionId) async {
    final res = await _dio.get('/attendance/remote/sessions/$sessionId/logs');
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> reportIpEvent(String ip, {String? ssid, bool? countAwayAsBreak, String? awayShiftBreakId}) async {
    final res = await _dio.post('/attendance/ip-event', data: {
      'ip':    ip,
      'event': 'match',
      if (ssid != null && ssid.isNotEmpty) 'ssid': ssid,
      if (countAwayAsBreak != null) 'count_away_as_break': countAwayAsBreak,
      if (awayShiftBreakId != null) 'away_shift_break_id': awayShiftBreakId,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendHeartbeat(String ip, {String? ssid}) async {
    final res = await _dio.post('/attendance/heartbeat', data: {
      'ip': ip,
      if (ssid != null && ssid.isNotEmpty) 'ssid': ssid,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  /// Returns shift breaks with live timing state (upcoming/imminent/active/overdue),
  /// current attendance record, and pre-check-in late minutes.
  Future<Map<String, dynamic>> getTodayStatus() async {
    final res = await _dio.get('/attendance/today-status');
    return res.data['data'] as Map<String, dynamic>;
  }

  /// Submit a generic attendance request: 'late_arrival' | 'leave' | 'early_departure'
  Future<Map<String, dynamic>> submitAttendanceRequest({
    required String type,   // 'late_arrival' | 'leave' | 'early_departure'
    required String date,   // yyyy-MM-dd
    required String reason,
    String? expectedTime,   // HH:mm – for late_arrival
    String? leaveType,      // e.g. 'annual', 'sick' – for leave
    String? leaveStartTime, // HH:mm – for mid-shift leave
    String? leaveEndTime,   // HH:mm – for mid-shift leave
  }) async {
    if (type == 'late_arrival') {
      return submitLateNotice(
        date: date,
        expectedTime: expectedTime ?? '09:00',
        reason: reason,
      );
    }
    if (type == 'leave') {
      final res = await _dio.post('/leave/requests', data: {
        'leave_type': leaveType ?? 'annual',
        'start_date': date,
        'end_date':   date,
        'reason':     reason,
        if (leaveStartTime != null) 'leave_start_time': leaveStartTime,
        if (leaveEndTime != null) 'leave_end_time': leaveEndTime,
      });
      return res.data['data'] as Map<String, dynamic>;
    }
    // early_departure — stored as a late notice with a special type tag until a
    // dedicated endpoint exists.
    final res = await _dio.post('/attendance/late-notice', data: {
      'date':          date,
      'expected_time': expectedTime ?? '17:00',
      'reason':        '[Early Departure] $reason',
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getLeaveAndNoticeCheck() async {
    final res = await _dio.get('/attendance/leave-check');
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitLateNotice({
    required String date,
    required String expectedTime,
    required String reason,
  }) async {
    final res = await _dio.post('/attendance/late-notice', data: {
      'date':          date,
      'expected_time': expectedTime,
      'reason':        reason,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> getMyLateNotices({int days = 7}) async {
    final res = await _dio.get('/attendance/late-notice/me', queryParameters: {'days': days});
    return res.data['data'] as List;
  }

  Future<void> cancelLateNotice(String id) async {
    await _dio.delete('/attendance/late-notice/$id');
  }

  // ─── Leave ────────────────────────────────────────
  Future<List<dynamic>> getMyLeaveRequests() async {
    final res = await _dio.get('/leave/requests/me');
    return res.data['data'] as List;
  }

  Future<List<dynamic>> getMyLeaveBalance() async {
    final res = await _dio.get('/leave/balance/me');
    return res.data['data'] as List;
  }

  Future<Map<String, dynamic>> submitLeave(Map<String, dynamic> data) async {
    final res = await _dio.post('/leave/requests', data: data);
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<void> cancelLeave(String id) async {
    await _dio.delete('/leave/requests/$id');
  }

  Future<List<dynamic>> getTeamLeave() async {
    final res = await _dio.get('/leave/requests/team');
    return res.data['data'] as List;
  }

  Future<void> approveLeave(String id) async {
    await _dio.put('/leave/requests/$id/approve');
  }

  Future<void> rejectLeave(String id, String reason) async {
    await _dio.put('/leave/requests/$id/reject', data: {'reason': reason});
  }

  // ─── Shifts ───────────────────────────────────────
  Future<List<dynamic>> getMyShifts() async {
    final res = await _dio.get('/shifts/assignments/me');
    return res.data['data'] as List;
  }

  Future<Map<String, dynamic>> getShiftAssignmentDetail(String assignmentId) async {
    final res = await _dio.get('/shifts/assignments/$assignmentId/detail');
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> requestOvertime({
    required String attendanceId,
    String? reason,
  }) async {
    final res = await _dio.post('/overtime/requests', data: {
      'attendance_id': attendanceId,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> getMyOvertimeRequests() async {
    final res = await _dio.get('/overtime/requests/me');
    return res.data['data'] as List;
  }

  Future<List<dynamic>> getSwapRequests() async {
    final res = await _dio.get('/shifts/swaps/me');
    return res.data['data'] as List;
  }

  Future<Map<String, dynamic>> requestSwap(Map<String, dynamic> data) async {
    final res = await _dio.post('/shifts/swaps', data: data);
    return res.data['data'] as Map<String, dynamic>;
  }

  // ─── Payroll ──────────────────────────────────────
  Future<List<dynamic>> getMyPayslips() async {
    final res = await _dio.get('/payroll/me');
    return res.data['data'] as List;
  }

  Future<Map<String, dynamic>> downloadPayslip(String id) async {
    final res = await _dio.get('/payroll/payslips/$id/download');
    return res.data['data'] as Map<String, dynamic>;
  }

  // ─── Performance ──────────────────────────────────
  Future<List<dynamic>> getMyReviews() async {
    final res = await _dio.get('/performance/reviews/me');
    return res.data['data'] as List;
  }

  Future<List<dynamic>> getMyGoals() async {
    final res = await _dio.get('/performance/goals');
    return res.data['data'] as List;
  }

  // ─── Notification Preferences ────────────────────
  Future<Map<String, dynamic>> getNotificationPrefs() async {
    final res = await _dio.get('/users/me/notification-prefs');
    return (res.data['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> updateNotificationPrefs(Map<String, bool> prefs) async {
    final res = await _dio.put('/users/me/notification-prefs', data: prefs);
    return (res.data['data'] as Map<String, dynamic>?) ?? {};
  }

  // ─── Profile ──────────────────────────────────────
  Future<Map<String, dynamic>> updateProfile({String? name, String? phone}) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (phone != null) data['phone'] = phone;
    final res = await _dio.put('/users/me', data: data);
    return res.data['data'] as Map<String, dynamic>;
  }

  // ─── Change Password ──────────────────────────────
  Future<void> changePassword(String currentPassword, String newPassword) async {
    await _dio.put('/auth/change-password', data: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  // ─── 2FA ──────────────────────────────────────────
  /// Completes a 2FA login challenge. Returns the same payload as /auth/login
  /// on success: {access_token, refresh_token, user}.
  Future<Map<String, dynamic>> authenticate2fa(String partialToken, String code) async {
    final res = await _dio.post('/auth/2fa/authenticate', data: {
      'partial_token': partialToken,
      'code': code,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setup2fa() async {
    final res = await _dio.post('/auth/2fa/setup');
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<void> verify2fa(String code) async {
    await _dio.post('/auth/2fa/verify', data: {'code': code});
  }

  Future<void> disable2fa(String code) async {
    await _dio.delete('/auth/2fa', data: {'code': code});
  }

  // ─── Notifications ────────────────────────────────
  Future<Map<String, dynamic>> getNotifications({int page = 1, int limit = 20}) async {
    final res = await _dio.get('/notifications', queryParameters: {'page': page, 'limit': limit});
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<int> getNotificationCount() async {
    final res = await _dio.get('/notifications/count');
    return (res.data['data']['count'] as int?) ?? 0;
  }

  Future<void> markNotificationRead(String id) async {
    await _dio.put('/notifications/$id/read');
  }

  Future<void> markAllNotificationsRead() async {
    await _dio.put('/notifications/read-all');
  }

  Future<void> deleteNotification(String id) async {
    await _dio.delete('/notifications/$id');
  }
}

final api = ApiService();
