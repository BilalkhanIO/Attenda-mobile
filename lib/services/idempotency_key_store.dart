import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storagePrefix = 'attenda_idempotency_v1_';
const _retention = Duration(hours: 24);

typedef IdempotencyKeyResolution = ({String key, String storageKey});

/// Persists request keys only while a write's outcome is ambiguous. The
/// fingerprint contains no raw request data, and the key expires with the
/// server's 24-hour idempotency record.
class IdempotencyKeyStore {
  IdempotencyKeyStore({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
    required Future<void> Function(String key) delete,
    required Future<Map<String, String>> Function() readAll,
    required String Function() generateKey,
    DateTime Function()? clock,
  })  : _read = read,
        _write = write,
        _delete = delete,
        _readAll = readAll,
        _generateKey = generateKey,
        _clock = clock ?? DateTime.now;

  factory IdempotencyKeyStore.secure(FlutterSecureStorage storage,
          {required String Function() generateKey}) =>
      IdempotencyKeyStore(
        read: (key) => storage.read(key: key),
        write: (key, value) => storage.write(key: key, value: value),
        delete: (key) => storage.delete(key: key),
        readAll: storage.readAll,
        generateKey: generateKey,
      );

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;
  final Future<void> Function(String key) _delete;
  final Future<Map<String, String>> Function() _readAll;
  final String Function() _generateKey;
  final DateTime Function() _clock;
  final Map<String, Future<IdempotencyKeyResolution>> _inFlight = {};

  Future<IdempotencyKeyResolution> resolve({
    required String identity,
    required String method,
    required String path,
    required Object? query,
    required Object? body,
  }) {
    final fingerprint = requestFingerprint(
      identity: identity,
      method: method,
      path: path,
      query: query,
      body: body,
    );
    final storageKey = '$_storagePrefix$fingerprint';
    final pending = _inFlight[fingerprint];
    if (pending != null) return pending;
    final resolution = _resolveStoredKey(storageKey);
    _inFlight[fingerprint] = resolution;
    return resolution.whenComplete(() {
      if (identical(_inFlight[fingerprint], resolution)) {
        _inFlight.remove(fingerprint);
      }
    });
  }

  Future<IdempotencyKeyResolution> _resolveStoredKey(String storageKey) async {
    final now = _clock().millisecondsSinceEpoch;

    for (final entry in (await _readAll()).entries) {
      if (!entry.key.startsWith(_storagePrefix)) continue;
      try {
        final saved = jsonDecode(entry.value) as Map<String, dynamic>;
        final createdAt = saved['created_at'] as int?;
        if (createdAt == null || now - createdAt >= _retention.inMilliseconds) {
          await _delete(entry.key);
        }
      } catch (_) {
        await _delete(entry.key);
      }
    }

    String? key;
    final previous = await _read(storageKey);
    if (previous != null) {
      try {
        final saved = jsonDecode(previous) as Map<String, dynamic>;
        final createdAt = saved['created_at'] as int?;
        final savedKey = saved['key'] as String?;
        if (createdAt != null &&
            savedKey != null &&
            now - createdAt < _retention.inMilliseconds) {
          key = savedKey;
        }
      } catch (_) {
        // Replace malformed storage entries with a fresh operation key.
      }
    }
    key ??= _generateKey();
    await _write(storageKey, jsonEncode({'key': key, 'created_at': now}));
    return (key: key, storageKey: storageKey);
  }

  Future<void> clear(String storageKey) async {
    if (storageKey.startsWith(_storagePrefix)) await _delete(storageKey);
  }

  static String requestFingerprint({
    required String identity,
    required String method,
    required String path,
    required Object? query,
    required Object? body,
  }) {
    final normalizedBody = body is Map
        ? Map<String, dynamic>.from(
            body.map((key, value) => MapEntry(key.toString(), value)))
        : body;
    if (normalizedBody is Map) normalizedBody.remove('idempotency_key');
    final canonical = jsonEncode(_stableValue({
      'identity': identity,
      'method': method.toUpperCase(),
      'path': path,
      'query': query,
      'body': normalizedBody,
    }));
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static dynamic _stableValue(dynamic value) {
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map) {
      final entries = value.entries
          .map((entry) => MapEntry(entry.key.toString(), entry.value))
          .toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      return {
        for (final entry in entries) entry.key: _stableValue(entry.value),
      };
    }
    if (value is Iterable) return value.map(_stableValue).toList();
    return value;
  }
}
