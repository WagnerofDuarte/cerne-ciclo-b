---
title: 'Request a Period Export & Job Status Tracking'
type: 'feature'
created: '2026-11-06'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: 'b5f52a32a884ed4f84c0a3ca006f1db267fa978a'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Meus Registros has no export entry point; the backend already exposes job creation (`POST /export/summary`) and polling (`GET /export/:jobId/status`), but `lib/features/export/` is three empty scaffold folders.

**Approach:** Build the `export` feature slice end to end: a download icon opens a period picker, confirming creates the job, and a bottom sheet polls status, swapping content in place across Pendente/Processando/Concluído/Erro/Período vazio, reusing existing sheet, button, and `Failure` infrastructure.

## Boundaries & Constraints

**Always:**
- Call `export-summary-create`/`export-status-get` by `x-cerne-function` name, `jobId` as trailing path segment — never the literal REST paths.
- Poll only, never stream. Reuse the existing `Failure.exportEmptyPeriod` for "Período vazio" — never add a new `Failure` subtype (AD-3).
- Model progress as its own sealed domain entity (mirror `BookmarkState`) — never force `status`+`narrativeStatus` into `Resource<T>` (AD-12).
- Sheet content replaces in place per stage change; sheet never closes/reopens mid-job; every state keeps "Fechar" (UX-DR15).
- Add `export-summary-create` to `RetryInterceptor.neverRetriedFunctions` (non-idempotent POST, no idempotency key — a transparent retry risks a duplicate job).

**Ask First:** None — docs/input is silent on poll cadence and the period-picker widget; both decided in Design Notes per AGENTS.md policy.

**Never:**
- Wire the real download (`GET /export/:jobId/download`) or make "Baixar PDF"/"Baixar dados brutos" tap-functional — Story 7.2.
- Give `data_ready` its own visual/download-enabled treatment — Story 7.2; render identically to "Processando" here.
- Add empty-period UX polish beyond `export-screen-states.md`'s table — Story 7.3.
- Persist jobs locally (no Hive box) — ephemeral, polled live (AD-15).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output | Error Handling |
|----------|--------------|------------------|-----------------|
| Create job | Confirm period | `jobId` stored, sheet opens Pendente | Create fails → inline error, sheet never opens |
| Pendente | `status=pending` | Spinner, "Preparando exportação..." | N/A |
| Processando | `status=processing\|data_ready` | Progress bar, "Gerando resumo com IA..." | N/A |
| Concluído | `status=done`, `narrativeStatus=done` | "Resumo pronto", PDF+raw buttons shown (disabled; 7.2 wires taps) | N/A |
| Narrativa falhou/pulada | `status=done`, `narrativeStatus in {failed,skipped}` | Only raw button; copy scoped to narrative | N/A |
| Erro | `status=error`, other `errorCode` | Generic error copy, no download | Non-retryable, terminal |
| Período vazio | `errorCode=EXPORT_EMPTY_PERIOD` | "Nenhum registro nesse período." + adjust-period suggestion | Maps to `Failure.exportEmptyPeriod` |

</frozen-after-approval>

## Code Map

- `lib/features/export/{data,domain,presentation}/` -- empty scaffold; target for all files below
- `lib/core/network/{api_client,url_builder,retry_interceptor}.dart` -- call via `get/post(function, {pathParams})`; `neverRetriedFunctions:36-40` add `'export-summary-create'`
- `lib/core/failure/failure.dart:30-31,67-83` -- `exportEmptyPeriod` already defined/wired; reuse only
- `lib/features/chat/domain/entities/bookmark_state.dart` -- sealed-base `const factory` pattern to mirror
- `lib/features/capture/capture_injection.dart:44-46` -- `registerFactory<TextEntryCubit>` one-shot-cubit precedent
- `lib/core/di/injection_container.dart:93-97` -- add `registerExportFeature()` after chat
- `lib/features/entries/presentation/widgets/entries_filter_sheet.dart:70-114,160-169` -- sheet choreography + shell to mirror (`radiusLg`/`elevation2`/`colorScrimHeavy`/`durationSheetUp`)
- `lib/features/entries/presentation/screens/meus_registros_screen.dart:202` + `lib/core/widgets/back_arrow_header.dart` -- header call site/widget; add optional `trailing` param (default null)
- `lib/core/widgets/app_button.dart` -- `primary`/`secondaryOutline`/`textGhost` for PDF/raw/"Fechar"
- `docs/input/backend/api/openapi.yaml:1417-1550` + `docs/input/backend/export-screen-states.md` -- schemas + authoritative status×narrativeStatus×downloadAvailable table
- `docs/input/prototype/prototype-extract.md:95-104` -- exact PT-BR copy per state

## Tasks & Acceptance

**Execution:**
- [x] `lib/core/design_tokens.dart`, `back_arrow_header.dart` (`trailing` param) -- visual plumbing
- [x] `lib/features/export/domain/{entities/export_job_state.dart,repositories/export_repository.dart}` -- sealed `preparing`/`generating`/`done(outcome)`/`error(Failure)`/`emptyPeriod`; `createJob(...) -> Either<Failure,String>`, `getStatus(jobId) -> Either<Failure,ExportJobState>`
- [x] `lib/features/export/data/{models/export_job_status_dto.dart(+.g.dart),datasources/export_remote_data_source.dart,repositories/export_repository_impl.dart}` -- DTO + calls to the two functions + thin repository pass-through (no cache); DTO→state mapping per the status table
- [x] `lib/features/export/presentation/cubit/export_job_cubit.dart` -- `Cubit<ExportJobState>`; `start()` creates job then `Timer.periodic` (2s) polls to a terminal state; cancels in `close()`
- [x] `lib/features/export/presentation/widgets/export_status_sheet.dart` -- static `.show(context, {cubit})` mirroring filter-sheet choreography; `BlocBuilder` swaps body per state
- [x] `lib/features/export/export_injection.dart` + `lib/core/di/injection_container.dart` -- `registerExportFeature()` (singleton data source + repository, `registerFactory<ExportJobCubit>`), wired in
- [x] `lib/features/entries/presentation/screens/meus_registros_screen.dart` -- download icon in header trailing slot; `onTap` → `showDateRangePicker` → `start()` → `ExportStatusSheet.show()`
- [x] `lib/core/network/retry_interceptor.dart` -- add `'export-summary-create'` to `neverRetriedFunctions`
- [x] Unit tests: `ExportJobCubit` transitions (I/O matrix rows), `ExportRemoteDataSource` DTO→state mapping incl. empty period

**Acceptance Criteria:**
- Given I tap the download icon and select a period, when I confirm, then the job is created and the export sheet opens (`radiusLg`/`elevation2`).
- Given the job is in progress, when polled, then the sheet reflects the five named states, `status`/`narrativeStatus` independent.
- Given a stage changes, when the sheet updates, then content replaces in place — never closes/reopens mid-job.

## Spec Change Log

## Design Notes

- Poll: fixed 2s `Timer.periodic`, no client timeout (docs/input silent; server job always reaches a terminal state).
- Period picker: Flutter's built-in `showDateRangePicker` (docs/input silent; free-form dates, unlike the 3 fixed `DateRangePreset` filter presets).
- `data_ready` folds into `generating`'s visual here (no case of its own) — same copy/no-download, since lighting it up is 7.2's job.

## Verification

**Commands:**
- `fvm flutter pub run build_runner build --delete-conflicting-outputs` -- generates the DTO's `.g.dart`, no conflicts
- `fvm flutter analyze` -- zero issues
- `fvm flutter test` -- all pass, incl. new cubit/data-source tests

## Suggested Review Order

**Job state model (entry point)**

- The two independent axes (`status`/`narrativeStatus`) collapsed into one sealed state, mirroring `BookmarkState` rather than `Resource<T>` (AD-12).
  [`export_job_state.dart:15`](../../lib/features/export/domain/entities/export_job_state.dart#L15)

- The authoritative status table implemented once, with `EXPORT_EMPTY_PERIOD` detected by `Failure` subtype rather than a second string check (AD-3).
  [`export_job_status_dto.dart:51`](../../lib/features/export/data/models/export_job_status_dto.dart#L51)

**Polling lifecycle & resilience (review patches)**

- `start()` creates the job then kicks off the poll loop; a create failure emits the terminal error state instead of ever polling.
  [`export_job_cubit.dart:60`](../../lib/features/export/presentation/cubit/export_job_cubit.dart#L60)

- `_pollInFlight` stops a slow `getStatus` call from racing a newer tick and un-terminating an already-finished job.
  [`export_job_cubit.dart:89`](../../lib/features/export/presentation/cubit/export_job_cubit.dart#L89)

- A persistent (not transient) poll failure now gives up after 5 consecutive misses, reusing the existing Erro state rather than polling forever.
  [`export_job_cubit.dart:109`](../../lib/features/export/presentation/cubit/export_job_cubit.dart#L109)

**Export request correctness (review patches)**

- `periodEnd` is bumped to local end-of-day before the UTC conversion, so the last day picked is no longer silently excluded.
  [`export_remote_data_source.dart:33`](../../lib/features/export/data/datasources/export_remote_data_source.dart#L33)

- `export-summary-create` added to the never-retry set — a transparent retry on this non-idempotent POST risked a duplicate job.
  [`retry_interceptor.dart:45`](../../lib/core/network/retry_interceptor.dart#L45)

**Entry point & sheet UI**

- Download icon → period picker → job creation → sheet, with an in-flight guard against a double-tap racing a second job.
  [`meus_registros_screen.dart:196`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L196)

- `BackArrowHeader` gains an optional trailing slot (default `null`) so the other two screens using it are unaffected.
  [`back_arrow_header.dart:13`](../../lib/core/widgets/back_arrow_header.dart#L13)

- One `BlocBuilder` swaps the sheet's body per state; `_doneContent` is where Concluído and Narrativa-falhou diverge.
  [`export_status_sheet.dart:127`](../../lib/features/export/presentation/widgets/export_status_sheet.dart#L127)

**PT-BR localization (review patch)**

- `showDateRangePicker` was rendering in English with no app-wide locale configured; now pinned to `pt_BR`.
  [`main.dart:161`](../../lib/main.dart#L161)

**Peripherals**

- Feature registration, wired in alongside every other feature.
  [`export_injection.dart:16`](../../lib/features/export/export_injection.dart#L16)

- Widget tests for the sheet's 5-state rendering and the cubit's poll-cap/overlap fixes (review patches: these didn't exist before this round).
  [`export_status_sheet_test.dart`](../../test/features/export/presentation/widgets/export_status_sheet_test.dart)
  [`export_job_cubit_test.dart`](../../test/features/export/presentation/cubit/export_job_cubit_test.dart)
