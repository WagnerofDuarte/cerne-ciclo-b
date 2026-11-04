/// `POST /entries`'s four possible origins (`openapi.yaml:345-351`). This
/// story only ever produces [manual] (Boundaries: "source=manual for this
/// story") — the other three exist here already so the port
/// ([EntriesRepository.create]) doesn't need to change shape when Stories
/// 3.2/3.3 (audio/photo) and RF10 (chat) start passing them.
enum EntrySource { manual, audio, photo, chat }

/// A saved journal entry — plain `{id, content, source, chatMessageId,
/// occurredAt, serverRevision, createdAt, updatedAt, mediaDurationSeconds}`
/// class, no `freezed` (mirrors `AuthenticatedUser`: this feature has no
/// need for the union/copyWith machinery `Failure` uses). Boundaries:
/// never a field beyond this exact set — `tags`/`piiStatus`/`piiSpans`/
/// `embeddingStatus` still belong to later epics, not this story.
/// [mediaDurationSeconds] was the one field Story 3.1 deferred (its own
/// comment named it "later epics") — spec-3-2 is that story, for the
/// `source: audio` entries it produces.
///
/// [occurredAt]/[createdAt]/[updatedAt] are kept as the backend's own ISO
/// 8601 strings rather than parsed into `DateTime` — nothing in this story
/// reads or formats them (Design Notes: the Hive box nothing reads from
/// yet), so parsing would add risk (a malformed string throwing) with no
/// behavior to justify it.
class Entry {
  const Entry({
    required this.id,
    required this.content,
    required this.source,
    required this.chatMessageId,
    required this.occurredAt,
    required this.serverRevision,
    required this.createdAt,
    required this.updatedAt,
    this.mediaDurationSeconds,
  });

  final String id;
  final String content;
  final EntrySource source;

  /// Non-null only for a [EntrySource.chat]-sourced entry (RF10) — always
  /// `null` for this story's [EntrySource.manual] entries.
  final String? chatMessageId;
  final String occurredAt;
  final int serverRevision;
  final String createdAt;
  final String updatedAt;

  /// Non-null only for an [EntrySource.audio]-sourced entry
  /// (`AudioEntryCubit.save()`) — `null` for every other source.
  final int? mediaDurationSeconds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Entry &&
          other.id == id &&
          other.content == content &&
          other.source == source &&
          other.chatMessageId == chatMessageId &&
          other.occurredAt == occurredAt &&
          other.serverRevision == serverRevision &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.mediaDurationSeconds == mediaDurationSeconds);

  @override
  int get hashCode => Object.hash(
    id,
    content,
    source,
    chatMessageId,
    occurredAt,
    serverRevision,
    createdAt,
    updatedAt,
    mediaDurationSeconds,
  );

  @override
  String toString() =>
      'Entry(id: $id, content: $content, source: $source, '
      'chatMessageId: $chatMessageId, occurredAt: $occurredAt, '
      'serverRevision: $serverRevision, createdAt: $createdAt, '
      'updatedAt: $updatedAt, '
      'mediaDurationSeconds: $mediaDurationSeconds)';
}
