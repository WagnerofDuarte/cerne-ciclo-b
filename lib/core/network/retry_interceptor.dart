import 'package:dio/dio.dart';

import 'dio_error_code.dart';
import 'header_interceptor.dart';

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

  /// Non-idempotent POSTs with no client-supplied idempotency key — a
  /// transparent retry here would silently resend the identical request
  /// (the same chat message content, or a second session-create) rather
  /// than surfacing the failure once to the caller. `dioErrorCodeOf` can
  /// return a retryable code for these from `DioException.type` alone
  /// (`NETWORK_TIMEOUT`/`NETWORK_OFFLINE`) even before any response body
  /// exists to carry the real `{code,message}`, so excluding by function
  /// name here is the only place this can be enforced.
  ///
  /// spec-7-1 — `export-summary-create` joins this set for the same
  /// reason: it enqueues a brand-new export job with no client-supplied
  /// idempotency key, so a transparent retry risks creating a second,
  /// duplicate job rather than resurfacing the original failure once.
  static const Set<String> neverRetriedFunctions = {
    'chat-messages-send',
    'chat-messages-retry',
    'chat-sessions-create',
    'export-summary-create',
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

  /// The backend error `code` for [err] — delegates to the shared
  /// [dioErrorCodeOf] (also used by `ApiClient`) so a client-side timeout or
  /// a cancelled request is never misread as `NETWORK_OFFLINE` here.
  static String? errorCodeOf(DioException err) => dioErrorCodeOf(err);

  /// Pure decision function, independently testable: retry only if the
  /// error's code is one of the 6 allowlisted codes, the max-retries
  /// budget isn't exhausted yet, and the request isn't one of the
  /// [neverRetriedFunctions].
  static bool shouldRetry(DioException err, int attempt) {
    final code = errorCodeOf(err);
    if (code == null || !retryableCodes.contains(code) || attempt >= maxRetries) {
      return false;
    }
    final function = HeaderInterceptor.functionNameOf(err.requestOptions.path);
    return !neverRetriedFunctions.contains(function);
  }
}
