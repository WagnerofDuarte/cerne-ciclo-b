import '../../domain/entities/entry.dart';
import '../../domain/entities/entry_date_group.dart';

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

/// The first page resolved with zero entries (Boundaries: "Zero entries ->
/// Plain 'no entries yet' text", no polished CTA — that's story 4.3).
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

  List<EntryDateGroup> get groups => groupEntriesByDate(entries);

  MeusRegistrosLoaded copyWith({
    List<Entry>? entries,
    String? nextCursor,
    bool? isLoadingMore,
    bool? loadMoreFailed,
  }) {
    return MeusRegistrosLoaded(
      entries: entries ?? this.entries,
      nextCursor: nextCursor ?? this.nextCursor,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MeusRegistrosLoaded &&
          other.nextCursor == nextCursor &&
          other.isLoadingMore == isLoadingMore &&
          other.loadMoreFailed == loadMoreFailed &&
          _listEquals(other.entries, entries));

  @override
  int get hashCode => Object.hash(
    Object.hashAll(entries),
    nextCursor,
    isLoadingMore,
    loadMoreFailed,
  );

  @override
  String toString() =>
      'MeusRegistrosLoaded(entries: ${entries.length}, nextCursor: '
      '$nextCursor, isLoadingMore: $isLoadingMore, loadMoreFailed: '
      '$loadMoreFailed)';
}

bool _listEquals(List<Entry> a, List<Entry> b) {
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
