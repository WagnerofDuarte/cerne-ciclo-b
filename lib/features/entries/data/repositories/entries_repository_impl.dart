// The constructor keeps public named params (`remoteDataSource`,
// `entriesBox`) distinct from the private fields they initialize, matching
// `account_settings_repository_impl.dart`'s documented convention.
// ignore_for_file: prefer_initializing_formals
import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../../../core/failure/failure.dart';
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
  }) async {
    final result = await _remoteDataSource.create(
      content: content,
      source: source,
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

  Entry _toEntry(EntryDto dto) => Entry(
    id: dto.id,
    content: dto.content,
    source: dto.source,
    chatMessageId: dto.chatMessageId,
    occurredAt: dto.occurredAt,
    serverRevision: dto.serverRevision,
    createdAt: dto.createdAt,
    updatedAt: dto.updatedAt,
  );
}
