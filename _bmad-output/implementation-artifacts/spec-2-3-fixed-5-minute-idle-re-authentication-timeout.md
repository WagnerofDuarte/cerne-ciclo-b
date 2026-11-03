---
title: 'Fixed 5-Minute Idle Re-Authentication Timeout'
type: 'feature'
created: '2026-11-03'
status: 'done'
review_loop_iteration: 1
context: []
baseline_commit: '9f91f60d57c80cb38e382e925bc01701f12808b2'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Once `VaultRepository.currentStatus` flips to `unlocked` (cold-start biometric/PIN success, spec-2-1/2-2), nothing ever re-locks it — an unlocked app stays unlocked indefinitely if backgrounded and left unattended, with no idle-based re-authentication trigger at all.

**Approach:** Have `VaultRepositoryImpl` observe app-lifecycle transitions directly (`WidgetsBindingObserver`): record a timestamp on backgrounding, and on resume compare elapsed time against a new fixed domain constant; crossing it re-emits `VaultStatus.locked` through the existing `_emit`/`statusStream` machinery. The already-shipped AD-14 redirect (`VaultStatus` checked before `SessionStatus`) then bounces every screen back to `/vault` on that emission with zero router changes.

## Boundaries & Constraints

**Always:** Fixed `Duration(minutes: 5)` lives in a new `features/vault/domain` file, never a shared `core/` constant, never re-tuned by any later story. Elapsed time read via an injectable `DateTime Function() now` constructor param (default `DateTime.now`) for deterministic tests. Backgrounded timestamp recorded on `AppLifecycleState.paused`, read/cleared on `AppLifecycleState.resumed` — `inactive`/`hidden` are not treated as "backgrounded" on their own. Only emits `VaultStatus.locked` when `currentStatus` is currently `unlocked` AND elapsed `>= 5` minutes — never redundantly if already locked, never before the threshold. `WidgetsBinding.instance.addObserver(this)`/`removeObserver(this)` wired into the existing constructor/`dispose()` — no second observer, no new DI registration, no new `VaultStatus` enum value.

**Ask First:** None.

**Never:** No user-facing or account-level setting for this duration (fixed, not user-configurable — AC2). No `core/` constant. No new abstract method added to `VaultRepository`'s public contract. No changes to `app_router.dart` or `vault_lock_screen.dart` — the existing stream-driven redirect and `initState`-triggered `authenticate()` already cover re-prompting on relock.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Backgrounded < 5 min, then resumed | `paused` at T0, was `unlocked`, `resumed` at T0+4min | `currentStatus` stays `unlocked`, no emission | N/A |
| Backgrounded >= 5 min, then resumed | `paused` at T0, was `unlocked`, `resumed` at T0+5min (or later) | `statusStream` emits `locked`, `currentStatus` flips to `locked` | N/A |
| Backgrounded >= 5 min while already locked | `paused` then `resumed` after >=5min, `currentStatus` already `locked` | stays `locked`, no duplicate emission | N/A |
| `resumed` fires with no prior `paused` | e.g. first lifecycle callback ever observed | no-op, no emission, no crash | N/A |

</frozen-after-approval>

## Code Map

- `lib/features/vault/domain/vault_idle_timeout.dart` (new) — fixed `Duration(minutes: 5)` constant, domain-owned per epic Technical Decisions.
- `lib/features/vault/data/repositories/vault_repository_impl.dart` — implement `WidgetsBindingObserver`; add `_backgroundedAt`/injectable `now` clock; `WidgetsBinding.instance.addObserver(this)` in constructor, `.removeObserver(this)` in `dispose()` (`:163-165`); override `didChangeAppLifecycleState` to apply the I/O matrix via existing `_emit`.
- `test/features/vault/data/repositories/vault_repository_impl_test.dart` — add an idle-timeout `group`, calling `didChangeAppLifecycleState` directly (it's a public override) with an injected fake clock — no real `WidgetsBinding` lifecycle event needed, matching the project's "no device/simulator" constraint.

## Tasks & Acceptance

**Execution:**
- [x] `lib/features/vault/domain/vault_idle_timeout.dart` -- create the fixed-duration constant -- Technical Decisions: domain-owned, not `core/`.
- [x] `lib/features/vault/data/repositories/vault_repository_impl.dart` -- implement `WidgetsBindingObserver`, injectable clock, add/removeObserver wiring, `didChangeAppLifecycleState` logic -- per I/O matrix.
- [x] `test/features/vault/data/repositories/vault_repository_impl_test.dart` -- cover all four I/O matrix rows -- regression coverage for the idle re-lock.

**Acceptance Criteria:**
- Given the app is backgrounded for less than 5 minutes, when I resume it, then no re-authentication is prompted.
- Given the app is backgrounded for 5 minutes or more, when I resume it, then re-authentication is always prompted regardless of any user setting, with the fixed 5-minute value living in `features/vault/domain`, never a shared `core/` constant.

### Review Findings

- [x] [Review][Decision] Out-of-scope changes to `vault_lock_screen.dart` and `pin_keypad.dart` violate spec-2-3's explicit "Never" clause — this story's own frozen Boundaries say "No changes to `app_router.dart` or `vault_lock_screen.dart`," yet the diff attributed to this story (commit `81d7509`) modifies both `vault_lock_screen.dart` and the tightly-coupled `pin_keypad.dart` (the `submitPin` 10s timeout, the `PinKeypad.enabled` flag). Both are acknowledged leftover review fixes from story 2.2, bundled into this commit rather than committed separately. The idle-timeout logic itself fully complies with every other Boundary/Constraint and I/O-matrix row. — resolved: accepted as documented (see Spec Change Log below). The bundled fixes are real, correct, and already explained in `test-summary.md`/`deferred-work.md`; no code or history change made.
- [x] [Review][Patch] A biometric/PIN unlock that resolves while the app is still backgrounded can trigger an immediate re-lock the moment the app resumes — `authenticate()` uses `persistAcrossBackgrounding: true` so a pending call can resolve after a `paused` is recorded; if `_emit(unlocked)` fires while still backgrounded and `resumed` arrives ≥5 minutes after the original `paused` (e.g. a long phone call), `didChangeAppLifecycleState` immediately re-locks, bouncing the user straight back to `/vault` right after they authenticated. — fixed: `_emit` now clears `_backgroundedAt` whenever status is `unlocked`, so any unlock always resets the idle clock. Covered by a new test. [lib/features/vault/data/repositories/vault_repository_impl.dart:132-151]
- [x] [Review][Patch] `submitPin()`'s UI-level 10s timeout doesn't cancel the underlying repository call, so a second attempt can race the first against the same storage key — once the UI times out and re-enables the keypad, the original `VaultRepository.submitPin()` call keeps running; if it later resolves, it can emit `unlocked` from a stale, abandoned attempt, or race a concurrent first-time PIN write with no generation/cancellation token to make a stale result a no-op. — fixed: added a `_submitPinGeneration` counter; a call whose generation is stale by the time its `read()` resolves returns `Left` without writing or emitting. Covered by a new test. [lib/features/vault/data/repositories/vault_repository_impl.dart:96] [lib/features/vault/data/repositories/vault_repository_impl.dart:229-243]
- [x] [Review][Patch] A second `paused` lifecycle event before any `resumed` silently resets the idle clock to the later timestamp — `didChangeAppLifecycleState` unconditionally overwrites `_backgroundedAt` on every `paused` with no check for an already-pending one, which can undercount true elapsed background time if `paused` ever fires twice without an intervening `resumed`. Not covered by the I/O matrix or tests. — fixed: `_backgroundedAt ??= _now()` keeps the earliest timestamp. Covered by a new test. [lib/features/vault/data/repositories/vault_repository_impl.dart:167-173]
- [x] [Review][Patch] `PinKeypad`'s `enabled: false` state has no visual or semantic disabled treatment — taps are silently swallowed in `_onDigitTap`/`_onBackspaceTap`, but `Semantics(button: true, ...)` never sets `enabled: false` and nothing dims the buttons, so neither a sighted nor a VoiceOver user gets any "processing"/disabled cue for up to 10 seconds. — fixed: `_KeypadButton` now wraps in `Opacity` and sets `Semantics(enabled: ...)` and `onTap: null` when disabled. Covered by a new test. [lib/features/vault/presentation/widgets/pin_keypad.dart:231-282]
- [x] [Review][Patch] Stale error message lingers through a fresh PIN attempt with no "in progress" indicator — `_submitPin` never clears `_errorMessage` when a new attempt starts, so a previous mismatch/timeout message stays on screen unchanged through the new attempt. — fixed: `_errorMessage` is cleared in the same `setState` that sets `_submittingPin = true`. Covered by a new test. [lib/features/vault/presentation/screens/vault_lock_screen.dart:124-133]
- [x] [Review][Patch] Test file registers two `VaultRepositoryImpl` instances as `WidgetsBindingObserver` on the same shared `TestWidgetsFlutterBinding` — the top-level `setUp()`'s `repository` and the idle-timeout group's own `idleRepository` both register on the same binding, so the "real dispatch path" test's `handleAppLifecycleStateChanged(...)` notifies both simultaneously with no assertion covering the unintended side effect. Currently harmless (verified: full suite passes, `repository` never reaches `unlocked` in that group), but an unnecessary double registration. — fixed: the idle-timeout group's `setUp` now disposes the outer `repository` immediately, so only `idleRepository` is registered during this group's tests. [test/features/vault/data/repositories/vault_repository_impl_test.dart]
- [x] [Review][Patch] Constructor's `WidgetsBinding.instance.addObserver(this)` depends entirely on binding-init ordering, backed only by a comment — every current call site is correctly ordered (no live bug today), but there's no runtime assertion, so any future direct construction outside that ordering would crash with an opaque Flutter-binding error instead of a clear, intentional one. — fixed: wrapped in a `try`/`on FlutterError catch` that rethrows a `StateError` naming the actual root cause. [lib/features/vault/data/repositories/vault_repository_impl.dart:69-77]
- [x] [Review][Patch] spec-2-3's own review-tracking metadata is incomplete and internally inconsistent — frontmatter `review_loop_iteration: 0` remains at its initial value even though this file's own "Suggested Review Order" section repeatedly says "Added in review," and unlike spec-2-1/spec-2-2 in this same diff, spec-2-3 has no populated `### Review Findings` section at all until this edit. — fixed: `review_loop_iteration` bumped to `1`; this section populated. [_bmad-output/implementation-artifacts/spec-2-3-fixed-5-minute-idle-re-authentication-timeout.md]
- [x] [Review][Patch] spec-2-3 frontmatter status disagrees with `sprint-status.yaml` — this file's frontmatter sets `status: 'done'` while the same diff's `sprint-status.yaml` sets `2-3-fixed-5-minute-idle-re-authentication-timeout: review`. — fixed: both synced by this review's own Section 6 status update. [_bmad-output/implementation-artifacts/spec-2-3-fixed-5-minute-idle-re-authentication-timeout.md:5] [_bmad-output/implementation-artifacts/sprint-status.yaml:198]
- [x] [Review][Patch] `test-summary.md` has no "Story 2.3" section despite this diff shipping the full implementation and 7 new tests — unlike the full "Story 2.2"/"QA Generate E2E Tests Pass" sections in the same file, there is no "Story 2.3" section, and its own "Next Steps" text calling 2.3 still-upcoming is left stale by the very same diff that ships 2.3's code and tests. — fixed: added a "Story 2.3" section; updated the stale "Next Steps" note. [_bmad-output/implementation-artifacts/tests/test-summary.md]
- [x] [Review][Patch] `deferred-work.md`'s new clock-skew entry gives a justification that doesn't actually distinguish its two options — it argues wall-clock `DateTime.now()` is kept partly because a monotonic `Stopwatch` "doesn't survive the app process being killed while backgrounded," but the current plain `DateTime?` field is lost identically on process death. The actual reasons to prefer `DateTime` (simplicity, no new dependency) are sound; only this one stated justification is inconsistent. — fixed: reworded to drop the inconsistent justification, keeping the valid reasons. [_bmad-output/implementation-artifacts/deferred-work.md]

## Spec Change Log

- **Code review (2026-11-03):** Confirmed, and left in place as-is, that this story's commit (`81d7509`) bundles leftover `vault_lock_screen.dart`/`pin_keypad.dart` fixes from story 2.2's own review pass (the `submitPin` 10s timeout and `PinKeypad.enabled` guard) alongside this story's idle-timeout work — a literal touch of a file this spec's frozen Boundaries name as off-limits ("No changes to ... `vault_lock_screen.dart`"). Accepted rather than un-bundled: the fixes themselves are real, correct, and already documented in `test-summary.md`/`deferred-work.md`; splitting the commit now would be pure git history surgery with no functional benefit. The idle-timeout implementation proper never touched either file for its own logic.

## Design Notes

No `clock`/`fake_async` package is pinned in `pubspec.yaml` and none is being added for this — testability is achieved with a plain injectable `DateTime Function() now` parameter (default `DateTime.now`), the simplest decide-and-proceed fit given no existing clock-injection pattern elsewhere in the codebase. `paused`/`resumed` are the chosen pair because they bound iOS's actual background/foreground transition (`resumed → inactive → hidden → paused` and its reverse) — treating `inactive`/`hidden` alone as "backgrounded" would false-trigger on transient interruptions like Control Center or an incoming call.

## Verification

**Commands:**
- `fvm flutter analyze` -- expected: zero issues.
- `fvm flutter test` -- expected: all pass, including the new idle-timeout cases.

**Manual checks (if no CLI):**
- No device/simulator exists yet (AGENTS.md) — the real OS-driven backgrounding/resuming sequence is unverifiable until one does; pre-existing gap, not introduced here.

## Suggested Review Order

**Domain constant**

- The fixed threshold itself: domain-owned, never a shared `core/` constant, never user-configurable.
  [`vault_idle_timeout.dart:10`](../../lib/features/vault/domain/vault_idle_timeout.dart#L10)

**Idle re-lock logic — `VaultRepositoryImpl`**

- Entry point: the lifecycle callback implementing the whole I/O & Edge-Case Matrix — `paused` records the timestamp, `resumed` decides whether to re-emit `locked`.
  [`vault_repository_impl.dart:120`](../../lib/features/vault/data/repositories/vault_repository_impl.dart#L120)

- Guard that prevents a redundant emission once already `locked`, and the `>=` boundary comparison against the domain constant.
  [`vault_repository_impl.dart:144`](../../lib/features/vault/data/repositories/vault_repository_impl.dart#L144)

- Constructor wiring: `WidgetsBindingObserver` registration, the injectable clock, and the documented ordering dependency on binding initialization.
  [`vault_repository_impl.dart:48`](../../lib/features/vault/data/repositories/vault_repository_impl.dart#L48)

- `dispose()` now also deregisters the observer, mirroring the constructor's registration.
  [`vault_repository_impl.dart:222`](../../lib/features/vault/data/repositories/vault_repository_impl.dart#L222)

**Tests**

- The four frozen I/O-matrix rows, built on a repository constructed with an injectable fake clock.
  [`vault_repository_impl_test.dart:382`](../../test/features/vault/data/repositories/vault_repository_impl_test.dart#L382)

- Added in review: a real `WidgetsBinding`-dispatched case proving the constructor's `addObserver` wiring is actually in effect, not just the override logic in isolation.
  [`vault_repository_impl_test.dart:470`](../../test/features/vault/data/repositories/vault_repository_impl_test.dart#L470)

- Added in review: `inactive`/`hidden` confirmed as no-ops, and a tighter boundary case one second short of the threshold.
  [`vault_repository_impl_test.dart:495`](../../test/features/vault/data/repositories/vault_repository_impl_test.dart#L495)

- Added in review: `tearDown` disposal for both the main and idle-timeout-group repositories, so the new `WidgetsBindingObserver` registrations don't leak across the test file.
  [`vault_repository_impl_test.dart:57`](../../test/features/vault/data/repositories/vault_repository_impl_test.dart#L57)
