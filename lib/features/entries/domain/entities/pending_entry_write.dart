import '../../../../core/failure/failure.dart';
import 'entry.dart';

/// A [PendingEntryWrite]'s own lifecycle — exactly the two states spec-4-2
/// needs (Boundaries: "status = inFlight or failed(Failure)"). A write that
/// resolves successfully is never represented here at all: `PendingEntry
/// WriteTracker.create()`/`retry()` drop the record outright on success
/// (Boundaries: "tracker drops the record") rather than modeling a third
/// "confirmed" variant — nothing downstream ever needs to render a pending
/// write as confirmed, only to stop rendering it as pending.
sealed class PendingEntryWriteStatus {
  const PendingEntryWriteStatus();
}

/// The write is in flight — `create()`/`retry()` already called the
/// repository, no response yet.
class PendingEntryWriteInFlight extends PendingEntryWriteStatus {
  const PendingEntryWriteInFlight();

  @override
  bool operator ==(Object other) => other is PendingEntryWriteInFlight;

  @override
  int get hashCode => (PendingEntryWriteInFlight).hashCode;

  @override
  String toString() => 'PendingEntryWriteInFlight()';
}

/// The write's last attempt failed — [failure] is kept verbatim so a later
/// retry can replay the exact same payload, and so `deriveSyncBadgeState()`
/// can read [Failure.retryable] off it directly (Boundaries: "Tap on error
/// badge: if `failure.retryable`...").
class PendingEntryWriteFailed extends PendingEntryWriteStatus {
  const PendingEntryWriteFailed({required this.failure});

  final Failure failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingEntryWriteFailed && other.failure == failure);

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'PendingEntryWriteFailed(failure: $failure)';
}

/// A capture write (`TextEntryCubit`/`AudioEntryCubit`/`PhotoEntryCubit`'s
/// own `save()`) that `PendingEntryWriteTracker` is currently tracking —
/// either still in flight or failed-but-not-yet-retried (Intent). [tempId]
/// is a client-generated id (`PendingEntryWriteTrackerImpl`'s own
/// generator), never the server's real `Entry.id` — it exists only so
/// [PendingEntryWriteTracker.retry] and `MeusRegistrosCubit`'s own per-card
/// lookup (`MeusRegistrosLoaded.badgeFor`) have something stable to key on
/// while the write has no server-assigned id yet.
///
/// Plain hand-rolled equality (existing convention — mirrors [Entry]/
/// [EntryDateGroup], never `freezed`, Tasks: "hand-rolled equality
/// (existing convention)").
class PendingEntryWrite {
  const PendingEntryWrite({
    required this.tempId,
    required this.content,
    required this.source,
    required this.mediaDurationSeconds,
    required this.startedAt,
    required this.status,
  });

  final String tempId;
  final String content;
  final EntrySource source;

  /// Carried through verbatim for a retry's own replayed `create()` call —
  /// mirrors [Entry.mediaDurationSeconds]'s own "non-null only for audio"
  /// contract.
  final int? mediaDurationSeconds;

  /// When this write first started — also doubles as the placeholder
  /// card's own `occurredAt` while pending (`MeusRegistrosLoaded`'s own
  /// placeholder-`Entry` construction), so a pending write always renders
  /// at the top of "Hoje" until it resolves.
  final DateTime startedAt;

  final PendingEntryWriteStatus status;

  PendingEntryWrite copyWith({PendingEntryWriteStatus? status}) =>
      PendingEntryWrite(
        tempId: tempId,
        content: content,
        source: source,
        mediaDurationSeconds: mediaDurationSeconds,
        startedAt: startedAt,
        status: status ?? this.status,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingEntryWrite &&
          other.tempId == tempId &&
          other.content == content &&
          other.source == source &&
          other.mediaDurationSeconds == mediaDurationSeconds &&
          other.startedAt == startedAt &&
          other.status == status);

  @override
  int get hashCode => Object.hash(
    tempId,
    content,
    source,
    mediaDurationSeconds,
    startedAt,
    status,
  );

  @override
  String toString() =>
      'PendingEntryWrite(tempId: $tempId, content: $content, source: '
      '$source, mediaDurationSeconds: $mediaDurationSeconds, startedAt: '
      '$startedAt, status: $status)';
}
