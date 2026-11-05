// The constructor keeps public named params (`remoteDataSource`,
// `entriesBox`) distinct from the private fields they initialize, matching
// `account_settings_repository_impl.dart`'s documented convention.
// ignore_for_file: prefer_initializing_formals
import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../../../core/failure/failure.dart';
import '../../../../core/utils/deduped_by_id.dart';
import '../../domain/entities/entries_page.dart';
import '../../domain/entities/entry.dart';
import '../../domain/repositories/entries_repository.dart';
import '../datasources/entries_remote_data_source.dart';
import '../models/entry_dto.dart';

/// On success, writes the entry through to the `entries` Hive box (`Box
/// <Map>`, keyed by id, raw `EntryDto.toJson()` — Design Notes) *before*
/// returning `right(...)`, same "persist then return" ordering
/// `AuthRepositoryImpl._authenticate` already uses for its own
/// post-success side effect.
class EntriesRepositoryImpl implements EntriesRepository {
  EntriesRepositoryImpl({
    required EntriesRemoteDataSource remoteDataSource,
    required Box<Map> entriesBox,
  }) : _remoteDataSource = remoteDataSource,
       _entriesBox = entriesBox;

  final EntriesRemoteDataSource _remoteDataSource;
  final Box<Map> _entriesBox;

  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
  }) async {
    final result = await _remoteDataSource.create(
      content: content,
      source: source,
      mediaDurationSeconds: mediaDurationSeconds,
    );
    return result.match((failure) async => left(failure), (dto) async {
      // A thrown Hive/disk exception must never escape unmapped (RNF09) —
      // same rationale/fallback `AuthRepositoryImpl` already uses for its
      // own local-persistence step.
      try {
        await _entriesBox.put(dto.id, dto.toJson());
      } catch (error) {
        return left(Failure.malformedResponse(message: error.toString()));
      }
      return right(_toEntry(dto));
    });
  }

  @override
  Future<Either<Failure, EntriesPage>> list({
    String? cursor,
    int limit = 20,
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final result = await _remoteDataSource.list(
      cursor: cursor,
      limit: limit,
      source: source,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    return result.match(
      (failure) async {
        // Boundaries/Design Notes: the Hive-cache fallback is scoped to
        // `cursor == null` (the first/fresh page) only — a paginated
        // continuation (`cursor != null`) that fails with
        // `networkOffline`/`networkTimeout` propagates as `Left` like any
        // other pagination failure instead, so `MeusRegistrosCubit`'s own
        // `loadMoreFailed`/retry path handles it uniformly rather than a
        // full unrelated cache dump silently replacing the in-progress
        // paginated list (and breaking its newest-first ordering).
        if (cursor == null &&
            (failure is NetworkOffline || failure is NetworkTimeout)) {
          return _offlineFallback();
        }
        return left(failure);
      },
      (page) async {
        try {
          await _entriesBox.putAll({
            for (final dto in page.items) dto.id: dto.toJson(),
          });
        } catch (error) {
          // Same RNF09 rationale as `create()`'s own Hive-write guard — a
          // thrown Hive/disk exception must never escape unmapped.
          return left(Failure.malformedResponse(message: error.toString()));
        }
        return right(
          EntriesPage(
            items: page.items.map(_toEntry).toList(),
            nextCursor: page.nextCursor,
          ),
        );
      },
    );
  }

  @override
  Future<Either<Failure, Entry>> getById(String id) async {
    final result = await _remoteDataSource.get(id);
    return result.match(
      (failure) async {
        // Boundaries: scoped to networkOffline/networkTimeout specifically
        // — every other Failure (notFound included) propagates as Left,
        // unmapped, same convention `list()`'s own cursor-scoped fallback
        // above uses.
        if (failure is NetworkOffline || failure is NetworkTimeout) {
          return _cachedEntryOrOriginalFailure(id, failure);
        }
        return left(failure);
      },
      (dto) async {
        // Same RNF09 rationale as `create()`/`list()`'s own Hive-write
        // guards — a thrown Hive/disk exception must never escape
        // unmapped.
        try {
          await _entriesBox.put(dto.id, dto.toJson());
        } catch (error) {
          return left(Failure.malformedResponse(message: error.toString()));
        }
        return right(_toEntry(dto));
      },
    );
  }

  @override
  Future<Either<Failure, List<Entry>>> search(String query) async {
    final result = await _remoteDataSource.search(query);
    return result.match(
      (failure) async {
        // Boundaries/AD-9: no cache fallback for search, unlike
        // list()/getById() — every Failure (including
        // networkOffline/networkTimeout) propagates as Left, unmapped.
        return left(failure);
      },
      (dtos) async {
        // Review finding: de-duplicated by id first (first-occurrence-wins,
        // same semantics as `MeusRegistrosCubit`'s own trust-but-verify
        // convention for server data, shared via `core/utils/
        // deduped_by_id.dart`) — so the `putAll` below and the returned
        // list stay consistent, and `_SearchResults`' `ListView.builder`
        // (keyed by `ValueKey(entry.id)`) never sees a duplicate key even
        // if the backend ever violated its own no-duplicate-ids invariant.
        final dedupedDtos = dedupedById(dtos, (dto) => dto.id);
        // Same RNF09 rationale as create()/list()/getById()'s own
        // Hive-write guards — a thrown Hive/disk exception must never
        // escape unmapped.
        try {
          await _entriesBox.putAll({
            for (final dto in dedupedDtos) dto.id: dto.toJson(),
          });
        } catch (error) {
          return left(Failure.malformedResponse(message: error.toString()));
        }
        return right(dedupedDtos.map(_toEntry).toList());
      },
    );
  }

  /// [getById]'s own offline/timeout fallback (Boundaries): a cache hit
  /// returns `Right` from the cached `EntryDto`; a cache miss propagates
  /// [originalFailure] unchanged — "no synthesized not-found" — rather than
  /// inventing a [Failure.notFound] this repository never actually
  /// received from the backend. A corrupt cached entry (should never
  /// happen — every entry here was written by [create]/[list]/[getById]
  /// themselves) maps to `Left(malformedResponse)` rather than throwing
  /// (RNF09), same guard `_offlineFallback()`'s own malformed-cache check
  /// uses.
  Either<Failure, Entry> _cachedEntryOrOriginalFailure(
    String id,
    Failure originalFailure,
  ) {
    try {
      final cached = _entriesBox.get(id);
      if (cached == null) {
        return left(originalFailure);
      }
      return right(
        _toEntry(EntryDto.fromJson(Map<String, dynamic>.from(cached))),
      );
    } catch (error) {
      return left(Failure.malformedResponse(message: error.toString()));
    }
  }

  /// The offline/timeout fallback (Boundaries): a full `entries` Hive box
  /// dump, sorted `occurredAt` desc, always `nextCursor: null` — a cached
  /// dump has no further page to request. A corrupt cached entry (should
  /// never happen — every entry here was written by [create]/[list]
  /// themselves) maps to `Left(malformedResponse)` rather than throwing
  /// (RNF09), same guard `create()`'s own Hive write already has.
  Either<Failure, EntriesPage> _offlineFallback() {
    try {
      final entries =
          _entriesBox.values
              .map(
                (json) => _toEntry(
                  EntryDto.fromJson(Map<String, dynamic>.from(json)),
                ),
              )
              .toList()
            ..sort(
              (a, b) =>
                  DateTime.parse(b.occurredAt)
                      .compareTo(DateTime.parse(a.occurredAt)),
            );
      return right(EntriesPage(items: entries, nextCursor: null));
    } catch (error) {
      return left(Failure.malformedResponse(message: error.toString()));
    }
  }

  Entry _toEntry(EntryDto dto) => Entry(
    id: dto.id,
    content: dto.content,
    source: dto.source,
    chatMessageId: dto.chatMessageId,
    occurredAt: dto.occurredAt,
    serverRevision: dto.serverRevision,
    createdAt: dto.createdAt,
    updatedAt: dto.updatedAt,
    mediaDurationSeconds: dto.mediaDurationSeconds,
  );
}
