import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/network/retry_interceptor.dart';

class MockDio extends Mock implements Dio {}

class MockErrorInterceptorHandler extends Mock
    implements ErrorInterceptorHandler {}

DioException _errorWithCode(
  String code, {
  RequestOptions? requestOptions,
}) {
  final options = requestOptions ?? RequestOptions(path: '/some-function');
  return DioException(
    requestOptions: options,
    response: Response(
      requestOptions: options,
      statusCode: 502,
      data: {'code': code, 'message': 'boom', 'retryable': true},
    ),
    type: DioExceptionType.badResponse,
  );
}

DioException _connectionErrorWithNoResponse({RequestOptions? requestOptions}) {
  final options = requestOptions ?? RequestOptions(path: '/some-function');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.connectionError,
  );
}

void main() {
  setUpAll(() {
    final fallbackOptions = RequestOptions(path: '/fallback');
    registerFallbackValue(fallbackOptions);
    registerFallbackValue(Response<dynamic>(requestOptions: fallbackOptions));
    registerFallbackValue(
      DioException(requestOptions: fallbackOptions),
    );
  });

  group('RetryInterceptor.errorCodeOf', () {
    test('reads the code from the response body when present', () {
      final err = _errorWithCode('RATE_LIMITED');
      expect(RetryInterceptor.errorCodeOf(err), 'RATE_LIMITED');
    });

    test('maps a response-less connection error to NETWORK_OFFLINE', () {
      final err = _connectionErrorWithNoResponse();
      expect(RetryInterceptor.errorCodeOf(err), 'NETWORK_OFFLINE');
    });

    test(
        'maps a client-side connect timeout to NETWORK_TIMEOUT, not '
        'NETWORK_OFFLINE', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/some-function'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(RetryInterceptor.errorCodeOf(err), 'NETWORK_TIMEOUT');
    });

    test('a cancelled request has no code (never retryable)', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/some-function'),
        type: DioExceptionType.cancel,
      );
      expect(RetryInterceptor.errorCodeOf(err), isNull);
    });
  });

  group('RetryInterceptor.shouldRetry — only the 6 retryable codes, AD-4', () {
    const retryableCodes = {
      'NETWORK_TIMEOUT',
      'NETWORK_OFFLINE',
      'PII_CHECK_FAILED',
      'EMBEDDING_FAILED',
      'AI_GENERATION_TIMEOUT',
      'RATE_LIMITED',
    };

    const nonRetryableCodes = {
      'AUTH_EXPIRED',
      'AUTH_INVALID',
      'VALIDATION_ERROR',
      'NOT_FOUND',
      'EXPORT_EMPTY_PERIOD',
      'PAYLOAD_TOO_LARGE',
      'OCR_NO_TEXT',
    };

    for (final code in retryableCodes) {
      test('$code retries on first attempt', () {
        final err = _errorWithCode(code);
        expect(RetryInterceptor.shouldRetry(err, 0), isTrue);
      });
    }

    for (final code in nonRetryableCodes) {
      test('$code never retries', () {
        final err = _errorWithCode(code);
        expect(RetryInterceptor.shouldRetry(err, 0), isFalse);
      });
    }

    test('stops retrying once maxRetries (2) is reached', () {
      final err = _errorWithCode('NETWORK_TIMEOUT');
      expect(RetryInterceptor.shouldRetry(err, 0), isTrue);
      expect(RetryInterceptor.shouldRetry(err, 1), isTrue);
      expect(RetryInterceptor.shouldRetry(err, 2), isFalse);
    });

    test('a cancelled request is never retried', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/some-function'),
        type: DioExceptionType.cancel,
      );
      expect(RetryInterceptor.shouldRetry(err, 0), isFalse);
    });

    test('a client-side connect timeout retries like a server timeout', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/some-function'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(RetryInterceptor.shouldRetry(err, 0), isTrue);
    });

    group(
      'neverRetriedFunctions — non-idempotent chat POSTs are never '
      'auto-retried, even with a retryable code (review finding: '
      'dioErrorCodeOf can return NETWORK_TIMEOUT/NETWORK_OFFLINE from '
      'DioException.type alone, before any {code,message} body exists, '
      'so a transparent retry here would silently resend the identical '
      'chat message / create a second session)',
      () {
        for (final function in RetryInterceptor.neverRetriedFunctions) {
          test(
            '$function is never retried on a retryable connect timeout '
            '(no response body yet)',
            () {
              final err = DioException(
                requestOptions: RequestOptions(path: '/$function'),
                type: DioExceptionType.connectionTimeout,
              );
              expect(RetryInterceptor.shouldRetry(err, 0), isFalse);
            },
          );

          test(
            '$function is never retried even when the error body does '
            'carry a retryable code',
            () {
              final err = _errorWithCode(
                'AI_GENERATION_TIMEOUT',
                requestOptions: RequestOptions(path: '/$function'),
              );
              expect(RetryInterceptor.shouldRetry(err, 0), isFalse);
            },
          );
        }

        test('an unrelated function with the same code still retries', () {
          final err = DioException(
            requestOptions: RequestOptions(path: '/chat-messages-list'),
            type: DioExceptionType.connectionTimeout,
          );
          expect(RetryInterceptor.shouldRetry(err, 0), isTrue);
        });
      },
    );
  });

  group('RetryInterceptor.onError — end-to-end retry behavior', () {
    late MockDio mockDio;
    late RetryInterceptor interceptor;

    setUp(() {
      mockDio = MockDio();
      interceptor = RetryInterceptor(mockDio);
    });

    test('retries a retryable error and resolves on success', () async {
      final options = RequestOptions(path: '/dashboard-summary');
      final err = _errorWithCode('AI_GENERATION_TIMEOUT', requestOptions: options);
      final successResponse = Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: {'ok': true},
      );

      when(() => mockDio.fetch<dynamic>(any()))
          .thenAnswer((_) async => successResponse);

      final handler = MockErrorInterceptorHandler();
      when(() => handler.resolve(any())).thenReturn(null);

      await _runOnError(interceptor, err, handler);

      verify(() => mockDio.fetch<dynamic>(any())).called(1);
      verify(() => handler.resolve(successResponse)).called(1);
    });

    test('never retries a non-retryable error', () async {
      final options = RequestOptions(path: '/auth-login');
      final err = _errorWithCode('AUTH_INVALID', requestOptions: options);

      final handler = MockErrorInterceptorHandler();
      when(() => handler.next(any())).thenReturn(null);

      await _runOnError(interceptor, err, handler);

      verifyNever(() => mockDio.fetch<dynamic>(any()));
      verify(() => handler.next(err)).called(1);
    });

    test(
      'retry-exhausted: a retryable code keeps failing through all '
      'maxRetries attempts, finally calling handler.next and never '
      'handler.resolve',
      () async {
        final options = RequestOptions(path: '/dashboard-summary');

        when(() => mockDio.fetch<dynamic>(any())).thenAnswer((invocation) {
          final opts = invocation.positionalArguments.first as RequestOptions;
          throw DioException(
            requestOptions: opts,
            response: Response(
              requestOptions: opts,
              statusCode: 504,
              data: {
                'code': 'NETWORK_TIMEOUT',
                'message': 'timeout',
                'retryable': true,
              },
            ),
            type: DioExceptionType.badResponse,
          );
        });

        final handler = MockErrorInterceptorHandler();
        when(() => handler.next(any())).thenReturn(null);
        when(() => handler.resolve(any())).thenReturn(null);

        DioException currentError =
            _errorWithCode('NETWORK_TIMEOUT', requestOptions: options);

        // Simulates the real Dio pipeline re-entering onError after each
        // failed retry (a bare mock doesn't loop by itself), carrying the
        // incremented attempt count forward each round, through and past
        // maxRetries.
        for (var round = 0; round <= RetryInterceptor.maxRetries; round++) {
          await _runOnError(interceptor, currentError, handler);

          final captured =
              verify(() => handler.next(captureAny())).captured;
          currentError = captured.last as DioException;
        }

        expect(
          RetryInterceptor.attemptOf(currentError),
          RetryInterceptor.maxRetries,
        );
        verify(() => mockDio.fetch<dynamic>(any()))
            .called(RetryInterceptor.maxRetries);
        verifyNever(() => handler.resolve(any()));
      },
    );
  });
}

/// `onError` is declared `void` but implemented `async`, so Dart still
/// returns a real `Future` at runtime even though the static type hides it
/// — awaiting that real Future deterministically waits for the retry
/// delay + fetch to finish, instead of a fixed-duration sleep.
Future<void> _runOnError(
  RetryInterceptor interceptor,
  DioException err,
  ErrorInterceptorHandler handler,
) async {
  // `onError`'s declared return type is `void`, but the real implementation
  // is `async` and returns a real `Future` at runtime. Calling through a
  // `dynamic`-typed reference bypasses the static void check so that real
  // Future can be captured and awaited.
  final dynamic pending = (interceptor.onError as dynamic)(err, handler);
  if (pending is Future) await pending;
}
