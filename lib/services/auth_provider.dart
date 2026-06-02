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
  final String? phone;
  final bool totpEnabled;

  const AuthUser({
    required this.id,
    required this.orgId,
    required this.role,
    required this.name,
    required this.email,
    this.phone,
    this.totpEnabled = false,
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
      String? token = await _storage.read(key: 'access_token');

      if (token != null && JwtDecoder.isExpired(token)) {
        // Try to refresh before giving up
        final refresh = await _storage.read(key: 'refresh_token');
        if (refresh != null) {
          try {
            final data = await api.refreshToken(refresh);
            token = data['access_token'] as String?;
            if (token != null) {
              await _storage.write(key: 'access_token', value: token);
              final newRefresh = data['refresh_token'] as String?;
              if (newRefresh != null) await _storage.write(key: 'refresh_token', value: newRefresh);
            }
          } catch (_) {
            token = null;
            await _storage.deleteAll();
          }
        } else {
          token = null;
        }
      }

      if (token != null && !JwtDecoder.isExpired(token)) {
        final claims = JwtDecoder.decode(token);
        _user = AuthUser(
          id: claims['sub'] as String,
          orgId: claims['org_id'] as String,
          role: claims['role'] as String,
          name: claims['name'] as String,
          email: claims['email'] as String,
        );
        // Fetch profile data to populate phone + totpEnabled
        try {
          final me = await api.getMe();
          _user = AuthUser(
            id: _user!.id,
            orgId: _user!.orgId,
            role: _user!.role,
            name: me['name'] as String? ?? _user!.name,
            email: _user!.email,
            phone: me['phone'] as String?,
            totpEnabled: me['totp_enabled'] as bool? ?? false,
          );
        } catch (_) {}
      }
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  Future<void> refreshUser() async {
    try {
      final me = await api.getMe();
      if (_user == null) return;
      _user = AuthUser(
        id: _user!.id,
        orgId: _user!.orgId,
        role: _user!.role,
        name: me['name'] as String? ?? _user!.name,
        email: _user!.email,
        phone: me['phone'] as String?,
        totpEnabled: me['totp_enabled'] as bool? ?? false,
      );
      notifyListeners();
    } catch (_) {}
  }

  // Returns null on success, or the temp_token string if 2FA is required.
  Future<String?> login(String email, String password) async {
    final data = await api.login(email, password);

    if (data['requires_2fa'] == true) {
      return data['temp_token'] as String?;
    }

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
    // Fetch profile data to populate phone + totpEnabled
    try {
      final me = await api.getMe();
      _user = AuthUser(
        id: _user!.id,
        orgId: _user!.orgId,
        role: _user!.role,
        name: me['name'] as String? ?? _user!.name,
        email: _user!.email,
        phone: me['phone'] as String?,
        totpEnabled: me['totp_enabled'] as bool? ?? false,
      );
      notifyListeners();
    } catch (_) {}
    return null;
  }

  Future<void> logout() async {
    await api.logout();
    _user = null;
    notifyListeners();
  }
}
