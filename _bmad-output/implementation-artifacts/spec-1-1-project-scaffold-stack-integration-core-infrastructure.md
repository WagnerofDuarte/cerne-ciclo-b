---
title: 'Story 1.1: Project Scaffold, Stack Integration & Core Infrastructure'
type: 'feature'
created: '2026-10-27'
status: 'done'
review_loop_iteration: 0
baseline_commit: 'c1706dc36898d91f6172f0356ac2ec49285a0bd6'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-cerne-ciclo-b-2026-10-26/ARCHITECTURE-SPINE.md'
  - '{project-root}/docs/input/backend/README.md'
  - '{project-root}/docs/input/backend/error-taxonomy.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** No Flutter project exists; every later feature assumes a scaffold with the pinned stack, DI, networking (URL builder + interceptors), the sealed `Failure` hierarchy, and a reusable write-failure-test helper already working together.

**Approach:** Scaffold via `fvm`-pinned Flutter, lay out the Structural Seed tree, wire one `get_it` instance with `dio` + `flutter_secure_storage` (proven by an integration test), implement `Failure`/URL-builder/interceptors in `core/`, and build the shared `mocktail` failure-matrix helper later stories reuse.

## Boundaries & Constraints

**Always:**
- Pin every dependency exactly per the architecture spine's Stack Pins table.
- `lib/` matches the Structural Seed exactly: `core/{design_tokens.dart, network/, failure/, di/, cache/, resource.dart, isolated_side_effect.dart, session/}` + `features/{auth,vault,entries,capture,chat,export,dashboard,account}/{data,domain,presentation}` (placeholder files so git tracks empty dirs).
- `apikey` header always; anon-key bearer only on signup/login/refresh, user-token bearer elsewhere. URL = `{FUNCTIONS_BASE_URL}/<x-cerne-function>/<path-params>`, never the OpenAPI path.
- Retry only on `NETWORK_TIMEOUT, NETWORK_OFFLINE, PII_CHECK_FAILED, EMBEDDING_FAILED, AI_GENERATION_TIMEOUT, RATE_LIMITED`; every other code (incl. local `MalformedResponse`) surfaces once, unretried.
- Secrets load only via `flutter_dotenv` from `.env`; `domain/` imports neither Flutter nor `data/` (RNF06).

**Never:**
- No `SessionStatus` (AD-8) or `go_router` redirect (AD-14) — Stories 1.4/1.6's job; `core/session/` is a placeholder.
- No real `design_tokens.dart` content (Story 1.2 owns it) or `isolatedSideEffect` logic (AD-13 defers to RF10) — both typed stubs only.
- No feature screens/BLoCs/repositories — `core/` infrastructure only.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Bootstrap | Cold start, valid `.env` | One `get_it` resolves `Dio`+`FlutterSecureStorage`+`ApiClient`; test writes/reads through it | N/A |
| Retryable vs. other | Stubbed response code | Retries only the 6 allowlisted codes, else maps to `Failure` immediately (parse failure -> `MalformedResponse`) | `Left(Failure)`, never unmapped |

</frozen-after-approval>

## Code Map

- `pubspec.yaml`, `.fvmrc` -- new; pinned Flutter + package versions (Stack Pins table).
- `lib/main.dart`, `lib/core/di/injection_container.dart` -- new; single `get_it` bootstrap, loads `.env`, registers `Dio`/`FlutterSecureStorage`/`ApiClient`.
- `lib/core/network/{url_builder,header_interceptor,retry_interceptor,api_client}.dart` -- new; AD-5 URL/header rules, AD-4 retry allowlist.
- `lib/core/failure/failure.dart` -- new; sealed `Failure` (freezed), 14 subtypes.
- `lib/core/resource.dart` -- new, implemented (AD-12). `lib/core/{design_tokens.dart, isolated_side_effect.dart, cache/, session/}` -- new, placeholders (owned later).
- `lib/features/{auth,vault,entries,capture,chat,export,dashboard,account}/{data,domain,presentation}/.gitkeep` -- new.
- `test/core/di/bootstrap_integration_test.dart` -- new; proves the 3-package spike.
- `test/core/{network/retry_interceptor_test,failure/failure_test}.dart` -- new.
- `test/support/write_failure_matrix_helper.dart` + `_test.dart` -- new; shared `mocktail` helper, demonstrated against `auth-signup`.
- `AGENTS.md` -- edit; fill in the "Running and verifying" TODO.

## Tasks & Acceptance

**Execution:**
- [x] `pubspec.yaml`, `.fvmrc` -- scaffold, pin stack
- [x] `lib/core/{failure,network}/*` -- `Failure` + URL builder + interceptors (AD-3/4/5)
- [x] `lib/core/di/injection_container.dart`, `lib/main.dart` -- `get_it` bootstrap + `.env` load (integration spike)
- [x] remaining Structural Seed paths (`resource.dart`, placeholders, `.gitkeep`s) -- AC2
- [x] `test/core/di/bootstrap_integration_test.dart` -- AC4
- [x] `test/core/{network,failure}/*_test.dart` -- AC5
- [x] `test/support/write_failure_matrix_helper.dart` + demo test -- AC6
- [x] `AGENTS.md` -- record real verification commands

**Acceptance Criteria:**
- Given a fresh checkout, when `pub get` + `build_runner` run, then all pinned deps resolve with no conflicts.
- Given scaffolded `lib/`, then it matches the Structural Seed exactly.
- Given `.env`, when the app boots, then both secrets load via `flutter_dotenv`, none hardcoded.
- Given the DI bootstrap, then exactly one `get_it` instance exists, `dio` is configured through it, and the integration test proves secure-storage read/write through it.
- Given a stubbed response, then only the 6 retryable codes retry; all 14 `Failure` subtypes are reachable.
- Given the matrix helper run against `auth-signup` for all 3 failure types, then each yields `Left(Failure)`, zero unhandled exceptions, via a reusable API.

### Review Findings

- [x] [Review][Patch] Client-side Dio timeouts (connectTimeout/sendTimeout/receiveTimeout) misclassified as `NETWORK_OFFLINE` instead of `NETWORK_TIMEOUT` [lib/core/network/api_client.dart:103, lib/core/network/retry_interceptor.dart:72] — fixed via shared `dioErrorCodeOf` (`lib/core/network/dio_error_code.dart`), which checks `e.type` before falling back to offline.
- [x] [Review][Patch] Cancelled requests (`DioExceptionType.cancel`) misread as `NETWORK_OFFLINE` and retried by `RetryInterceptor` [lib/core/network/retry_interceptor.dart:72] — fixed in the same shared helper; `cancel` now yields no code, so it's never retried.
- [x] [Review][Patch] `DioException` → error-code extraction logic duplicated between `ApiClient` and `RetryInterceptor`, risking drift [lib/core/network/api_client.dart:94, lib/core/network/retry_interceptor.dart:67] — unified into `dioErrorCodeOf` (`lib/core/network/dio_error_code.dart`); both files now delegate to it.
- [x] [Review][Patch] `UrlBuilder.build` only strips a single trailing slash from `baseUrl`, leaving a double slash if `FUNCTIONS_BASE_URL` has two or more [lib/core/network/url_builder.dart:17] — now strips all trailing slashes via `replaceAll(RegExp(r'/+$'), '')`.
- [x] [Review][Patch] `HeaderInterceptor.functionNameOf` can throw unguarded inside `onRequest`, hanging the request with no visible error if it does [lib/core/network/header_interceptor.dart:35] — call site now wrapped in try/catch, falling back to an unrecognized function name and logging via `debugPrint`.
- [x] [Review][Patch] Bootstrap has no error handling for a missing/malformed `.env` — raw crash from `setupCoreDependencies`/`main` instead of a clear setup message [lib/core/di/injection_container.dart:23, lib/main.dart:7] — `main()` now catches, logs a clear "copy .env.example to .env" diagnostic, and rethrows.
- [x] [Review][Patch] Interceptor tests rely on fixed-duration sleeps instead of deterministic synchronization, risking flakiness under load [test/core/network/header_interceptor_test.dart:56, test/core/network/retry_interceptor_test.dart:126] — replaced with `_runOnRequest`/`_runOnError` helpers that await the interceptor's real (void-hidden) Future.
- [x] [Review][Patch] `ApiClient.get`/`patch`/`delete` have no test coverage — only `post` is exercised [test/core/network/api_client_test.dart:1] — added coverage for all three, including `queryParameters`/`pathParams` pass-through.
- [x] [Review][Patch] `SecureStorageAccessTokenProvider` has no dedicated unit test [lib/core/network/access_token_provider.dart:19] — added `test/core/network/access_token_provider_test.dart`.
- [x] [Review][Patch] `HeaderInterceptor` swallows any exception from `readAccessToken()` with a bare `catch (_)` and no logging [lib/core/network/header_interceptor.dart:42] — now logs via `debugPrint` before proceeding without a token.

## Spec Change Log

## Design Notes

Gaps silent in all planning docs, decided here per AGENTS.md's "decide and proceed" policy:
- **Retry:** fixed 500ms delay, max 2 retries.
- **"5 write endpoints" (RNF09):** never enumerated; only auth writes exist yet. Helper built generic, proven once against `auth-signup`; the count accumulates across later stories.
- **`isolated_side_effect.dart`:** typed stub, throws `UnimplementedError` — real logic deferred to RF10 (AD-13).
- **`Dio` timeouts:** no planning doc specifies exact numbers; set via `BaseOptions` in `injection_container.dart` as `connectTimeout: 10s`, `receiveTimeout: 30s`, `sendTimeout: 30s`, so a stalled connection fails instead of hanging indefinitely.
- **Stack Pins table version-pin resolution:** the architecture spine writes `freezed + freezed_annotation ^4.0.3` and `hive_ce + hive_ce_flutter ^2.22.0` as if each pair shared one version line; neither does. `freezed ^4.0.3` itself requires `freezed_annotation ^3.1.0` (pinned exactly that in `pubspec.yaml`); `hive_ce_flutter` versions independently of `hive_ce` and its own latest (`^2.5.0`) depends on `hive_ce ^2.22.0` (the spine's number), so `hive_ce` stays `^2.22.0` and `hive_ce_flutter` is pinned `^2.5.0`. `freezed` itself stays `^4.0.3` as specified.

## Verification

**Commands:**
- `fvm flutter pub get` -- resolves, no conflicts
- `fvm flutter pub run build_runner build --delete-conflicting-outputs` -- generates `.freezed`/`.g.dart` for `Failure`, no errors
- `fvm flutter test` -- all new tests pass
- `fvm flutter analyze` -- zero issues

## Suggested Review Order

**DI bootstrap (the integration spike)**

- Entry point: single `get_it` instance wiring `dio` + `flutter_secure_storage` together — the spike this whole story exists to prove.
  [`injection_container.dart:22`](../../lib/core/di/injection_container.dart#L22)
- `Dio` timeout defaults were a silent-gap decision (no planning doc specified values) — see Design Notes above.
  [`injection_container.dart:38`](../../lib/core/di/injection_container.dart#L38)

**Failure hierarchy (AD-3)**

- The one closed union every repository will return through — 14 subtypes, never redefined per feature.
  [`failure.dart:14`](../../lib/core/failure/failure.dart#L14)
- `retryable` is derived once here from the 6 AD-4 codes — no other file re-decides this.
  [`failure.dart:45`](../../lib/core/failure/failure.dart#L45)
- Backend code → subtype mapping; unrecognized codes fall back to `malformedResponse` instead of throwing.
  [`failure.dart:67`](../../lib/core/failure/failure.dart#L67)

**Networking façade (AD-2/AD-5)**

- Every dio outcome funnels through here to `Either<Failure, T>` — the no-unmapped-exception guarantee (RNF09).
  [`api_client.dart:75`](../../lib/core/network/api_client.dart#L75)
- Patched post-review: a non-String `message` field used to throw an uncaught `TypeError` here.
  [`api_client.dart:94`](../../lib/core/network/api_client.dart#L94)
- Headers: `apikey` always, anon-vs-user bearer branch — patched post-review to never crash on a storage-read failure.
  [`header_interceptor.dart:29`](../../lib/core/network/header_interceptor.dart#L29)
- Retry policy: only the 6 allowlisted codes, fixed delay/max-retries (a decided gap, see Design Notes) — patched post-review to catch any exception from the retried fetch, not just `DioException`.
  [`retry_interceptor.dart:31`](../../lib/core/network/retry_interceptor.dart#L31)
- URL construction: `{FUNCTIONS_BASE_URL}/<function>/<path-params>` — patched post-review to percent-encode each segment.
  [`url_builder.dart:16`](../../lib/core/network/url_builder.dart#L16)

**Scaffold & stack pins**

- Two pins deviate from the architecture spine's literal table for documented ecosystem-constraint reasons (see Design Notes).
  [`pubspec.yaml:38`](../../pubspec.yaml#L38)
- Root bootstrap — loads `.env`, wires DI, runs the bare app shell (no screens yet, by design).
  [`main.dart:1`](../../lib/main.dart#L1)
- Required `.env` keys, placeholder only — copy to `.env` before running.
  [`.env.example:1`](../../.env.example#L1)

**Shared write-failure-matrix helper (RNF09)**

- Generic, table-driven helper every later write-endpoint story reuses — proven once against `auth-signup` here.
  [`write_failure_matrix_helper.dart:20`](../../test/support/write_failure_matrix_helper.dart#L20)

**Tests (peripherals)**

- DI/secure-storage integration spike proof (AC4) — native channel faked, DI wiring and `FlutterSecureStorage` API genuinely exercised.
  [`bootstrap_integration_test.dart:1`](../../test/core/di/bootstrap_integration_test.dart#L1)
- All 14 `Failure` subtypes + `fromCode` + exact retryable-set coverage (AC5).
  [`failure_test.dart:1`](../../test/core/failure/failure_test.dart#L1)
- Retry allowlist, exhausted-retries path, and any-exception-from-fetch coverage.
  [`retry_interceptor_test.dart:1`](../../test/core/network/retry_interceptor_test.dart#L1)
- New: direct header-decision behavioral coverage (apikey/Authorization branches), added post-review.
  [`header_interceptor_test.dart:1`](../../test/core/network/header_interceptor_test.dart#L1)
- New: `ApiClient`'s real send/mapping logic against a mocked `Dio`, added post-review.
  [`api_client_test.dart:1`](../../test/core/network/api_client_test.dart#L1)
- New: `UrlBuilder.build` encoding/trailing-slash coverage, added post-review.
  [`url_builder_test.dart:1`](../../test/core/network/url_builder_test.dart#L1)
- AGENTS.md's "Running and verifying" TODO replaced with the real fvm-wrapped commands.
  [`AGENTS.md:24`](../../AGENTS.md#L24)
