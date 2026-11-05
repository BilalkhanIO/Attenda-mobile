import 'package:dio/dio.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'idempotency_key_store.dart';

const _pendingIdempotencyMarker = 'attenda-pending';

/// Adds a stable key to writes and keeps it when the transport outcome is
/// ambiguous. Authentication is read from the Authorization header attached
/// by the preceding auth interceptor, so retries use the current user token.
class RequestIdempotencyInterceptor extends Interceptor {
  RequestIdempotencyInterceptor({
    required IdempotencyKeyStore store,
    required String Function() generateKey,
  })  : _store = store,
        _generateKey = generateKey;

  final IdempotencyKeyStore _store;
  final String Function() _generateKey;

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      await _prepare(options);
    } catch (_) {
      // Storage/crypto failure should not block the requested operation. The
      // fallback protects this attempt only; it cannot promise retry reuse.
      final supplied = options.headers['Idempotency-Key'];
      if (supplied == null || supplied == _pendingIdempotencyMarker) {
        options.headers['Idempotency-Key'] = _generateKey();
      }
    }
    handler.next(options);
  }

  Future<void> _prepare(RequestOptions options) async {
    if (!const {'POST', 'PUT', 'PATCH', 'DELETE'}
        .contains(options.method.toUpperCase())) {
      return;
    }
    final path = options.path;
    final multipart = options.data is FormData;
    final multipartFingerprint = options.extra['_attenda_idempotency_body'];
    final authIdempotencyEnabled = options.extra['_attenda_idempotency_auth'] == true;
    if ((path.startsWith('/auth/') && !authIdempotencyEnabled) ||
        path == '/attendance/sync' ||
        path == '/attendance/heartbeat' ||
        path == '/attendance/ip-event' ||
        path.startsWith('/ai/') ||
        path == '/webhooks/whatsapp' ||
        (multipart && multipartFingerprint == null)) {
      return;
    }

    final headers = options.headers;
    final headerKey = headers['Idempotency-Key']?.toString();
    final body = multipart ? multipartFingerprint : options.data;
    final bodyKey = body is Map ? body['idempotency_key']?.toString() : null;
    final markerUsed = headerKey == _pendingIdempotencyMarker ||
        bodyKey == _pendingIdempotencyMarker;
    if (!markerUsed &&
        (headerKey?.isNotEmpty == true || bodyKey?.isNotEmpty == true)) {
      return;
    }

    var identity = 'anonymous';
    final authorization = headers['Authorization']?.toString();
    if (authorization?.startsWith('Bearer ') == true) {
      try {
        final claims = JwtDecoder.decode(authorization!.substring(7));
        identity = '${claims['org_id'] ?? ''}:${claims['sub'] ?? ''}';
      } catch (_) {/* keep the anonymous storage namespace */}
    }
    final resolution = await _store.resolve(
      identity: identity,
      method: options.method,
      path: path,
      query: options.queryParameters,
      body: body,
    );
    options.extra['_attenda_idempotency_storage_key'] = resolution.storageKey;
    headers['Idempotency-Key'] = resolution.key;
    if (body is Map && bodyKey == _pendingIdempotencyMarker) {
      options.data = {...body, 'idempotency_key': resolution.key};
    }
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    await _clear(response.requestOptions);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    final body = err.response?.data;
    final code = body is Map ? body['code']?.toString() : null;
    if (status != null &&
        status < 500 &&
        status != 401 &&
        code != 'IDEMPOTENCY_OUTCOME_UNKNOWN' &&
        code != 'IDEMPOTENCY_REQUEST_IN_PROGRESS') {
      await _clear(err.requestOptions);
    }
    handler.next(err);
  }

  Future<void> _clear(RequestOptions options) async {
    final key = options.extra['_attenda_idempotency_storage_key']?.toString();
    if (key == null) return;
    try {
      await _store.clear(key);
      options.extra.remove('_attenda_idempotency_storage_key');
    } catch (_) {/* preserve the original HTTP result */}
  }
}
