import '../../../../core/failure/failure.dart';
import 'entry.dart';
import 'pending_entry_write.dart';

/// A single `EntryRecordCard`'s own sync badge (AD-10) — exactly the 3
/// states `docs/input/backend/sync-badge.md` names, never a 4th: the
/// server exposes no sync field of its own, so these 3 are the complete
/// set this app ever needs to render. Sealed, with `const factory`
/// constructors on the base class (mirrors `Failure`'s own shape, minus
/// the `freezed` codegen — no `==`/`copyWith` machinery is needed here
/// beyond the hand-rolled equality each subclass already carries) so call
/// sites read as `SyncBadgeState.synchronizing()` rather than naming each
/// subclass directly.
sealed class SyncBadgeState {
  const SyncBadgeState();

  const factory SyncBadgeState.synchronizing() = SyncBadgeSynchronizing;

  const factory SyncBadgeState.synchronized() = SyncBadgeSynchronized;

  const factory SyncBadgeState.error(Failure failure) = SyncBadgeError;
}

/// "Synchronizing" (ochre) — a local write not yet confirmed by the
/// server.
class SyncBadgeSynchronizing extends SyncBadgeState {
  const SyncBadgeSynchronizing();

  @override
  bool operator ==(Object other) => other is SyncBadgeSynchronizing;

  @override
  int get hashCode => (SyncBadgeSynchronizing).hashCode;

  @override
  String toString() => 'SyncBadgeSynchronizing()';
}

/// "Synchronized" (green) — nothing pending for this entry; the last
/// confirmed write matched.
class SyncBadgeSynchronized extends SyncBadgeState {
  const SyncBadgeSynchronized();

  @override
  bool operator ==(Object other) => other is SyncBadgeSynchronized;

  @override
  int get hashCode => (SyncBadgeSynchronized).hashCode;

  @override
  String toString() => 'SyncBadgeSynchronized()';
}

/// "Synchronization error" (red) — the write was attempted and failed,
/// never yet reconciled. [failure] is kept so the badge's own tap handler
/// (`SyncBadge`) can read [Failure.retryable]/[Failure.message] directly,
/// per the Boundaries' "Tap on error badge" rule.
class SyncBadgeError extends SyncBadgeState {
  const SyncBadgeError(this.failure);

  final Failure failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncBadgeError && other.failure == failure);

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'SyncBadgeError(failure: $failure)';
}

/// The one place this app ever decides a card's badge (Never: "any screen
/// recomputing badge state inline") — pure, no I/O, no `package:flutter`
/// import (RNF06).
///
/// [pending] wins whenever it's non-null, regardless of [entry] — per
/// `sync-badge.md`, "Synchronizing"/"Synchronization error" both describe
/// *client-side pending state*, not anything read off [entry] itself, so a
/// pending write's own status is always the authoritative answer for
/// whichever card it belongs to. Once [pending] is `null`, the existence of
/// a confirmed [entry] already means "it is on the server" (sync-
/// badge.md: "it is on the server already means synchronized, by
/// definition") -> [SyncBadgeSynchronized]. [entry] and [pending] both
/// `null` is unreachable from every real caller (`MeusRegistrosLoaded`
/// always derives a displayed card from one or the other, never neither)
/// but still resolves to [SyncBadgeSynchronized] rather than throwing
/// (RNF09-style defensiveness) — "nothing pending" is the closest true
/// reading of that combination regardless of [entry].
SyncBadgeState deriveSyncBadgeState(Entry? entry, PendingEntryWrite? pending) {
  if (pending != null) {
    return switch (pending.status) {
      PendingEntryWriteInFlight() => const SyncBadgeState.synchronizing(),
      PendingEntryWriteFailed(failure: final failure) => SyncBadgeState.error(
        failure,
      ),
    };
  }
  return const SyncBadgeState.synchronized();
}
