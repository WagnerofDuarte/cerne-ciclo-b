import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/entry.dart';
import '../models/entry_dto.dart';

/// The entries feature's one write call so far (`entries-create`) — posts
/// via the shared `ApiClient`, mirroring `account_remote_data_source.dart`'s
/// pattern.
class EntriesRemoteDataSource {
  EntriesRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  /// Sends `{content, source}` plus `mediaDurationSeconds` only when
  /// non-null (spec-3-2's `source: audio` entries) — this story still
  /// never passes `chatMessageId`/`occurredAt` (Boundaries: no `Entry`
  /// field beyond the modeled 9; those two are optional in the contract
  /// and belong to later stories/epics).
  Future<Either<Failure, EntryDto>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
  }) async {
    final result = await _apiClient.post(
      'entries-create',
      data: {
        'content': content,
        'source': source.name,
        'mediaDurationSeconds': ?mediaDurationSeconds,
      },
    );
    return result.flatMap((json) {
      try {
        final data = json['data'] as Map<String, dynamic>;
        return right(EntryDto.fromJson(data));
      } catch (error) {
        // A 200 response that doesn't match the expected shape is a
        // client-side parse failure, never a backend-sent code — maps to
        // the local-only `malformedResponse` (RNF09: no exception escapes
        // unmapped).
        return left(Failure.malformedResponse(message: error.toString()));
      }
    });
  }

  /// Calls `entries-list` (`ApiClient.get`) with `limit` always sent, and
  /// `cursor` only when non-null (spec-4-1's own convention for an
  /// optional-in-the-contract query parameter, mirroring [create]'s own
  /// `mediaDurationSeconds` handling). Returns the raw page as a record —
  /// no dedicated DTO wrapper type, since `EntriesRepositoryImpl.list()` is
  /// this record's only reader.
  Future<Either<Failure, ({List<EntryDto> items, String? nextCursor})>> list({
    String? cursor,
    int limit = 20,
  }) async {
    final result = await _apiClient.get(
      'entries-list',
      queryParameters: {'limit': limit, 'cursor': ?cursor},
    );
    return result.flatMap((json) {
      try {
        final data = json['data'] as List<dynamic>;
        final items = data
            .map((item) => EntryDto.fromJson(item as Map<String, dynamic>))
            .toList();
        final meta = json['meta'] as Map<String, dynamic>;
        final nextCursor = meta['nextCursor'] as String?;
        return right((items: items, nextCursor: nextCursor));
      } catch (error) {
        // Same client-side-parse-failure rationale as `create()` above.
        return left(Failure.malformedResponse(message: error.toString()));
      }
    });
  }

  /// Calls `entries-get` (`ApiClient.get`) with [id] appended as the one
  /// trailing path segment (Conventions: "path parameters appended as
  /// trailing segments") — decodes the response's own `data` object exactly
  /// as [create]/[list] already do, a superset [EntryDto] already handles
  /// (Boundaries: "its response is a superset, same as create/list's DTO
  /// reuse").
  Future<Either<Failure, EntryDto>> get(String id) async {
    final result = await _apiClient.get('entries-get', pathParams: [id]);
    return result.flatMap((json) {
      try {
        final data = json['data'] as Map<String, dynamic>;
        return right(EntryDto.fromJson(data));
      } catch (error) {
        // Same client-side-parse-failure rationale as `create()`/`list()`
        // above.
        return left(Failure.malformedResponse(message: error.toString()));
      }
    });
  }

  /// spec-5-1 — calls `entries-search` (`ApiClient.get`) with exactly one
  /// query parameter, `q` (Boundaries: no `limit`/`cursor`). The response's
  /// `data` array decodes with the exact same `EntryDto.fromJson` [list]
  /// already uses — a superset response (`similarity`/`mode` fields the
  /// Code Map names) is simply ignored by `json_serializable`'s generated
  /// `fromJson`, same convention [get]'s own superset-response doc already
  /// gives.
  Future<Either<Failure, List<EntryDto>>> search(String query) async {
    final result = await _apiClient.get(
      'entries-search',
      queryParameters: {'q': query},
    );
    return result.flatMap((json) {
      try {
        final data = json['data'] as List<dynamic>;
        final items = data
            .map((item) => EntryDto.fromJson(item as Map<String, dynamic>))
            .toList();
        return right(items);
      } catch (error) {
        // Same client-side-parse-failure rationale as `create()`/`list()`/
        // `get()` above.
        return left(Failure.malformedResponse(message: error.toString()));
      }
    });
  }
}
