import 'package:dio/dio.dart';

/// AD-4 — the one place retry policy lives. Retries only the 6 server
/// `retryable:true` codes (`error-taxonomy.md`); every other failure
/// (including the local `MalformedResponse`) surfaces once, unretried.
///
/// Design note (docs/input is silent on the schedule): fixed 500ms delay,
/// max 2 retries.
class RetryInterceptor extends Interceptor {
  RetryInterceptor(this._dio);

  final Dio _dio;

  /// The 6 server `retryable:true` codes — the only codes this interceptor
  /// ever retries.
  static const Set<String> retryableCodes = {
    'NETWORK_TIMEOUT',
    'NETWORK_OFFLINE',
    'PII_CHECK_FAILED',
    'EMBEDDING_FAILED',
    'AI_GENERATION_TIMEOUT',
    'RATE_LIMITED',
  };

  static const int maxRetries = 2;
  static const Duration retryDelay = Duration(milliseconds: 500);

  static const _attemptKey = 'cerne_retry_attempt';

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final attempt = attemptOf(err);

    if (shouldRetry(err, attempt)) {
      await Future<void>.delayed(retryDelay);
      final options = err.requestOptions;
      options.extra[_attemptKey] = attempt + 1;
      try {
        final response = await _dio.fetch<dynamic>(options);
        handler.resolve(response);
      } on DioException catch (retryError) {
        handler.next(retryError);
      } catch (retryError) {
        // Any non-DioException thrown by the retried fetch must still reach
        // the caller through `handler`, never escape unhandled (RNF09).
        handler.next(
          DioException(
            requestOptions: options,
            error: retryError,
            type: DioExceptionType.unknown,
          ),
        );
      }
      return;
    }

    handler.next(err);
  }

  /// How many retries have already been attempted for this request.
  static int attemptOf(DioException err) =>
      (err.requestOptions.extra[_attemptKey] as int?) ?? 0;

  /// The backend error `code` for [err] — `NETWORK_OFFLINE` is the one code
  /// with no HTTP response at all (`error-taxonomy.md`); every other code is
  /// read from the response body `{code, message, retryable}`.
  static String? errorCodeOf(DioException err) {
    final data = err.response?.data;
    if (data is Map && data['code'] is String) {
      return data['code'] as String;
    }
    if (err.response == null) {
      return 'NETWORK_OFFLINE';
    }
    return null;
  }

  /// Pure decision function, independently testable: retry only if the
  /// error's code is one of the 6 allowlisted codes and the max-retries
  /// budget isn't exhausted yet.
  static bool shouldRetry(DioException err, int attempt) {
    final code = errorCodeOf(err);
    return code != null && retryableCodes.contains(code) && attempt < maxRetries;
  }
}
