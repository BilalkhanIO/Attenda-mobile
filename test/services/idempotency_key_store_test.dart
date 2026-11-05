import 'package:flutter_test/flutter_test.dart';
import 'package:attenda/services/idempotency_key_store.dart';

void main() {
  group('IdempotencyKeyStore', () {
    late Map<String, String> values;
    late DateTime now;
    var sequence = 0;

    IdempotencyKeyStore createStore() => IdempotencyKeyStore(
          read: (key) async => values[key],
          write: (key, value) async {
            values[key] = value;
          },
          delete: (key) async {
            values.remove(key);
          },
          readAll: () async => Map<String, String>.from(values),
          generateKey: () => 'generated-${++sequence}',
          clock: () => now,
        );

    setUp(() {
      values = {};
      now = DateTime.utc(2026, 11, 3, 12);
      sequence = 0;
    });

    test('reuses an ambiguous request key after store recreation', () async {
      final request = {
        'identity': 'org-a:user-a',
        'method': 'POST',
        'path': '/leave/requests',
        'query': const <String, Object?>{},
        'body': {'leave_type': 'annual', 'start_date': '2026-11-10'},
      };
      final first = await createStore().resolve(
        identity: request['identity']! as String,
        method: request['method']! as String,
        path: request['path']! as String,
        query: request['query'],
        body: request['body'],
      );
      final retry = await createStore().resolve(
        identity: request['identity']! as String,
        method: request['method']! as String,
        path: request['path']! as String,
        query: request['query'],
        body: request['body'],
      );

      expect(retry.key, first.key);
      expect(retry.storageKey, first.storageKey);
    });

    test('coalesces concurrent resolutions for the same operation', () async {
      final store = createStore();
      final results = await Future.wait([
        store.resolve(
          identity: 'org-a:user-a',
          method: 'POST',
          path: '/expenses',
          query: const {},
          body: {'amount': 10},
        ),
        store.resolve(
          identity: 'org-a:user-a',
          method: 'POST',
          path: '/expenses',
          query: const {},
          body: {'amount': 10},
        ),
      ]);

      expect(results[0].key, results[1].key);
      expect(sequence, 1);
    });

    test('separates different payloads and starts a fresh key after success',
        () async {
      final store = createStore();
      final first = await store.resolve(
        identity: 'org-a:user-a',
        method: 'POST',
        path: '/projects',
        query: const {},
        body: {'name': 'Alpha'},
      );
      final different = await store.resolve(
        identity: 'org-a:user-a',
        method: 'POST',
        path: '/projects',
        query: const {},
        body: {'name': 'Beta'},
      );
      await store.clear(first.storageKey);
      final nextOperation = await store.resolve(
        identity: 'org-a:user-a',
        method: 'POST',
        path: '/projects',
        query: const {},
        body: {'name': 'Alpha'},
      );

      expect(different.key, isNot(first.key));
      expect(nextOperation.key, isNot(first.key));
    });

    test('canonicalizes nested map key order and omits the idempotency field',
        () {
      String fingerprint(Object? body) =>
          IdempotencyKeyStore.requestFingerprint(
            identity: 'org-a:user-a',
            method: 'POST',
            path: '/time/entries',
            query: const {},
            body: body,
          );

      expect(
        fingerprint({
          'idempotency_key': 'old-key',
          'entry': {'a': 1, 'b': 2},
        }),
        fingerprint({
          'entry': {'b': 2, 'a': 1},
          'idempotency_key': 'new-key',
        }),
      );
      expect(
          fingerprint({
            'entry': {'a': 1}
          }),
          isNot(fingerprint({
            'entry': {'a': 2}
          })));
    });

    test('expires saved keys after the server retention interval', () async {
      final store = createStore();
      final first = await store.resolve(
        identity: 'org-a:user-a',
        method: 'POST',
        path: '/expenses',
        query: const {},
        body: {'amount': 10},
      );
      now = now.add(const Duration(hours: 25));
      final afterExpiry = await store.resolve(
        identity: 'org-a:user-a',
        method: 'POST',
        path: '/expenses',
        query: const {},
        body: {'amount': 10},
      );

      expect(afterExpiry.key, isNot(first.key));
      expect(values.length, 1);
    });
  });
}
