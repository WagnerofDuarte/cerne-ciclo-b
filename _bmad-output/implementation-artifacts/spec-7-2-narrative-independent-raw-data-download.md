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

### Review Findings

_Code review (lib/ group, 2026-11-07) — chunked review; test/ and docs/metadata groups pending in follow-up rounds._

- [x] [Review][Patch] Single `_downloadInFlight` flag blocks cross-format concurrent downloads silently [lib/features/export/presentation/cubit/export_job_cubit.dart:145] — fixed: keyed by format (`Set<ExportDownloadFormat>`); also dropped the `isClosed` short-circuit before `DownloadOpener.open` so dismissing the sheet mid-download no longer silently aborts it
- [x] [Review][Patch] Dismissing the sheet before a download resolves silently aborts the `DownloadOpener.open` call [lib/features/export/presentation/cubit/export_job_cubit.dart:178] — fixed alongside the item above
- [x] [Review][Patch] Duplicated failure-message literal repeated 3x in `_download` instead of a shared constant [lib/features/export/presentation/cubit/export_job_cubit.dart:174] — fixed: extracted `_downloadFailureMessage`
- [x] [Review][Patch] Empty-string `Location` header is not rejected as missing (only `null` is checked) [lib/core/network/api_client.dart:117] — fixed: `location == null || location.isEmpty`
- [x] [Review][Patch] "Fechar" button lost its `Center` wrap and now stretches full-width under `CrossAxisAlignment.stretch` [lib/features/export/presentation/widgets/export_status_sheet.dart:115] — fixed: re-wrapped in `Center`
- [x] [Review][Defer] Inconsistent SnackBar message tone (PT copy vs. raw Dio message) [lib/features/export/presentation/widgets/export_status_sheet.dart:271] — deferred, pre-existing (mirrors `_onExportTap`'s own established pattern)
- [x] [Review][Defer] `getRedirectLocation`'s generic `catch (e)` buckets a client-side bug with a genuine backend contract violation [lib/core/network/api_client.dart:125] — deferred, pre-existing (mirrors `_send`'s own established pattern)
- [x] [Review][Defer] `followRedirects: false` is never actually exercised by existing tests — both the mocked unit test and the e2e fake adapter bypass `Options.followRedirects` [test/core/network/api_client_test.dart:406, test/features/export/export_flow_e2e_test.dart:385] — deferred, carry forward to the test/ group review round

_Code review (test/ group, 2026-11-07) — round 2 of the chunked review; docs/metadata group still pending._

- [x] [Review][Patch] `url_launcher_download_opener_test.dart`'s `setUp` overwrites the static `UrlLauncherPlatform.instance` with no `tearDown` restoring it, and the "external-application mode" test never actually captures/asserts `LaunchOptions.mode` [test/features/export/data/services/url_launcher_download_opener_test.dart:40] — fixed: added `tearDown` restoring the original instance and a `capturedOptions`/`PreferredLaunchMode.externalApplication` assertion
- [x] [Review][Patch] `export_status_sheet_test.dart`'s "Dados prontos"/"Concluído" tests check `getDownloadUrlCalls` after tapping a download button but never `downloadOpener.openCalls` — a broken URL→opener hand-off would pass undetected [test/features/export/presentation/widgets/export_status_sheet_test.dart:216,181] — fixed: added the missing `openCalls` assertions to both
- [x] [Review][Patch] No test exercises a raw-data download failure's `SnackBar` in the `narrativeUnavailable` state (only a PDF-download failure is tested, in `narrativeReady`) [test/features/export/presentation/widgets/export_status_sheet_test.dart:224] — fixed: added that test
- [x] [Review][Patch] `export_remote_data_source_test.dart`'s "sends format=raw" test never asserts the decoded return value, only `verify(...).called(1)` [test/features/export/data/datasources/export_remote_data_source_test.dart:1176] — fixed: added the `Right`/URL assertion
- [x] [Review][Patch] `bootstrap_integration_test.dart`'s new export-wiring test has no explicit assertion that `DownloadOpener` is registered — a broken binding would only surface as an incidental exception from `sl<ExportJobCubit>()` [test/core/di/bootstrap_integration_test.dart:80] — fixed: added `sl.isRegistered<DownloadOpener>()` assertion
- [x] [Review][Patch] `export_flow_e2e_test.dart`'s `getRedirectLocation` group calls `sl<ApiClient>().getRedirectLocation(...)` directly, bypassing `ExportRepositoryImpl`/`ExportJobCubit` entirely — no e2e test drives `downloadPdf()`/`downloadRawData()` through the real DI graph the way the create/poll flow already is [test/features/export/export_flow_e2e_test.dart:386] — fixed: added a `download` group with 2 new e2e tests (success through the full real chain + a NOT_FOUND failure), faking `UrlLauncherPlatform.instance` so `sl<DownloadOpener>()`'s real `UrlLauncherDownloadOpener` never reaches a native channel

_Code review (docs/metadata group, 2026-11-07) — round 3 of the chunked review, closing it out._

- [x] [Review][Patch] `tests/test-summary.md` has no `Target feature` entry documenting spec-7-2's own e2e additions (`getRedirectLocation`/`download` groups) — its only export entry is a leftover, uncommitted spec-7-1 artifact (per this story's own commit message); the "Coverage" section also conflated "auth/vault missing e2e coverage" with the unrelated "epic 8 is backlog" fact [_bmad-output/implementation-artifacts/tests/test-summary.md:69] — fixed: separated the two facts and cross-referenced the undocumented 7.2 e2e work

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
