import 'package:dio/dio.dart';

/// Sealed failure hierarchy for API errors. ALL DioException → user-facing
/// mapping lives here — screens must never string-match on e.toString().
sealed class ApiFailure implements Exception {
  const ApiFailure({this.serverMessage, this.serverCode});

  /// `error` field from the API envelope, when a response body was present.
  final String? serverMessage;

  /// `code` field from the API envelope (e.g. VALIDATION_ERROR, ACCOUNT_LOCKED).
  final String? serverCode;

  /// Sensible default copy for snackbars/banners.
  String get userMessage;

  static ApiFailure fromError(Object error) {
    if (error is ApiFailure) return error;
    if (error is! DioException) return const UnknownFailure();

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const TimeoutFailure();
      case DioExceptionType.connectionError:
        return const NetworkFailure();
      case DioExceptionType.cancel:
        return const CancelledFailure();
      case DioExceptionType.badResponse:
        return _fromResponse(error.response);
      case DioExceptionType.badCertificate:
        return const NetworkFailure();
      case DioExceptionType.unknown:
        // SocketException etc. surface as unknown with a nested error
        return error.error != null ? const NetworkFailure() : const UnknownFailure();
    }
  }

  static ApiFailure _fromResponse(Response<dynamic>? res) {
    final status = res?.statusCode ?? 0;
    String? message;
    String? code;
    final data = res?.data;
    if (data is Map) {
      message = data['error'] as String?;
      code = data['code'] as String?;
    }

    return switch (status) {
      401 => UnauthorizedFailure(serverMessage: message, serverCode: code),
      403 => ForbiddenFailure(serverMessage: message, serverCode: code),
      404 => NotFoundFailure(serverMessage: message, serverCode: code),
      422 || 400 => ValidationFailure(serverMessage: message, serverCode: code),
      423 => AccountLockedFailure(serverMessage: message, serverCode: code),
      429 => RateLimitedFailure(serverMessage: message, serverCode: code),
      >= 500 => ServerFailure(status, serverMessage: message, serverCode: code),
      _ => UnknownFailure(serverMessage: message, serverCode: code),
    };
  }
}

class NetworkFailure extends ApiFailure {
  const NetworkFailure();
  @override
  String get userMessage => 'Cannot connect to server. Check your network.';
}

class TimeoutFailure extends ApiFailure {
  const TimeoutFailure();
  @override
  String get userMessage => 'The server took too long to respond. Try again.';
}

class CancelledFailure extends ApiFailure {
  const CancelledFailure();
  @override
  String get userMessage => 'Request cancelled.';
}

class UnauthorizedFailure extends ApiFailure {
  const UnauthorizedFailure({super.serverMessage, super.serverCode});
  @override
  String get userMessage => serverMessage ?? 'Your session has expired. Please sign in again.';
}

class ForbiddenFailure extends ApiFailure {
  const ForbiddenFailure({super.serverMessage, super.serverCode});
  @override
  String get userMessage => serverMessage ?? 'You don\'t have permission to do that.';
}

class NotFoundFailure extends ApiFailure {
  const NotFoundFailure({super.serverMessage, super.serverCode});
  @override
  String get userMessage => serverMessage ?? 'Not found.';
}

class ValidationFailure extends ApiFailure {
  const ValidationFailure({super.serverMessage, super.serverCode});
  @override
  String get userMessage => serverMessage ?? 'Please check your input and try again.';
}

class AccountLockedFailure extends ApiFailure {
  const AccountLockedFailure({super.serverMessage, super.serverCode});
  @override
  String get userMessage =>
      serverMessage ?? 'Account locked. Try again in 30 minutes.';
}

class RateLimitedFailure extends ApiFailure {
  const RateLimitedFailure({super.serverMessage, super.serverCode});
  @override
  String get userMessage => serverMessage ?? 'Too many attempts. Please wait and try again.';
}

class ServerFailure extends ApiFailure {
  const ServerFailure(this.statusCode, {super.serverMessage, super.serverCode});
  final int statusCode;
  @override
  String get userMessage => 'Something went wrong on our side. Please try again.';
}

class UnknownFailure extends ApiFailure {
  const UnknownFailure({super.serverMessage, super.serverCode});
  @override
  String get userMessage => serverMessage ?? 'Something went wrong. Please try again.';
}
