import 'dart:typed_data';

import 'package:attenda/services/idempotency_interceptor.dart';
import 'package:attenda/services/idempotency_key_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter(this.respond);
  final ResponseBody Function(RequestOptions options) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('RequestIdempotencyInterceptor transport behavior', () {
    late Map<String, String> stored;
    late int keyNumber;

    IdempotencyKeyStore createStore() => IdempotencyKeyStore(
          read: (key) async => stored[key],
          write: (key, value) async {
            stored[key] = value;
          },
          delete: (key) async {
            stored.remove(key);
          },
          readAll: () async => Map<String, String>.from(stored),
          generateKey: () => 'transport-key-${++keyNumber}',
        );

    Dio createDio(RecordingAdapter adapter) {
      final dio = Dio(BaseOptions(baseUrl: 'https://attenda.test/api/v1'));
      dio.httpClientAdapter = adapter;
      dio.interceptors.add(RequestIdempotencyInterceptor(
        store: createStore(),
        generateKey: () => 'fallback-${++keyNumber}',
      ));
      return dio;
    }

    ResponseBody json(int status, String body) => ResponseBody.fromString(
          body,
          status,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          },
        );

    setUp(() {
      stored = {};
      keyNumber = 0;
    });

    test(
        'reuses the same key after an ambiguous server failure then clears on success',
        () async {
      var calls = 0;
      final adapter = RecordingAdapter((_) {
        calls++;
        return calls == 1
            ? json(500, '{"code":"INTERNAL_ERROR"}')
            : json(200, '{"data":{"ok":true}}');
      });

      final dio = createDio(adapter);
      final body = {'leave_type': 'annual', 'start_date': '2026-11-10'};
      await expectLater(dio.post('/leave/requests', data: body),
          throwsA(isA<DioException>()));
      final firstKey = adapter.requests.first.headers['Idempotency-Key'];
      expect(firstKey, isNotNull);

      await dio.post('/leave/requests', data: body);
      expect(adapter.requests.last.headers['Idempotency-Key'], firstKey);
      expect(stored, isEmpty);
    });

    test('replaces the key after a definite client rejection', () async {
      var calls = 0;
      final adapter = RecordingAdapter((_) => ++calls == 1
          ? json(422, '{"code":"VALIDATION_ERROR"}')
          : json(200, '{"data":{"ok":true}}'));
      final dio = createDio(adapter);
      await expectLater(dio.post('/projects', data: {'name': 'Alpha'}),
          throwsA(isA<DioException>()));
      final rejectedKey = adapter.requests.first.headers['Idempotency-Key'];
      await dio.post('/projects', data: {'name': 'Alpha'});
      expect(
          adapter.requests.last.headers['Idempotency-Key'], isNot(rejectedKey));
      expect(stored, isEmpty);
    });

    test('retains keys for outcome-unknown conflicts', () async {
      var calls = 0;
      final adapter = RecordingAdapter((_) => ++calls == 1
          ? json(409, '{"code":"IDEMPOTENCY_OUTCOME_UNKNOWN"}')
          : json(200, '{"data":{"ok":true}}'));
      final dio = createDio(adapter);
      final body = {'amount': 10};
      await expectLater(
          dio.post('/expenses', data: body), throwsA(isA<DioException>()));
      final firstKey = adapter.requests.first.headers['Idempotency-Key'];
      await dio.post('/expenses', data: body);
      expect(adapter.requests.last.headers['Idempotency-Key'], firstKey);
      expect(stored, isEmpty);
    });

    test('replaces marker keys in headers and request bodies', () async {
      final adapter =
          RecordingAdapter((_) => json(200, '{"data":{"ok":true}}'));
      await createDio(adapter).post('/attendance/checkin',
          data: {'type': 'manual', 'idempotency_key': 'attenda-pending'},
          options: Options(headers: {'Idempotency-Key': 'attenda-pending'}));

      final sent = adapter.requests.single;
      expect(sent.headers['Idempotency-Key'], startsWith('transport-key-'));
      expect(sent.data['idempotency_key'], sent.headers['Idempotency-Key']);
    });

    test(
        'preserves explicit keys and skips non-opted-in auth, AI, sync, multipart writes',
        () async {
      final adapter =
          RecordingAdapter((_) => json(200, '{"data":{"ok":true}}'));
      final dio = createDio(adapter);
      await dio.post('/projects',
          data: {'name': 'Alpha'},
          options: Options(headers: {'Idempotency-Key': 'caller-key-123'}));
      await dio.post('/auth/login', data: {'email': 'a@example.com'});
      await dio.post('/ai/chat', data: {'message': 'hello'});
      await dio.post('/attendance/sync', data: {'events': []});
      await dio.post('/documents/upload',
          data: FormData.fromMap({
            'file': MultipartFile.fromBytes([1, 2, 3], filename: 'a.bin')
          }));

      expect(adapter.requests[0].headers['Idempotency-Key'], 'caller-key-123');
      for (final request in adapter.requests.skip(1)) {
        expect(request.headers['Idempotency-Key'], isNull,
            reason: request.path);
      }
    });

    test('uses secure persisted idempotency keys for opted-in auth writes', () async {
      final adapter =
          RecordingAdapter((_) => json(200, '{"data":{"ok":true}}'));
      final dio = createDio(adapter);
      await dio.post('/auth/refresh',
          data: {'refresh_token': 'refresh-secret'},
          options: Options(
            headers: {'Idempotency-Key': 'attenda-pending'},
            extra: {'_attenda_idempotency_auth': true},
          ));

      expect(adapter.requests.single.headers['Idempotency-Key'],
          startsWith('transport-key-'));
      expect(stored, isEmpty, reason: 'successful auth action clears its key');
    });

    test(
        'reuses multipart upload keys when the caller provides a content fingerprint',
        () async {
      var calls = 0;
      final adapter = RecordingAdapter((_) => ++calls == 1
          ? json(500, '{"code":"INTERNAL_ERROR"}')
          : json(200, '{"data":{"id":"attachment-1"}}'));
      final dio = createDio(adapter);
      Future<Response<dynamic>> upload() => dio.post(
            '/projects/project-1/attachments/upload-local',
            data: FormData.fromMap({
              'file': MultipartFile.fromBytes([1, 2, 3], filename: 'plan.pdf'),
              'task_id': 'task-1',
            }),
            options: Options(
              headers: {'Idempotency-Key': 'attenda-pending'},
              extra: {
                '_attenda_idempotency_body': {
                  'file_name': 'plan.pdf',
                  'file_size': 3,
                  'file_sha256': 'sha256-of-file-bytes',
                  'task_id': 'task-1',
                },
              },
            ),
          );

      await expectLater(upload(), throwsA(isA<DioException>()));
      final firstKey = adapter.requests.first.headers['Idempotency-Key'];
      await upload();
      expect(adapter.requests.last.headers['Idempotency-Key'], firstKey);
      expect(stored, isEmpty);
    });
  });
}
