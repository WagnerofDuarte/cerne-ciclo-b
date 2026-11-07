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

## Target feature: auth (story 1.3 — account creation & login)

Chosen because capture, entries, chat, and export already had this
level of coverage; auth (and vault) were the two gaps this same file's
own "Next Steps" section previously called out.

- [x] `test/features/auth/auth_flow_e2e_test.dart` — 4 tests, driven
  directly against the real, DI-resolved `AuthCubit`:
  - Happy path (signUp mode): `submit()` → genuine `auth-signup` POST,
    carrying the anon key as *both* `apikey` and the `Authorization`
    bearer (this function has `security: []` in the contract — never a
    user token) → session pair lands in the real
    `flutter_secure_storage` channel via the real `AccessTokenProvider`
    → the real `SessionRepository` singleton's `statusStream` flips to
    `authenticated` *before* `AuthCubit` emits its own success state
    (the story 1.6 `markAuthenticated()`-ordering boundary) → typed
    password cleared.
  - Happy path (login mode): same assertions against `auth-login`.
  - Email trimming: a value with stray leading/trailing whitespace
    reaches the real transport already trimmed.
  - Failure path: a non-retryable `AUTH_INVALID` (401) surfaces as
    `formError` with `Failure.message` verbatim, status returns to
    idle, nothing is written to the real secure-storage channel, and
    `SessionRepository.currentStatus` is never touched.

This complements, and does not duplicate, existing coverage:
`auth_cubit_test.dart` (fake `AuthRepository`/`SessionRepository`),
`auth_repository_impl_test.dart` / `auth_remote_data_source_test.dart`
(mocked `ApiClient`, the 15-scenario write-failure matrix), and
`auth_screen_test.dart` (widget rendering). None of them drove a real
`auth-signup`/`auth-login` POST — built by the real `UrlBuilder`,
carrying the real anon-key-as-bearer header policy — all the way
through to a real secure-storage write and a real
`SessionRepository.statusStream` flip, in one `submit()` call.

### API Tests

Not applicable separately, same rationale as the export entry above —
exercised through the same e2e suite.

## Verification

- `fvm flutter analyze` — 0 issues (project-wide)
- `fvm flutter test` — **1135/1135 passed**, no regressions in the
  existing suite (export's own entry above was last verified at
  1128/1128; the auth additions above account for the +7 difference —
  4 new auth tests plus 3 already added by story 7.3 in between)

## Coverage

- Features with `*_flow_e2e_test.dart` coverage: capture, entries,
  chat, export, **auth** (new)
- Still missing this level of coverage: vault (biometric/PIN gate) —
  already `done`, revisit when its own review cycle comes up. Unlike
  the others, `VaultRepositoryImpl` makes zero network calls
  (Boundaries) and already has very thorough mocked-plugin unit
  coverage in `vault_repository_impl_test.dart` (every I/O-matrix
  branch, including two superseded-call races) — the remaining gap
  there is narrower: proving the real DI-resolved
  `sl<VaultRepository>()` and `sl<AccessTokenProvider>()` share the
  real secure-storage channel without a key collision (`vault_pin` vs.
  `user_access_token`/`user_refresh_token`), which no current test
  exercises end to end.
- Epic 8 (dashboard/profile/logout/account-deletion) is still
  `backlog`, so e2e coverage for it is N/A for now.

## Next Steps

- Consider the same real-pipeline e2e treatment for vault (biometric/
  PIN gate) when its own review cycle comes up — see the narrower gap
  described under Coverage above.
- This entry (story 7.1) predates story 7.2's own e2e additions — the
  `getRedirectLocation` group and the `download` group (`downloadPdf()`/
  `downloadRawData()` through the real DI graph) in the same
  `export_flow_e2e_test.dart`, added across spec-7-2's own commit and
  its code review — have no `Target feature` entry of their own above
  (review finding, code review of spec-7-2, docs/metadata group: this
  file was committed late, as a leftover uncommitted spec-7-1 artifact,
  per spec-7-2's own commit message — nothing has documented 7.2's own
  e2e work here yet).
