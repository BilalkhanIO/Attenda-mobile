import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:typed_data';
import 'attendance_clock.dart';

const _baseUrl = String.fromEnvironment('API_URL',
    defaultValue: 'https://attenda-api-production.up.railway.app/api/v1');
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
              final res = await Dio().post('$_baseUrl/auth/refresh',
                  data: {'refresh_token': refresh});
              final newToken = res.data['data']['access_token'] as String;
              await _storage.write(key: 'access_token', value: newToken);
              // Rotation: store the successor refresh token — reusing the old
              // one would revoke the whole token family on the server.
              final rotated = res.data['data']['refresh_token'] as String?;
              if (rotated != null) {
                await _storage.write(key: 'refresh_token', value: rotated);
              }
              error.requestOptions.headers['Authorization'] =
                  'Bearer $newToken';
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
    final res = await _dio
        .post('/auth/login', data: {'email': email, 'password': password});
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } catch (_) {}
    await _storage.deleteAll();
  }

  Future<void> forgotPassword(String email) async {
    await _dio.post('/auth/forgot-password', data: {'email': email});
  }

  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    final res = await Dio()
        .post('$_baseUrl/auth/refresh', data: {'refresh_token': refreshToken});
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

  // ─── Attenda AI ────────────────────────────────────
  Future<Map<String, dynamic>> chatWithAi(String message,
      {String? conversationId, String? context}) async {
    final res = await _dio.post('/ai/chat',
        data: {
          'message': message,
          if (conversationId != null) 'conversation_id': conversationId,
          if (context != null && conversationId == null) 'context': context,
        },
        options: Options(receiveTimeout: const Duration(seconds: 125)));
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> getAiConversations() async {
    final res = await _dio.get('/ai/conversations');
    return res.data['data'] as List;
  }

  Future<Map<String, dynamic>> getAiConversation(String id) async {
    final res = await _dio.get('/ai/conversations/$id');
    return res.data['data'] as Map<String, dynamic>;
  }

  // ─── Attendance ───────────────────────────────────
  Future<List<dynamic>> getTodayAttendance() async {
    final res = await _dio.get('/attendance/today');
    return res.data['data'] as List;
  }

  Future<List<dynamic>> getMyAttendance({int days = 30}) async {
    final res =
        await _dio.get('/attendance/me', queryParameters: {'days': days});
    return res.data['data'] as List;
  }

  Future<Map<String, dynamic>> checkIn(
      {String type = 'manual',
      String? qrCode,
      String? durationType,
      String? idempotencyKey,
      DateTime? clientEventAt,
      bool offline = false,
      double? latitude,
      double? longitude,
      double? accuracyM,
      bool? isMocked,
      Map<String, dynamic>? clockProof}) async {
    final res = await _dio.post('/attendance/checkin', data: {
      'type': type,
      if (qrCode != null) 'qr_code': qrCode,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (clientEventAt != null)
        'client_event_at': clientEventAt.toUtc().toIso8601String(),
      if (offline) 'offline': true,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (accuracyM != null) 'accuracy_m': accuracyM,
      if (isMocked != null) 'is_mocked': isMocked,
      if (clockProof != null) ...clockProof,
      if (type == 'remote' && durationType != null)
        'duration_type': durationType,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> checkOut() async {
    final res = await _dio.post('/attendance/checkout');
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> startBreak(
      {String breakType = 'manual', String? shiftBreakId}) async {
    final res = await _dio.post('/attendance/break/start', data: {
      'break_type': breakType,
      if (shiftBreakId != null) 'shift_break_id': shiftBreakId,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> endBreak({bool? wifiConnected}) async {
    final res = await _dio.post('/attendance/break/end',
        data: {if (wifiConnected != null) 'wifi_connected': wifiConnected});
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

  /// Remote-session approval queue (requires remote.approve).
  /// [status]: 'pending' | 'approved' | 'rejected'.
  Future<List<dynamic>> getRemoteSessions({String status = 'pending'}) async {
    final res = await _dio.get('/attendance/remote/sessions',
        queryParameters: {'status': status});
    return res.data['data'] as List;
  }

  Future<void> approveRemoteSession(String id) async {
    await _dio.put('/attendance/remote/sessions/$id/approve');
  }

  Future<void> rejectRemoteSession(String id) async {
    await _dio.put('/attendance/remote/sessions/$id/reject');
  }

  Future<Map<String, dynamic>> reportIpEvent(String ip,
      {String? ssid, bool? countAwayAsBreak, String? awayShiftBreakId}) async {
    final res = await _dio.post('/attendance/ip-event', data: {
      'ip': ip,
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
    return AttendanceClock.attachAnchor(
        (res.data['data'] as Map).cast<String, dynamic>());
  }

  /// Submit a generic attendance request: 'late_arrival' | 'leave' | 'early_departure'
  Future<Map<String, dynamic>> submitAttendanceRequest({
    required String type, // 'late_arrival' | 'leave' | 'early_departure'
    required String date, // yyyy-MM-dd
    required String reason,
    String? expectedTime, // HH:mm – for late_arrival
    String? leaveType, // e.g. 'annual', 'sick' – for leave
    String? leaveStartTime, // HH:mm – for mid-shift leave
    String? leaveEndTime, // HH:mm – for mid-shift leave
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
        'end_date': date,
        'reason': reason,
        if (leaveStartTime != null) 'leave_start_time': leaveStartTime,
        if (leaveEndTime != null) 'leave_end_time': leaveEndTime,
      });
      return res.data['data'] as Map<String, dynamic>;
    }
    // early_departure — stored as a late notice with a special type tag until a
    // dedicated endpoint exists.
    final res = await _dio.post('/attendance/late-notice', data: {
      'date': date,
      'expected_time': expectedTime ?? '17:00',
      'reason': '[Early Departure] $reason',
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  // ─── Attendance Corrections ───────────────────────
  /// Requests a correction of a past day's times ("forgot to check out").
  /// [requestedCheckIn]/[requestedCheckOut] are ISO 8601 with offset;
  /// at least one must be provided. [reason] must be 5+ characters.
  Future<Map<String, dynamic>> submitCorrection({
    required String date, // yyyy-MM-dd
    String? requestedCheckIn,
    String? requestedCheckOut,
    required String reason,
  }) async {
    final res = await _dio.post('/attendance/corrections', data: {
      'date': date,
      if (requestedCheckIn != null) 'requested_check_in': requestedCheckIn,
      if (requestedCheckOut != null) 'requested_check_out': requestedCheckOut,
      'reason': reason,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> getMyCorrections() async {
    final res = await _dio.get('/attendance/corrections/me');
    return res.data['data'] as List;
  }

  /// Org correction queue (requires attendance.override).
  /// [status]: 'pending' | 'approved' | 'rejected' | 'all'.
  Future<List<dynamic>> getCorrections({String status = 'pending'}) async {
    final res = await _dio
        .get('/attendance/corrections', queryParameters: {'status': status});
    return res.data['data'] as List;
  }

  Future<Map<String, dynamic>> approveCorrection(String id,
      {String? note}) async {
    final res = await _dio.put('/attendance/corrections/$id/approve', data: {
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> rejectCorrection(String id,
      {String? note}) async {
    final res = await _dio.put('/attendance/corrections/$id/reject', data: {
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  /// Rolling lateness totals + policy points (requires attendance.view_team):
  /// `{window_days, policy_configured, users: [...]}`.
  Future<Map<String, dynamic>> getLateSummary() async {
    final res = await _dio.get('/attendance/late-summary');
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
      'date': date,
      'expected_time': expectedTime,
      'reason': reason,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> getMyLateNotices({int days = 7}) async {
    final res = await _dio
        .get('/attendance/late-notice/me', queryParameters: {'days': days});
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

  // ─── Org ──────────────────────────────────────────
  /// Who's away for a date range (defaults to today server-side):
  /// `{on_leave: [...], remote: [...], holidays: ['yyyy-MM-dd', ...]}`.
  Future<Map<String, dynamic>> getWhosOut({String? from, String? to}) async {
    final res = await _dio.get('/org/whos-out', queryParameters: {
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  // ─── Shifts ───────────────────────────────────────
  Future<List<dynamic>> getMyShifts() async {
    final res = await _dio.get('/shifts/assignments/me');
    return res.data['data'] as List;
  }

  Future<List<dynamic>> getShiftTemplates() async {
    final res = await _dio.get('/shifts');
    return res.data['data'] as List;
  }

  Future<Map<String, dynamic>> assignShift({
    required String userId,
    required String shiftId,
    required String date,
  }) async {
    final res = await _dio.post('/shifts/assignments', data: {
      'user_id': userId,
      'shift_id': shiftId,
      'date': date,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> bulkAssignShifts(
      List<Map<String, dynamic>> assignments,
      {bool dryRun = false}) async {
    final res = await _dio.post('/shifts/assignments/bulk', data: {
      'assignments': assignments,
      'dry_run': dryRun,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getShiftAssignmentDetail(
      String assignmentId) async {
    final res = await _dio.get('/shifts/assignments/$assignmentId/detail');
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> getOpenShiftOffers() async {
    final res = await _dio.get('/shifts/open-shifts');
    return res.data['data'] as List;
  }

  Future<Map<String, dynamic>> claimOpenShift(String offerId) async {
    final res = await _dio.post('/shifts/open-shifts/$offerId/claim');
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<void> cancelOpenShiftOffer(String offerId) async {
    await _dio.post('/shifts/open-shifts/$offerId/cancel');
  }

  Future<Map<String, dynamic>> createOpenShiftOffer({
    required String shiftId,
    required String date,
    required int expiresInMinutes,
    String? note,
  }) async {
    final res = await _dio.post('/shifts/open-shifts', data: {
      'shift_id': shiftId,
      'date': date,
      'expires_in_minutes': expiresInMinutes,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> getAssignmentCheckpoints(String assignmentId) async {
    final res = await _dio.get('/shifts/assignments/$assignmentId/checkpoints');
    return res.data['data']['checkpoints'] as List;
  }

  Future<Map<String, dynamic>> scanShiftCheckpoint({
    required String assignmentId,
    required String qrCode,
    double? latitude,
    double? longitude,
    double? accuracyM,
  }) async {
    final res = await _dio.post('/shifts/checkpoints/scan', data: {
      'assignment_id': assignmentId,
      'qr_code': qrCode,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (accuracyM != null) 'accuracy_m': accuracyM,
    });
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

  /// Org overtime queue (requires overtime.manage).
  /// [status]: 'pending' | 'approved' | 'rejected'.
  Future<List<dynamic>> getOvertimeRequests({String status = 'pending'}) async {
    final res = await _dio
        .get('/overtime/requests', queryParameters: {'status': status});
    return res.data['data'] as List;
  }

  Future<Map<String, dynamic>> approveOvertime(String id) async {
    final res = await _dio.put('/overtime/requests/$id/approve');
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> rejectOvertime(String id, String reason) async {
    final res = await _dio
        .put('/overtime/requests/$id/reject', data: {'reason': reason});
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> getSwapRequests() async {
    final res = await _dio.get('/shifts/swaps/me');
    return res.data['data'] as List;
  }

  /// Org-wide assignments for the 7-day window starting [weekStart]
  /// (yyyy-MM-dd). Requires shifts.view — employees without it get a 403.
  Future<List<dynamic>> getOrgSchedule({String? weekStart}) async {
    final res = await _dio.get('/shifts/schedule', queryParameters: {
      if (weekStart != null) 'week_start': weekStart,
    });
    return res.data['data'] as List;
  }

  Future<List<dynamic>> getMyShiftAvailability() async {
    final res = await _dio.get('/shifts/planning/availability/me');
    return res.data['data'] as List;
  }

  Future<Map<String, dynamic>> requestShiftAvailability(
      Map<String, dynamic> data) async {
    final res = await _dio.post('/shifts/planning/availability', data: data);
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<void> cancelShiftAvailability(String id) async {
    await _dio.delete('/shifts/planning/availability/$id');
  }

  Future<List<dynamic>> getTeamShiftAvailability(
      {String status = 'pending'}) async {
    final res = await _dio.get('/shifts/planning/availability',
        queryParameters: {'status': status});
    return res.data['data'] as List;
  }

  Future<void> reviewShiftAvailability(String id,
      {required String status, String? reason}) async {
    await _dio.put('/shifts/planning/availability/$id/review',
        data: {'status': status, if (reason != null) 'review_note': reason});
  }

  Future<Map<String, dynamic>> getShiftPlanningIssues(String weekStart) async {
    final res = await _dio.get('/shifts/planning/issues',
        queryParameters: {'week_start': weekStart});
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> getShiftWorkload(String weekStart) async {
    final res = await _dio.get('/shifts/planning/workload',
        queryParameters: {'week_start': weekStart});
    return res.data['data'] as List;
  }

  Future<List<dynamic>> getShiftCoverageRules() async {
    final res = await _dio.get('/shifts/planning/coverage');
    return res.data['data'] as List;
  }

  Future<List<dynamic>> saveShiftCoverageRules(
      List<Map<String, dynamic>> rules) async {
    final res =
        await _dio.put('/shifts/planning/coverage', data: {'rules': rules});
    return res.data['data'] as List;
  }

  Future<Map<String, dynamic>> copyShiftWeek(String from, String to) async {
    final res = await _dio.post('/shifts/planning/copy-week',
        data: {'from_week_start': from, 'to_week_start': to});
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> publishShiftWeek(String from, String to) async {
    final res = await _dio.post('/shifts/schedule/publish',
        data: {'from_date': from, 'to_date': to});
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> getShiftScheduleHistory({int limit = 100}) async {
    final res = await _dio
        .get('/shifts/planning/history', queryParameters: {'limit': limit});
    return res.data['data'] as List;
  }

  Future<List<int>> exportShiftCalendar(String from, String to) async {
    final res = await _dio.get<List<int>>('/shifts/planning/export.ics',
        queryParameters: {'from': from, 'to': to},
        options: Options(responseType: ResponseType.bytes));
    return res.data ?? <int>[];
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

  // ─── Expenses ─────────────────────────────────────
  /// Submits an expense claim. [expenseDate] is yyyy-MM-dd and must not be in
  /// the future; [currency] defaults to the org currency server-side.
  Future<Map<String, dynamic>> submitExpense({
    required double amount,
    required String category,
    required String description,
    required String expenseDate, // yyyy-MM-dd
    String? currency,
    String? receiptUrl,
  }) async {
    final res = await _dio.post('/expenses', data: {
      'amount': amount,
      'category': category,
      'description': description,
      'expense_date': expenseDate,
      if (currency != null && currency.isNotEmpty) 'currency': currency,
      if (receiptUrl != null && receiptUrl.isNotEmpty)
        'receipt_url': receiptUrl,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  /// Own expense claims, newest first.
  Future<List<dynamic>> getMyExpenses() async {
    final res = await _dio.get('/expenses/me');
    return res.data['data'] as List;
  }

  /// Org expense queue (requires expenses.view).
  /// [status]: 'pending' | 'approved' | 'rejected' | 'reimbursed' | 'all'.
  Future<List<dynamic>> getExpenses({String status = 'pending'}) async {
    final res =
        await _dio.get('/expenses', queryParameters: {'status': status});
    return res.data['data'] as List;
  }

  Future<Map<String, dynamic>> approveExpense(String id, {String? note}) async {
    final res = await _dio.put('/expenses/$id/approve', data: {
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> rejectExpense(String id, {String? note}) async {
    final res = await _dio.put('/expenses/$id/reject', data: {
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  // ─── Documents ────────────────────────────────────
  /// Own document-vault entries (contracts, IDs, visas, …), newest first.
  Future<List<dynamic>> getMyDocuments() async {
    final res = await _dio.get('/documents/me');
    return res.data['data'] as List;
  }

  /// 15-minute presigned link for a document:
  /// `{download_url, file_name, mime_type, expires_in}`.
  Future<Map<String, dynamic>> getDocumentDownload(String id) async {
    final res = await _dio.get('/documents/$id/download');
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

  // ─── Announcements ────────────────────────────────
  /// Published announcements targeted at me (org-wide + my department),
  /// newest first; each row carries `my_read_at`.
  Future<List<dynamic>> getAnnouncements() async {
    final res = await _dio.get('/performance/announcements');
    return res.data['data'] as List;
  }

  /// Records my read receipt. Idempotent server-side — re-reading keeps
  /// the original read_at.
  Future<void> markAnnouncementRead(String id) async {
    await _dio.post('/performance/announcements/$id/read');
  }

  // ─── Onboarding ───────────────────────────────────
  /// Onboarding tasks assigned to me (own onboarding and, for managers,
  /// manager-side items for their hires) — pending first.
  Future<List<dynamic>> getMyOnboardingTasks() async {
    final res = await _dio.get('/onboarding/me');
    return res.data['data'] as List;
  }

  /// Marks a pending task done. 400 INVALID_STATUS if it isn't pending.
  Future<Map<String, dynamic>> completeOnboardingTask(String id) async {
    final res = await _dio.put('/onboarding/tasks/$id/complete');
    return res.data['data'] as Map<String, dynamic>;
  }

  /// Marks a pending task skipped. 400 INVALID_STATUS if it isn't pending.
  Future<Map<String, dynamic>> skipOnboardingTask(String id) async {
    final res = await _dio.put('/onboarding/tasks/$id/skip');
    return res.data['data'] as Map<String, dynamic>;
  }

  // ─── Kudos ────────────────────────────────────────
  /// Org-wide recognition feed, newest first (latest 100 without paging).
  Future<List<dynamic>> getKudosFeed() async {
    final res = await _dio.get('/kudos');
    return res.data['data'] as List;
  }

  /// My counters and recent recognitions:
  /// `{received, given, recent_received: [...]}`.
  Future<Map<String, dynamic>> getMyKudos() async {
    final res = await _dio.get('/kudos/mine');
    return res.data['data'] as Map<String, dynamic>;
  }

  /// Sends kudos (message 3–500 chars). 429 RATE_LIMITED at 20/day,
  /// 422 for self-kudos.
  Future<Map<String, dynamic>> giveKudos({
    required String toUserId,
    required String message,
    String? emoji,
  }) async {
    final res = await _dio.post('/kudos', data: {
      'to_user_id': toUserId,
      'message': message,
      if (emoji != null && emoji.isNotEmpty) 'emoji': emoji,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  /// Org member list (requires employees.view or employees.view_team —
  /// plain employees get a 403; callers must handle the fallback).
  Future<List<dynamic>> getOrgMembers({String? q}) async {
    final res = await _dio.get('/users', queryParameters: {
      'limit': 100,
      'status': 'active',
      if (q != null && q.isNotEmpty) 'q': q,
    });
    return res.data['data'] as List;
  }

  // ─── Projects ─────────────────────────────────────
  Future<List<dynamic>> getProjects() async {
    final res = await _dio.get('/projects');
    return res.data['data'] as List;
  }

  Future<Map<String, dynamic>> createProject(Map<String, dynamic> data) async {
    final res = await _dio.post('/projects', data: data);
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateProject(
      String id, Map<String, dynamic> data) async {
    final res = await _dio.put('/projects/$id', data: data);
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> addProjectMember(
      String id, String userId) async {
    final res =
        await _dio.post('/projects/$id/members', data: {'user_id': userId});
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createProjectTask(
      String projectId, Map<String, dynamic> data) async {
    final res = await _dio.post('/projects/$projectId/tasks', data: data);
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateProjectTask(
      String taskId, Map<String, dynamic> data) async {
    final res = await _dio.put('/projects/tasks/$taskId', data: data);
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> addProjectTaskComment(
      String taskId, String body) async {
    final res = await _dio
        .post('/projects/tasks/$taskId/comments', data: {'body': body});
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getProjectAttachmentUploadUrl(
      String projectId, Map<String, dynamic> data) async {
    final res = await _dio.post('/projects/$projectId/attachments/upload-url',
        data: data);
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> uploadProjectAttachmentLocal({
    required String projectId,
    required String fileName,
    required String mimeType,
    required List<int> bytes,
    String? taskId,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes,
          filename: fileName, contentType: DioMediaType.parse(mimeType)),
      if (taskId != null) 'task_id': taskId,
    });
    final res = await _dio.post('/projects/$projectId/attachments/upload-local',
        data: form, options: Options(contentType: 'multipart/form-data'));
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<void> uploadProjectAttachmentSigned({
    required String uploadUrl,
    required String mimeType,
    required List<int> bytes,
  }) async {
    // Signed storage URLs must not receive the Attenda bearer token.
    await Dio().put(uploadUrl,
        data: Uint8List.fromList(bytes),
        options: Options(headers: {'Content-Type': mimeType}));
  }

  Future<Map<String, dynamic>> registerProjectAttachment(
      String projectId, Map<String, dynamic> data) async {
    final res = await _dio.post('/projects/$projectId/attachments', data: data);
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getProjectAttachmentDownload(
      String attachmentId) async {
    final res = await _dio.get('/projects/attachments/$attachmentId/download');
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> getProjectActivity(String projectId) async {
    final res = await _dio.get('/projects/$projectId/activity');
    return res.data['data'] as List;
  }

  Future<List<int>> downloadLocalProjectAttachment(String attachmentId) async {
    final res = await _dio.get<List<int>>(
        '/projects/attachments/$attachmentId/file',
        options: Options(responseType: ResponseType.bytes));
    return res.data ?? const [];
  }

  // ─── Notification Preferences ────────────────────
  Future<Map<String, dynamic>> getNotificationPrefs() async {
    final res = await _dio.get('/users/me/notification-prefs');
    return (res.data['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> updateNotificationPrefs(
      Map<String, bool> prefs) async {
    final res = await _dio.put('/users/me/notification-prefs', data: prefs);
    return (res.data['data'] as Map<String, dynamic>?) ?? {};
  }

  // ─── Profile ──────────────────────────────────────
  Future<Map<String, dynamic>> updateProfile(
      {String? name, String? phone}) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (phone != null) data['phone'] = phone;
    final res = await _dio.put('/users/me', data: data);
    return res.data['data'] as Map<String, dynamic>;
  }

  // ─── Change Password ──────────────────────────────
  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    await _dio.put('/auth/change-password', data: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  // ─── 2FA ──────────────────────────────────────────
  /// Completes a 2FA login challenge. Returns the same payload as /auth/login
  /// on success: {access_token, refresh_token, user}.
  Future<Map<String, dynamic>> authenticate2fa(
      String partialToken, String code) async {
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
  Future<Map<String, dynamic>> getNotifications(
      {int page = 1, int limit = 20}) async {
    final res = await _dio
        .get('/notifications', queryParameters: {'page': page, 'limit': limit});
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
