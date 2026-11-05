import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../entities/entries_page.dart';
import '../entities/entry.dart';

/// The port later epics extend (Code Map) — `features/capture/` depends on
/// this abstract class only, never `entries/data` or `entries/presentation`
/// (RNF06).
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
    int? mediaDurationSeconds,
  });

  /// Calls `entries-list` (`ApiClient.get`, via
  /// `EntriesRemoteDataSource`), newest-first by `occurredAt` — server
  /// behavior assumed, undocumented (Code Map, decided per AGENTS.md
  /// policy: "where `docs/input/` is silent... decide and proceed").
  ///
  /// On [Failure.networkOffline]/[Failure.networkTimeout] specifically,
  /// falls back to a full dump of the `entries` Hive box, sorted
  /// `occurredAt` desc, with `EntriesPage.nextCursor: null` (Boundaries) —
  /// every *other* [Failure] (e.g. [Failure.authExpired]) propagates as
  /// `Left`, unmapped (RNF09).
  ///
  /// A successful page persists every item to the `entries` Hive box
  /// *before* returning `Right` — same "persist then return" ordering
  /// [create] already uses.
  Future<Either<Failure, EntriesPage>> list({String? cursor, int limit = 20});
}
