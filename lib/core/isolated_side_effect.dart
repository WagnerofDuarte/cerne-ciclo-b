import 'package:fpdart/fpdart.dart';

import 'failure/failure.dart';

/// AD-13 — the never-throws wrapper RF08 and RF10 both need for a side
/// effect that must never block or crash its caller, even on failure.
///
/// spec-6-4 (RF10) is this helper's first real consumer, per the
/// architecture spine; spec-6-5 reuses it fire-and-forget (unawaited).
typedef IsolatedSideEffect<T> = Future<Either<Failure, T>> Function(
  Future<T> Function() action,
);

/// Runs [action], mapping any thrown exception (sync or async) to
/// [Failure.malformedResponse] rather than letting it escape — mirrors
/// `EntriesRepositoryImpl`'s own existing catch-to-`malformedResponse`
/// convention (`entries_repository_impl.dart`'s Hive-write guards). A
/// caller that awaits this never needs its own try/catch; a caller that
/// fires it unawaited (spec-6-5) can never crash the isolate it runs in
/// either way.
Future<Either<Failure, T>> isolatedSideEffect<T>(
  Future<T> Function() action,
) async {
  try {
    return right(await action());
  } catch (error) {
    return left(Failure.malformedResponse(message: error.toString()));
  }
}
