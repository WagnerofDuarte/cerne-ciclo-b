import '../../domain/entities/entry.dart';
import '../../domain/entities/sync_badge_state.dart';

/// `EntryDetailScreen`'s own sealed state (spec-4-4, Code Map) — mirrors
/// `MeusRegistrosState`'s shape (a loading/resolved/empty-ish/error split),
/// never the shared `Resource<T>` (same exclusion rationale
/// `MeusRegistrosState`'s own doc already gives): this screen's one-shot
/// fetch still has its own distinct "not found" outcome `Resource<T>`
/// doesn't model.
sealed class EntryDetailState {
  const EntryDetailState();
}

/// The one `EntriesRepository.getById` fetch is in flight — `EntryDetail
/// Screen` renders nothing below this (no skeleton of its own; this
/// screen has no prototype precedent to match, Intent).
class EntryDetailLoading extends EntryDetailState {
  const EntryDetailLoading();
}

/// The fetch resolved to a real [Entry] — [badgeState] is always
/// [SyncBadgeState.synchronized] in practice (Boundaries: "a fetched Entry
/// is always server-confirmed"), still derived through the one shared
/// `deriveSyncBadgeState()` rather than hardcoded here (Never: "a second
/// sync-badge derivation path").
class EntryDetailData extends EntryDetailState {
  const EntryDetailData({required this.entry, required this.badgeState});

  final Entry entry;
  final SyncBadgeState badgeState;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntryDetailData &&
          other.entry == entry &&
          other.badgeState == badgeState);

  @override
  int get hashCode => Object.hash(entry, badgeState);

  @override
  String toString() =>
      'EntryDetailData(entry: ${entry.id}, badgeState: $badgeState)';
}

/// `Failure.notFound` specifically — an id that never existed or belongs
/// to another user (RNF04). Kept as its own sealed variant purely so a
/// test can assert exactly which `Failure` produced a given outcome;
/// `EntryDetailScreen` renders this identically to [EntryDetailError]
/// (RNF04's "never a distinguishable permission-denied state" extends
/// here to "never a distinguishable failure-reason state" either, Code
/// Map) — the two variants never look different on screen.
class EntryDetailNotFound extends EntryDetailState {
  const EntryDetailNotFound();
}

/// Every other `Failure` this screen's fetch can surface that the
/// repository's own offline/timeout cache fallback doesn't absorb (e.g. a
/// cache-miss `networkOffline`/`networkTimeout`, or any backend code the
/// fallback never intercepts) — Boundaries: "`Failure.notFound` (and any
/// other failure the cache doesn't absorb) renders one generic not-found
/// treatment". [message] is [Failure.message] verbatim (same convention
/// `MeusRegistrosError.message` already uses) but is never actually
/// surfaced as screen copy — kept only for this state's own equality/
/// toString and tests.
class EntryDetailError extends EntryDetailState {
  const EntryDetailError({required this.message});

  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntryDetailError && other.message == message);

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'EntryDetailError(message: $message)';
}
