/// `chat.sessions.list`/`chat.sessions.create`'s own `personaSnapshot` enum
/// (`openapi.yaml`) — the persona is frozen onto the session at creation
/// time ("persona taken from the profile at creation", `openapi.yaml`'s own
/// summary for `chat.sessions.create`); this story never reads or surfaces
/// it anywhere in the UI (Boundaries: no persona selector exists yet,
/// RF08's extension scope), it's modeled here only because the response
/// shape requires it.
enum ChatPersona { analitico, empatico, socratico }

/// A chat session — `chat.sessions.list`/`chat.sessions.create`'s own
/// response `data` object (`openapi.yaml:1026-1059`/`:1098-1135`), modeled
/// 1:1. This story's own session bootstrap (Design Notes: "kept in memory
/// only") is [ChatCubit.init]'s job, not this entity's — a plain value
/// type, no `freezed` (mirrors `Entry`: no union/copyWith machinery
/// needed here either).
class ChatSession {
  const ChatSession({
    required this.id,
    required this.title,
    required this.persona,
    required this.userMessageCount,
    required this.lastUserMessageAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final ChatPersona persona;
  final int userMessageCount;

  /// `null` for a session with no user message sent yet.
  final String? lastUserMessageAt;
  final String createdAt;
  final String updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatSession &&
          other.id == id &&
          other.title == title &&
          other.persona == persona &&
          other.userMessageCount == userMessageCount &&
          other.lastUserMessageAt == lastUserMessageAt &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    persona,
    userMessageCount,
    lastUserMessageAt,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'ChatSession(id: $id, title: $title, persona: $persona, '
      'userMessageCount: $userMessageCount, '
      'lastUserMessageAt: $lastUserMessageAt, createdAt: $createdAt, '
      'updatedAt: $updatedAt)';
}
