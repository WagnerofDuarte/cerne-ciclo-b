# Digest: HTTP client & secure storage — round 1

## Q1 — HTTP client package

**Pick: `dio`. Runner-up: `package:http` (+ hand-rolled `BaseClient` wrapper). Switch condition: switch to `chopper` only if the project later wants compile-time-generated, Retrofit-style typed API clients and is willing to add `build_runner` codegen to a solo-dev tight-timeline project — not recommended here.**

Reasoning: `dio` ships first-class `Interceptor`s (onRequest/onResponse/onError hooks) that map directly onto the two needs called out in the brief — global+per-call header injection and centralizing retry on `retryable:true` codes (documented pattern: a custom interceptor with a `retryEvaluator` keyed off `DioExceptionType`/status code). It throws a single typed `DioException` on every failure path (timeout, cancel, bad response, connection error) — a clean, narrow surface to catch at the data-source boundary and map into `Failure` variants for `Either<Failure,T>`, no competing result-type ecosystem to fight `fpdart`. Mockable with `mocktail` (`class MockDio extends Mock implements Dio {}`) or `http_mock_adapter` for adapter-level stubbing. `package:http` is the safer minimal-dependency fallback (first-party/Dart-team-maintained) but has **no built-in interceptor system** — centralized header injection/retry needs manually extending `http.BaseClient.send()` or a third-party interceptor package of uncertain maturity. `chopper` (906 likes vs dio's 8.37k) is a Retrofit-style generator needing `build_runner` + `chopper_generator` — codegen friction that doesn't pay off at this project's scope.

## Q2 — Secure storage package

**Pick: `flutter_secure_storage`. Runner-up: `flutter_keychain`. Switch condition: only if `flutter_secure_storage`'s v10→v11 migration (custom cipher / SecAccess changes) causes unresolvable data-loss on upgrade, or the project needs Android-specific tuning it doesn't — neither applies to an iOS-only app, so no real switch trigger here.**

Reasoning: `flutter_secure_storage` leads on maintenance signal (160 pub points, 4.5k likes, 5.64M weekly downloads, last published ~39 days ago, verified publisher) vs `flutter_keychain` (latest 3.0.1, March 2026, far smaller footprint — "small and quiet," not necessarily "small and solid"). On iOS it wraps Keychain and exposes the accessibility-class knob directly (`IOSOptions(accessibility: KeychainAccessibility.xxx)`), including `first_unlock`/`first_unlock_this_device` — exactly the control needed for "available after biometric unlock, persists across restarts, protected at rest." For a 5-minute-background biometric-gate app, `first_unlock` is the accessibility class to pick (readable once the device has been unlocked after boot, without requiring it to stay unlocked). Both packages abstract trivially behind a repository interface for `mocktail`. Known pain points: a breaking change at v10/v11 (custom cipher; pre-v10 data needs the v10 migration step before jumping to v11, or becomes unreadable) — mitigated by pinning a current v11.x and not skipping the v10 migration step; and scattered iOS Keychain error codes (-25308, -25291) reported around background/restart, reportedly solvable via `first_unlock`/`first_unlock_this_device` — but this is single-source/anecdotal, flagged low confidence.

**Architectural note (not directly evidenced, flagged as reasoning not a sourced claim):** Keychain accessibility classes govern device-lock state, not in-app biometric gates — the app's RF03 biometric re-auth logic is a separate, app-level concern layered on top of (not solved by) the storage package choice.

## Claims

| claim | source | publisher | pub_date | accessed | confidence | class |
|---|---|---|---|---|---|---|
| dio current version 5.11.1, 160 pub points, 8.37k likes, 5.2M weekly downloads, last published ~51 days ago, verified publisher flutter.cn | https://pub.dev/packages/dio | pub.dev | live page | 2026-10-25 | high | maintenance signal |
| dio supports Interceptors, request cancel/abort, custom adapters, transformers | https://pub.dev/packages/dio | pub.dev | live page | 2026-10-25 | high | feature |
| DioException carries a `type` (e.g. connectionTimeout, badResponse) checkable via a `retryEvaluator` to drive retry interceptors | https://pub.dev/documentation/dio_retry_it/latest/ ; https://pub.dev/documentation/gt_api/1.1.0/api_service_retry_interceptor/RetryInterceptor/onError.html | pub.dev docs | current | 2026-10-25 | high (2 independent sources) | pattern |
| MockDio via mocktail (`class MockDio extends Mock implements Dio`) is a standard dio test pattern; alternative `http_mock_adapter` for adapter-level stubbing | https://pub.dev/packages/http_mock_adapter ; https://sahasuthpala.medium.com/unit-testing-in-dio-dart-package-91b7a78314bc | pub.dev / Medium | current | 2026-10-25 | medium | testability |
| chopper current version ~8.5–8.6, 906 likes, 160 pub points, 130.9k monthly downloads, requires build_runner + chopper_generator | https://pub.dev/packages/chopper | pub.dev | live page | 2026-10-25 | medium (minor version discrepancy between two fetched fragments) | maintenance signal |
| `package:http` has no built-in interceptor mechanism; interception requires extending `http.BaseClient.send()` or a third-party package (`http_interceptor`, `http_client_interceptor`) | https://pub.dev/documentation/http_interceptor/latest/ ; https://pub.dev/documentation/http_client_interceptor/latest/ | pub.dev docs | current | 2026-10-25 | medium (inferred, not a direct maintainer statement) | architectural gap |
| flutter_secure_storage current version 11.2.0, 160 pub points, 4.5k likes, 5.64M weekly downloads, last published ~39 days ago, verified publisher steenbakker.dev | https://pub.dev/packages/flutter_secure_storage | pub.dev | live page | 2026-10-25 | high | maintenance signal |
| v10.0.0 introduced a custom-cipher security change; pre-v10 data needs the v10 migration before going to v11, or becomes unreadable | https://pub.dev/packages/flutter_secure_storage ; https://github.com/juliansteenbakker/flutter_secure_storage/releases | pub.dev / GitHub | 2026 | 2026-10-25 | medium (single clear source) | migration pitfall |
| IOSOptions `accessibility` (e.g. `KeychainAccessibility.first_unlock`, `first_unlock_this_device`) controls when stored Keychain values are readable relative to device unlock/boot state | https://docs.flet.dev/secure_storage/types/keychainaccessibility ; https://pub.dev/documentation/flutter_secure_storage/latest/ | flet.dev docs / pub.dev docs | current | 2026-10-25 | high (2 independent sources) | iOS-specific behavior |
| Reported Keychain error codes -25308 ("user interaction not allowed") and -25291 ("no keychain available") around app restart/background, addressed by setting `first_unlock`/`first_unlock_this_device` | community forum thread (FlutterFlow community) | community forum | undated | 2026-10-25 | low — single-source/anecdotal | known issue |
| flutter_keychain latest version 3.0.1 (~March 2026), created 2018, 0 open issues reported at search time | search snippet (aggregator) | secondary aggregator, not pub.dev directly | 2026-03 (claimed) | 2026-10-25 | low-medium (unverified at source) | maintenance signal |

## Leads not chased (budget spent)
- `flutter_keychain`'s pub.dev score page not fetched directly (only via aggregator snippet) — verify before relying on it.
- dio's GitHub issue tracker not searched directly for HTTP/2 adapter / cert-pinning complaints.
- chopper's own docs not read directly for retry/interceptor API surface.
- No second independent source found for the -25308/-25291 Keychain codes — a direct `github.com/juliansteenbakker/flutter_secure_storage/issues` search filtered for "iOS"+"restart" would resolve this.
- Did not evidence "read after biometric re-auth without fresh app launch" behavior — flagged as an architectural reasoning note, not a sourced claim.

## Explicit gaps
- No clean single authoritative chopper likes/points number (minor inconsistency between two fetched fragments).
- No freshness-qualified (≤1 month) source confirming dio's cert-pinning/HTTP2 adapter stability in production specifically.
- No primary GitHub issue page confirming whether the -25308/-25291 Keychain codes reproduce on current flutter_secure_storage (11.2.0) vs. being a legacy complaint.
