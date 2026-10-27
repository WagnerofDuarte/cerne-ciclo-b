---
title: 'technical research: Flutter package selection for F000 and RF03 free-choice slots'
type: 'technical'
topic: 'Flutter package selection for F000 and RF03 free-choice slots'
decision: 'Pick concrete packages for Cerne''s six free-choice technical slots (routing, HTTP client, local cache, dependency injection, secure storage, biometrics), needed for F000 (foundation) and RF03 (biometric vault), the next two units in the delivery order.'
source: 'run'
status: complete
preset: 'standard'
validation: 'normal'
created: '2026-10-25'
updated: '2026-10-25'
claims_verified: 2
claims_unverified: 2
claims_overturned: 1
---

# technical research: Flutter package selection for F000 and RF03 free-choice slots

**Decision this research serves:** Pick concrete packages for Cerne's six free-choice technical slots (routing, HTTP client, local cache, dependency injection, secure storage, biometrics), needed for F000 (foundation) and RF03 (biometric vault), the next two units in the delivery order.

## Executive summary

Six picks, each with a clear runner-up and switch condition:

| Slot | Pick | Runner-up | Confidence |
|---|---|---|---|
| Routing | `go_router` | `auto_route` | High |
| HTTP client | `dio` | `package:http` | High |
| Local cache / persistence | `drift` | `sqflite` | High |
| Dependency injection | `get_it` | `riverpod`-as-DI | Medium-high |
| Secure storage | `flutter_secure_storage` | `flutter_keychain` | High |
| Biometrics | `local_auth` | none (sole credible candidate) | High |

The driving pattern across all six: **avoid build-time codegen unless it earns its keep.** `go_router`, `get_it`, and `dio` all have codegen-based siblings (`auto_route`+generator, `injectable`, `chopper`) that are credible but add a `build_runner` step a solo developer on a fixed timeline doesn't need yet — every codegen alternative is kept as the documented upgrade path, not dismissed. The other driving pattern: **two of the "obvious" NoSQL picks are traps.** Both `isar` and `hive`, the packages most tutorials still point to, have their original packages effectively abandoned (last releases 2022–2023); only community forks remain. `drift` (SQLite, actively maintained, Flutter Favorite) avoids that risk entirely.

Biggest caveat: none of these picks were checked against each other for cross-package friction (e.g., `dio` + `flutter_secure_storage` + `get_it` wired together) — each was researched independently. This is a reasonable risk to accept (all six are mainstream, independently popular, non-exotic choices with no known incompatibilities surfaced), but it is an open question, not a verified fact.

## 1. Routing

**Pick: `go_router`. Runner-up: `auto_route`.**

| Criterion | `go_router` | `auto_route` | `Beamer` | GetX router |
|---|---|---|---|---|
| Fit: `flutter_bloc` redirect-on-session-expiry | Documented pattern via `redirect` + `refreshListenable` [30] | Supported, less first-party-documented | Not screened | Poor prior fit, not screened |
| Clean Architecture fit | Pure presentation layer, no codegen required [26] | Pure presentation layer, needs `build_runner` + annotations | — | — |
| Maturity / adoption | Flutter-team-maintained, larger adoption, 4,435 likes [26][27] | Active (11.1.0, Dec 2025; generator 10.5.0, Feb 2026), 3.39K likes, smaller ecosystem [28] | Last GitHub push reported Oct 2024, no 2025/2026 activity found [29] | Not researched |
| Learning curve (solo dev, deadline) | No codegen, largest tutorial volume | One more moving part (codegen) | — | — |
| Cut reason | — | Kept as runner-up | Stale — screened out | Conflicts with `flutter_bloc` + Clean Architecture commitments; not pursued |

**Switch condition:** move to `auto_route` if compile-time-checked route arguments become worth a second codegen pipeline, or if `go_router`'s maintenance-mode status (Flutter team shipping bug fixes, not new features [27]) turns into an actually-missing capability.

**Verified at landing:** the "go_router is still the right 2026 default" verdict was single-sourced to a Feb 2025 article [27]; an independent, fresher check (Jul 2026) reached the same conclusion [36] — **status: verified**. A separate claim in [27] that `auto_route` was "stagnating" is **overturned** by current `auto_route` release data showing active Dec 2025/Feb 2026 releases [28] — `auto_route` is not stagnant, it is simply smaller.

**Unverified pain-point (flagged, not a finding):** reports of `go_router` API instability across versions and `StatefulShellRoute` complaints surfaced only as a single aggregated search synthesis [31], not two independent primary sources. Treat as a signal worth watching during implementation, not a confirmed flaw.

## 2. HTTP client

**Pick: `dio`. Runner-up: `package:http`.**

| Criterion | `dio` | `package:http` | `chopper` |
|---|---|---|---|
| Header injection (apikey always, Bearer conditionally) | First-class `Interceptor`s, global + per-request [1] | No built-in interceptor system — needs hand-extending `BaseClient.send()` or a third-party add-on [7][8] | Interceptor support exists but gated behind codegen |
| Retry on `retryable:true` error codes | Documented `retryEvaluator` pattern keyed off exception type/status [2][3] | Manual | Not independently checked |
| Mapping into `Either<Failure,T>` | Single typed `DioException` on every failure path — narrow, clean catch surface [1] | Throws various exception types; no unifying type | Not independently checked |
| Testability (`mocktail`) | `MockDio` or `http_mock_adapter` [4][5] | Mockable, simpler surface | Not independently checked |
| Maturity | 160 pub points, 8.37k likes, 5.2M weekly downloads [1] | First-party Dart-team package | 906 likes, needs `build_runner` [6] |

**Switch condition:** only to `chopper`, only if the project later wants Retrofit-style typed API clients and accepts a `build_runner` pipeline — not recommended given the timeline.

## 3. Local cache / persistence

**Pick: `drift`. Runner-up: `sqflite`.**

| Criterion | `drift` | `sqflite` | `isar` | `hive` |
|---|---|---|---|---|
| Maintenance status | Actively published (~2 days old at check), Flutter Favorite, verified publisher [20] | Flutter Favorite, no codegen [21] | **Original package abandoned** — last release Apr 2023; only `isar_community` fork remains [15][16] | **Original packages abandoned** — last releases 2021/2022; only `hive_ce` fork remains [17][18][19] |
| Fit: filter by sync status (`pending`/`synced`/`failed`) | Native SQL `WHERE` filtering | Native SQL `WHERE` filtering, hand-written | Possible via fork, less direct | Possible via fork, less direct |
| Codegen cost | `build_runner` required | None — hand-written SQL/mapping | Fork-dependent | Fork-dependent |
| Risk | Low — primary package itself is healthy | Low — but hand-rolled mapping | **Elevated** — fork-maintenance risk, smaller/younger community | **Elevated** — same fork risk |

**Switch condition:** drop to `sqflite` if `build_runner`/codegen friction becomes a real blocker on a solo timeline — the schema here (an entries table + a `syncStatus` column) is simple enough that losing codegen costs little.

**Note (not independently sourced, architectural inference):** none of the four candidates expose `Either` natively — all throw exceptions, so the repository layer catches and maps to `Failure` regardless of pick. Not a differentiator between candidates.

## 4. Dependency injection

**Pick: `get_it`** (manual registration at a single composition root; skip `injectable` unless registration volume gets painful). **Runner-up: `riverpod`-as-DI.**

| Criterion | `get_it` | `riverpod`-as-DI | `injectable` (codegen add-on) |
|---|---|---|---|
| Flutter-free (RNF06 — domain never imports `flutter`) | Pure Dart, no Flutter dependency (architectural inference, not independently sourced) | Non-Flutter core package, usable without Flutter dependency | N/A — add-on to `get_it` |
| Testability | Singleton locator, but explicitly designed to reset/override per test (`getIt.reset()`, `pushNewScope()`) — satisfies "no untestable hidden singleton" in practice, though it architecturally *is* a singleton | Provider-override (`overrideWithValue`) arguably cleaner for test swapping | Same as `get_it` |
| Fit alongside `flutter_bloc` | Standard: `BlocProvider(create: (_) => getIt<MyBloc>())` | No current production source found pairing Riverpod-as-DI underneath `flutter_bloc` — unverified/thin combination | — |
| Maturity | 140/140 pub points, 4.7K likes, 1.7M downloads/30d [32] | Not independently checked as standalone signal | v3.0.0, LeanBuilder since 2.12.0+ fixes historical slow-build complaint [33] |

**Switch condition:** only if the project drops `flutter_bloc` for Riverpod's own state-management primitives — running two separate reactive/DI paradigms side by side adds avoidable conceptual overhead on a solo deadline.

**Explicit gap:** `provider` and "no-package manual DI" were named candidates but not researched this round — no claims are reported for them; they are not evidenced as cut, simply not pursued.

## 5. Secure storage

**Pick: `flutter_secure_storage`. Runner-up: `flutter_keychain`.**

| Criterion | `flutter_secure_storage` | `flutter_keychain` |
|---|---|---|
| Maintenance | 160 pub points, 4.5k likes, 5.64M weekly downloads, last published ~39 days before check, verified publisher [9] | Latest 3.0.1 (~Mar 2026), far smaller footprint — "small and quiet," not confirmed "small and solid"; unverified [14] |
| iOS Keychain control | Exposes `IOSOptions(accessibility: ...)` directly, including `first_unlock`/`first_unlock_this_device` [11][12] — the control needed for "readable after biometric unlock, survives restart" | Not independently checked |
| Known pitfall | v10→v11 breaking change (custom cipher); pre-v10 data needs the v10 migration step before jumping to v11 or becomes unreadable [9][10] | — |
| Testability | Trivially abstracted behind a repository interface, mockable | Same |

**Switch condition:** none realistic for an iOS-only app — would only apply if the v10/v11 migration caused unresolvable data loss, or Android-specific tuning were needed (it isn't).

**Architectural note, not independently sourced:** Keychain accessibility classes govern *device*-lock state, not the app's own biometric re-auth gate — RF03's 5-minute-timeout re-auth logic sits on top of, not inside, whichever storage package is chosen.

**Unverified pain-point:** reported iOS Keychain error codes (-25308, -25291) around app restart/background are single-source/anecdotal [13] — no second source found; not treated as a confirmed, current issue.

## 6. Biometrics

**Pick: `local_auth`. No real runner-up — sole credible candidate.**

A hand-rolled platform-channel implementation was considered and rejected: it duplicates what the plugin already does, with no documented upside found for a solo-dev timeline.

- Maturity: verified `flutter.dev` publisher, 160 pub points, 3.38k likes, 1.82M weekly downloads, last release ~3 months before check [22].
- `NSFaceIDUsageDescription` is required in `Info.plist` for Face ID; not required for Touch ID [23].
- `AuthenticationOptions.stickyAuth`: `true` resumes an in-flight auth when the app returns to foreground; `false` (default) returns immediate failure on backgrounding — the app decides whether to restart it [24]. The 5-minute idle-timeout gate itself (RF03) is app-level logic built on `WidgetsBindingObserver`/`didChangeAppLifecycleState`, not something the plugin provides.
- Biometric lockout (`LAError.biometryLockout`/`lockedOut`) after repeated failures can only be cleared by the user entering the device passcode — no programmatic reset. The app must catch this and route to a passcode-entry fallback rather than retry biometrics [23][25].

**Switch condition:** none identified — only if `local_auth` became unmaintained, which current data does not support.

## Cross-dimension insights

- **The codegen-avoidance pattern recurs independently three times** (routing vs. `auto_route`, DI vs. `injectable`, HTTP vs. `chopper`) — each dimension was researched in isolation, yet all three landed on "skip the codegen sibling for now, keep it as a named upgrade path." That consistency is itself a weak signal that the "no codegen yet" call is the right default for this project's size and timeline, not an artifact of one researcher's bias.
- **The abandoned-package trap is specific to the local-cache dimension.** No other category had a "popular package, but actually dead" result — `isar`/`hive` is a real, non-obvious risk this research caught; a developer going by package-name familiarity alone (both are still widely referenced in older tutorials) would have picked a fork-dependent, higher-risk option without knowing it.
- **Biometrics and secure storage are adjacent but distinct concerns that a less careful pick could conflate.** `local_auth` gates *access*; `flutter_secure_storage`'s Keychain accessibility class governs *when stored data is readable relative to device-lock state* — the RF03 "5-minute background timeout → re-auth" flow needs both, wired together at the app layer, and neither package solves the other's half.

## Recommendations

Each pick feeds the same two downstream units — **F000** (foundation: routing, HTTP client, local cache, DI, secure storage) and **RF03** (biometric vault: secure storage, biometrics) — the next two items in the delivery order (`docs/input/requirements.md` §12). None of these picks are architecture-spine input yet, since no architecture spine has been produced for this project; if one is, these six choices are its "free-choice slot" resolutions.

1. **Routing — `go_router`.** High confidence. Adopt directly into F000's base navigation; the `redirect`+`refreshListenable` pattern is the mechanism for F000's expired-session handling.
2. **HTTP client — `dio`.** High confidence. Adopt directly into F000's HTTP client; its interceptor model is the mechanism for the `apikey`/`Authorization` header rules and `retryable` error-code handling.
3. **Local cache — `drift`.** High confidence. Adopt into F000; needed wherever offline-queued entries and sync-badge status are first modeled (ahead of RF01/RF07 per the delivery order).
4. **Dependency injection — `get_it`.** Medium-high confidence. Adopt into F000 as the single composition root; revisit only if registration volume later justifies `injectable`.
5. **Secure storage — `flutter_secure_storage`.** High confidence. Adopt into F000 for token storage; the `first_unlock` accessibility class is the specific configuration RF03 needs.
6. **Biometrics — `local_auth`.** High confidence. Adopt directly into RF03; no credible alternative was found.

## Open questions

- **Cross-package integration friction** (e.g., `dio` + `flutter_secure_storage` + `get_it` wired together in the same composition root) was not tested — each pick was researched independently. Resolving this needs hands-on integration during F000, not more research.
- **`go_router`'s version-to-version API stability** complaint [31] is a single aggregated, unattributed synthesis — resolving it needs a direct read of `github.com/flutter/packages` issues filtered for `go_router` + "breaking change."
- **`flutter_secure_storage`'s iOS Keychain error codes (-25308/-25291) on restart/background** [13] — resolving it needs a direct search of `github.com/juliansteenbakker/flutter_secure_storage/issues` filtered for "iOS" + "restart"; currently single-source/anecdotal.
- **`provider` and manual-constructor DI** (named Q2 candidates) and **GetX's router** (named Q1 candidate) were never researched — if either is later reconsidered, this report provides no evidence on them either way.
- **`riverpod`-as-DI-under-`flutter_bloc`** is a named runner-up with no current production source evidencing the combination works well in practice — treat it as a reasoned inference, not a verified pattern, if ever promoted from runner-up to pick.

## Source appendix

| # | Claim / finding it supports | Publisher | Pub. date | Accessed | Confidence |
|---|---|---|---|---|---|
| [1] | [dio version 5.11.1, interceptors, DioException](https://pub.dev/packages/dio) | pub.dev | live page | 2026-10-25 | High |
| [2] | [dio retryEvaluator pattern](https://pub.dev/documentation/dio_retry_it/latest/) | pub.dev docs | current | 2026-10-25 | High |
| [3] | [RetryInterceptor.onError pattern](https://pub.dev/documentation/gt_api/1.1.0/api_service_retry_interceptor/RetryInterceptor/onError.html) | pub.dev docs | current | 2026-10-25 | High |
| [4] | [http_mock_adapter for dio testing](https://pub.dev/packages/http_mock_adapter) | pub.dev | current | 2026-10-25 | Medium |
| [5] | [dio mocktail pattern / MockDio](https://sahasuthpala.medium.com/unit-testing-in-dio-dart-package-91b7a78314bc) | Medium | current | 2026-10-25 | Medium |
| [6] | [chopper version ~8.5-8.6, 906 likes, needs build_runner](https://pub.dev/packages/chopper) | pub.dev | live page | 2026-10-25 | Medium |
| [7] | [package:http has no built-in interceptors](https://pub.dev/documentation/http_interceptor/latest/) | pub.dev docs | current | 2026-10-25 | Medium |
| [8] | [http_client_interceptor as third-party add-on](https://pub.dev/documentation/http_client_interceptor/latest/) | pub.dev docs | current | 2026-10-25 | Medium |
| [9] | [flutter_secure_storage v11.2.0, 5.64M weekly downloads](https://pub.dev/packages/flutter_secure_storage) | pub.dev | live page | 2026-10-25 | High |
| [10] | [v10→v11 cipher migration pitfall](https://github.com/juliansteenbakker/flutter_secure_storage/releases) | GitHub | 2026 | 2026-10-25 | Medium |
| [11] | [IOSOptions KeychainAccessibility semantics](https://docs.flet.dev/secure_storage/types/keychainaccessibility) | flet.dev docs | current | 2026-10-25 | High |
| [12] | [flutter_secure_storage IOSOptions docs](https://pub.dev/documentation/flutter_secure_storage/latest/) | pub.dev docs | current | 2026-10-25 | High |
| [13] | iOS Keychain error codes -25308/-25291 on restart | community forum (FlutterFlow community) | undated | 2026-10-25 | Low (single-source, unverified) |
| [14] | flutter_keychain v3.0.1 adoption snippet | aggregator (fluttergems-adjacent) | 2026-03 (claimed) | 2026-10-25 | Low-medium (unverified at source) |
| [15] | [Isar original package abandoned](https://dev.co/databases/open-source/isar) | dev.co | n/a | 2026-10-25 | High (2 sources) |
| [16] | [isar_community fork, v3.4.1](https://pub.dev/packages/isar_community) | pub.dev | 2026-10-14 (approx) | 2026-10-25 | High |
| [17] | [hive_flutter stale since ~2021](https://fluttergems.dev/packages/hive_flutter) | FlutterGems | n/a | 2026-10-25 | High (2 sources) |
| [18] | [hive README, no new releases](https://github.com/hivedb/hive) | GitHub | n/a | 2026-10-25 | High |
| [19] | [hive_ce active fork, v2.19.3](https://fluttergems.dev/packages/hive_ce) | FlutterGems | 2026-02 (approx) | 2026-10-25 | Medium (borderline freshness) |
| [20] | [drift v2.35.3, Flutter Favorite, verified publisher](https://pub.dev/packages/drift) | pub.dev | 2026-10-23 (approx) | 2026-10-25 | High |
| [21] | sqflite Flutter Favorite designation | aggregator (FlutterGems/Walturn) | n/a | 2026-10-25 | Medium |
| [22] | [local_auth v3.0.2, verified flutter.dev publisher](https://pub.dev/packages/local_auth) | pub.dev | ~2026-07/08 | 2026-10-25 | High |
| [23] | NSFaceIDUsageDescription requirement; biometric lockout semantics | developer.apple.com (LocalAuthentication / LAError docs) | n/a | 2026-10-25 | High |
| [24] | stickyAuth option semantics | flutter.dev (pub-web mirror of local_auth docs) | n/a | 2026-10-25 | High |
| [25] | LAError lockout semantics restated | pub.dev (`local_biometric` package docs) | n/a | 2026-10-25 | High (2 sources) |
| [26] | go_router 4,435 likes, score 87/100 | pub.dev mirror (pub-web.flutter-io.cn) | ~Apr 2026 | 2026-10-25 | Medium |
| [27] | ["Is GoRouter Still The Best Choice?"](https://8thlight.com/insights/flutter-navigation-is-gorouter-still-the-best-choice) | 8th Light | ~Feb 2025 | 2026-10-25 | Medium (dated; independently re-confirmed by [36]) |
| [28] | auto_route v11.1.0 (Dec 2025), active releases | pub.dev mirror (pub-web-s2.flutter-io.cn) | Dec 2025/Feb 2026 | 2026-10-25 | Medium |
| [29] | [Beamer last push Oct 2024](https://gittrend.io/repo/slovnicki/beamer) | gittrend.io | n/a | 2026-10-25 | Low-medium (single third-party source) |
| [30] | [go_router redirect + refreshListenable pattern](https://gurubase.io/g/flutter/redirecting-routes-go-router-bloc-flutter) | gurubase.io | n/a | 2026-10-25 | Medium |
| [31] | go_router API-instability complaints | aggregated WebSearch synthesis, unattributed | unknown | 2026-10-25 | Low (unverified, single aggregated synthesis) |
| [32] | get_it v9.2.1, 4.7K likes, 1.7M downloads/30d | pub.dev / FlutterGems mirror | Feb 2026 | 2026-10-25 | Medium-high |
| [33] | injectable v3.0.0, LeanBuilder since 2.12.0+ | pub.dev documentation / FlutterGems | Apr 2026 | 2026-10-25 | Medium-high |
| [34] | [get_it vs riverpod DI comparison](https://blog.gskinner.com/archives/2021/11/flutter-comparing-getit-provider-and-riverpod.html) | gskinner blog | Nov 2021 | 2026-10-25 | Low (stale, outside 2-year pattern bar) |
| [35] | Clean Architecture + get_it + injectable + mocktail pairing | aggregated dev.to/Medium tutorials, unattributed | unknown | 2026-10-25 | Low-medium |
| [36] | ["go_router vs auto_route vs Navigator 2.0 in Flutter"](https://startdebugging.net/2026/07/go-router-vs-auto-route-vs-navigator-2-0-in-flutter/) — independent 2026 confirmation of [27]'s verdict | startdebugging.net | 2026-07 | 2026-10-25 | High (fresh, independent) |

## Staleness map

| Claim | Class | Pub. date | Freshness bar | Re-check by |
|---|---|---|---|---|
| Version/adoption numbers for all 6 picks ([1][9][16][20][22][26][28][32][33]) | version/compatibility | 2026-10 to 2026-04 | ≤ 1 month | 2026-11-25 (re-check immediately before F000/RF03 implementation starts) |
| Ecosystem/maintenance health signals ([15][17][18][19][29]) | ecosystem health | 2022–2026 | ≤ 6 months | 2027-04-25 |
| Pattern-level claims (redirect/refreshListenable [30], Clean Architecture pairing [35], DI comparison [34]) | pattern | 2021–current | ≤ 2 years | 2027-10 (claims 2 years from publication) — [34] (Nov 2021) is already past this bar and should be treated as background context only, not current evidence |

**Earliest re-check: 2026-11-25** — version/compatibility numbers age fastest in this report; re-verify current `pub.dev` figures for all six picks directly (not via mirrors) before F000 implementation locks in dependencies.

**Standing caveat (per the research firewall):** these picks were screened and scored against a constraints frame derived from this project's own docs (`flutter_bloc`, Clean Architecture/RNF06, `fpdart`/`Either`, `mocktail`, iOS-only, solo-dev timeline) — that frame is the only project-sourced input; every factual claim above traces to an external source in the appendix, never to project documentation.
