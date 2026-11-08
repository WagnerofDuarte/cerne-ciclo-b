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

## Target feature: dashboard (story 8.1 — on-demand dashboard aggregation
across entry counts)

Chosen because it's the most recently implemented story (epic 8, the
rest of which is still `backlog`), and — same gap pattern as auth
above — had thorough per-layer and fake-repository widget coverage but
no `*_flow_e2e_test.dart` of its own.

- [x] `test/features/dashboard/dashboard_flow_e2e_test.dart` — 5 tests,
  driven directly against the real, DI-resolved `DashboardCubit`
  (`sl<DashboardCubit>()`, the exact instance `AccountSettingsScreen`
  resolves via `app_router.dart`):
  - Happy path: `load()` → genuine `dashboard-aggregate-get` GET
    (`period: 'all'` query param, real `apikey`/bearer headers) → real
    `DashboardAggregateDto.toDomain()` decode of a 3-bucket JSON
    payload → `ResourceData` with `bucketCounts` in the exact backend
    order.
  - A response missing the required `totals` field → the real
    `DashboardRemoteDataSource` try/catch → `ResourceError
    (MalformedResponse)` (the local decode-failure path, distinct from
    `Failure.fromCode`).
  - A non-retryable `VALIDATION_ERROR` → real `Failure.fromCode` →
    `ResourceError`, exactly one request (no `RetryInterceptor` retry).
  - A retryable `NETWORK_TIMEOUT` → exhausts the real
    `RetryInterceptor` policy (1 + `maxRetries` requests) before
    surfacing as `ResourceError`.
  - Acceptance Criteria ("entry created elsewhere while mounted ...
    chart recomputes"), driven for real: a genuine `entries-create`
    round trip through the exact shared `sl<PendingEntryWriteTracker>()`
    singleton confirms a write, and `DashboardCubit`'s own constructor
    subscription (wired by `registerDashboardFeature()`'s real call
    order in `injection_container.dart`) reacts with a brand-new real
    `dashboard-aggregate-get` fetch — with no test/screen code ever
    calling `load()` a second time. Asserts exactly two
    `dashboard-aggregate-get` requests left through the real transport.
  - **(story 8.2 addition)** A `DashboardNarrativeCubit — spec-8-2
    independent narrative fetch` group, same real DI-resolved pattern
    (`sl<DashboardNarrativeCubit>()`), 3 tests: happy path (`load()` →
    genuine `dashboard-narrative-get` GET, `period: 'all'`, real
    headers → real `DashboardNarrativeDto.toDomain()` decode →
    `ResourceData` with the narrative text); a response missing the
    required `generatedAt` field → `ResourceError(MalformedResponse)`
    (local decode-failure path); a non-retryable `VALIDATION_ERROR` →
    `ResourceError`, exactly one request (no `RetryInterceptor` retry).

This complements, and does not duplicate, existing coverage:
`dashboard_cubit_test.dart`/`dashboard_narrative_cubit_test.dart`
(hand-written fake `DashboardRepository`/`PendingEntryWriteTracker`,
every I/O-matrix transition including the stale-in-flight generation
guard), `dashboard_remote_data_source_test.dart` (mocked `ApiClient`,
DTO decoding for both `getAggregate`/`getNarrative`),
`dashboard_aggregate_dto_test.dart`/`dashboard_narrative_dto_test.dart`,
`dashboard_repository_impl_test.dart`, and
`account_settings_screen_test.dart`/`dashboard_chart_section_test.dart`
(widget rendering against a fake repository, including the
`initState`-calls-`load()`-unconditionally, screen-reader-announcement,
and — story 8.2 — the gated narrative-error-announcement review
findings). None of those drove a real `dashboard-aggregate-get`/
`dashboard-narrative-get` round trip — real URL building, real
headers, the real `RetryInterceptor` policy, the real DTO mapping off
a real decoded JSON payload — nor proved that `DashboardCubit`'s
constructor subscription actually reaches the exact shared
`sl<PendingEntryWriteTracker>()` singleton a real `entries-create`
confirms a write through.

### API Tests

Not applicable separately, same rationale as export/auth above —
exercised through the same e2e suite.

## Verification

- `fvm flutter analyze` — 0 issues (project-wide)
- `fvm flutter test` — **1239/1239 passed**, no regressions in the
  existing suite (story 8.2's additions — the 3-test narrative e2e
  group above, plus the account-settings-screen announcement-gating
  widget tests and the rest of its own unit/widget coverage, plus a
  code-review round adding 7 tests across the narrative cubit/widget/e2e
  suites — account for the +71 difference from the 1135/1135 baseline
  above (review finding: this entry previously claimed a "+24 ... from
  the prior 1175/1175 baseline," an intermediate total this diff never
  actually ran or committed — 8.1 and 8.2 land together in this single
  commit, so 1135 is the only real prior baseline). Story 8.3 (profile
  name editing) then adds its own coverage on top — `updateDisplayName`'s
  RNF09 write-failure matrix plus request-shape/decode tests in
  `account_remote_data_source_test.dart`; the `displayName`/`email`
  boot-fetch piggyback, `setDisplayName`'s not-optimistic success/
  failure and its own (separate-from-the-toggle's) generation guard in
  `account_settings_repository_impl_test.dart`; the full inline-edit
  I/O & Edge-Case Matrix (start/update/cancel/confirm across empty-draft,
  unchanged-draft, success, failure, and the superseded-message
  suppression) in `account_settings_cubit_test.dart`; and the four
  Acceptance Criteria plus the long-name/emoji-initials edge cases in
  `account_settings_screen_test.dart` — 29 tests from the initial
  implementation plus a further 4 from a code-review round (a stale-
  fetch-must-not-clobber-a-saved-name race, the PATCH response's own
  echoed `displayName` winning over the locally-sent value, a long
  (80-char) display name's overflow handling, and an emoji-led name's
  Unicode-grapheme-aware initials) — account for the full +33 difference
  from the 1206/1206 baseline above

## Coverage

- Features with `*_flow_e2e_test.dart` coverage: capture, entries,
  chat, export, auth, **dashboard** (now covering both
  `dashboard-aggregate-get` since story 8.1 and `dashboard-narrative-get`
  since story 8.2's own addition to the same file)
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
- Story 8.2 (narrative text) now has the same e2e treatment as 8.1
  (see the `DashboardNarrativeCubit` group above). Epic 8 beyond that
  — profile editing, logout, account deletion — is still `backlog`, so
  e2e coverage for those is N/A for now.

## Target feature: account (story 8.3 — profile name editing)

Chosen because `account` was the one remaining feature with thorough
per-layer/widget coverage (see the story 8.3 paragraph under
Verification above) but no `*_flow_e2e_test.dart` of its own — the same
gap pattern auth/dashboard above were chosen to close.

- [x] `test/features/account/account_settings_flow_e2e_test.dart` — 7
  new tests, driven directly against the real, DI-resolved
  `AccountSettingsRepository` (`sl<AccountSettingsRepository>()`, the
  exact instance `AccountSettingsCubit`/`VaultLockScreen` share via
  `app_router.dart`):
  - Happy path: `fetchBiometricEnabled()` → genuine empty-body
    `account-settings-update` PATCH (Boundaries: "called empty to
    read"), real `apikey`/bearer headers → real
    `AccountSettingsDto.fromJson()` decode → `currentBiometricEnabled`/
    `currentDisplayName`/`currentEmail` all set from one real response.
  - `setBiometricEnabled(true)` → genuine PATCH with exactly
    `{"biometricEnabled": true}` and real headers.
  - spec-8-3 `setDisplayName` group: happy path (genuine PATCH with
    exactly `{"displayName": name}`); the code-review "response's echo
    wins over the locally-sent value" patch proved for real (sends a
    padded name, the fixture echoes back a different, normalized one,
    and `currentDisplayName` takes the echoed value); a non-retryable
    `VALIDATION_ERROR` → real `Failure.fromCode` → `Left(Validation)`,
    exactly one request (no `RetryInterceptor` retry — confirms
    `account-settings-update` is not in `neverRetriedFunctions`); a
    retryable `NETWORK_TIMEOUT` → exhausts the real `RetryInterceptor`
    policy (1 + `maxRetries` requests); a response missing a required
    field (`email`) → the real `AccountRemoteDataSource` try/catch →
    `Left(MalformedResponse)`, never a crash.

  This complements, and does not duplicate, existing coverage:
  `account_settings_repository_impl_test.dart` (mocked
  `AccountRemoteDataSource`, every I/O-matrix transition including both
  generation guards), `account_remote_data_source_test.dart` (mocked
  `ApiClient`, the RNF09 write-failure matrix and request-shape/decode
  tests), and `account_settings_cubit_test.dart`/
  `account_settings_screen_test.dart` (fake-repository cubit/widget
  coverage). None of those drove a real `account-settings-update` round
  trip — real URL building, real headers, the real `RetryInterceptor`
  policy, the real `AccountSettingsDto.fromJson()` mapping off a real
  decoded JSON payload — nor proved that `setDisplayName`'s "echo wins"
  patch survives a real backend-side normalization rather than a
  hand-written fake's own pass-through.

- [x] `test/core/navigation/app_router_test.dart` — 2 new tests in a
  `spec-8-3 — profile name editing survives real router navigation`
  group, closing a gap the router suite's own pre-existing
  `_FakeAccountSettingsRepository` comment flagged ("this suite never
  exercises the profile-name feature"):
  - Editing the name on `/configuracoes`, navigating away to another
    real destination (`/`) and back shows the saved name, not a stale
    draft or a blank field — the exact "left via back arrow, reopened"
    scenario spec-8-3's own review finding describes, now proved
    against the app's real multi-destination `GoRouter` instead of
    `account_settings_screen_test.dart`'s own synthetic two-route stub.
  - A failed save leaves the field editable with the typed draft when
    reached through the real router, not just the isolated screen
    test's own stub.

### API Tests

Not applicable separately, same rationale as export/auth/dashboard
above — exercised through the same e2e suite.

## Verification

- `fvm flutter analyze` — 0 issues (project-wide)
- `fvm flutter test` — **1251/1251 passed**, no regressions. (Review
  finding from this same file, taken to heart: rather than re-deriving
  a delta against a prior tally that has already drifted twice, this
  entry reports only the one number that was actually run just now —
  1251/1251 — plus the exact count of tests this round added: 9 (7 in
  the new `account_settings_flow_e2e_test.dart` + 2 in
  `app_router_test.dart`'s new spec-8-3 group). A future entry should
  do the same rather than trust-and-propagate this section's own prior
  arithmetic.)

## Coverage

- Features with `*_flow_e2e_test.dart` coverage: capture, entries,
  chat, export, auth, dashboard, **account** (now covering both the
  Story 2.4 biometric toggle and spec-8-3's `setDisplayName`/
  `fetchBiometricEnabled` boot-fetch piggyback through the real
  transport).
- Still missing this level of coverage: vault (biometric/PIN gate) —
  unchanged from the gap already described above.

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
