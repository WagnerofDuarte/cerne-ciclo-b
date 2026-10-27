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
  });

  group('RetryInterceptor.onError — end-to-end retry behavior', () {
    late MockDio mockDio;
    late RetryInterceptor interceptor;

    setUp(() {
      mockDio = MockDio();
      interceptor = RetryInterceptor(mockDio);
    });

    test('retries a retryable error and resolves on success', () async {
      final options = RequestOptions(path: '/chat-messages-send');
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

      interceptor.onError(err, handler);
      // Allow the 500ms delay + async fetch to complete.
      await Future<void>.delayed(const Duration(milliseconds: 700));

      verify(() => mockDio.fetch<dynamic>(any())).called(1);
      verify(() => handler.resolve(successResponse)).called(1);
    });

    test('never retries a non-retryable error', () async {
      final options = RequestOptions(path: '/auth-login');
      final err = _errorWithCode('AUTH_INVALID', requestOptions: options);

      final handler = MockErrorInterceptorHandler();
      when(() => handler.next(any())).thenReturn(null);

      interceptor.onError(err, handler);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verifyNever(() => mockDio.fetch<dynamic>(any()));
      verify(() => handler.next(err)).called(1);
    });

    test(
      'retry-exhausted: a retryable code keeps failing through all '
      'maxRetries attempts, finally calling handler.next and never '
      'handler.resolve',
      () async {
        final options = RequestOptions(path: '/chat-messages-send');

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
          interceptor.onError(currentError, handler);
          await Future<void>.delayed(const Duration(milliseconds: 700));

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
