import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../entities/entry.dart';

/// The port later epics extend (Code Map) — this story gives it exactly
/// one method, [create]. `features/capture/` depends on this abstract
/// class only, never `entries/data` or `entries/presentation` (RNF06).
abstract class EntriesRepository {
  /// Posts to `entries-create` (`ApiClient.post`, via
  /// `EntriesRemoteDataSource`) and, on success, writes the entry through
  /// to the `entries` Hive box before returning `Right` (Boundaries) — a
  /// caller that only reads the returned [Entry] never needs to touch the
  /// box itself. Every [Failure] — including
  /// [Failure.networkOffline] — is returned as `Left`, unmapped and
  /// un-retried; the caller decides what to do with it (RNF09).
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
  });
}
