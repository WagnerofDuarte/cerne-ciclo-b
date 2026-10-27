import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:cerne/features/auth/data/models/auth_response_dto.dart';

import '../../../../support/write_failure_matrix_helper.dart';

class MockApiClient extends Mock implements ApiClient {}

Map<String, dynamic> _refreshBody({
  String accessToken = 'new-access-token',
  String refreshToken = 'new-refresh-token',
}) => {
  'data': {
    'session': {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresIn': 3600,
      'expiresAt': 1999999999,
      'tokenType': 'bearer',
    },
  },
};

void main() {
  late MockApiClient mockApiClient;
  late AuthRemoteDataSource dataSource;

  setUp(() {
    mockApiClient = MockApiClient();
    dataSource = AuthRemoteDataSource(mockApiClient);
  });

  // RNF09 — this story's slice of the 15-scenario matrix is `auth-refresh`,
  // 3 failure types.
  runWriteFailureMatrix<AuthSessionDto>(
    endpointName: 'auth-refresh',
    stubNetworkTimeout: () =>
        when(() => mockApiClient.post(any(), data: any(named: 'data')))
            .thenAnswer(
              (_) async =>
                  left(const Failure.networkTimeout(message: 'Timed out')),
            ),
    stubMalformedResponse: () =>
        when(() => mockApiClient.post(any(), data: any(named: 'data')))
            .thenAnswer((_) async => right({'unexpected': 'shape'})),
    stubNoConnection: () =>
        when(() => mockApiClient.post(any(), data: any(named: 'data')))
            .thenAnswer(
              (_) async =>
                  left(const Failure.networkOffline(message: 'Offline')),
            ),
    invoke: () => dataSource.refresh('some-refresh-token'),
  );

  group('AuthRemoteDataSource.refresh', () {
    test('posts exactly {refreshToken} to auth-refresh', () async {
      when(() => mockApiClient.post('auth-refresh', data: any(named: 'data')))
          .thenAnswer((_) async => right(_refreshBody()));

      await dataSource.refresh('stored-refresh-token');

      final captured = verify(
        () =>
            mockApiClient.post('auth-refresh', data: captureAny(named: 'data')),
      ).captured;
      expect(captured.single, {'refreshToken': 'stored-refresh-token'});
    });

    test('decodes the nested session object into AuthSessionDto', () async {
      when(() => mockApiClient.post('auth-refresh', data: any(named: 'data')))
          .thenAnswer(
            (_) async => right(
              _refreshBody(accessToken: 'token-a', refreshToken: 'token-b'),
            ),
          );

      final result = await dataSource.refresh('whatever');

      expect(result.isRight(), isTrue);
      result.match((_) => fail('expected Right'), (session) {
        expect(session.accessToken, 'token-a');
        expect(session.refreshToken, 'token-b');
      });
    });

    test('a dead-token backend response (AUTH_EXPIRED) maps straight through '
        'as Left(AuthExpired)', () async {
      when(() => mockApiClient.post('auth-refresh', data: any(named: 'data')))
          .thenAnswer(
            (_) async =>
                left(const Failure.authExpired(message: 'Refresh token dead')),
          );

      final result = await dataSource.refresh('dead-token');

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<AuthExpired>()),
        (_) => fail('expected Left'),
      );
    });
  });
}
