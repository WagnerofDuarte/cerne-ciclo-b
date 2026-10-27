import 'package:fpdart/fpdart.dart';

import 'failure/failure.dart';

/// AD-13 — the never-throws wrapper RF08 and RF10 both need for a side
/// effect that must never block or crash its caller, even on failure.
///
/// Typed stub only: the real implementation ships with RF10 (delivery
/// order's first consumer, per the architecture spine), not built
/// speculatively here in F000. RF10 may `await` it; RF08 must be able to
/// call it fire-and-forget (without awaiting).
typedef IsolatedSideEffect<T> = Future<Either<Failure, T>> Function(
  Future<T> Function() action,
);

/// Placeholder implementation — throws until RF10 replaces it.
Future<Either<Failure, T>> isolatedSideEffect<T>(
  Future<T> Function() action,
) {
  throw UnimplementedError(
    'isolatedSideEffect is a typed stub (AD-13) — implemented in RF10.',
  );
}
