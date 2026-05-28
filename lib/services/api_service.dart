import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:5000/api/v1');
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

  Future<Map<String, dynamic>> reportIpEvent(String ip, bool connected) async {
    final res = await _dio.post('/attendance/ip-event', data: {'ip': ip, 'event': connected ? 'match' : 'unmatch'});
    return res.data['data'] as Map<String, dynamic>;
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
    final res = await _dio.get('/performance/reviews');
    return res.data['data'] as List;
  }

  Future<List<dynamic>> getMyGoals() async {
    final res = await _dio.get('/performance/goals');
    return res.data['data'] as List;
  }
}

final api = ApiService();
