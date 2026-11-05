/// One parsed SSE event from `chat.messages.send`'s streaming response
/// (`openapi.yaml`: `message_created -> context -> token* -> done|error`,
/// in this order). `context` is intentionally never modeled here — the
/// Boundaries explicitly exclude "rendering the SSE `context` event's
/// retrieval/citation data"; `ChatRemoteDataSource` receives and discards
/// it before it would ever become one of these. `error` likewise never
/// becomes a member of this type — it's a terminal failure, surfaced as
/// `Left(Failure.fromCode(...))` by the same stream this event type flows
/// through (`ChatRepository.sendMessage`'s own `Stream<Either<Failure,
/// ChatStreamEvent>>`), never wrapped as a `Right` value.
///
/// A plain sealed class, not `freezed` (mirrors `core/resource.dart`'s own
/// `Resource<T>` — AD-12's prose: "Chat's state is its own sealed class,
/// never forced into `Resource<T>`" extends to this smaller stream-event
/// type too, no union/copyWith machinery needed for 3 fixed, flat shapes).
sealed class ChatStreamEvent {
  const ChatStreamEvent();
}

/// Design Notes: "`message_created` carries the persisted user-message
/// id" — the id the backend just assigned to the user's own just-sent
/// message (not the AI response being generated). Unused by this story's
/// own `ChatCubit` (no retry-by-id feature yet, Boundaries) — modeled now
/// so Story 6.3's retry call has a value to key off without re-parsing the
/// stream.
class ChatMessageCreatedEvent extends ChatStreamEvent {
  const ChatMessageCreatedEvent(this.userMessageId);

  final String userMessageId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMessageCreatedEvent &&
          other.userMessageId == userMessageId);

  @override
  int get hashCode => userMessageId.hashCode;

  @override
  String toString() => 'ChatMessageCreatedEvent(userMessageId: $userMessageId)';
}

/// One `token` event's `delta` — Design Notes: "this spec assumes `token`
/// carries a `delta` text field". `ChatCubit` appends [delta] onto the
/// streaming AI bubble's content on every emission.
class ChatTokenEvent extends ChatStreamEvent {
  const ChatTokenEvent(this.delta);

  final String delta;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ChatTokenEvent && other.delta == delta);

  @override
  int get hashCode => delta.hashCode;

  @override
  String toString() => 'ChatTokenEvent(delta: $delta)';
}

/// The stream's own successful terminator — marks the AI bubble `complete`.
class ChatDoneEvent extends ChatStreamEvent {
  const ChatDoneEvent();

  @override
  bool operator ==(Object other) => other is ChatDoneEvent;

  @override
  int get hashCode => (ChatDoneEvent).hashCode;

  @override
  String toString() => 'ChatDoneEvent()';
}
