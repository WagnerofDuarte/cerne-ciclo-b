import '../../../../core/failure/failure.dart';
import '../../domain/entities/chat_message.dart';

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
    this.isSending = false,
  });

  final String sessionId;

  /// Append-only for the lifetime of this cubit (Code Map) — a message is
  /// ever only added to the end, or mutated in place by id (a streaming
  /// AI bubble's own `content`/`status`), never removed or reordered.
  final List<ChatUiMessage> messages;

  /// Whether `ChatCubit.sendMessage`'s own send is actively in flight —
  /// the composer's one enable/disable signal (`_ChatComposer`). Kept as
  /// its own field rather than derived by scanning [messages] for a
  /// persisted `streaming` status: a message restored from history/cache
  /// can legitimately carry that status without a send being in flight
  /// (I/O matrix: mid-stream drop), which would otherwise permanently
  /// disable the composer.
  final bool isSending;

  ChatReady copyWith({List<ChatUiMessage>? messages, bool? isSending}) =>
      ChatReady(
        sessionId: sessionId,
        messages: messages ?? this.messages,
        isSending: isSending ?? this.isSending,
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
