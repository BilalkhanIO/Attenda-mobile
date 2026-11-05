import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Android Keystore backed P-256 signing keys used to prove device-key
/// possession during enrollment. Private key material never enters Dart.
class AttendanceDeviceKeys {
  static const _channel = MethodChannel('app.attenda/attendance_device_keys');
  static const _storage = FlutterSecureStorage();

  static String _deviceAliasKey(String userId, String deviceId) =>
      'attendance_device_alias_${userId}_$deviceId';
  static String _deviceIdsKey(String userId) => 'attendance_device_ids_$userId';
  static String _challengeKey(String userId, String deviceId) =>
      'attendance_checkin_challenge_${userId}_$deviceId';
  static String _pendingProofKey(String idempotencyKey) =>
      'attendance_pending_proof_$idempotencyKey';

  String _newAlias() {
    final random = Random.secure();
    return 'attenda-${List<int>.generate(16, (_) => random.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  Future<({String alias, String publicKey})> createKey() async {
    final alias = _newAlias();
    final publicKey =
        await _channel.invokeMethod<String>('generate', {'alias': alias});
    if (publicKey == null || publicKey.isEmpty) {
      throw PlatformException(
          code: 'UNSUPPORTED',
          message:
              'Secure attendance device enrollment is available on supported Android devices.');
    }
    return (alias: alias, publicKey: publicKey);
  }

  Future<String> signChallenge(String alias, String challenge) async {
    final signature = await _channel
        .invokeMethod<String>('sign', {'alias': alias, 'message': challenge});
    if (signature == null || signature.isEmpty) {
      throw PlatformException(
          code: 'SIGN_FAILED', message: 'Could not verify this device key.');
    }
    return signature;
  }

  Future<String?> signForEnrolledDevice({
    required String userId,
    required String deviceId,
    required String message,
  }) async {
    final alias = await _storage.read(key: _deviceAliasKey(userId, deviceId));
    if (alias == null) return null;
    return signChallenge(alias, message);
  }

  Future<void> rememberEnrollment(
      String userId, String deviceId, String alias) async {
    await _storage.write(key: _deviceAliasKey(userId, deviceId), value: alias);
    final current = await enrolledDeviceIds(userId);
    if (!current.contains(deviceId)) {
      await _storage.write(
          key: _deviceIdsKey(userId),
          value: jsonEncode([...current, deviceId]));
    }
  }

  Future<List<String>> enrolledDeviceIds(String userId) async {
    final raw = await _storage.read(key: _deviceIdsKey(userId));
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> storeCheckinChallenge(
          String userId, String deviceId, Map<String, dynamic> challenge) =>
      _storage.write(
          key: _challengeKey(userId, deviceId), value: jsonEncode(challenge));

  Future<Map<String, dynamic>?> readCheckinChallenge(
      String userId, String deviceId) async {
    final raw = await _storage.read(key: _challengeKey(userId, deviceId));
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      await _storage.delete(key: _challengeKey(userId, deviceId));
      return null;
    }
  }

  Future<void> clearCheckinChallenge(String userId, String deviceId) =>
      _storage.delete(key: _challengeKey(userId, deviceId));

  Future<void> storePendingProof(
          String idempotencyKey, Map<String, String> proof) =>
      _storage.write(
          key: _pendingProofKey(idempotencyKey), value: jsonEncode(proof));

  Future<Map<String, dynamic>?> takePendingProof(String idempotencyKey) async {
    final key = _pendingProofKey(idempotencyKey);
    final raw = await _storage.read(key: key);
    await _storage.delete(key: key);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> discardPendingProof(String idempotencyKey) =>
      _storage.delete(key: _pendingProofKey(idempotencyKey));

  Future<void> clearIfRevoked(String userId, String deviceId) async {
    final key = _deviceAliasKey(userId, deviceId);
    final alias = await _storage.read(key: key);
    if (alias != null) {
      try {
        await _channel.invokeMethod<void>('delete', {'alias': alias});
      } on PlatformException {/* server revocation remains authoritative */}
    }
    await _storage.delete(key: key);
    final ids = await enrolledDeviceIds(userId);
    ids.remove(deviceId);
    await _storage.write(key: _deviceIdsKey(userId), value: jsonEncode(ids));
  }
}
