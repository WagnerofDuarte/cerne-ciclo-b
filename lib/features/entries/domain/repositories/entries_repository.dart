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

  /// spec-4-4 (RF07) — calls `entries-get` (`ApiClient.get`, via
  /// `EntriesRemoteDataSource`) with [id] as the one path parameter, then
  /// persists the fetched entry to the `entries` Hive box (`put`) *before*
  /// returning `Right` — same "persist then return" ordering
  /// [create]/[list] already use. AD-11 keeps this port create+read-only,
  /// not count-capped — [search] (spec-5-1) added a fourth method without
  /// contradicting that.
  ///
  /// On [Failure.networkOffline]/[Failure.networkTimeout] specifically,
  /// falls back to `entriesBox.get(id)` if present; a cache miss propagates
  /// the original failure unchanged (no synthesized not-found — that
  /// distinction belongs to whichever `Failure` the backend/network
  /// actually produced). Every *other* [Failure] — including
  /// [Failure.notFound] for an id that never existed or belongs to another
  /// user — is returned as `Left`, unmapped (RNF09); RNF04 (identical
  /// treatment for both causes) is the caller's own rendering job, never
  /// this repository's.
  Future<Either<Failure, Entry>> getById(String id);

  /// spec-5-1 — calls `entries-search` (`ApiClient.get`, via
  /// `EntriesRemoteDataSource`) with [query] as the one `q` query
  /// parameter (no `limit`/`cursor` — Boundaries). [query] is always
  /// already a non-empty, pre-trimmed string by the time it reaches this
  /// method — `EntriesSearchCubit` owns that guarantee, never this
  /// repository.
  ///
  /// On success, persists every returned entry to the `entries` Hive box
  /// (`putAll`) *before* returning `Right` — same "persist then return"
  /// ordering [list]/[getById] already use. Unlike [list]/[getById], there
  /// is no offline/timeout cache fallback here (AD-9: no client-side
  /// vector index) — every [Failure], including
  /// [Failure.networkOffline], is returned as `Left`, unmapped (RNF09).
  Future<Either<Failure, List<Entry>>> search(String query);
}
