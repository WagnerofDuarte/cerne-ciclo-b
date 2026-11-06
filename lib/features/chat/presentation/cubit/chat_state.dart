import '../../../../core/failure/failure.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_session.dart';

/// `ChatCubit`'s own sealed state — AD-12: "Chat's state is its own sealed
/// class, never forced into `Resource<T>`", because it isn't a single
/// fetch (the append-only [ChatReady.messages] list keeps growing one
/// token at a time while a response streams in, long after the initial
/// bootstrap fetch that produced it has already resolved).
sealed class ChatState {
  const ChatState();
}

/// The initial state, and the state while `ChatCubit.init()`'s own
/// session-bootstrap (list-or-create-one-session) + history fetch are
/// still in flight.
class ChatBootstrapLoading extends ChatState {
  const ChatBootstrapLoading();
}

/// I/O matrix: "Bootstrap failure" — `chat-sessions-list`/`create` (or the
/// history fetch right after) failed; the screen shows this generic error
/// state instead of spinning forever.
class ChatBootstrapError extends ChatState {
  const ChatBootstrapError(this.failure);

  final Failure failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatBootstrapError && other.failure == failure);

  @override
  int get hashCode => failure.hashCode;
}

/// The composer is enabled, [messages] renders — [ChatUiMessage]'s own
/// [ChatUiMessage.status] drives each bubble's one of the 3 visible states
/// (streaming/failed/complete, RF04's Acceptance Criteria).
class ChatReady extends ChatState {
  const ChatReady({
    required this.sessionId,
    required this.messages,
    required this.sessions,
    this.isSending = false,
    this.restoreScrollOffset,
  });

  final String sessionId;

  /// Append-only for the lifetime of this cubit (Code Map) — a message is
  /// ever only added to the end, or mutated in place by id (a streaming
  /// AI bubble's own `content`/`status`), never removed or reordered.
  final List<ChatUiMessage> messages;

  /// Every Chat Session the drawer's own "CONVERSAS" section renders
  /// (spec-6-2 Code Map) — populated once by `ChatCubit._bootstrap`'s own
  /// `listSessions()`/`createSession()` call, then kept current by
  /// `ChatCubit.startNewSession` prepending its own result. Never
  /// re-fetched/paginated past that first page (Boundaries: "Never:
  /// paginating past the backend's default first page").
  final List<ChatSession> sessions;

  /// Whether `ChatCubit.sendMessage`'s own send is actively in flight —
  /// the composer's one enable/disable signal (`_ChatComposer`). Kept as
  /// its own field rather than derived by scanning [messages] for a
  /// persisted `streaming` status: a message restored from history/cache
  /// can legitimately carry that status without a send being in flight
  /// (I/O matrix: mid-stream drop), which would otherwise permanently
  /// disable the composer.
  final bool isSending;

  /// The scroll offset `ChatScreen` should jump to the moment this exact
  /// [ChatReady] becomes the active session (spec-6-2 I/O matrix: "Switch
  /// session") — `ChatCubit._scrollOffsets[sessionId]`'s own last
  /// recorded value, or `null` when none was ever recorded (a brand new
  /// session, or a session visited for the first time this app run),
  /// which `ChatScreen` reads as "jump to bottom instead" (Code Map).
  /// Deliberately never cleared by the cubit itself once set — `ChatScreen`
  /// only consults it the instant [sessionId] changes from the previous
  /// state it observed, so a later unrelated emit (e.g. a streamed token)
  /// carrying the same value forward via [copyWith] is harmless (Design
  /// Notes).
  final double? restoreScrollOffset;

  ChatReady copyWith({
    List<ChatUiMessage>? messages,
    List<ChatSession>? sessions,
    bool? isSending,
    double? restoreScrollOffset,
  }) => ChatReady(
    sessionId: sessionId,
    messages: messages ?? this.messages,
    sessions: sessions ?? this.sessions,
    isSending: isSending ?? this.isSending,
    restoreScrollOffset: restoreScrollOffset ?? this.restoreScrollOffset,
  );
}

/// One bubble's own presentation-layer shape — distinct from the domain
/// `ChatMessage` entity (Code Map) because a message in flight has no
/// server-assigned `seq`/`retryCount`/`createdAt` yet; [id] is a locally
/// generated, UI-only identifier (`ChatCubit._nextLocalId()`), never the
/// server's own message id (Design Notes: `message_created`'s id is the
/// *user* message's server id, unused by this story — see
/// `ChatStreamEvent`'s own doc).
class ChatUiMessage {
  const ChatUiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.status,
  });

  final String id;
  final ChatMessageRole role;
  final String content;
  final ChatMessageStatus status;

  ChatUiMessage copyWith({String? content, ChatMessageStatus? status}) =>
      ChatUiMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        status: status ?? this.status,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatUiMessage &&
          other.id == id &&
          other.role == role &&
          other.content == content &&
          other.status == status);

  @override
  int get hashCode => Object.hash(id, role, content, status);

  @override
  String toString() =>
      'ChatUiMessage(id: $id, role: $role, content: $content, '
      'status: $status)';
}
