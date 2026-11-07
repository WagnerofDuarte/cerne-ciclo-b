---
title: 'Narrative-Independent Raw-Data Download'
type: 'feature'
created: '2026-11-07'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '753d448f4e84e41655e9291a5efd56999154bf6b'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Spec-7-1 left both download buttons `onPressed: null` and folded `data_ready` into the same visual as `processing` — raw data is never actually downloadable, even once the backend has it ready ahead of the narrative.

**Approach:** Wire `GET /export/:jobId/download` behind both buttons (open the signed URL externally, never buffer it in-app), and give `data_ready` its own state so the sheet shows "Baixar dados brutos" already enabled while the narrative keeps processing underneath.

## Boundaries & Constraints

**Always:**
- Call `export-download-get` by function name, `jobId` trailing, `format=pdf|raw` query param.
- Capture the `302`'s `Location` header directly (`followRedirects: false` + a permissive `validateStatus`) — never auto-follow into the signed-storage host.
- Open the signed URL externally (new `DownloadOpener` port, `url_launcher`-backed) — never buffer/write the file in-app.
- `data_ready` → its own `ExportJobState.dataReady()`: same progress-bar/text as `generating`, plus the now-enabled raw button beneath.
- A download failure shows an inline `SnackBar` (mirrors `_onExportTap`'s create-failure pattern), never mutates the sheet's job-status content.

**Ask First:** None — docs/input is silent on how a finished file reaches the user; external-open vs. in-app buffering is decided here.

**Never:** add a new `Failure` subtype for download errors (reuse `Failure.fromCode`, AD-3); touch empty-period state/copy (Story 7.3); add a busy state to `AppButton` itself (deferred).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output | Error Handling |
|----------|--------------|------------------|-----------------|
| Hybrid state | `status=data_ready`, `narrativeStatus=processing` | Progress bar + text + enabled "Baixar dados brutos" | N/A |
| Raw/PDF tap | Tap enabled button | `GET export-download-get?format=raw\|pdf` → opens URL externally | Failure → `SnackBar`, state unchanged |
| Narrative failed/skipped | `status=done`, `narrativeStatus in {failed,skipped}` | Only raw button, now enabled | N/A |
| Missing `Location` | `302` with no header | `Failure.malformedResponse` | Same `SnackBar` path |

</frozen-after-approval>

## Code Map

- `lib/core/network/api_client.dart:79` -- new `getRedirectLocation(function, {pathParams, queryParameters})`: `_dio.get<dynamic>`, `followRedirects: false` + permissive `validateStatus`, reads `response.headers.value('location')`; don't override `responseType` — error bodies stay JSON so `_mapDioException`/`dioErrorCodeOf` keep working unchanged
- `lib/features/export/domain/entities/export_job_state.dart:28` -- add `ExportJobState.dataReady()` + `ExportJobDataReady` (mirror `ExportJobPreparing`'s no-field shape)
- `lib/features/export/domain/entities/export_download_format.dart` (new) -- `enum ExportDownloadFormat { pdf, raw }`
- `lib/features/export/domain/services/download_opener.dart` (new) -- abstract `DownloadOpener { Future<bool> open(String url); }`, mirrors `chat/domain/services/connectivity_watcher.dart`'s port shape
- `lib/features/export/data/services/url_launcher_download_opener.dart` (new) -- `launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)`
- `export_repository.dart:30` / `export_remote_data_source.dart:77` / `export_repository_impl.dart:31` -- add `getDownloadUrl(jobId, {required format})` through all three layers; data source calls `_apiClient.getRedirectLocation('export-download-get', pathParams: [jobId], queryParameters: {'format': format.name})`
- `lib/features/export/data/models/export_job_status_dto.dart:55-60` -- split `'data_ready'` out of `'processing'`
- `lib/features/export/presentation/cubit/export_job_cubit.dart` -- inject `DownloadOpener`; add `Failure? lastDownloadFailure`, `downloadPdf()`/`downloadRawData()` (delegate to private `_download(ExportDownloadFormat)` using stored `_jobId`); `_isTerminal` unchanged
- `lib/features/export/presentation/widgets/export_status_sheet.dart:134-220` -- `_contentFor`/`_doneContent` gain `context`+`cubit`; new `ExportJobDataReady()` case; both buttons wired via new `_handleDownload` (shows `SnackBar` with `cubit.lastDownloadFailure?.message` on failure)
- `lib/features/export/export_injection.dart:17-27` -- register `DownloadOpener`, inject into `ExportJobCubit`'s factory
- `test/features/export/presentation/cubit/export_job_cubit_test.dart` -- `_FakeExportRepository` needs `getDownloadUrl`; add `_FakeDownloadOpener`
- `pubspec.yaml` -- add `url_launcher` (`fvm flutter pub add url_launcher`)
- `docs/input/backend/api/openapi.yaml:1550-1580`, `export-screen-states.md` -- contract + hybrid-row authority

## Tasks & Acceptance

**Execution:** one task per Code Map bullet above, in that order, plus:
- [x] Unit tests: `getRedirectLocation` (success/missing-location/error-status), `getDownloadUrl`, `toState()`'s `data_ready`, cubit download methods
- [x] Widget tests: hybrid-state render, both `done` buttons call through, download failure → `SnackBar` with state unchanged

**Acceptance Criteria:**
- Given `status=data_ready`/`narrativeStatus=processing`, when polled, then "Baixar dados brutos" is already enabled and downloads via `GET /export/:jobId/download` while summary-progress text stays visible underneath.
- Given the narrative fails/is skipped at `status=done`, then "Baixar dados brutos" stays enabled, error copy stays scoped to the narrative.
- Given the narrative succeeds at `status=done`, then both "Baixar PDF" and "Baixar dados brutos" are enabled and tappable.

## Spec Change Log

## Design Notes

- Download mechanism (docs/input silent): open the signed URL externally via `url_launcher` rather than buffering bytes in-app — no storage permissions, no local file/share-sheet plumbing.
- Download-tap failures surface via `SnackBar`, not a cubit state transition — the sealed `ExportJobState` models job *progress*, not one-off actions; a transient failure must never mutate the displayed state.

## Verification

**Commands:**
- `fvm flutter pub add url_launcher` -- resolves cleanly
- `fvm flutter pub run build_runner build --delete-conflicting-outputs` -- no conflicts
- `fvm flutter analyze` -- zero issues
- `fvm flutter test` -- all pass

## Suggested Review Order

**Redirect-based download (entry point)**

- The one place a non-JSON, `302`-shaped response is handled: `followRedirects: false` + a permissive `validateStatus`, error bodies still decode as JSON so existing error-mapping is untouched.
  [`api_client.dart:102`](../../lib/core/network/api_client.dart#L102)

**Download wiring through the layers**

- The port every other layer calls through — `jobId` + `format` in, signed URL out.
  [`export_repository.dart:41`](../../lib/features/export/domain/repositories/export_repository.dart#L41)

- Resolves to `export-download-get` by function name, `format.name` as the query value verbatim.
  [`export_remote_data_source.dart:85`](../../lib/features/export/data/datasources/export_remote_data_source.dart#L85)

- Thin pass-through, no cache — same shape as every other method on this repository.
  [`export_repository_impl.dart:34`](../../lib/features/export/data/repositories/export_repository_impl.dart#L34)

**The hybrid `data_ready` state**

- `data_ready` gets its own sealed case instead of folding into `generating` — the whole point of this story.
  [`export_job_state.dart:35`](../../lib/features/export/domain/entities/export_job_state.dart#L35)

- Where the DTO's raw `status` string is split into this new case.
  [`export_job_status_dto.dart:59`](../../lib/features/export/data/models/export_job_status_dto.dart#L59)

**Cubit download lifecycle (review-patch round)**

- `_download`'s own shape after review: in-flight guard, `jobId == null` and a throwing opener both map to `Failure`, returned directly rather than through a shared field.
  [`export_job_cubit.dart:161`](../../lib/features/export/presentation/cubit/export_job_cubit.dart#L161)

- The guard itself — a second call while one is in flight is a no-op, mirroring `_pollInFlight`.
  [`export_job_cubit.dart:145`](../../lib/features/export/presentation/cubit/export_job_cubit.dart#L145)

- `downloadPdf`/`downloadRawData`'s own `Future<Failure?>` signature — what callers actually see.
  [`export_job_cubit.dart:148`](../../lib/features/export/presentation/cubit/export_job_cubit.dart#L148)

**External-open port**

- The domain port — never promises it won't throw, which is exactly why the cubit now guards its own call to it.
  [`download_opener.dart:11`](../../lib/features/export/domain/services/download_opener.dart#L11)

- The real, `url_launcher`-backed implementation — catches internally so a malformed URL/platform failure degrades to `false`.
  [`url_launcher_download_opener.dart:10`](../../lib/features/export/data/services/url_launcher_download_opener.dart#L10)

**Sheet UI wiring**

- Reads the download method's own return value directly now — no more side-channel field the widget used to mutate.
  [`export_status_sheet.dart:267`](../../lib/features/export/presentation/widgets/export_status_sheet.dart#L267)

- The hybrid state's own content — shares the `generating` sequence, appends the now-enabled raw button beneath it.
  [`export_status_sheet.dart:162`](../../lib/features/export/presentation/widgets/export_status_sheet.dart#L162)

- Both `done` buttons wired to a real download instead of `onPressed: null`.
  [`export_status_sheet.dart:219`](../../lib/features/export/presentation/widgets/export_status_sheet.dart#L219)

**Peripherals**

- `DownloadOpener` registered alongside the rest of the feature, injected into the cubit's factory.
  [`export_injection.dart:29`](../../lib/features/export/export_injection.dart#L29)

- The two formats the contract accepts, named to match its enum exactly.
  [`export_download_format.dart:6`](../../lib/features/export/domain/entities/export_download_format.dart#L6)

- New: the real `DownloadOpener` impl's own test, faking `url_launcher`'s platform interface (previously untested).
  [`url_launcher_download_opener_test.dart:1`](../../test/features/export/data/services/url_launcher_download_opener_test.dart#L1)

- New: a real `302`+`Location` round trip through the actual interceptor chain, not just a mocked `Dio`.
  [`export_flow_e2e_test.dart:1`](../../test/features/export/export_flow_e2e_test.dart#L1)
