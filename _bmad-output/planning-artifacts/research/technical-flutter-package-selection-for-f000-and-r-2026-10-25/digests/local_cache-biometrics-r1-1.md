# Digest: local cache & biometrics — round 1

## Q1 — Local persistence/cache package for offline-sync journal entries

**Pick: `drift`** (SQLite, code-generated, reactive). **Runner-up: `sqflite`** (raw SQLite, no codegen). **Switch condition:** if build_runner/codegen friction becomes a real blocker on a single-dev timeline, drop to `sqflite` directly and hand-roll mapping — the schema here (entries table + a `syncStatus` enum column) is simple enough that losing codegen costs little.

Reasoning: both NoSQL candidates (`isar`, `hive`) have their *original* packages effectively abandoned (isar: last release 3.1.0+1, April 2023; hive/hive_flutter: last releases 2022/2021), forcing reliance on third-party community forks (`isar_community`, `hive_ce`) that are smaller, younger, and carry fork-maintenance risk. `drift` is actively published (2 days old at check time), Flutter Favorite, verified-publisher maintained, built on SQLite — real `WHERE`-clause filtering (`status = 'pending'`) natively, a good match for "give me all pending-sync entries." `sqflite` is the lower-ceremony fallback: also Flutter Favorite, no codegen, but hand-written SQL/mapping.

None of drift/sqflite/hive/isar expose `Either` natively — all throw exceptions (sync or async) — so the repository layer catches and maps into `Failure` regardless of pick; not a differentiator. Testability with `mocktail` means hiding the storage engine behind a data-source interface and mocking *that*, never the engine's client directly — true for all four, but this guidance is architectural inference, not independently sourced this round.

### Claims (Q1)

| claim | source | publisher | pub_date | accessed | confidence | class |
|---|---|---|---|---|---|---|
| Original Isar's last release is 3.1.0+1, repo activity stalled, described as abandoned/predates Dart 3 | https://dev.co/databases/open-source/isar ; https://pub.dev/packages/isar_community | dev.co; pub.dev | n/a | 2026-10-25 | high (2 sources) | fact |
| `isar_community` is the maintained fork, v3.4.1, published ~11 days before check, 140 pub points, 161 likes, 115k weekly downloads | https://pub.dev/packages/isar_community | pub.dev | 2026-10-14 (approx) | 2026-10-25 | high | fact |
| Original `hive` (2.2.3, ~June 2022) and `hive_flutter` (1.1.0, ~June 2021) have had no new releases for years | fluttergems.dev/packages/hive_flutter ; github.com/hivedb/hive README | FlutterGems; GitHub | n/a | 2026-10-25 | high (2 sources) | fact |
| `hive_ce` ("Hive Community Edition") is the actively maintained continuation, v2.19.3 released Feb 2026 | fluttergems.dev/packages/hive_ce | FlutterGems | 2026-02 (approx) | 2026-10-25 | medium (single source, ~8mo old, borderline past 6-month ecosystem freshness bar) | fact |
| `drift` is at v2.35.3, published ~2 days before check, 160 pub points, 2.48k likes, Flutter Favorite, verified publisher (simonbinder.eu) | https://pub.dev/packages/drift | pub.dev (direct fetch) | 2026-10-23 (approx) | 2026-10-25 | high | fact |
| `sqflite` carries the Flutter Favorite designation | aggregated search snippet (fluttergems/walturn) | FlutterGems / Walturn | n/a | 2026-10-25 | medium (not a direct pub.dev fetch) | fact |

## Q2 — Biometrics package for Face ID/Touch ID gating

**Only one serious candidate: `local_auth`.** A hand-rolled platform-channel implementation is not credible for a single-dev TCC timeline — duplicates what the plugin does with no documented upside.

**Pick: `local_auth`. No real runner-up.** Switch condition: none identified — only if it became unmaintained, which it is not (verified flutter.dev publisher, v3.0.2, 160 pub points, 3.38k likes, 1.82M weekly downloads, last release ~3 months before check).

iOS specifics confirmed:
- `NSFaceIDUsageDescription` required in Info.plist for Face ID; not required for Touch ID (Apple docs).
- `AuthenticationOptions.stickyAuth`: `true` resumes in-flight auth when app returns to foreground; `false` (default) returns immediate failure to Dart on backgrounding mid-auth — app decides whether to restart it. Directly relevant to the "unlock on return from 5-minute background timeout" flow; the idle-timeout gate itself is app logic (`WidgetsBindingObserver`/`didChangeAppLifecycleState`), not plugin-provided.
- Biometric lockout (`LAError` `biometryLockout`/`lockedOut` after repeated failures) can only be cleared by successful device-passcode entry — no programmatic reset. App must catch this and fall back to a passcode-entry path.
- Fallback-to-device-passcode is default unless `biometricOnly: true` is set — this detail is inferred from general API-shape mentions across search results, not independently confirmed by opening `local_auth_darwin`'s README this round (flagged as gap).

### Claims (Q2)

| claim | source | publisher | pub_date | accessed | confidence | class |
|---|---|---|---|---|---|---|
| `local_auth` v3.0.2, 160 pub points, 3.38k likes, 1.82M weekly downloads, verified publisher flutter.dev, iOS 13.0+/macOS 10.15+ support | https://pub.dev/packages/local_auth | pub.dev (direct fetch) | ~2026-07/08 ("3 months ago") | 2026-10-25 | high | fact |
| `NSFaceIDUsageDescription` required in Info.plist for Face ID; not required for Touch ID | developer.apple.com (LocalAuthentication docs) | Apple | n/a | 2026-10-25 | high | fact |
| `stickyAuth` option: true = resume auth on resume; false (default) = immediate failure on backgrounding | pub-web.flutter-io.cn mirror of local_auth docs | flutter.dev (mirrored) | n/a | 2026-10-25 | high | fact |
| Biometric lockout after repeated failed attempts requires passcode entry to reset; no programmatic reset | developer.apple.com LAError docs; pub.dev `local_biometric` package docs (restates same LAError semantics) | Apple; pub.dev | n/a | 2026-10-25 | high (2 sources, second restates Apple's own semantics) | fact |

## Leads not chased (budget spent)
- Direct pub.dev fetch of `sqflite` itself (version/last-publish/score) — relied on aggregated snippet.
- `local_auth_darwin` README's exact `biometricOnly`/fallback wording and iOS-simulator testing caveats — not independently verified; treat simulator-behavior statements as unverified.
- Comparing Isar forks (`isar_community`, `isar_db`, `isar_plus`) against each other — only `isar_community` checked directly.
- Production retrospective on `drift` pain points (web/wasm build issues, migration tooling) — not searched; recommendation rests on maintenance/adoption signals only.
- A documented pairing of `drift`/`local_auth` with `mocktail` — testability answer is architectural inference, not independently sourced.

## Explicit gaps
- `local_auth`'s current Flutter Favorite badge status not confirmed via direct pub.dev fetch — inferred from aggregated listings.
- No sourced evidence on iOS Simulator biometric testing limitations — do not treat any simulator claim as verified.
- `hive_ce`'s broader production track record beyond its pub.dev listing snippet not checked — "actively maintained" claim rests on one ~8-month-old source, at the edge of the freshness bar.
