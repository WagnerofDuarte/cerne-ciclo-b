/// `chat.messages.list`'s own `role` enum (`openapi.yaml:1188-1192`).
enum ChatMessageRole { user, assistant }

/// `chat.messages.list`'s own `status` enum (`openapi.yaml:1198-1203`) —
/// the exact 3 states RF04's own Acceptance Criteria names
/// ("processing/streaming, error, complete"), reused verbatim here rather
/// than a second near-duplicate enum: [ChatMessageStatus.failed] is this
/// story's "error" state, [ChatMessageStatus.streaming] its
/// "processing/streaming" state.
enum ChatMessageStatus { streaming, complete, failed }

/// A persisted chat message — `chat.messages.list`'s own response `data`
/// item (`openapi.yaml:1180-1218`), modeled 1:1. A plain value type, no
/// `freezed` (same rationale as [ChatSession]/`Entry`), but with a
/// `copyWith` — unlike those two, this entity's [content]/[status] mutate
/// repeatedly as a streaming response grows (`ChatCubit`'s own append-only
/// message list rebuilds entries of this exact shape on every `token`
/// event).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.seq,
    required this.status,
    required this.retryCount,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final ChatMessageRole role;
  final String content;
  final int seq;
  final ChatMessageStatus status;
  final int retryCount;
  final String createdAt;

  ChatMessage copyWith({String? content, ChatMessageStatus? status}) =>
      ChatMessage(
        id: id,
        sessionId: sessionId,
        role: role,
        content: content ?? this.content,
        seq: seq,
        status: status ?? this.status,
        retryCount: retryCount,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMessage &&
          other.id == id &&
          other.sessionId == sessionId &&
          other.role == role &&
          other.content == content &&
          other.seq == seq &&
          other.status == status &&
          other.retryCount == retryCount &&
          other.createdAt == createdAt);

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    role,
    content,
    seq,
    status,
    retryCount,
    createdAt,
  );

  @override
  String toString() =>
      'ChatMessage(id: $id, sessionId: $sessionId, role: $role, '
      'content: $content, seq: $seq, status: $status, '
      'retryCount: $retryCount, createdAt: $createdAt)';
}
