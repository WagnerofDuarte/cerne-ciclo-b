import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/url_builder.dart';

class MockDio extends Mock implements Dio {}

void main() {
  const baseUrl = 'https://host.example.com';

  late MockDio mockDio;
  late ApiClient apiClient;
  late RequestOptions requestOptions;

  setUp(() {
    mockDio = MockDio();
    apiClient = ApiClient(dio: mockDio, urlBuilder: const UrlBuilder(baseUrl));
    requestOptions = RequestOptions(path: '$baseUrl/auth-signup');
  });

  group('ApiClient — real send/mapping logic, mocked Dio', () {
    test('success response -> Right(data)', () async {
      final response = Response<Map<String, dynamic>>(
        requestOptions: requestOptions,
        statusCode: 200,
        data: {'id': 'abc123'},
      );
      when(
        () => mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => response);

      final result = await apiClient.post('auth-signup', data: {'a': 1});

      expect(result.isRight(), isTrue);
      result.match(
        (_) => fail('expected Right'),
        (data) => expect(data, {'id': 'abc123'}),
      );
    });

    test(
        'DioException with a {code, message} body maps to the matching '
        'Failure', () async {
      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 429,
          data: {
            'code': 'RATE_LIMITED',
            'message': 'Too many requests',
            'retryable': true,
          },
        ),
        type: DioExceptionType.badResponse,
      );
      when(
        () => mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenThrow(dioError);

      final result = await apiClient.post('auth-signup', data: {'a': 1});

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) {
          expect(failure, isA<RateLimited>());
          expect(failure.retryable, isTrue);
        },
        (_) => fail('expected Left'),
      );
    });

    test(
        'a {code, message} body where message is not a String still maps '
        'without throwing (patch item 1)', () async {
      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 400,
          data: {
            'code': 'VALIDATION_ERROR',
            // Malformed on purpose: the contract says `message` is a
            // String, but nothing stops a backend bug from sending an int.
            'message': 12345,
            'retryable': false,
          },
        ),
        type: DioExceptionType.badResponse,
      );
      when(
        () => mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenThrow(dioError);

      final result = await apiClient.post('auth-signup', data: {'a': 1});

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<Validation>()),
        (_) => fail('expected Left'),
      );
    });

    test('DioException with no response at all -> Left(NetworkOffline)',
        () async {
      final dioError = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.connectionError,
      );
      when(
        () => mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenThrow(dioError);

      final result = await apiClient.post('auth-signup', data: {'a': 1});

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<NetworkOffline>()),
        (_) => fail('expected Left'),
      );
    });

    test(
        'a non-DioException thrown by dio -> Left(MalformedResponse), never '
        'a crash', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenThrow(StateError('unexpected native failure'));

      final result = await apiClient.post('auth-signup', data: {'a': 1});

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });

    test('a null response body -> Left(MalformedResponse)', () async {
      final response = Response<Map<String, dynamic>>(
        requestOptions: requestOptions,
        statusCode: 200,
      );
      when(
        () => mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => response);

      final result = await apiClient.post('auth-signup', data: {'a': 1});

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });
  });
}
