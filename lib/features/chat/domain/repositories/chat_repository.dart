import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../entities/chat_message.dart';
import '../entities/chat_session.dart';
import '../entities/chat_stream_event.dart';

/// The chat feature's one port — `features/chat/presentation` depends on
/// this abstract class only, never `chat/data` (RNF06). Every method but
/// [sendMessage] returns `Future<Either<Failure, T>>` (RNF09); [sendMessage]
/// alone returns a `Stream` given the SSE nature of its response
/// (Boundaries).
abstract class ChatRepository {
  /// Calls `chat-sessions-list` (`ApiClient.get`, via
  /// `ChatRemoteDataSource`) — works offline via the `chat_sessions` Hive
  /// box (Code Map): on [Failure.networkOffline]/[Failure.networkTimeout],
  /// falls back to a full dump of that box, same "cache fallback"
  /// convention `EntriesRepositoryImpl.list()` already uses for its own
  /// first/fresh page. Every other [Failure] propagates as `Left`,
  /// unmapped (RNF09).
  Future<Either<Failure, List<ChatSession>>> listSessions();

  /// Calls `chat-sessions-create` (`ApiClient.post`) with no title
  /// (Boundaries: "`chat-sessions-create` with no title") — blocked
  /// offline per `requirements.md` ("`POST /chat/sessions` — blocked
  /// offline"), so unlike [listSessions] there is no cache fallback here:
  /// every [Failure], including [Failure.networkOffline], is returned as
  /// `Left`, unmapped. On success, persists the new session to the
  /// `chat_sessions` Hive box before returning `Right`, same
  /// "persist then return" ordering [listSessions] already uses.
  Future<Either<Failure, ChatSession>> createSession();

  /// Calls `chat-messages-list` (`ApiClient.get`, [sessionId] appended as
  /// the one trailing path segment) — works offline via the
  /// `chat_messages` Hive box, same cache-fallback convention
  /// [listSessions] already uses, filtered to [sessionId] and sorted by
  /// `seq` ascending (the backend's own "ordered by seq", `openapi.yaml`).
  Future<Either<Failure, List<ChatMessage>>> listMessages(String sessionId);

  /// Calls `chat-messages-send` (`ApiClient.postStream`, [sessionId]
  /// appended as the one trailing path segment) with `{content}` — the
  /// one streaming exception to this port's otherwise all-`Future` shape
  /// (Boundaries/RNF09: "every other method returns
  /// `Future<Either<Failure, T>>`"). No connectivity resolves immediately
  /// to a single `Left(Failure.networkOffline)` emission, never queued
  /// (Boundaries) — `ApiClient.postStream`'s own first awaited `Dio.post`
  /// call surfaces that failure before any byte streams. A connection that
  /// closes without a `done`/`error` SSE event is surfaced as a single
  /// trailing `Left(Failure.networkTimeout)` (Design Notes: "the taxonomy
  /// has no dedicated 'dropped stream' code"). No local write queue, no
  /// Hive persistence of sent messages (Design Notes: chat holds no local
  /// write queue for this story).
  Stream<Either<Failure, ChatStreamEvent>> sendMessage(
    String sessionId,
    String content,
  );
}
