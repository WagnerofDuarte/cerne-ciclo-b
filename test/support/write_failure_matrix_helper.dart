import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';

/// RNF09 — the one shared, table-driven helper every write-endpoint test
/// reuses: for a given write call, stubs each of the 3 failure types
/// (timeout, malformed response, no connection) and asserts it resolves to
/// `Left<Failure>` with zero unhandled exceptions, via `mocktail`.
///
/// Callers stub their own mocked `ApiClient` (per the architecture spine's
/// testing convention — tests mock `ApiClient`, not a fake transport layer)
/// through [stubNetworkTimeout]/[stubMalformedResponse]/[stubNoConnection],
/// then supply [invoke] — the repository/data-source call under test, which
/// must itself return `Either<Failure, T>`.
///
/// The 5-write-endpoints x 3-failure-types = 15-scenario matrix (RNF09)
/// accumulates across stories as each write endpoint gets its own call to
/// this helper; this story proves the helper once against `auth-signup`.
void runWriteFailureMatrix<T>({
  required String endpointName,
  required void Function() stubNetworkTimeout,
  required void Function() stubMalformedResponse,
  required void Function() stubNoConnection,
  required Future<Either<Failure, T>> Function() invoke,
}) {
  group('$endpointName write-failure matrix (RNF09)', () {
    test('network timeout -> Left(Failure), no unhandled exception',
        () async {
      stubNetworkTimeout();

      final result = await invoke();

      expect(result.isLeft(), isTrue);
    });

    test('malformed response -> Left(Failure), no unhandled exception',
        () async {
      stubMalformedResponse();

      final result = await invoke();

      expect(result.isLeft(), isTrue);
    });

    test('no connection -> Left(Failure), no unhandled exception', () async {
      stubNoConnection();

      final result = await invoke();

      expect(result.isLeft(), isTrue);
    });
  });
}
