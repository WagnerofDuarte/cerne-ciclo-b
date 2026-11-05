import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/resource.dart';
import '../../domain/entities/entry.dart';
import '../../domain/repositories/entries_repository.dart';

/// Drives `EntriesSearchBar`/`MeusRegistrosScreen`'s docked search surface
/// (spec-5-1) — the first real `Resource<T>` consumer (AD-12: "single data
/// source, single fetch" is exactly this screen's search slice, unlike
/// `MeusRegistrosState`'s own paginated shape). A DI `lazySingleton`
/// (Code Map), mirroring `MeusRegistrosCubit`: long-lived, so a query
/// already typed survives leaving and re-entering `/meus-registros` within
/// the same app session — though [onQueryChanged] is never called except
/// by the live `EntriesSearchBar`'s own `onChanged`, there is no
/// "re-run the last query on return" behavior to preserve here beyond the
/// cubit simply outliving the screen like `MeusRegistrosCubit` already
/// does.
class EntriesSearchCubit extends Cubit<Resource<List<Entry>>> {
  EntriesSearchCubit(this._repository) : super(const ResourceIdle());

  final EntriesRepository _repository;

  /// `EntriesSearchBar`'s own debounce window (I/O matrix: "5 keystrokes
  /// within 300ms -> exactly one `entries-search` call fires, for the
  /// final value").
  static const _debounceDuration = Duration(milliseconds: 300);

  Timer? _debounceTimer;

  /// A monotonic counter guarding against a stale in-flight [search] call's
  /// result landing after a newer one has already changed the state —
  /// mirrors `MeusRegistrosCubit._generation` exactly. Bumped both when a
  /// new debounced search actually starts *and* when the query is cleared
  /// back to idle (Boundaries' "Stale response" row: an in-flight query A
  /// must never land once query B — even an empty one — has already
  /// superseded it).
  int _generation = 0;

  /// spec-5-3 — this cubit's own copy of the active filter selection
  /// (Design Notes: filter state is duplicated, never shared —
  /// `MeusRegistrosCubit` importing/being imported by this cubit would
  /// violate RNF06; `MeusRegistrosScreen` is the only legitimate bridge,
  /// via [updateFilters]). `null` for each field means "no filter of that
  /// kind", same convention `MeusRegistrosCubit`'s own
  /// `_activeSource`/`_activeDateFrom`/`_activeDateTo` already use.
  EntrySource? _activeSource;
  DateTime? _activeDateFrom;
  DateTime? _activeDateTo;

  /// The current (trimmed) query text, kept in lockstep with every
  /// [onQueryChanged] call — empty exactly when idle (Boundaries:
  /// "While idle: silent storage, no call"), non-empty for as long as the
  /// search box holds a non-empty term, regardless of whether the
  /// debounced [_search] for it has actually fired yet. [updateFilters]
  /// reads this to decide whether a filter change needs to re-run a
  /// search at all.
  String _lastQuery = '';

  /// `EntriesSearchBar.onChanged`'s one call site — [raw] is the text
  /// field's current (untrimmed) value on every keystroke. Cancels any
  /// pending debounce `Timer` first, regardless of outcome below (Code
  /// Map/Boundaries): a keystroke always supersedes whatever this cubit
  /// was about to do next.
  void onQueryChanged(String raw) {
    _debounceTimer?.cancel();
    final query = raw.trim();
    _lastQuery = query;
    if (query.isEmpty) {
      // I/O matrix: "Query cleared" — no request, pending work discarded,
      // timeline shown. Bumping the generation here (not only inside
      // [_search]) is what actually discards an already-in-flight
      // previous query's result once it resolves.
      _generation++;
      // Review finding: `close()` can race this synchronous call too (a
      // fast app teardown landing between a keystroke and this handler) —
      // same `isClosed` rationale `_search`'s own guard below already
      // documents; `emit()` after `close()` would otherwise throw.
      if (isClosed) {
        return;
      }
      emit(const ResourceIdle());
      return;
    }
    _debounceTimer = Timer(_debounceDuration, () => _search(query));
  }

  /// spec-5-3 — `EntriesFilterSheet`'s "Aplicar", `_ActiveFiltersRow`'s
  /// chip-remove ×2, and "Limpar filtros", all via `MeusRegistrosScreen`'s
  /// own bridge (Design Notes) — called right alongside the existing
  /// `MeusRegistrosCubit.applyFilters()`/`clearFilters()` call, never in
  /// place of it. Also called unconditionally from `MeusRegistrosScreen.
  /// initState()` on every mount (Boundaries: "no stale filter carried
  /// forward"). Always stores [source]/[dateFrom]/[dateTo] regardless of
  /// whether a search is active (Boundaries: "always stores the fields").
  ///
  /// Only when [_lastQuery] is non-empty — a search is actually active —
  /// *and* at least one of [source]/[dateFrom]/[dateTo] actually differs
  /// from what was already stored (review finding: skips a wasted
  /// `entries-search` network call when `initState()`'s own unconditional
  /// reset finds nothing to actually reset) — does this cancel any pending
  /// debounce and immediately re-run [_search] with that same term and the
  /// just-stored filters (Boundaries: "no debounce on the filter-triggered
  /// re-search"); while idle, the new selection is simply kept for
  /// whenever the next query starts.
  void updateFilters({
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) {
    final filtersChanged =
        source != _activeSource ||
        dateFrom != _activeDateFrom ||
        dateTo != _activeDateTo;
    _activeSource = source;
    _activeDateFrom = dateFrom;
    _activeDateTo = dateTo;
    if (_lastQuery.isEmpty || !filtersChanged) {
      return;
    }
    // Review finding: `close()` can race this call too (e.g. `initState()`
    // now calls this unconditionally on every mount) — same `isClosed`
    // rationale `onQueryChanged`'s own guard above documents; `_search()`'s
    // first line is `emit(ResourceLoading())`, which would otherwise throw
    // after `close()`.
    if (isClosed) {
      return;
    }
    _debounceTimer?.cancel();
    _search(_lastQuery);
  }

  Future<void> _search(String query) async {
    final generation = ++_generation;
    // Review finding: deliberately *not* `const` — `ResourceLoading<T>`
    // has no custom `==`, so `const ResourceLoading()` is a canonicalized
    // singleton instance. Two searches in a row (e.g. "an" still in
    // flight when "ans" debounces) would otherwise both emit that exact
    // same instance; `Cubit.emit` (package:bloc) skips re-emitting a state
    // `==` to the current one, so the second transition into loading
    // would silently no-op — `MeusRegistrosScreen._onSearchStateChanged`'s
    // listener never re-fires, and its 300ms skeleton timer never resets
    // for "ans", measuring RNF01's threshold from the wrong start time. A
    // fresh (non-const) instance is identity-distinct from the prior one
    // even though both are `ResourceLoading`, so `emit` always proceeds.
    emit(ResourceLoading());
    final result = await _repository.search(
      query,
      source: _activeSource,
      dateFrom: _activeDateFrom,
      dateTo: _activeDateTo,
    );
    // Mirrors `MeusRegistrosCubit.loadFirstPage`'s own guard: `close()` can
    // race this awaited call, and a newer query (or a clear back to idle)
    // can have superseded this one while it was in flight.
    if (isClosed || generation != _generation) {
      return;
    }
    result.match(
      (failure) => emit(ResourceError(failure)),
      (entries) => emit(ResourceData(entries)),
    );
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }
}
