/// spec-6-5 — a single proactively generated insight. Appended onto
/// `ChatReady.activeInsight` as a plain nullable value (Intent: "never a
/// second state container"), rendered as the ochre-spine "INSIGHT" card at
/// the end of the message list. Plain value type, mirrors `ChatSession`:
/// no `freezed`/`copyWith` machinery needed, manual `==`/`hashCode`/
/// `toString`. Never persisted (Boundaries: "Never persist ChatInsight —
/// no new Hive box").
class ChatInsight {
  const ChatInsight({required this.id, required this.content});

  final String id;
  final String content;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatInsight && other.id == id && other.content == content);

  @override
  int get hashCode => Object.hash(id, content);

  @override
  String toString() => 'ChatInsight(id: $id, content: $content)';
}

/// The two trigger conditions `ChatCubit`'s own per-session window races
/// (Boundaries: "a counter ... and a Timer ... race; whichever hits its
/// threshold first") — a fixed user-message count vs. a fixed inactivity
/// timeout, whichever is satisfied first.
enum InsightTriggerType { messageCount, inactivity }

/// `chat-insight-create`'s own wire strings for [InsightTriggerType]
/// (`openapi.yaml`'s `message_count`/`inactivity` enum) — the member
/// names don't match them 1:1 (unlike `EntrySource.name`, which already
/// matches the backend's lowercase strings verbatim), so this extension
/// maps explicitly instead.
extension InsightTriggerTypeWireValue on InsightTriggerType {
  String get wireValue => switch (this) {
    InsightTriggerType.messageCount => 'message_count',
    InsightTriggerType.inactivity => 'inactivity',
  };
}
