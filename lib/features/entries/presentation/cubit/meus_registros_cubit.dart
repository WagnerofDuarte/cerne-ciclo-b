import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/repositories/entries_repository.dart';
import 'meus_registros_state.dart';

/// Drives `MeusRegistrosScreen` — calls `EntriesRepository.list()` directly
/// (no use-case layer, matching this codebase's existing small-scope
/// convention: `AccountSettingsCubit`/`AuthCubit`/`TextEntryCubit`). A
/// `lazySingleton` (Code Map), like `AccountSettingsCubit` — long-lived, so
/// the already-fetched pages survive leaving and re-entering
/// `/meus-registros` within the same app session.
class MeusRegistrosCubit extends Cubit<MeusRegistrosState> {
  MeusRegistrosCubit(this._repository) : super(const MeusRegistrosLoading());

  final EntriesRepository _repository;

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
      (failure) => emit(MeusRegistrosError(message: failure.message)),
      (page) {
        if (page.items.isEmpty) {
          emit(const MeusRegistrosEmpty());
          return;
        }
        emit(
          MeusRegistrosLoaded(entries: page.items, nextCursor: page.nextCursor),
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
        // by the server.
        final existingIds = latest.entries.map((entry) => entry.id).toSet();
        final newEntries = page.items
            .where((entry) => !existingIds.contains(entry.id))
            .toList();
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
          ),
        );
      },
    );
  }
}
