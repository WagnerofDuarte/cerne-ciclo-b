import '../../domain/entities/entry.dart';
import '../../domain/entities/entry_date_group.dart';
import '../../domain/entities/pending_entry_write.dart';
import '../../domain/entities/sync_badge_state.dart';

/// `MeusRegistrosScreen`'s own sealed state — never the shared
/// `Resource<T>` (Boundaries, mirrors `capture`'s `TextEntryState`
/// sealed-class convention, `resource.dart`'s own doc already excludes
/// RF07 the same way): this screen's shape — a first load, a grouped list
/// with its own pagination sub-state, an empty result, or a terminal
/// error — doesn't fit that single-fetch lifecycle.
sealed class MeusRegistrosState {
  const MeusRegistrosState();
}

/// The first page is in flight — `MeusRegistrosScreen` shows a skeleton
/// for this only past the shared 300ms threshold (RNF01), mirroring
/// `BootSplashScreen`'s own `Timer` pattern; blank below it.
class MeusRegistrosLoading extends MeusRegistrosState {
  const MeusRegistrosLoading();
}

/// The first page resolved with zero entries — `MeusRegistrosScreen`'s
/// `_EmptyState` renders the prototype's Tela 4 — Vazio dedicated empty
/// state (icon, copy, "Criar primeiro registro" CTA opening the Insertion
/// Modal) for this (story 4.3).
class MeusRegistrosEmpty extends MeusRegistrosState {
  const MeusRegistrosEmpty();
}

/// The first load failed with a `Failure` the repository's own
/// offline/Hive fallback never absorbs (e.g. `Failure.authExpired`) —
/// [message] is `Failure.message` verbatim, same convention
/// `TextEntryError.message` already uses.
class MeusRegistrosError extends MeusRegistrosState {
  const MeusRegistrosError({required this.message});

  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MeusRegistrosError && other.message == message);

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'MeusRegistrosError(message: $message)';
}

/// A resolved page — [entries] accumulates every page fetched so far
/// (first load plus every successful [MeusRegistrosCubit.loadMore]),
/// already de-duplicated by id. [groups] re-derives the grouped view via
/// the pure `groupEntriesByDate()` on every read rather than this state
/// storing a separately-maintained, pre-grouped copy that `loadMore` would
/// otherwise have to keep in sync by hand.
class MeusRegistrosLoaded extends MeusRegistrosState {
  const MeusRegistrosLoaded({
    required this.entries,
    required this.nextCursor,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
    this.pendingWrites = const [],
  });

  final List<Entry> entries;

  /// `null` once the server's `meta.nextCursor` says there's no further
  /// page — also always `null` for a page served from the offline Hive
  /// fallback (Boundaries).
  final String? nextCursor;

  /// `true` for the duration of one in-flight `loadMore()` call —
  /// `MeusRegistrosScreen`'s list footer shows a small spinner for this,
  /// distinct from the first load's full-screen skeleton.
  final bool isLoadingMore;

  /// `true` after a `loadMore()` attempt fails — I/O matrix: "keeps
  /// current items + inline retry". [entries] is left exactly as it was;
  /// only the footer switches to a retry affordance.
  final bool loadMoreFailed;

  /// spec-4-2 — every write `PendingEntryWriteTracker` currently holds
  /// (in flight or failed), mirrored from its own `pendingWrites` stream
  /// by `MeusRegistrosCubit`. Never contains a write that's already
  /// confirmed — that one has already moved into [entries] instead
  /// (`MeusRegistrosCubit._onEntryConfirmed`).
  final List<PendingEntryWrite> pendingWrites;

  /// [entries] with each [pendingWrites] member rendered as its own
  /// placeholder [Entry] (content/source/[mediaDurationSeconds] from the
  /// pending write itself; `occurredAt` = [PendingEntryWrite.startedAt]),
  /// prepended ahead of [entries] — Boundaries: "Card appears top-of-
  /// today... before server responds". Grouping this combined list by day
  /// (via the same [groupEntriesByDate] every confirmed entry already
  /// uses) naturally lands a pending write's own card at the top of
  /// "Hoje", with no separate rendering path needed in the screen itself.
  ///
  /// [pendingWrites] itself holds insertion order (oldest-started first,
  /// `PendingEntryWriteTrackerImpl`'s own `Map` — Review finding, round 2):
  /// reversed here so two writes pending at once still land newest-first,
  /// matching [groupEntriesByDate]'s documented "callers always pass
  /// entries already newest-first" contract.
  List<Entry> get _displayEntries => [
    for (final pending in pendingWrites.reversed) _placeholderEntryFor(pending),
    ...entries,
  ];

  List<EntryDateGroup> get groups => groupEntriesByDate(_displayEntries);

  /// [entry]'s own badge (Code Map/Never: the one call site for
  /// `deriveSyncBadgeState()` outside its own unit tests). [entry] is
  /// looked up against [pendingWrites] by id — a placeholder [Entry]
  /// built by [_displayEntries] always has [PendingEntryWrite.tempId] as
  /// its [Entry.id], so this matches it back to its own pending write; a
  /// genuinely confirmed [Entry] from [entries] never matches one (the
  /// tracker's own `create()`/`retry()` already remove a pending record
  /// before `MeusRegistrosCubit` ever prepends the matching confirmed
  /// entry, so the two can never coexist here).
  SyncBadgeState badgeFor(Entry entry) {
    for (final pending in pendingWrites) {
      if (pending.tempId == entry.id) {
        return deriveSyncBadgeState(null, pending);
      }
    }
    return deriveSyncBadgeState(entry, null);
  }

  MeusRegistrosLoaded copyWith({
    List<Entry>? entries,
    String? nextCursor,
    bool? isLoadingMore,
    bool? loadMoreFailed,
    List<PendingEntryWrite>? pendingWrites,
  }) {
    return MeusRegistrosLoaded(
      entries: entries ?? this.entries,
      nextCursor: nextCursor ?? this.nextCursor,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
      pendingWrites: pendingWrites ?? this.pendingWrites,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MeusRegistrosLoaded &&
          other.nextCursor == nextCursor &&
          other.isLoadingMore == isLoadingMore &&
          other.loadMoreFailed == loadMoreFailed &&
          _listEquals(other.entries, entries) &&
          _listEquals(other.pendingWrites, pendingWrites));

  @override
  int get hashCode => Object.hash(
    Object.hashAll(entries),
    nextCursor,
    isLoadingMore,
    loadMoreFailed,
    Object.hashAll(pendingWrites),
  );

  @override
  String toString() =>
      'MeusRegistrosLoaded(entries: ${entries.length}, nextCursor: '
      '$nextCursor, isLoadingMore: $isLoadingMore, loadMoreFailed: '
      '$loadMoreFailed, pendingWrites: ${pendingWrites.length})';
}

Entry _placeholderEntryFor(PendingEntryWrite pending) {
  final startedAtIso = pending.startedAt.toIso8601String();
  return Entry(
    id: pending.tempId,
    content: pending.content,
    source: pending.source,
    chatMessageId: null,
    occurredAt: startedAtIso,
    serverRevision: 0,
    createdAt: startedAtIso,
    updatedAt: startedAtIso,
    mediaDurationSeconds: pending.mediaDurationSeconds,
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
