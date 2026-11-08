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
  ///
  /// spec-6-4 — [chatMessageId] is sent only when non-null (the pre-
  /// reserved `Entry.chatMessageId`/`EntrySource.chat` slot, Boundaries:
  /// "not a new architectural call"); every caller before RF10 passed
  /// `null` implicitly, so this is purely additive. Idempotent at the
  /// backend level for a given [chatMessageId] — a repeat call with the
  /// same value never creates a second Entry (epic context's own
  /// Technical Decisions).
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
    String? chatMessageId,
  });

  /// Calls `entries-list` (`ApiClient.get`, via
  /// `EntriesRemoteDataSource`), newest-first by `occurredAt` — server
  /// behavior assumed, undocumented (Code Map, decided per AGENTS.md
  /// policy: "where `docs/input/` is silent... decide and proceed").
  ///
  /// spec-5-2 — [source]/[dateFrom]/[dateTo] are forwarded to
  /// `entries-list` as its own `source`/`dateFrom`/`dateTo` query
  /// parameters (`EntriesRemoteDataSource.list()`'s own doc), each only
  /// when non-null; combining more than one narrows with AND logic (the
  /// backend's own semantics, RF06 Acceptance Criteria) — this repository
  /// does no client-side filtering/joining of its own (AD-9).
  ///
  /// On [Failure.networkOffline]/[Failure.networkTimeout] specifically,
  /// falls back to a full dump of the `entries` Hive box, sorted
  /// `occurredAt` desc, with `EntriesPage.nextCursor: null` (Boundaries) —
  /// every *other* [Failure] (e.g. [Failure.authExpired]) propagates as
  /// `Left`, unmapped (RNF09). That fallback (`cursor == null` only) stays
  /// filter-oblivious regardless of [source]/[dateFrom]/[dateTo] — AD-9:
  /// the cache is never locally filtered, so an offline first page always
  /// renders the full cached list even with filters active.
  ///
  /// A successful page persists every item to the `entries` Hive box
  /// *before* returning `Right` — same "persist then return" ordering
  /// [create] already uses.
  Future<Either<Failure, EntriesPage>> list({
    String? cursor,
    int limit = 20,
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
  });

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
  /// spec-5-3 — [source]/[dateFrom]/[dateTo] are forwarded to
  /// `entries-search` as its own `source`/`dateFrom`/`dateTo` query
  /// parameters, each only when non-null — same AND-narrowing convention
  /// [list]'s own doc already gives, now carried by `EntriesSearchCubit`'s
  /// own filter fields (`updateFilters()`) instead of `MeusRegistrosCubit`'s
  /// (the two cubits never share state directly, RNF06 — only
  /// `MeusRegistrosScreen` bridges them).
  ///
  /// On success, persists every returned entry to the `entries` Hive box
  /// (`putAll`) *before* returning `Right` — same "persist then return"
  /// ordering [list]/[getById] already use. Unlike [list]/[getById], there
  /// is no offline/timeout cache fallback here (AD-9: no client-side
  /// vector index) — every [Failure], including
  /// [Failure.networkOffline], is returned as `Left`, unmapped (RNF09).
  Future<Either<Failure, List<Entry>>> search(
    String query, {
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
  });

  /// Story 8.4 — closes deferred-work.md's "no clear-on-logout hook" gap:
  /// empties the `entries` Hive box, called by `AccountSettingsCubit.
  /// logout()` alongside [ChatRepository.clearLocalCache]. A thrown Hive/
  /// disk exception never escapes unmapped (RNF09), same convention every
  /// other write in this port already follows.
  Future<Either<Failure, Unit>> clearLocalCache();
}
