import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../entities/export_job_state.dart';

/// The export feature's one port (RNF06) — `features/export/presentation`
/// depends on this abstract class only, never `export/data` directly.
/// Every method returns `Either<Failure, T>` (RNF09).
abstract class ExportRepository {
  /// Calls `export-summary-create` (`ApiClient.post`) — RF05's own job
  /// kickoff for the period [periodStart]..[periodEnd]. Returns the
  /// created job's `jobId` on success. `RetryInterceptor.
  /// neverRetriedFunctions` already excludes this call from any
  /// transparent retry (non-idempotent POST, no idempotency key) — every
  /// [Failure] here, including a theoretical synchronous rejection,
  /// propagates as `Left`, unmapped.
  Future<Either<Failure, String>> createJob({
    required DateTime periodStart,
    required DateTime periodEnd,
  });

  /// Calls `export-status-get` (`ApiClient.get`, [jobId] appended as the
  /// one trailing path segment) and maps the response straight into
  /// [ExportJobState] — a thin pass-through, no cache (AD-15: ephemeral,
  /// polled live). `Left` here is a transport-level failure only
  /// (offline/timeout/malformed) — a backend-reported job failure
  /// (including the empty-period case) already arrives as a
  /// `Right(ExportJobState.error(...))`/`Right(ExportJobState.
  /// emptyPeriod())`, never as a `Left`.
  Future<Either<Failure, ExportJobState>> getStatus(String jobId);
}
