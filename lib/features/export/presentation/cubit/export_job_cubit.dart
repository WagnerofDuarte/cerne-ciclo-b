import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/export_job_state.dart';
import '../../domain/repositories/export_repository.dart';

/// Drives `ExportStatusSheet` (spec-7-1) — a fresh, `get_it`-factory-
/// scoped instance per download-icon tap (Code Map: the `registerFactory`
/// one-shot-cubit precedent set by `TextEntryCubit`), closed by the call
/// site itself once done with it (`MeusRegistrosScreen`'s own export handler/
/// `ExportStatusSheet.show()`, mirroring `InsertionModal.show()`'s own
/// cubit-disposal convention), never by a `get_it` `dispose:` hook.
///
/// Starts in [ExportJobState.preparing] — the same visual the
/// `export-summary-create` 202 response's own `status: 'pending'` always
/// implies (`openapi.yaml`), so no separate "creating..." state is needed
/// before [start]'s own `createJob` call resolves.
class ExportJobCubit extends Cubit<ExportJobState> {
  ExportJobCubit(this._repository) : super(const ExportJobState.preparing());

  final ExportRepository _repository;

  /// Design Notes — fixed poll cadence (docs/input is silent on this):
  /// the server job always reaches a terminal state, so no client
  /// timeout exists either.
  static const _pollInterval = Duration(seconds: 2);

  /// Review finding (blind-hunter/edge-case-hunter layers) — a persistent
  /// `getStatus` failure (as opposed to one flaky blip) would otherwise
  /// poll forever with the sheet stuck on its last state and no visible
  /// indication anything is wrong. After this many *consecutive* failures,
  /// [_poll] gives up and surfaces the existing generic [ExportJobError]
  /// state instead — reusing the sheet's own already-built error visual
  /// rather than inventing a new one.
  static const _maxConsecutivePollFailures = 5;

  String? _jobId;
  Timer? _pollTimer;
  int _consecutivePollFailures = 0;

  /// Review finding (blind-hunter/edge-case-hunter layers) — `Timer.
  /// periodic` doesn't wait for one tick's own `_poll()` to finish before
  /// firing the next; without this guard, a `getStatus` call slower than
  /// [_pollInterval] could race a second, overlapping call, and a late,
  /// stale response landing after a newer terminal state was already
  /// emitted could "un-terminate" an already-finished job in the UI.
  bool _pollInFlight = false;

  /// Creates the export job for [periodStart]/[periodEnd]
  /// (`export-summary-create`) and, on success, starts this cubit's own
  /// `Timer.periodic` poll loop against `export-status-get`.
  ///
  /// Returns `false` on a create failure (Boundaries: "Create fails →
  /// inline error, sheet never opens") — the same failure is also
  /// emitted as [ExportJobState.error] so the caller can read [state] for
  /// [Failure.message] without this method also having to hand back the
  /// raw `Failure` itself (the `Either<Failure, T>` shape, RNF09, is the
  /// repository's own contract, not every cubit method's).
  Future<bool> start({
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final result = await _repository.createJob(
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
    if (isClosed) {
      return false;
    }
    return result.match(
      (failure) {
        emit(ExportJobState.error(failure));
        return false;
      },
      (jobId) {
        _jobId = jobId;
        _startPolling();
        return true;
      },
    );
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    final jobId = _jobId;
    if (jobId == null || _pollInFlight || _isTerminal(state)) {
      return;
    }
    _pollInFlight = true;
    try {
      final result = await _repository.getStatus(jobId);
      if (isClosed || _isTerminal(state)) {
        return;
      }
      result.match(
        (failure) {
          // A transient poll failure (docs/input is silent on this) is
          // swallowed rather than surfaced, so one flaky network blip
          // never flips a still-running job to a false terminal error —
          // the next tick simply tries again. A *persistent* one gives up
          // after [_maxConsecutivePollFailures] instead of polling
          // forever.
          _consecutivePollFailures++;
          if (_consecutivePollFailures >= _maxConsecutivePollFailures) {
            _pollTimer?.cancel();
            emit(ExportJobState.error(failure));
          }
        },
        (newState) {
          _consecutivePollFailures = 0;
          emit(newState);
          if (_isTerminal(newState)) {
            _pollTimer?.cancel();
          }
        },
      );
    } finally {
      _pollInFlight = false;
    }
  }

  bool _isTerminal(ExportJobState state) =>
      state is ExportJobDone ||
      state is ExportJobError ||
      state is ExportJobEmptyPeriod;

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    return super.close();
  }
}
