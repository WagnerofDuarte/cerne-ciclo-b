---
title: 'Empty-Period Handling'
type: 'feature'
created: '2026-11-07'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '3ce4d329a1943d6ebfeae891e5dc3adc9097943b'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `export-summary-create`'s summary — "synchronous count, enqueues the job" — plus `EXPORT_EMPTY_PERIOD`'s `400`/non-retryable entry in `error-taxonomy.md` mean the backend rejects the *create* call itself for a zero-Entry period, never issuing a `jobId`. `ExportJobCubit.start()` doesn't special-case this: every create failure emits the generic `ExportJobState.error(failure)` and returns `false`, which `MeusRegistrosScreen._onExportTap()` reads as "never open the sheet, show an inline `SnackBar` instead." The user sees "Não foi possível gerar a exportação.", not the prototype's "Período vazio" sheet state.

**Approach:** In `start()`'s create-failure branch, special-case `failure is ExportEmptyPeriod`: emit `ExportJobState.emptyPeriod()` (already exists, built for the poll path in Story 7.1) and return `true` instead of `false` — the screen's existing `if (started) { ExportStatusSheet.show(...) }` then opens the sheet unchanged, landing directly on the already-correct "Período vazio" content. No `jobId` is stored and polling never starts.

## Boundaries & Constraints

**Always:**
- Only functional change: `ExportJobCubit.start()`'s create-failure handler. No change to `ExportJobState`, `ExportJobStatusDto`, `ExportStatusSheet`, or `MeusRegistrosScreen`.
- On this branch, `_jobId` stays `null`, `_startPolling()` is never called.
- Reuse `Failure.exportEmptyPeriod`/`ExportEmptyPeriod` (AD-3) via an `is` check — never a new `Failure` subtype or a string check on `failure.message`.
- Every other create-failure subtype keeps today's behavior: `ExportJobState.error(failure)`, returns `false`, sheet never opens.

**Ask First:** None — the contract (create endpoint's "synchronous count" summary + `EXPORT_EMPTY_PERIOD`'s `400` entry) is specific enough to settle the delivery path without a human call.

**Never:** touch the DTO's existing poll-path `EXPORT_EMPTY_PERIOD` → `emptyPeriod()` mapping (`export_job_status_dto.dart`) — leave it as defensive coverage in case the backend ever also reports it there; touch `ExportStatusSheet._contentFor`'s empty-period copy/layout (already matches the prototype exactly); add a new `Failure` subtype or new `ExportJobState` variant.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output | Error Handling |
|----------|--------------|------------------|-----------------|
| Create rejected, empty period | `createJob` → `Left(Failure.exportEmptyPeriod(...))` | `start()` emits `ExportJobState.emptyPeriod()`, returns `true`; sheet opens on "Período vazio" | N/A |
| Create rejected, other failure | `createJob` → `Left(Failure.networkOffline(...))` (unchanged) | emits `ExportJobState.error(failure)`, returns `false` | inline `SnackBar`, sheet never opens (existing, untouched) |
| Empty-period terminal, no poll | After the above | `_jobId` stays `null`; elapsing time never triggers `getStatus` | N/A |

</frozen-after-approval>

## Code Map

- `lib/features/export/presentation/cubit/export_job_cubit.dart:76-80` -- `start()`'s `result.match` failure branch -- add the `is ExportEmptyPeriod` check (Approach). Only line-level change in this spec.
- `lib/core/failure/failure.dart:30-31` -- `ExportEmptyPeriod` (exists, Story 7.1) -- read-only, used for the `is` check.
- `lib/features/export/domain/entities/export_job_state.dart:60,161-172` -- `ExportJobState.emptyPeriod()` (exists) -- read-only, emitted as-is.
- `lib/features/entries/presentation/screens/meus_registros_screen.dart:196-241` -- `_onExportTap` -- read-only; its `if (started) { ExportStatusSheet.show(...) }` already opens the sheet once `start()` returns `true`.
- `lib/features/export/presentation/widgets/export_status_sheet.dart:195-202` -- `ExportJobEmptyPeriod()` render case (exists) -- read-only.
- `test/features/export/presentation/cubit/export_job_cubit_test.dart:171-194` -- sibling to the existing "Create fails" test, for the new branch.
- `test/features/export/export_flow_e2e_test.dart:326-350` -- sibling to the existing poll-path "Período vazio" e2e test, for the create-path.

## Tasks & Acceptance

**Execution:**
- [x] `lib/features/export/presentation/cubit/export_job_cubit.dart` -- branch `start()`'s create-failure handler on `failure is ExportEmptyPeriod` -- closes the one path (contract: `export-summary-create`'s synchronous rejection) not already covered by Story 7.1's poll-path handling in the DTO.
- [x] `test/features/export/presentation/cubit/export_job_cubit_test.dart` -- unit test: `createJobResult = left(const Failure.exportEmptyPeriod(message: ...))` → `started` is `true`, `cubit.state` is `ExportJobEmptyPeriod`, elapsing a poll interval never calls `getStatus`.
- [x] `test/features/export/export_flow_e2e_test.dart` -- e2e test: queue a single `400` response `{'code': 'EXPORT_EMPTY_PERIOD', 'message': ..., 'retryable': false}` to `export-summary-create`, drive the real `ExportJobCubit` through DI, assert `cubit.state is ExportJobEmptyPeriod` and that `export-status-get` is never requested.

**Acceptance Criteria:**
- Given a period with zero Entries, when the user requests an export and `export-summary-create` rejects synchronously with `EXPORT_EMPTY_PERIOD`, then the sheet opens directly into "Período vazio" (no download button, "Fechar" only) — never a generic error `SnackBar`, never a crash.
- Given that empty-period state, then no poll ever fires — there was never a `jobId` to poll.
- Given a different create failure (any other `Failure` subtype), then today's existing behavior is unchanged: inline `SnackBar`, sheet never opens.

## Design Notes

`start()` returning `true` here is deliberate: for this one case its boolean stops meaning "job created" and starts meaning "safe to open the sheet" — the sheet shows "Período vazio" with no underlying job, mirroring what the empty-period AC already forces on the sheet itself.

## Verification

**Commands:**
- `fvm flutter analyze` -- zero issues
- `fvm flutter test test/features/export/` -- all pass, including the two new tests

## Suggested Review Order

**The create-failure branch (entry point)**

- The only functional change: special-cases `ExportEmptyPeriod` so `start()` returns `true`/emits `emptyPeriod()` instead of the generic error path.
  [`export_job_cubit.dart:88`](../../lib/features/export/presentation/cubit/export_job_cubit.dart#L88)

- `start()`'s own doc comment, updated to state the carve-out this branch introduces.
  [`export_job_cubit.dart:64-66`](../../lib/features/export/presentation/cubit/export_job_cubit.dart#L64-L66)

**Where the exception now has to be honored downstream**

- `_onExportTap`'s doc comment — the hand-off this change relies on: `start() == true` already falls through to `ExportStatusSheet.show(...)` unchanged.
  [`meus_registros_screen.dart:195-197`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L195-L197)

- `ExportStatusSheet`'s own class doc, same carve-out noted at the sheet's own Boundaries quote.
  [`export_status_sheet.dart:23-26`](../../lib/features/export/presentation/widgets/export_status_sheet.dart#L23-L26)

**Tests — the one new behavior, verified at three depths**

- Unit: the cubit emits `emptyPeriod()`/returns `true`/never polls, against a fake repository.
  [`export_job_cubit_test.dart:196`](../../test/features/export/presentation/cubit/export_job_cubit_test.dart#L196)

- E2e: the same outcome through the real DI graph and a mocked HTTP 400, proving the wiring from `Failure.fromCode` through.
  [`export_flow_e2e_test.dart:355`](../../test/features/export/export_flow_e2e_test.dart#L355)

- Widget: the actual user-visible gap this review round caught — the real sheet opens on "Período vazio" through `MeusRegistrosScreen`, not a `SnackBar`.
  [`meus_registros_screen_test.dart:1772`](../../test/features/entries/presentation/screens/meus_registros_screen_test.dart#L1772)

