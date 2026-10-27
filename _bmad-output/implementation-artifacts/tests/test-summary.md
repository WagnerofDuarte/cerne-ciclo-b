# Test Automation Summary

## Context

Story 1.1 (project scaffold, stack integration & core infrastructure) is the
only story marked `done`. No feature screens exist yet (`lib/features/` is
empty) and no device/simulator/CI pipeline exists (AGENTS.md), so there is no
UI to drive a traditional E2E test against. The only "API" surface
implemented so far is the core network pipeline: `UrlBuilder`,
`HeaderInterceptor`, `RetryInterceptor`, `ApiClient`, `AccessTokenProvider`,
and their DI wiring in `setupCoreDependencies`.

Each of those units already had thorough isolated unit tests (mocking `Dio`
directly, or driving one interceptor at a time). The gap: nothing proved the
pieces work *wired together* the way `setupCoreDependencies` actually wires
them — real `Dio`, both real interceptors attached, real `UrlBuilder` — or
that a retry genuinely goes back out over the wire. That gap is what this
pass fills, in the same spirit `bootstrap_integration_test.dart` already
established (fake only the transport boundary; everything above it is real).

## Generated Tests

### API Tests (network pipeline, end-to-end through the real wiring)

- [x] `test/core/network/network_pipeline_integration_test.dart` — real `Dio`
      + real `HeaderInterceptor` + real `RetryInterceptor` + real
      `UrlBuilder`, with only `HttpClientAdapter` faked (no real network
      calls). Covers:
  - anon-only operation (`auth-login`): correct `x-cerne-function` URL,
    `apikey` + anon `Authorization` headers, success maps to `Right`.
  - bearer operation with a stored user token + trailing path params
    (`chat-messages-retry/{sessionId}/{messageId}`): user token sent instead
    of the anon key, URL built from the real segments, never the literal
    `openapi.yaml` path (AD-5).
  - a retryable error (`RATE_LIMITED`) that recovers on retry: the retry
    actually re-sends a second real request and the eventual success maps to
    `Right`.
  - a retryable error (`NETWORK_TIMEOUT`) that never recovers: retried
    exactly `maxRetries` times, then surfaces as `Left(NetworkTimeout)`.
  - a non-retryable error (`AUTH_INVALID`): surfaces immediately as
    `Left(AuthInvalid)`, with no retry request ever sent.

No new UI exists to generate E2E tests for; no new API endpoints beyond the
network pipeline itself exist yet.

## Coverage

- Core network pipeline: unit-level coverage already complete (pre-existing);
  this pass adds the missing wired-together integration coverage.
- UI features: none implemented yet (first screen is story 1.3,
  account-creation-and-login — backlog).

## Verification

- `fvm flutter test` — 88/88 passing (83 pre-existing + 5 new).
- `fvm flutter analyze` — no issues found.

## Next Steps

- Revisit E2E test strategy once a device/simulator or CI step exists
  (AGENTS.md's open TODO) and once story 1.3 ships the first real screen.
- Add API-pipeline coverage for each new `x-cerne-function` operation as its
  consuming feature/story is implemented, following this same
  faked-transport-boundary pattern.

---

# Story 1.2 — Design Token System & Core Component Library

## Context

Story 1.2 delivered `lib/core/design_tokens.dart` and three shared widgets
(`AppButton`, `AppTextField`, `Avatar`). Each component already had thorough
*isolated* widget tests (one component at a time, checked against
`DesignTokens` values). The gap: nothing proved the shared text-field/button
primitives work together the way a consuming screen composes them — user
keystrokes, taps, and focus changes flowing through multiple widgets in the
same tree. That is a gap in the component library's own test coverage, not a
screen's — it holds regardless of which feature consumes the widgets, and
still no device/simulator/CI pipeline exists (AGENTS.md), so a traditional
on-device E2E run isn't possible either way.

(Story 1.3's actual login screen, `auth_screen.dart`, already shipped by the
time of this round of patches — see `git log`. Its own `auth_screen_test.dart`
is BLoC/cubit-focused and doesn't exercise raw widget interaction such as
obscured-text-while-typing, keyboard-action focus movement, or a disabled
button's `onPressed` actually staying `null`; this harness is not a stand-in
for that screen, it covers what that screen's test suite does not.)

## Generated Tests

### Composition/interaction tests (shared widget library, user-driven)

- [x] `test/core/widgets/component_library_interaction_test.dart` — a
      `StatefulWidget` test harness (test-only, not shipped code) composing
      two `AppTextField`s + one `AppButton` the way a form screen will.
      Covers, through real taps and keystrokes:
  - submit button stays disabled (`onPressed: null`) until both fields are
    non-empty, and enables once they are.
  - tapping the enabled button delivers the typed e-mail and senha values.
  - an invalid e-mail surfaces the error border (`colorError`, 1.5px
    `borderWidthEmphasis`) and error text, and never calls the submit
    callback.
  - correcting the e-mail after an invalid submit and resubmitting clears
    the error and calls the submit callback.
  - pressing the keyboard's "next" action on the e-mail field moves focus
    to the senha field (`TextField`'s built-in default behavior — no extra
    wiring needed).
  - the senha field stays obscured while typing.
  - a disabled button's `onPressed` is actually `null`, and tapping it never
    fires the callback.
  - the whole composed form renders with no overflow/exception at a 3.0x
    Dynamic Type scale.

No new API endpoints exist for this story (pure UI/design-system work).

## Coverage

- Core component library: unit-level coverage already complete
  (pre-existing, one widget at a time); this pass adds the missing
  cross-component interaction coverage.
- UI features: Story 1.3's login/signup screen is covered by its own
  `auth_screen_test.dart` (BLoC-focused); this harness covers the shared
  widgets' interaction behavior independent of any one screen.

## Verification

- `fvm flutter test` — 169/169 passing (161 pre-existing + 8 new).
- `fvm flutter analyze` — no issues found.

## Next Steps

- Revisit true device E2E once a device/simulator or CI step exists
  (AGENTS.md's open TODO).

---

# Story 1.3 — Account Creation and Login

## Context

Story 1.3 delivered the first real feature screen (`AuthScreen`, Tela 0.1a)
and the first feature-level API surface (`auth-login`/`auth-signup`). Unlike
stories 1.1 and 1.2, the dev-story and code-review passes for this story
already produced both an E2E-shaped screen test and an API-shaped repository
test directly — this pass's job is to audit that coverage against the
story's own I/O matrix (`spec-1-3-account-creation-and-login.md`) rather than
author it from scratch, and to record the audit here since this file hadn't
been updated since story 1.2.

No device/simulator/CI pipeline exists yet (AGENTS.md), so "E2E" here still
means the same thing it meant for stories 1.1/1.2: drive the real composition
through `flutter_test`, faking only the one boundary each layer can't avoid
(the native secure-storage channel, or the HTTP transport) — not a
traditional on-device run.

## Audited Tests (pre-existing, not newly generated this pass)

### E2E (screen- and composition-root-level, user-driven)

- [x] `test/features/auth/presentation/screens/auth_screen_test.dart` — real
      `AuthCubit` + mocked `AuthRepository`, driven via actual taps/keystrokes
      on `AuthScreen`. Covers every row of the story's I/O matrix: valid
      login, valid signup (exactly `{email, password}`), `AUTH_INVALID` in
      both login and signup mode (both fields bordered, message shown once,
      typed values kept), malformed e-mail blocked pre-network, empty
      password blocked pre-network, a generic network failure rendered via
      `Failure.message`, and no overflow at 3.0x Dynamic Type.
- [x] `test/main_test.dart` — the one test that exercises the real
      composition root (`CerneApp` → `sl<AuthCubit>()` → `onAuthenticated` →
      `Navigator.pushReplacement`), added as a code-review patch for this
      story (`spec-1-3-account-creation-and-login.md`, Review Findings). Only
      `AuthRepository` is swapped for a mock; DI, the real cubit, and the
      real navigation callback all run unchanged.

### API (repository/data-source level, real wiring down to the HTTP boundary)

- [x] `test/features/auth/data/repositories/auth_repository_impl_test.dart`
      — real `AuthRemoteDataSource` (so the real DTO `fromJson`/request-body
      shape is exercised), only `ApiClient` mocked. Runs the project's
      standard `runWriteFailureMatrix` across `auth-signup` and `auth-login`
      (3 failure types each) plus success mapping and the
      save-token-before-`Right` ordering.
- [x] `test/core/network/network_pipeline_integration_test.dart` (story 1.1)
      already uses `auth-login` as its anon-only-operation example end to
      end through the real `Dio` + both real interceptors + `UrlBuilder`,
      with only the `HttpClientAdapter` faked — so the feature's actual
      operation name is proven to reach the wire correctly, not just a
      generic placeholder.

## Gap Analysis — no new tests generated

Between the two layers above, every AC and I/O-matrix row already has
coverage, and the split mirrors this codebase's established pattern (each
integration test fakes exactly one boundary, per `bootstrap_integration_test.dart`'s
and `network_pipeline_integration_test.dart`'s own stated scope). A third
test re-driving `auth-login`/`auth-signup` through the full stack with only
transport faked would duplicate assertions already made in the two tests
above without proving anything new, so none was added (skill guidance:
avoid unnecessary abstractions/duplication).

## Coverage

- Auth feature: validators, cubit, repository/data-source, screen, and
  composition root are each covered at the layer where coverage is cheapest
  and clearest — no layer is untested.
- API endpoints introduced by this story: `auth-login`, `auth-signup` — both
  covered at the repository layer (full failure matrix) and proven to reach
  the real wire at the pipeline layer.

## Verification

- `fvm flutter test` — 171/171 passing.
- `fvm flutter analyze` — no issues found.

## Next Steps

- When story 1.4 (silent session refresh) lands, extend
  `network_pipeline_integration_test.dart`-style real-wiring coverage to the
  refresh-token operation, and add the equivalent repository-layer failure
  matrix for it.
- Revisit true device E2E once a device/simulator or CI step exists
  (AGENTS.md's open TODO).

---

# Story 1.4 — Silent Session Refresh & Persistence

## Context

Story 1.4 delivered the epic's one `SessionRepository`/`SessionStatus` stream
and wired `auth-refresh` + boot-time restoration through it, closing the gap
story 1.3's own summary flagged above. No new screen exists (`main.dart`
branches `home` on the stream instead), so, as with stories 1.1/1.3, "E2E"
here still means driving the real composition through `flutter_test`, faking
only the one boundary each layer can't avoid.

## Generated Tests

### API (data-source/repository level, real wiring down to the HTTP boundary)

- [x] `test/features/auth/data/datasources/auth_remote_data_source_test.dart`
      — real `AuthRemoteDataSource.refresh()`, only `ApiClient` mocked. Runs
      the project's standard `runWriteFailureMatrix` for `auth-refresh` (3
      failure types), plus exact-request-body, nested-`session`-decoding, and
      dead-token-passthrough checks.
- [x] `test/features/auth/data/repositories/session_repository_impl_test.dart`
      — real `SessionRepositoryImpl`, `AuthRemoteDataSource` +
      `AccessTokenProvider` mocked. Covers every row of the story's I/O
      matrix (valid refresh token, no stored session, dead token —
      `AUTH_EXPIRED` and `AUTH_INVALID` — and offline/fail-closed), the two
      platform-exception paths (`readRefreshToken()`/`saveSession()`
      throwing, RNF09), and `statusStream`'s replay-last-value semantics for
      a late subscriber.
- [x] `test/features/auth/data/repositories/auth_repository_impl_test.dart`
      (story 1.3) — updated in place: `saveAccessToken` assertions became
      `saveSession` assertions, now that signup/login persist both tokens.
- [x] `test/core/network/network_pipeline_integration_test.dart` (story 1.1)
      — extended with an `auth-refresh` case proving it goes out with the
      anon-key bearer even when a stale user access token is already stored,
      mirroring the existing `auth-login` case.
- [x] `test/core/network/access_token_provider_test.dart` (story 1.1) —
      extended with round-trip coverage for `saveSession`/`readRefreshToken`/
      `clearSession` against the real `SecureStorageAccessTokenProvider`
      (same faked-native-channel approach as the pre-existing three-method
      coverage in that file).

### Composition root

- [x] `test/main_test.dart` (story 1.3) — extended with the two boot
      branches this story adds: `statusStream` emitting `authenticated` lands
      directly on the post-auth placeholder with `AuthScreen` never shown,
      and emitting `unauthenticated` shows `AuthScreen` with the placeholder
      never shown. The pre-existing login-flow test now also pumps past the
      real (unmocked in that test) `restoreSession()` boot call before
      interacting with the screen.

No new UI exists to generate a traditional E2E test for; `auth-refresh` is
the only new API endpoint this story introduces, and it's covered at both
the data-source/repository layer (above) and the real-pipeline layer.

## Coverage

- Session feature: `AccessTokenProvider`'s new surface, the data source, the
  repository (full I/O matrix + exception paths + stream semantics), and the
  composition root (`main.dart`'s boot branch) are each covered at the layer
  where coverage is cheapest and clearest.
- API endpoints introduced by this story: `auth-refresh` — covered at the
  data-source layer (full failure matrix) and proven to reach the real wire
  at the pipeline layer, same as `auth-login`/`auth-signup` were in story 1.3.

## Verification

- `fvm flutter test` — 192/192 passing.
- `fvm flutter analyze` — no issues found.

## Next Steps

- When story 1.5 (expired-session recovery overlay) lands, it listens to
  this same `statusStream` reactively (on a raw 401 mid-session) rather than
  only at boot — extend coverage there rather than re-deriving session
  validity from a second mechanism.
- Revisit true device E2E once a device/simulator or CI step exists
  (AGENTS.md's open TODO).
