import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../entities/chat_insight.dart';
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

  /// spec-6-3 — calls `chat-messages-retry` (`ApiClient.postStream`,
  /// [sessionId] then [userMessageId] appended as the two trailing path
  /// segments, `data: const {}`) — regenerates the AI response for an
  /// already-persisted user message without re-sending its content
  /// (Boundaries: "never a duplicate question"). Same streaming shape and
  /// terminal handling as [sendMessage] (SSE events via
  /// `ChatRemoteDataSource`'s shared buffer/parse helper); [userMessageId]
  /// must be a real, already-persisted user message id — `ChatCubit`
  /// itself never calls this with one that's `null` (Boundaries: "Never
  /// calling `chat-messages-retry` with no `serverId`"), falling back to
  /// [sendMessage] instead in that case.
  Stream<Either<Failure, ChatStreamEvent>> retryMessage(
    String sessionId,
    String userMessageId,
  );

  /// spec-6-5 — calls `chat-insight-create` (`ApiClient.post`, [sessionId]
  /// appended as the one trailing path segment) with `{triggerType:
  /// triggerType.wireValue, triggerKey}`. `ChatCubit` fires this
  /// fire-and-forget, unawaited, through `isolatedSideEffect` — its first
  /// unawaited caller (Boundaries). `null` means "no insight to show": a
  /// successful (200) response whose `status` isn't `'ready'` — RF08:
  /// "never an HTTP error; a failure becomes status='failed'", so a
  /// genuine backend-side generation failure still arrives as a `Right`
  /// here, just carrying `null`. Only a transport-level problem (offline,
  /// timeout, malformed shape, etc.) surfaces as `Left`, unmapped
  /// (RNF09) — `ChatCubit` drops both cases silently either way
  /// (Boundaries).
  Future<Either<Failure, ChatInsight?>> generateInsight(
    String sessionId, {
    required InsightTriggerType triggerType,
    required String triggerKey,
  });
}
