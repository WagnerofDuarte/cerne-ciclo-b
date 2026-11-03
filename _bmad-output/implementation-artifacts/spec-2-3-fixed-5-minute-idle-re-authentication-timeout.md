---
title: 'Fixed 5-Minute Idle Re-Authentication Timeout'
type: 'feature'
created: '2026-11-03'
status: 'done'
review_loop_iteration: 0
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

## Spec Change Log

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
