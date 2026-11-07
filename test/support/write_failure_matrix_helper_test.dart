import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/network/api_client.dart';

import 'write_failure_matrix_helper.dart';

class MockApiClient extends Mock implements ApiClient {}

/// Stands in for a write-endpoint's repository call (none exists yet — this
/// story builds no feature repository, AGENTS.md's F000 boundary). It is
/// exactly the generic shape every later write-endpoint call will have:
/// call `ApiClient.post` for a function name and pass its `Either` straight
/// through — proving [runWriteFailureMatrix] against `auth-signup`.
Future<Either<Failure, Map<String, dynamic>>> _signUp(ApiClient apiClient) =>
    apiClient.post(
      'auth-signup',
      data: {'email': 'user@example.com', 'password': 'p4ssw0rd'},
    );

void main() {
  late MockApiClient mockApiClient;

  setUp(() {
    mockApiClient = MockApiClient();
  });

  runWriteFailureMatrix<Map<String, dynamic>>(
    endpointName: 'auth-signup',
    stubNetworkTimeout: () {
      when(
        () => mockApiClient.post(any(), data: any(named: 'data')),
      ).thenAnswer(
        (_) async =>
            left(const Failure.networkTimeout(message: 'Request timed out')),
      );
    },
    stubMalformedResponse: () {
      when(
        () => mockApiClient.post(any(), data: any(named: 'data')),
      ).thenAnswer(
        (_) async => left(
          const Failure.malformedResponse(message: 'Could not parse response'),
        ),
      );
    },
    stubNoConnection: () {
      when(() => mockApiClient.post(any(), data: any(named: 'data')))
          .thenAnswer(
            (_) async =>
                left(const Failure.networkOffline(message: 'No connection')),
          );
    },
    invoke: () => _signUp(mockApiClient),
  );
}
