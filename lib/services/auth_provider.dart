import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../services/api_service.dart';

class AuthUser {
  final String id;
  final String orgId;
  final String role;
  final String name;
  final String email;

  const AuthUser({
    required this.id,
    required this.orgId,
    required this.role,
    required this.name,
    required this.email,
  });

  bool get isManager    => role == 'manager' || role == 'hr_admin' || role == 'super_admin';
  bool get isHRAdmin    => role == 'hr_admin' || role == 'super_admin';
  bool get isSuperAdmin => role == 'super_admin';
}

class AuthProvider extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();

  AuthUser? _user;
  bool _loading = true;

  AuthUser? get user     => _user;
  bool get isLoading     => _loading;
  bool get isAuthenticated => _user != null;

  AuthProvider() { _init(); }

  Future<void> _init() async {
    try {
      final token = await _storage.read(key: 'access_token');
      if (token != null && !JwtDecoder.isExpired(token)) {
        final claims = JwtDecoder.decode(token);
        _user = AuthUser(
          id: claims['sub'] as String,
          orgId: claims['org_id'] as String,
          role: claims['role'] as String,
          name: claims['name'] as String,
          email: claims['email'] as String,
        );
      }
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final data = await api.login(email, password);
    await _storage.write(key: 'access_token',  value: data['access_token'] as String);
    await _storage.write(key: 'refresh_token', value: data['refresh_token'] as String);

    final token  = data['access_token'] as String;
    final claims = JwtDecoder.decode(token);
    _user = AuthUser(
      id: claims['sub'] as String,
      orgId: claims['org_id'] as String,
      role: claims['role'] as String,
      name: claims['name'] as String,
      email: claims['email'] as String,
    );
    notifyListeners();
  }

  Future<void> logout() async {
    await api.logout();
    _user = null;
    notifyListeners();
  }
}
