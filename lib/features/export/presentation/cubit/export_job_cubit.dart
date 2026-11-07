import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/failure/failure.dart';
import '../../domain/entities/export_download_format.dart';
import '../../domain/entities/export_job_state.dart';
import '../../domain/repositories/export_repository.dart';
import '../../domain/services/download_opener.dart';

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
  ExportJobCubit(this._repository, this._downloadOpener)
    : super(const ExportJobState.preparing());

  final ExportRepository _repository;
  final DownloadOpener _downloadOpener;

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

  /// Review finding (code review, patch item 3) — mirrors [_pollInFlight]:
  /// without this guard, a rapid double-tap on a download button (or one
  /// tap on each of the two "done" buttons in quick succession) could fire
  /// two overlapping [_download] calls, each with its own
  /// `getDownloadUrl`/`DownloadOpener.open` pair in flight at once. A
  /// second call arriving while one is still in flight is a no-op —
  /// resolves to `null` (no failure to surface) without touching the
  /// repository or the opener at all.
  bool _downloadInFlight = false;

  /// "Baixar PDF" — see [_download].
  Future<Failure?> downloadPdf() => _download(ExportDownloadFormat.pdf);

  /// "Baixar dados brutos" — see [_download].
  Future<Failure?> downloadRawData() => _download(ExportDownloadFormat.raw);

  /// Resolves [format]'s signed download URL (`export-download-get`) and
  /// hands it to [_downloadOpener] to open externally — never buffered in
  /// this app (Boundaries). Returns `null` on success, or the `Failure`
  /// that explains why otherwise — `ExportStatusSheet._handleDownload`
  /// awaits this return value directly, rather than reading it back off a
  /// side-channel field (review finding: a shared mutable field, written
  /// by the cubit and mutated by the widget, broke encapsulation and was
  /// racy before [_downloadInFlight] existed).
  Future<Failure?> _download(ExportDownloadFormat format) async {
    if (_downloadInFlight) {
      return null;
    }
    _downloadInFlight = true;
    try {
      final jobId = _jobId;
      if (jobId == null) {
        // Shouldn't happen — every download button only ever renders once
        // `start()` has already stored a jobId — but silently reporting
        // success here would be indistinguishable from a real one
        // (review finding, patch item 4).
        return const Failure.malformedResponse(
          message: 'Não foi possível abrir o arquivo.',
        );
      }
      final result = await _repository.getDownloadUrl(jobId, format: format);
      if (isClosed) {
        return null;
      }
      return await result.match((failure) async => failure, (url) async {
        try {
          final opened = await _downloadOpener.open(url);
          return opened
              ? null
              : const Failure.malformedResponse(
                  message: 'Não foi possível abrir o arquivo.',
                );
        } catch (_) {
          // [DownloadOpener]'s own contract never promises it won't throw
          // — the real `UrlLauncherDownloadOpener` already catches
          // internally, but nothing enforces that on the port itself
          // (review finding, patch item 5). RNF09: never let a thrown
          // exception escape uncaught out of `_handleDownload`'s own
          // unguarded `await`.
          return const Failure.malformedResponse(
            message: 'Não foi possível abrir o arquivo.',
          );
        }
      });
    } finally {
      _downloadInFlight = false;
    }
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    return super.close();
  }
}
