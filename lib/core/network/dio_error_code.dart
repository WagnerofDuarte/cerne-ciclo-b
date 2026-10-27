import 'package:dio/dio.dart';

/// AD-4/AD-5 — the one place a `DioException` is mapped to the backend's
/// error `code` (`error-taxonomy.md`), shared by `ApiClient` (which turns it
/// into a `Failure`) and `RetryInterceptor` (which decides whether to
/// retry). Previously reimplemented independently in both files, which let
/// a client-side timeout and a cancelled request both be misread as
/// `NETWORK_OFFLINE`.
///
/// Returns `null` when no code can be determined: a cancelled request
/// (`DioExceptionType.cancel`) or an HTTP response that doesn't carry the
/// expected `{code, message, retryable}` body. Neither is retryable, and
/// both end up mapped to `Failure.malformedResponse` by the caller.
String? dioErrorCodeOf(DioException e) {
  final data = e.response?.data;
  if (data is Map && data['code'] is String) {
    return data['code'] as String;
  }
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'NETWORK_TIMEOUT';
    case DioExceptionType.cancel:
      return null;
    default:
      break;
  }
  if (e.response == null) {
    return 'NETWORK_OFFLINE';
  }
  return null;
}
