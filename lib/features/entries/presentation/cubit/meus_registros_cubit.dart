import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/deduped_by_id.dart';
import '../../domain/entities/date_range_preset.dart';
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
    _confirmedSubscription = _tracker.confirmedWrites.listen(_onEntryConfirmed);
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

  /// spec-5-2 — the session-scoped filter selection (Design Notes): `null`
  /// for each field means "no filter of that kind", never a sentinel
  /// value. Reset to "no filters" by [loadFirstPage] itself (a fresh
  /// mount always starts from the full unfiltered timeline — same
  /// "always re-fetches from scratch" contract that method's own doc
  /// already gives, extended here to the filter selection too), set by
  /// [applyFilters], cleared by [clearFilters], and carried forward by
  /// every [_fetchMore] call so a paginated continuation never silently
  /// drops the filters its first page was fetched with.
  EntrySource? _activeSource;
  DateTime? _activeDateFrom;
  DateTime? _activeDateTo;

  /// Round-2 review fix: the [DateRangePreset] the active date range was
  /// actually selected from (if any), stored verbatim rather than
  /// re-derived from [_activeDateFrom] — a derivation-by-equality-match
  /// against a freshly recomputed "today" boundary goes stale the moment
  /// a day/week/month boundary rolls over while the filter stays active,
  /// mis-pre-selecting `EntriesFilterSheet`'s reopen state and mislabeling
  /// the active-filter chip. Defaults to [DateRangePreset.allTime] — same
  /// "no filter of that kind" convention [_activeDateFrom]/[_activeDateTo]
  /// already use, just non-nullable since [DateRangePreset] already has
  /// its own explicit "none" value.
  DateRangePreset _activeDateRangePreset = DateRangePreset.allTime;

  /// `MeusRegistrosScreen`'s own read of the current filter selection —
  /// deliberately not part of [MeusRegistrosState] itself: [applyFilters]/
  /// [clearFilters] already re-emit a new state on every change, so
  /// whichever `BlocBuilder` reads these getters during its own `builder`
  /// callback rebuilds in lockstep with them regardless.
  EntrySource? get activeSource => _activeSource;
  DateTime? get activeDateFrom => _activeDateFrom;
  DateTime? get activeDateTo => _activeDateTo;
  DateRangePreset get activeDateRangePreset => _activeDateRangePreset;

  /// `EntriesSearchBar.hasActiveFilters`/the active-filter chip row's own
  /// "is any filter active at all" check.
  bool get hasActiveFilters =>
      _activeSource != null || _activeDateFrom != null || _activeDateTo != null;

  /// Code-review fix (spec-5-2): whether [source]/[occurredAt] would pass
  /// the currently active filter selection — `true` unconditionally once
  /// [hasActiveFilters] is false. Guards every path below that would
  /// otherwise prepend/show a brand-new confirmed entry or pending-write
  /// placeholder that doesn't actually belong in the currently filtered
  /// view (Review finding: "a newly-created entry bypasses the active
  /// filter" — e.g. saving a manual-text entry while `source: audio` is
  /// active must never visibly violate that filter).
  ///
  /// Round-2 review fix: deliberately does not check [_activeDateTo] —
  /// unlike [_activeSource]/[_activeDateFrom], `dateTo` only narrows the
  /// server-side `list()` query in [_loadFiltered] (`_activeDateTo` is
  /// passed straight through there); [occurredAt] here is always a
  /// brand-new local entry/pending-write whose timestamp is effectively
  /// "now", so enforcing a `dateTo` frozen at the moment the filter was
  /// applied would permanently hide every entry created afterward for as
  /// long as "Esta semana"/"Este mês" stayed active — silently breaking
  /// the "new entries always show immediately" guarantee every other
  /// filter path here already upholds.
  bool _matchesActiveFilters({
    required EntrySource source,
    required DateTime occurredAt,
  }) {
    if (_activeSource != null && source != _activeSource) {
      return false;
    }
    if (_activeDateFrom != null && occurredAt.isBefore(_activeDateFrom!)) {
      return false;
    }
    return true;
  }

  /// [_pendingWrites] filtered down to the ones that actually match
  /// [_matchesActiveFilters] — [_pendingWrites] itself stays the tracker's
  /// own full, unfiltered bookkeeping (every write in flight/failed,
  /// regardless of the active filter), but a placeholder card for one
  /// that doesn't match the active filter must never render, same
  /// invariant a confirmed [Entry] gets below.
  List<PendingEntryWrite> get _visiblePendingWrites => _pendingWrites
      .where(
        (pending) => _matchesActiveFilters(
          source: pending.source,
          occurredAt: pending.startedAt,
        ),
      )
      .toList();

  void _onPendingWritesChanged(List<PendingEntryWrite> pendingWrites) {
    _pendingWrites = pendingWrites;
    final visible = _visiblePendingWrites;
    final current = state;
    if (current is MeusRegistrosLoaded) {
      emit(current.copyWith(pendingWrites: visible));
    } else if ((current is MeusRegistrosEmpty ||
            current is MeusRegistrosError) &&
        visible.isNotEmpty) {
      // A capture save starts while this screen is showing "no entries
      // yet" or a load failure (Review finding: the latter previously
      // fell through this check entirely, silently dropping the pending
      // card) — its own placeholder card must still show immediately
      // (Acceptance Criteria), not wait for a reload. Gated on `visible`
      // rather than the raw `pendingWrites` (code-review fix): a pending
      // write that doesn't match the active filter has nothing to show
      // here at all.
      emit(
        MeusRegistrosLoaded(
          entries: const [],
          nextCursor: null,
          pendingWrites: visible,
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
    // Code-review fix: a confirmed entry that doesn't match the active
    // filter selection must never visibly violate it by appearing in the
    // list anyway.
    final matchesFilter = _matchesActiveFilters(
      source: entry.source,
      occurredAt: DateTime.parse(entry.occurredAt).toLocal(),
    );
    final current = state;
    if (current is MeusRegistrosLoaded) {
      // Prepended, not reloaded (Design Notes) — preserves this cubit's
      // own pagination state (`nextCursor`/`loadMoreFailed`) exactly as
      // `loadMore()`'s own cursor-overlap robustness already relies on;
      // `dedupedById` (unchanged) absorbs the degenerate case where a
      // later `list()`/`loadMore()` page's cursor also happens to repeat
      // this same (now server-known) id.
      emit(
        current.copyWith(
          entries: matchesFilter
              ? dedupedById([entry, ...current.entries], (e) => e.id)
              : current.entries,
          pendingWrites: _visiblePendingWrites,
        ),
      );
    } else if (current is MeusRegistrosEmpty || current is MeusRegistrosError) {
      // Review finding: MeusRegistrosError previously fell through this
      // check too, same rationale as `_onPendingWritesChanged` above.
      // Only transitions into `MeusRegistrosLoaded` when this entry
      // actually matches the active filter (code-review fix) — otherwise
      // there's nothing new to show here, so the screen stays exactly as
      // it was.
      if (matchesFilter) {
        emit(
          MeusRegistrosLoaded(
            entries: [entry],
            nextCursor: null,
            pendingWrites: _visiblePendingWrites,
          ),
        );
      }
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
  /// 3) since the last visit. spec-5-2: also resets the filter selection
  /// to "none" first (a fresh mount's own "from scratch" promise extended
  /// to filters, Design Notes) — [_loadFiltered] then runs with that
  /// cleared selection, same as [clearFilters] would.
  Future<void> loadFirstPage() {
    _activeSource = null;
    _activeDateFrom = null;
    _activeDateTo = null;
    _activeDateRangePreset = DateRangePreset.allTime;
    return _loadFiltered();
  }

  /// `MeusRegistrosScreen`'s own `_ErrorState` retry button (code-review
  /// fix, spec-5-2) — unlike [loadFirstPage] (always resets to "no
  /// filters", for the fresh-mount case), this retries with whichever
  /// filter selection is still current. Review finding: wiring the error
  /// retry button to [loadFirstPage] silently dropped the active filter
  /// on retry — a failed *filtered* query would "succeed" by quietly
  /// showing the full unfiltered list instead of retrying the same
  /// filtered one.
  Future<void> retryCurrentPage() => _loadFiltered();

  /// `EntriesFilterSheet`'s own "Aplicar" button (spec-5-2) — replaces
  /// whichever filters were active before with exactly [source]/
  /// [dateFrom]/[dateTo] (never merged with the previous selection: the
  /// active-filter chip row's own "x" already recomputes the full
  /// replacement set itself, passing back in every filter it wants kept —
  /// I/O matrix: "Remove one of two active chips"). Omitting a parameter
  /// clears that one filter dimension; omitting all three is equivalent to
  /// [clearFilters]. A separate method from [loadFirstPage] by design —
  /// see Design Notes — though both ultimately share [_loadFiltered]'s own
  /// "bump generation, replace state via list()" body.
  ///
  /// [dateRangePreset] (round-2 review fix) — the caller's own record of
  /// which [DateRangePreset] (if any) [dateFrom]/[dateTo] came from;
  /// defaults to [DateRangePreset.allTime], same "omitting clears it"
  /// convention as [dateFrom]/[dateTo] themselves. A caller re-applying an
  /// already-active date range verbatim (e.g. the chip row's own "remove
  /// just the source chip") must pass [activeDateRangePreset] back in
  /// explicitly to keep it from reverting to "Todo o período".
  Future<void> applyFilters({
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
    DateRangePreset dateRangePreset = DateRangePreset.allTime,
  }) {
    _activeSource = source;
    _activeDateFrom = dateFrom;
    _activeDateTo = dateTo;
    _activeDateRangePreset = dateRangePreset;
    return _loadFiltered();
  }

  /// The active-filter chip row's own "Limpar filtros" link (spec-5-2) —
  /// restores the full unfiltered list in place (I/O matrix: "Clear all
  /// filters"), without a screen reload/re-mount.
  Future<void> clearFilters() {
    _activeSource = null;
    _activeDateFrom = null;
    _activeDateTo = null;
    _activeDateRangePreset = DateRangePreset.allTime;
    return _loadFiltered();
  }

  /// [loadFirstPage]/[applyFilters]/[clearFilters]'s own shared "bump
  /// generation, replace state via list()" body — always queries
  /// whichever filter selection ([_activeSource]/[_activeDateFrom]/
  /// [_activeDateTo]) is current at call time, cursor-less (always a
  /// fresh first page, never a continuation — [_fetchMore] is the one
  /// path that ever passes a cursor).
  Future<void> _loadFiltered() async {
    final generation = ++_generation;
    emit(const MeusRegistrosLoading());
    final result = await _repository.list(
      source: _activeSource,
      dateFrom: _activeDateFrom,
      dateTo: _activeDateTo,
    );
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
        // until the next unrelated `pendingWrites` emission. Gated on
        // `_visiblePendingWrites` (code-review fix, spec-5-2): a pending
        // write that doesn't match the active filter selection has
        // nothing to show here either.
        final visiblePendingWrites = _visiblePendingWrites;
        if (visiblePendingWrites.isEmpty) {
          emit(MeusRegistrosError(message: failure.message));
          return;
        }
        emit(
          MeusRegistrosLoaded(
            entries: const [],
            nextCursor: null,
            pendingWrites: visiblePendingWrites,
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
        // applies. Gated on `_visiblePendingWrites` (code-review fix,
        // spec-5-2), same rationale as the failure branch above.
        final visiblePendingWrites = _visiblePendingWrites;
        if (page.items.isEmpty && visiblePendingWrites.isEmpty) {
          emit(const MeusRegistrosEmpty());
          return;
        }
        emit(
          MeusRegistrosLoaded(
            entries: dedupedById(page.items, (entry) => entry.id),
            nextCursor: nextCursor,
            pendingWrites: visiblePendingWrites,
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
    // spec-5-2 I/O matrix: "Load more with filters active" — the
    // continuation carries the exact same filter selection as whichever
    // `_loadFiltered()` call fetched this page's own first page.
    final result = await _repository.list(
      cursor: current.nextCursor,
      source: _activeSource,
      dateFrom: _activeDateFrom,
      dateTo: _activeDateTo,
    );
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
        // (`dedupedById`'s running `seenIds` set covers both).
        final seenIds = latest.entries.map((entry) => entry.id).toSet();
        final newEntries = dedupedById(
          page.items,
          (entry) => entry.id,
          seenIds: seenIds,
        );
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
