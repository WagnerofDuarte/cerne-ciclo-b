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
