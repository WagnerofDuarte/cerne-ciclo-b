import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/entry.dart';
import '../../domain/entities/pending_entry_write.dart';
import '../../domain/repositories/entries_repository.dart';
import '../../domain/services/pending_entry_write_tracker.dart';
import 'meus_registros_state.dart';

/// Drives `MeusRegistrosScreen` — calls `EntriesRepository.list()` directly
/// (no use-case layer, matching this codebase's existing small-scope
/// convention: `AccountSettingsCubit`/`AuthCubit`/`TextEntryCubit`). A
/// `lazySingleton` (Code Map), like `AccountSettingsCubit` — long-lived, so
/// the already-fetched pages survive leaving and re-entering
/// `/meus-registros` within the same app session.
///
/// spec-4-2 — also subscribes to [PendingEntryWriteTracker.pendingWrites]/
/// `.confirmedWrites` for this cubit's whole lifetime (constructor-wired,
/// not `loadFirstPage()`-wired): both streams are shared singleton
/// broadcasts a capture cubit on a *different* screen can drive at any
/// time, and this cubit is itself a long-lived singleton that must reflect
/// them regardless of which screen is currently visible.
class MeusRegistrosCubit extends Cubit<MeusRegistrosState> {
  MeusRegistrosCubit(this._repository, this._tracker)
    : super(const MeusRegistrosLoading()) {
    _pendingSubscription = _tracker.pendingWrites.listen(
      _onPendingWritesChanged,
    );
    _confirmedSubscription = _tracker.confirmedWrites.listen(
      _onEntryConfirmed,
    );
  }

  final EntriesRepository _repository;
  final PendingEntryWriteTracker _tracker;
  late final StreamSubscription<List<PendingEntryWrite>> _pendingSubscription;
  late final StreamSubscription<({String tempId, Entry entry})>
  _confirmedSubscription;

  /// Mirrors the tracker's own latest snapshot regardless of [state]'s
  /// current type — so a pending write that arrives while [state] is
  /// still [MeusRegistrosLoading]/[MeusRegistrosError] isn't lost: the
  /// next [loadFirstPage] that resolves into [MeusRegistrosLoaded]/
  /// [MeusRegistrosEmpty] seeds itself from this field directly.
  List<PendingEntryWrite> _pendingWrites = const [];

  /// A monotonic counter guarding against a stale in-flight call's result
  /// landing after a newer call has already changed the state (e.g. the
  /// user leaves and quickly re-enters `/meus-registros` while a slow
  /// first request is still pending, or taps retry before the original
  /// request resolves). Incremented at the start of every [loadFirstPage],
  /// then captured locally before each `await` in [loadFirstPage]/
  /// [_fetchMore] — a result whose captured generation no longer matches
  /// this counter by the time it resolves is discarded rather than
  /// emitted.
  int _generation = 0;

  void _onPendingWritesChanged(List<PendingEntryWrite> pendingWrites) {
    _pendingWrites = pendingWrites;
    final current = state;
    if (current is MeusRegistrosLoaded) {
      emit(current.copyWith(pendingWrites: pendingWrites));
    } else if ((current is MeusRegistrosEmpty || current is MeusRegistrosError) &&
        pendingWrites.isNotEmpty) {
      // A capture save starts while this screen is showing "no entries
      // yet" or a load failure (Review finding: the latter previously
      // fell through this check entirely, silently dropping the pending
      // card) — its own placeholder card must still show immediately
      // (Acceptance Criteria), not wait for a reload.
      emit(
        MeusRegistrosLoaded(
          entries: const [],
          nextCursor: null,
          pendingWrites: pendingWrites,
        ),
      );
    }
    // MeusRegistrosLoading: nothing to overlay onto yet — [_pendingWrites]
    // above already keeps the latest snapshot, which the next
    // loadFirstPage() resolution reads directly.
  }

  void _onEntryConfirmed(({String tempId, Entry entry}) confirmation) {
    final entry = confirmation.entry;
    // Review finding: drops this write's own pending placeholder from
    // this cubit's *local* record synchronously with prepending the
    // confirmed entry, in the very same handler — the tracker's own
    // `pendingWrites` stream will also eventually deliver the matching
    // removal, but that's a separate `Stream.multi`-wrapped subscription
    // that can land one microtask late, which previously left a one-frame
    // window where both the stale placeholder and the real confirmed
    // entry rendered at once.
    _pendingWrites = [
      for (final pending in _pendingWrites)
        if (pending.tempId != confirmation.tempId) pending,
    ];
    final current = state;
    if (current is MeusRegistrosLoaded) {
      // Prepended, not reloaded (Design Notes) — preserves this cubit's
      // own pagination state (`nextCursor`/`loadMoreFailed`) exactly as
      // `loadMore()`'s own cursor-overlap robustness already relies on;
      // `_dedupedById` (unchanged) absorbs the degenerate case where a
      // later `list()`/`loadMore()` page's cursor also happens to repeat
      // this same (now server-known) id.
      emit(
        current.copyWith(
          entries: _dedupedById([entry, ...current.entries]),
          pendingWrites: _pendingWrites,
        ),
      );
    } else if (current is MeusRegistrosEmpty || current is MeusRegistrosError) {
      // Review finding: MeusRegistrosError previously fell through this
      // check too, same rationale as `_onPendingWritesChanged` above.
      emit(
        MeusRegistrosLoaded(
          entries: [entry],
          nextCursor: null,
          pendingWrites: _pendingWrites,
        ),
      );
    }
    // MeusRegistrosLoading: the next loadFirstPage() fetches the server's
    // own fresh page, which already includes this entry now that it's
    // confirmed server-side — nothing to reconcile.
  }

  /// `EntryRecordCard`'s own retry tap (`MeusRegistrosScreen`) — forwards
  /// to the shared tracker verbatim (Never: "a second retry endpoint").
  Future<void> retry(String tempId) => _tracker.retry(tempId);

  /// `MeusRegistrosScreen.initState` calls this once, every mount — always
  /// re-fetches from scratch rather than keeping a previous visit's page
  /// around, since a new entry may have been saved (Insertion Modal, Epic
  /// 3) since the last visit.
  Future<void> loadFirstPage() async {
    final generation = ++_generation;
    emit(const MeusRegistrosLoading());
    final result = await _repository.list();
    // Mirrors `AccountSettingsCubit.toggleBiometric`'s own guard: `close()`
    // can race this awaited call (e.g. a fast app teardown mid-request) —
    // `emit()` after `close()` would otherwise throw.
    if (isClosed || generation != _generation) {
      return;
    }
    result.match(
      (failure) {
        // Review finding (round 2): mirrors the success branch's own
        // `_pendingWrites` overlay below — a write already pending/failed
        // when the first page fails to load must still show its own
        // placeholder card, not disappear behind a plain error screen
        // until the next unrelated `pendingWrites` emission.
        if (_pendingWrites.isEmpty) {
          emit(MeusRegistrosError(message: failure.message));
          return;
        }
        emit(
          MeusRegistrosLoaded(
            entries: const [],
            nextCursor: null,
            pendingWrites: _pendingWrites,
          ),
        );
      },
      (page) {
        // Same degenerate-cursor distrust as `_fetchMore`'s own guard below:
        // a page reporting zero items is treated as exhausted regardless of
        // `page.nextCursor` — an empty first page with a non-null cursor
        // would otherwise strand the user on `MeusRegistrosEmpty` with no
        // way back to a cursor this state no longer tracks. Forced
        // unconditionally (Review finding, round 1): independent of
        // `_pendingWrites` below — a pending write outstanding over an
        // otherwise-empty first page must still null out the cursor, not
        // just skip the `MeusRegistrosEmpty` branch beneath it.
        final nextCursor = page.items.isEmpty ? null : page.nextCursor;
        // spec-4-2: a pending write already outstanding still needs its
        // own placeholder card to show, even over an otherwise-empty first
        // page — skips straight to `MeusRegistrosEmpty` only once neither
        // applies.
        if (page.items.isEmpty && _pendingWrites.isEmpty) {
          emit(const MeusRegistrosEmpty());
          return;
        }
        emit(
          MeusRegistrosLoaded(
            entries: _dedupedById(page.items),
            nextCursor: nextCursor,
            pendingWrites: _pendingWrites,
          ),
        );
      },
    );
  }

  /// `MeusRegistrosScreen`'s scroll listener calls this near the list's
  /// end. A no-op while not [MeusRegistrosLoaded], while
  /// [MeusRegistrosLoaded.nextCursor] is already `null`, while a call is
  /// already in flight, or — critically — once
  /// [MeusRegistrosLoaded.loadMoreFailed] is already `true`: without that
  /// last guard, a failed page's own footer swapping from a spinner to a
  /// "Tentar novamente" button can shift the list's `maxScrollExtent`
  /// just enough to leave the scroll position still inside the
  /// pre-fetch-buffer zone, re-firing this same listener and retrying
  /// forever — observed directly as an unbounded `pumpAndSettle` loop in
  /// this screen's own widget test. Once failed, only an explicit
  /// [retryLoadMore] (the footer's own button) tries again.
  Future<void> loadMore() => _fetchMore(isRetry: false);

  /// The footer's "Tentar novamente" button — the one path allowed to
  /// retry past a [MeusRegistrosLoaded.loadMoreFailed] of `true`
  /// ([loadMore]'s own doc).
  Future<void> retryLoadMore() => _fetchMore(isRetry: true);

  Future<void> _fetchMore({required bool isRetry}) async {
    final current = state;
    if (current is! MeusRegistrosLoaded ||
        current.nextCursor == null ||
        current.isLoadingMore ||
        (current.loadMoreFailed && !isRetry)) {
      return;
    }
    final generation = _generation;
    emit(current.copyWith(isLoadingMore: true, loadMoreFailed: false));
    final result = await _repository.list(cursor: current.nextCursor);
    if (isClosed || generation != _generation) {
      return;
    }
    // Re-reads `state` rather than closing over `current` — defensive
    // against `loadFirstPage()` having reset the state to something other
    // than `MeusRegistrosLoaded` while this await was pending.
    final latest = state;
    if (latest is! MeusRegistrosLoaded) {
      return;
    }
    result.match(
      (failure) =>
          emit(latest.copyWith(isLoadingMore: false, loadMoreFailed: true)),
      (page) {
        // I/O matrix: "Next page appended, no dup ids" — defensive
        // de-duplication in case a cursor-boundary entry is ever repeated
        // by the server, including a repeat *within* this same page
        // (`_dedupedById`'s running `seenIds` set covers both).
        final seenIds = latest.entries.map((entry) => entry.id).toSet();
        final newEntries = _dedupedById(page.items, seenIds: seenIds);
        // Defensive guard against a degenerate server response: if every
        // item in this "successful" page was already present by id (zero
        // genuinely-new entries) yet the server still reports a non-null
        // `nextCursor`, treat the page as exhausted rather than trusting
        // that cursor — otherwise a misbehaving/stuck server cursor could
        // make the scroll listener keep re-triggering `loadMore()`
        // indefinitely with no progress.
        final nextCursor = newEntries.isEmpty ? null : page.nextCursor;
        emit(
          MeusRegistrosLoaded(
            entries: [...latest.entries, ...newEntries],
            nextCursor: nextCursor,
            pendingWrites: latest.pendingWrites,
          ),
        );
      },
    );
  }

  @override
  Future<void> close() async {
    await _pendingSubscription.cancel();
    await _confirmedSubscription.cancel();
    return super.close();
  }
}

/// Filters [entries] down to the first occurrence of each id, checked
/// against [seenIds] (default empty) — covers both a duplicate against an
/// already-held id *and* a duplicate within [entries] itself, since a
/// local copy of [seenIds] accumulates as entries are walked (the caller's
/// own set, if any, is never mutated).
List<Entry> _dedupedById(List<Entry> entries, {Set<String>? seenIds}) {
  final seen = {...?seenIds};
  return [
    for (final entry in entries)
      if (seen.add(entry.id)) entry,
  ];
}
