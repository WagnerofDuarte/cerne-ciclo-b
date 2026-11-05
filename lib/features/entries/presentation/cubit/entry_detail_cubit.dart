import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/failure/failure.dart';
import '../../../auth/domain/entities/session_status.dart';
import '../../../auth/domain/repositories/session_repository.dart';
import '../../domain/entities/pending_entry_write.dart';
import '../../domain/entities/sync_badge_state.dart';
import '../../domain/repositories/entries_repository.dart';
import '../../domain/services/pending_entry_write_tracker.dart';
import 'entry_detail_state.dart';

/// Drives `EntryDetailScreen` (spec-4-4) — the Boundaries' three-source
/// composition, merged only here (AD-7: "it never imports/reaches into
/// `MeusRegistrosCubit` or any other Cubit"):
/// [SessionRepository.statusStream] (auth status — folded into
/// [EntryDetailState.sessionStatus] on every emit, the documented compose
/// point the Acceptance Criteria's third bullet names, even though nothing
/// this screen renders branches on it today: `ExpiryOverlayHost`'s own
/// independent subscription to the same stream, unchanged, is still what
/// actually shows the session-expired overlay above this screen,
/// Boundaries: "no new overlay"), [PendingEntryWriteTracker.pendingWrites]
/// feeding the one shared `deriveSyncBadgeState()` (never recomputed
/// inline), and one [EntriesRepository.getById] fetch per [load] call.
///
/// A DI `factory` (Code Map) — unlike `MeusRegistrosCubit`'s
/// `lazySingleton`, a fresh instance per visit to `/meus-registros/:id`
/// matches this screen's single-fetch, throwaway lifecycle, mirroring the
/// capture cubits' own factory shape (`capture_injection.dart`).
class EntryDetailCubit extends Cubit<EntryDetailState> {
  EntryDetailCubit(this._repository, this._tracker, this._sessionRepository)
    : super(const EntryDetailLoading()) {
    _pendingSubscription = _tracker.pendingWrites.listen(
      (writes) => _pendingWrites = writes,
    );
    _sessionSubscription = _sessionRepository.statusStream.listen(
      _onSessionStatusChanged,
    );
  }

  final EntriesRepository _repository;
  final PendingEntryWriteTracker _tracker;
  final SessionRepository _sessionRepository;

  late final StreamSubscription<List<PendingEntryWrite>> _pendingSubscription;
  late final StreamSubscription<SessionStatus> _sessionSubscription;

  /// Mirrors `MeusRegistrosCubit`'s own field of the same name — the
  /// tracker's latest snapshot, read synchronously by [load]'s own badge
  /// derivation rather than awaiting a fresh stream value.
  List<PendingEntryWrite> _pendingWrites = const [];

  /// The latest [SessionStatus] this cubit has observed off the composed
  /// [SessionRepository.statusStream] — stamped onto every emitted
  /// [EntryDetailState] (including a re-emit of the current state below,
  /// so a status tick that arrives after [load] has already resolved is
  /// still reflected without disturbing the resolved entry/badge data).
  SessionStatus? _sessionStatus;

  void _onSessionStatusChanged(SessionStatus status) {
    _sessionStatus = status;
    if (!isClosed) {
      emit(_restamped(state, status));
    }
  }

  /// Returns [current] with [status] stamped on, preserving every other
  /// field — used both by [_onSessionStatusChanged] (re-emit) and [load]
  /// (first emit of each new variant).
  EntryDetailState _restamped(EntryDetailState current, SessionStatus? status) =>
      switch (current) {
        EntryDetailLoading() => EntryDetailLoading(sessionStatus: status),
        EntryDetailData(entry: final entry, badgeState: final badgeState) =>
          EntryDetailData(
            entry: entry,
            badgeState: badgeState,
            sessionStatus: status,
          ),
        EntryDetailNotFound() => EntryDetailNotFound(sessionStatus: status),
        EntryDetailError(message: final message) =>
          EntryDetailError(message: message, sessionStatus: status),
      };

  /// Guards a stale in-flight [load] call's result landing after a newer
  /// one (e.g. a quick back-then-forward re-navigation) — same rationale
  /// and shape as `MeusRegistrosCubit._generation`.
  int _generation = 0;

  /// `EntryDetailScreen`'s one driver, called from the `GoRoute.builder`
  /// cascade (Code Map: `sl<EntryDetailCubit>()..load(...)`) — [id] is
  /// either a real server id or a still-pending/failed placeholder's
  /// synthetic `tempId` (Boundaries: "un-special-cased navigation target");
  /// both are simply passed straight through to [EntriesRepository.
  /// getById] with no branching here.
  Future<void> load(String id) async {
    final generation = ++_generation;
    emit(EntryDetailLoading(sessionStatus: _sessionStatus));
    final result = await _repository.getById(id);
    if (isClosed || generation != _generation) {
      return;
    }
    result.match(
      (failure) {
        if (failure is NotFound) {
          emit(EntryDetailNotFound(sessionStatus: _sessionStatus));
          return;
        }
        // Boundaries: every other non-absorbed Failure renders the exact
        // same generic not-found treatment `EntryDetailScreen` gives
        // EntryDetailNotFound — kept as its own state only for a test's
        // sake (entry_detail_state.dart's own doc).
        emit(
          EntryDetailError(
            message: failure.message,
            sessionStatus: _sessionStatus,
          ),
        );
      },
      (entry) {
        PendingEntryWrite? matchingPending;
        for (final pending in _pendingWrites) {
          if (pending.tempId == entry.id) {
            matchingPending = pending;
            break;
          }
        }
        emit(
          EntryDetailData(
            entry: entry,
            badgeState: deriveSyncBadgeState(entry, matchingPending),
            sessionStatus: _sessionStatus,
          ),
        );
      },
    );
  }

  @override
  Future<void> close() async {
    await _pendingSubscription.cancel();
    await _sessionSubscription.cancel();
    return super.close();
  }
}
