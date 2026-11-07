# Test Automation Summary

## Scope

Flutter/Dart project — "E2E" here means the project's own established
convention of `*_flow_e2e_test.dart` files: the real DI graph (`sl`),
real `Cubit` -> `Repository` -> `DataSource` -> `ApiClient` -> `Dio`
pipeline (both real interceptors attached), with only the transport
boundary (`HttpClientAdapter`) and native plugins faked (no
device/simulator/CI exists yet per AGENTS.md). Playwright/browser E2E
does not apply to this codebase.

Target feature: **export** (story 7.1 — request a period export & job
status tracking), chosen because capture, entries, and chat already had
this level of coverage; export did not.

## Generated Tests

### E2E Tests

- [x] `test/features/export/export_flow_e2e_test.dart` — 5 tests, driven
  directly against the real, DI-resolved `ExportJobCubit`:
  - Happy path: `start()` → genuine `export-summary-create` POST (URL,
    headers, periodEnd bumped to local end-of-day before UTC
    conversion) → real `Timer.periodic` poll loop → genuine
    `export-status-get/{jobId}` GETs → Pendente → Processando →
    Concluído (`ExportOutcome.narrativeReady`); also asserts polling
    really stops once terminal.
  - Narrativa falhou: `narrativeStatus: failed` maps to
    `ExportOutcome.narrativeUnavailable` through the real DTO mapping.
  - Período vazio: `errorCode: EXPORT_EMPTY_PERIOD` maps through the
    real `Failure.fromCode` → `ExportJobState.emptyPeriod()`.
  - Erro: a non-empty-period error code (`AI_GENERATION_TIMEOUT`) maps
    to the generic `ExportJobState.error`.
  - Review-patch coverage: `export-summary-create` failing with a
    *retryable* code (`RATE_LIMITED`) is never retried — proves
    `RetryInterceptor.neverRetriedFunctions`' real wiring for this
    function (previously only exercised in isolation or against a fake
    repository, never through the real Dio pipeline).

- [x] `test/core/network/api_client_test.dart` / `test/features/export/
  export_flow_e2e_test.dart` — closed a test-pinning gap flagged by
  spec-7-2's round-2 code review (`deferred-work.md`): the mocked unit
  test now captures the `options` argument to `getRedirectLocation`'s
  `Dio.get` call and asserts `followRedirects == false` and the
  permissive `validateStatus` boundary (302 true / 400 false); the e2e
  test now asserts `followRedirects` on the request that actually
  reached the fake transport adapter, after passing through the real
  header + retry interceptor chain. Previously, flipping or dropping
  `followRedirects: false` in `ApiClient.getRedirectLocation` would not
  have failed either test.

This complements, and does not duplicate, existing coverage:
`export_job_cubit_test.dart` (fake repository, I/O-matrix transitions),
`export_remote_data_source_test.dart` (mocked `ApiClient`, DTO
decoding), `export_status_sheet_test.dart` (widget rendering per
state), and `meus_registros_screen_test.dart`'s "export entry point"
group (tap → picker → `start()` → sheet, against a fake repository).
None of those drove a real network/poll round trip end to end.

### API Tests

Not applicable separately — the backend contract is exercised through
the same e2e suite above (real `ApiClient`/`Dio`/interceptors against a
faked transport), consistent with how every other feature in this
project is tested (no standalone HTTP-level test layer exists outside
this pattern).

## Verification

- `fvm flutter analyze` — 0 issues
- `dart format --set-exit-if-changed` — clean (after one auto-format
  pass)
- `fvm flutter test` — **1128/1128 passed**, no regressions in the
  existing suite

## Coverage

- Features with `*_flow_e2e_test.dart` coverage: capture, entries,
  chat, **export** (new)
- Still missing this level of coverage: auth (login/refresh/expired-
  session recovery), vault (biometric/PIN gate) — both already `done`,
  revisit when their own review cycles come up
- Epic 8 (dashboard/profile/logout/account-deletion) is still `backlog`,
  so e2e coverage for it is N/A for now — unrelated to the auth/vault
  gap above (review finding, code review of spec-7-2, docs/metadata
  group — this bullet previously conflated the two)

## Next Steps

- Consider the same real-pipeline e2e treatment for auth (login/refresh/
  expired-session recovery) and vault (biometric/PIN gate) when their
  own review cycles come up.
- This entry (story 7.1) predates story 7.2's own e2e additions — the
  `getRedirectLocation` group and the `download` group (`downloadPdf()`/
  `downloadRawData()` through the real DI graph) in the same
  `export_flow_e2e_test.dart`, added across spec-7-2's own commit and
  its code review — have no `Target feature` entry of their own above
  (review finding, code review of spec-7-2, docs/metadata group: this
  file was committed late, as a leftover uncommitted spec-7-1 artifact,
  per spec-7-2's own commit message — nothing has documented 7.2's own
  e2e work here yet).
