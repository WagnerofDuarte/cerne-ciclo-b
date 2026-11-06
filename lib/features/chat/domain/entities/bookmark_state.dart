import '../../../../core/failure/failure.dart';

/// spec-6-4 — a single user-only chat bubble's own bookmark affordance
/// (AGENTS.md: "a four-state... idle/saving/saved/error bookmark button to
/// user-only chat bubbles"), mirrors `entries/domain/entities/
/// sync_badge_state.dart`'s own per-feature placement/shape: sealed, with
/// `const factory` constructors on the base class so call sites read as
/// `BookmarkState.idle()` rather than naming each subclass directly.
/// Never persisted across restarts (Never) — in-memory only, on
/// `ChatUiMessage.bookmarkState`.
sealed class BookmarkState {
  const BookmarkState();

  const factory BookmarkState.idle() = BookmarkIdle;

  const factory BookmarkState.saving() = BookmarkSaving;

  const factory BookmarkState.saved() = BookmarkSaved;

  const factory BookmarkState.error(Failure failure) = BookmarkError;
}

/// The default state — outline icon, tappable.
class BookmarkIdle extends BookmarkState {
  const BookmarkIdle();

  @override
  bool operator ==(Object other) => other is BookmarkIdle;

  @override
  int get hashCode => (BookmarkIdle).hashCode;

  @override
  String toString() => 'BookmarkIdle()';
}

/// The save is in flight — spinner (or a static label under Reduce
/// Motion, `ChatBubble`'s own concern, not this state's).
class BookmarkSaving extends BookmarkState {
  const BookmarkSaving();

  @override
  bool operator ==(Object other) => other is BookmarkSaving;

  @override
  int get hashCode => (BookmarkSaving).hashCode;

  @override
  String toString() => 'BookmarkSaving()';
}

/// The save succeeded — ochre check (`colorAccent`). Tapping an already-
/// [BookmarkSaved] bubble is a client-side no-op (Boundaries).
class BookmarkSaved extends BookmarkState {
  const BookmarkSaved();

  @override
  bool operator ==(Object other) => other is BookmarkSaved;

  @override
  int get hashCode => (BookmarkSaved).hashCode;

  @override
  String toString() => 'BookmarkSaved()';
}

/// The save failed — red warning, retryable: tapping it re-attempts the
/// same save (I/O matrix: "Save fails"). [failure] is kept for parity with
/// `SyncBadgeError`'s own shape, even though `ChatBubble` only ever needs
/// the state's own identity (icon/color), never [failure]'s own message —
/// no UI surface for it exists in this story's Boundaries.
class BookmarkError extends BookmarkState {
  const BookmarkError(this.failure);

  final Failure failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookmarkError && other.failure == failure);

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'BookmarkError(failure: $failure)';
}
