// The constructor keeps public named params distinct from the private
// fields they initialize, same convention `entries_repository_impl.dart`
// already documents.
// ignore_for_file: prefer_initializing_formals
import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../../../core/failure/failure.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_session.dart';
import '../../domain/entities/chat_stream_event.dart';
import '../../domain/repositories/chat_repository.dart';
import '../datasources/chat_remote_data_source.dart';
import '../models/chat_message_dto.dart';
import '../models/chat_session_dto.dart';

/// On success, [listSessions]/[createSession]/[listMessages] each write
/// through to their own Hive box *before* returning `right(...)`, same
/// "persist then return" ordering `EntriesRepositoryImpl` already uses.
class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl({
    required ChatRemoteDataSource remoteDataSource,
    required Box<Map> sessionsBox,
    required Box<Map> messagesBox,
  }) : _remoteDataSource = remoteDataSource,
       _sessionsBox = sessionsBox,
       _messagesBox = messagesBox;

  final ChatRemoteDataSource _remoteDataSource;
  final Box<Map> _sessionsBox;
  final Box<Map> _messagesBox;

  @override
  Future<Either<Failure, List<ChatSession>>> listSessions() async {
    final result = await _remoteDataSource.listSessions();
    return result.match(
      (failure) async {
        // `requirements.md`: "`GET /chat/sessions` — works offline
        // (cache)" — same cursor-null-page cache-fallback convention
        // `EntriesRepositoryImpl.list()` already uses; every other
        // `Failure` (e.g. `authExpired`) propagates as `Left`, unmapped.
        if (failure is NetworkOffline || failure is NetworkTimeout) {
          return _cachedSessions();
        }
        return left(failure);
      },
      (dtos) async {
        try {
          await _sessionsBox.putAll({
            for (final dto in dtos) dto.id: dto.toJson(),
          });
        } catch (error) {
          // A thrown Hive/disk exception must never escape unmapped
          // (RNF09) — same fallback `EntriesRepositoryImpl`'s own writes
          // already use.
          return left(Failure.malformedResponse(message: error.toString()));
        }
        return right(dtos.map((dto) => dto.toEntity()).toList());
      },
    );
  }

  @override
  Future<Either<Failure, ChatSession>> createSession() async {
    final result = await _remoteDataSource.createSession();
    return result.match(
      // Blocked offline (`requirements.md`) — no cache fallback, unlike
      // [listSessions]/[listMessages]: every `Failure` propagates as
      // `Left`, unmapped.
      (failure) async => left(failure),
      (dto) async {
        // A local cache-write failure must never mask an already-
        // succeeded remote create: the session exists server-side
        // regardless, so surfacing `left(...)` here would show the user
        // a bootstrap error for an operation that actually succeeded
        // (it would simply be re-fetched via `listSessions()` next
        // time). Best-effort only.
        try {
          await _sessionsBox.put(dto.id, dto.toJson());
        } catch (_) {
          // Intentionally ignored — see above.
        }
        return right(dto.toEntity());
      },
    );
  }

  @override
  Future<Either<Failure, List<ChatMessage>>> listMessages(
    String sessionId,
  ) async {
    final result = await _remoteDataSource.listMessages(sessionId);
    return result.match(
      (failure) async {
        // `requirements.md`: "`GET /chat/sessions/:id/messages` — works
        // offline (cache)" — same convention [listSessions] above uses.
        if (failure is NetworkOffline || failure is NetworkTimeout) {
          return _cachedMessages(sessionId);
        }
        return left(failure);
      },
      (dtos) async {
        try {
          await _messagesBox.putAll({
            for (final dto in dtos) dto.id: dto.toJson(),
          });
        } catch (error) {
          return left(Failure.malformedResponse(message: error.toString()));
        }
        return right(dtos.map((dto) => dto.toEntity()).toList());
      },
    );
  }

  @override
  Stream<Either<Failure, ChatStreamEvent>> sendMessage(
    String sessionId,
    String content,
  ) =>
      // Design Notes: "Chat holds no local write queue" — a pure
      // passthrough, no Hive persistence of sent messages for this story.
      _remoteDataSource.sendMessage(sessionId, content);

  /// [listSessions]'s own offline/timeout fallback — a full `chat_
  /// sessions` Hive box dump, sorted `updatedAt` desc (so `ChatCubit.
  /// init()`'s own "reuse the most recent session" pick is already
  /// correctly ordered even against the cache), same "always `Right`,
  /// even if empty" convention `EntriesRepositoryImpl._offlineFallback()`
  /// already uses. Each entry is decoded independently — one corrupt
  /// cached entry is skipped, never discarding every other (valid)
  /// session in the box over it.
  Either<Failure, List<ChatSession>> _cachedSessions() {
    final sessions = <ChatSession>[];
    for (final json in _sessionsBox.values) {
      try {
        sessions.add(
          ChatSessionDto.fromJson(Map<String, dynamic>.from(json)).toEntity(),
        );
      } catch (_) {
        // Skip this one corrupt entry — see doc above.
      }
    }
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return right(sessions);
  }

  /// [listMessages]'s own offline/timeout fallback — a full `chat_
  /// messages` Hive box dump filtered to [sessionId] and sorted `seq`
  /// ascending (the backend's own "ordered by seq", `openapi.yaml`), same
  /// "always `Right`, even if empty" convention [_cachedSessions] above
  /// uses. Each entry is decoded independently, same corrupt-entry
  /// isolation as [_cachedSessions].
  Either<Failure, List<ChatMessage>> _cachedMessages(String sessionId) {
    final messages = <ChatMessage>[];
    for (final json in _messagesBox.values) {
      try {
        final message = ChatMessageDto.fromJson(
          Map<String, dynamic>.from(json),
        ).toEntity();
        if (message.sessionId == sessionId) {
          messages.add(message);
        }
      } catch (_) {
        // Skip this one corrupt entry — see doc above.
      }
    }
    messages.sort((a, b) => a.seq.compareTo(b.seq));
    return right(messages);
  }
}
