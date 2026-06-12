import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attenda/services/api_failure.dart';

DioException _badResponse(int status, {Map<String, dynamic>? body}) {
  final req = RequestOptions(path: '/x');
  return DioException(
    requestOptions: req,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: req, statusCode: status, data: body),
  );
}

void main() {
  group('ApiFailure.fromError', () {
    test('maps timeouts and connection errors', () {
      final req = RequestOptions(path: '/x');
      expect(
        ApiFailure.fromError(DioException(
            requestOptions: req, type: DioExceptionType.connectionTimeout)),
        isA<TimeoutFailure>(),
      );
      expect(
        ApiFailure.fromError(DioException(
            requestOptions: req, type: DioExceptionType.connectionError)),
        isA<NetworkFailure>(),
      );
    });

    test('maps status codes with server envelope fields', () {
      final f401 = ApiFailure.fromError(_badResponse(401,
          body: {'error': 'Invalid or expired partial token', 'code': 'INVALID_TOKEN'}));
      expect(f401, isA<UnauthorizedFailure>());
      expect(f401.serverCode, 'INVALID_TOKEN');

      expect(ApiFailure.fromError(_badResponse(423)), isA<AccountLockedFailure>());
      expect(ApiFailure.fromError(_badResponse(429)), isA<RateLimitedFailure>());
      expect(ApiFailure.fromError(_badResponse(422)), isA<ValidationFailure>());
      expect(ApiFailure.fromError(_badResponse(500)), isA<ServerFailure>());
    });

    test('validation failures surface the server message', () {
      final f = ApiFailure.fromError(_badResponse(422,
          body: {'error': 'end_date must be on or after start_date'}));
      expect(f.userMessage, 'end_date must be on or after start_date');
    });

    test('non-dio errors fall back to UnknownFailure', () {
      expect(ApiFailure.fromError(StateError('x')), isA<UnknownFailure>());
    });
  });
}
