import '../../../../core/failure/failure.dart';

/// spec-7-1 — the export job's own progress, modeled as its own sealed
/// domain entity (AD-12: never force `status`+`narrativeStatus` into
/// `Resource<T>`), mirroring `BookmarkState`'s own shape: sealed, with
/// `const factory` constructors declared on the base class so call sites
/// read as `ExportJobState.preparing()` rather than naming each subclass
/// directly. Exactly the 5 states `docs/input/backend/export-screen-
/// states.md`'s own status×narrativeStatus×downloadAvailable table
/// collapses into (`data_ready` folds into [ExportJobState.generating],
/// Design Notes — no case of its own here).
///
/// Never persisted (AD-15: ephemeral, polled live) — lives only on
/// `ExportJobCubit.state`.
sealed class ExportJobState {
  const ExportJobState();

  /// `status: 'pending'` — spinner, "Preparando exportação...". Also this
  /// cubit's own initial state, since `export-summary-create`'s 202
  /// response always answers `status: 'pending'` (`openapi.yaml`), so no
  /// separate "creating..." state is needed before that call resolves.
  const factory ExportJobState.preparing() = ExportJobPreparing;

  /// `status in {processing, data_ready}` — progress bar, "Gerando resumo
  /// com IA...". `data_ready` renders identically to `processing` here
  /// (Design Notes/Never: lighting up its own download-enabled treatment
  /// is Story 7.2's job).
  const factory ExportJobState.generating() = ExportJobGenerating;

  /// `status: 'done'` — [outcome] distinguishes "Concluído" (narrative
  /// succeeded, both download buttons shown) from "Narrativa falhou/
  /// pulada" (only the raw-data button, copy scoped to the narrative
  /// failure) without needing two separate sealed variants for what is,
  /// to the job itself, one and the same terminal success.
  const factory ExportJobState.done(ExportOutcome outcome) = ExportJobDone;

  /// `status: 'error'`, any `errorCode` other than `EXPORT_EMPTY_PERIOD` —
  /// generic error copy, no download, non-retryable/terminal. [failure]
  /// is always built via the one shared `Failure.fromCode` (AD-3) — never
  /// a second, ad hoc mapping of the raw `errorCode` string.
  const factory ExportJobState.error(Failure failure) = ExportJobError;

  /// `status: 'error'`, `errorCode: 'EXPORT_EMPTY_PERIOD'` — "Nenhum
  /// registro nesse período." + an adjust-period suggestion, no download.
  /// AD-3 ("reuse the existing `Failure.exportEmptyPeriod`... never add a
  /// new `Failure` subtype") is honored one layer down, in
  /// `ExportJobStatusDto.toState()`: that mapping step always goes
  /// through `Failure.fromCode` first and only reaches this case by
  /// checking the *subtype* it returns — this variant itself carries no
  /// `Failure` of its own, since by the time the job-level state is
  /// "empty period" there is nothing further for the UI to do with one
  /// (no retry, no message beyond the copy above).
  const factory ExportJobState.emptyPeriod() = ExportJobEmptyPeriod;
}

/// The default state — outline spinner, tappable only via "Fechar".
class ExportJobPreparing extends ExportJobState {
  const ExportJobPreparing();

  @override
  bool operator ==(Object other) => other is ExportJobPreparing;

  @override
  int get hashCode => (ExportJobPreparing).hashCode;

  @override
  String toString() => 'ExportJobPreparing()';
}

class ExportJobGenerating extends ExportJobState {
  const ExportJobGenerating();

  @override
  bool operator ==(Object other) => other is ExportJobGenerating;

  @override
  int get hashCode => (ExportJobGenerating).hashCode;

  @override
  String toString() => 'ExportJobGenerating()';
}

/// [ExportJobDone]'s own two flavors — never a boolean, so a third future
/// outcome (unlikely, but the taxonomy's own `narrativeStatus` enum has
/// exactly `done`/`failed`/`skipped`, the latter two collapsing here into
/// one) never silently reads as the wrong one of only two choices.
enum ExportOutcome {
  /// `narrativeStatus: 'done'` — "Resumo pronto", PDF + raw buttons
  /// (disabled this story; Story 7.2 wires the taps).
  narrativeReady,

  /// `narrativeStatus in {failed, skipped}` — only the raw-data button
  /// (disabled this story), copy scoped to the narrative failure, not a
  /// job-wide error.
  narrativeUnavailable,
}

class ExportJobDone extends ExportJobState {
  const ExportJobDone(this.outcome);

  final ExportOutcome outcome;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ExportJobDone && other.outcome == outcome);

  @override
  int get hashCode => outcome.hashCode;

  @override
  String toString() => 'ExportJobDone(outcome: $outcome)';
}

/// The job itself failed — red warning, terminal (I/O matrix: "Non-
/// retryable, terminal"). [failure] is kept for parity with
/// `BookmarkError`'s own shape, even though the sheet only ever needs
/// generic error copy, never [failure].message, for this variant (the
/// taxonomy's own 13 codes carry no export-specific text).
class ExportJobError extends ExportJobState {
  const ExportJobError(this.failure);

  final Failure failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ExportJobError && other.failure == failure);

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'ExportJobError(failure: $failure)';
}

/// "Período vazio" — see [ExportJobState.emptyPeriod]'s own doc for why
/// this variant carries no [Failure] of its own.
class ExportJobEmptyPeriod extends ExportJobState {
  const ExportJobEmptyPeriod();

  @override
  bool operator ==(Object other) => other is ExportJobEmptyPeriod;

  @override
  int get hashCode => (ExportJobEmptyPeriod).hashCode;

  @override
  String toString() => 'ExportJobEmptyPeriod()';
}
