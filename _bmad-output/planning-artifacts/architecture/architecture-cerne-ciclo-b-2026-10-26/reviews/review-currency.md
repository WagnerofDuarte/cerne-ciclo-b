# Review: Stack Currency (Reviewer Gate — web-verification lens)

**Verdict: minor drift** — 12 of 13 spot-checked pins are exactly right against live pub.dev data; one (`json_serializable`) is stale by six minor versions, including a release that landed only 6 days before the spine's own claimed verification date.

## Findings

1. **`json_serializable ^6.9.5` is stale — actual latest is 6.15.2.** Checked `https://pub.dev/api/packages/json_serializable` directly: latest published version is **6.15.2**, published **October 20, 2026** — six days before the spine's "web-verified 2026-10-26" timestamp. Intermediate releases (6.15.1 Oct 13 2026, 6.15.0 Sep 24 2026, 6.14.0 Jun 12 2026, 6.13.1 Mar 8 2026, 6.13.0 Feb 10 2026) show the spine's pin is roughly 8–9 months and 6 minor versions behind. This one entry looks asserted rather than freshly checked; the other 12 pins in the table were bang-on, so the gap is isolated rather than systemic. Source: `pub.dev/api/packages/json_serializable` (fetched live 2026-10-26).

2. **hive_ce vs. plain hive/hive_flutter claim holds up, but with a nuance worth recording.** `hive` latest is 2.2.3, published June 30, 2022 (4+ years stale); `hive_flutter` latest is 1.1.0, published ~5 years ago; pub.dev's package-metadata API shows **no formal `isDiscontinued` flag** on `hive` (only one retracted version, 2.2.0, which is unrelated). So the spine's wording "now unmaintained" overstates what pub.dev itself declares — it is a substantive, not official, judgment. In practice the judgment is correct: `hive_ce`/`hive_ce_flutter`/`hive_ce_generator` have all shipped within the last ~30 days (hive_ce 2.22.0 published 12 days ago), versus years of silence on the originals. Net: the pick is right, the review should just note "unmaintained" is the reviewer's inference, not a pub.dev badge. Sources: `pub.dev/packages/hive`, `pub.dev/packages/hive_flutter`, `pub.dev/api/packages/hive`, `pub.dev/packages/hive_ce`.

3. **No other listed package has quietly gone unmaintained or been superseded.** Live-checked `flutter_bloc` (9.1.1, published 18 months ago but still the current release and actively tracked), `go_router` (18.1.1, published 6 days ago, verified flutter.dev publisher), `dio` (5.11.1, published ~52 days ago), `get_it` (9.3.0, 37 days ago), `fpdart` (1.2.0, Oct 29 2025 — genuinely the current latest despite an irregular release cadence, not abandonment), `freezed` (4.0.3, 9 days ago), `mocktail` (1.0.5, 6 months ago, verified felangel.dev publisher), `fl_chart` (1.3.0, 5 days ago), `local_auth` (3.0.2, 3 months ago, verified flutter.dev publisher), `flutter_secure_storage` (11.2.0, 40 days ago), `flutter_dotenv` (6.0.1, 6 months ago) — every one of these matches the spine's pin exactly and shows ongoing maintenance. Sources: respective `pub.dev/packages/<name>` pages, fetched live 2026-10-26.

4. **Flutter 3.47.x / "3.50 not yet promoted to stable" framing is accurate as of today.** `docs.flutter.dev/release/archive` (and the release-schedule table) shows Flutter 3.47 is the current stable family (branch cutoff 2026-07-07, released August 2026, latest patch referenced is 3.47.8 per a security advisory on the page), while Flutter 3.50 is scheduled for a **November 2026** release with branch cutoff **2026-10-06** — i.e. still in pre-release/beta as of 2026-10-26, not yet promoted to stable. The spine's framing matches exactly. Source: `docs.flutter.dev/release/archive`.

5. **whisper_ggml genuinely supports iOS on-device Whisper STT, matching the Structural Seed diagram's assumption.** `pub.dev/packages/whisper_ggml` lists supported platforms as Android (API 24+), **iOS (15.6+)**, macOS, Windows, and Linux; it wraps whisper.cpp for fully on-device transcription, with Core ML acceleration on iOS, and documents the iOS deployment-target requirement (`ios/Podfile` + Xcode ≥ 15.6). Latest version 2.8.1 was published 12 days ago with no discontinuation notice — matches the spine's pin and claim exactly. Source: `pub.dev/packages/whisper_ggml`.

## Pins verified (exact match to live pub.dev, 2026-10-26)

flutter_bloc 9.1.1 · go_router 18.1.1 · dio 5.11.1 · hive_ce/hive_ce_flutter 2.22.0 · get_it 9.3.0 · fpdart 1.2.0 · freezed 4.0.3 · mocktail 1.0.5 · fl_chart 1.3.0 · local_auth 3.0.2 · flutter_secure_storage 11.2.0 · flutter_dotenv 6.0.1 · whisper_ggml 2.8.1

## Pin found wrong

json_serializable: spine says ^6.9.5, live latest is 6.15.2 (see Finding 1).
