---
title: 'Biometric-Failure Fallback to PIN'
type: 'feature'
created: '2026-11-03'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '815e7cc4fb8633554f0483eb0c31ad81f35d1f97'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Spec-2-1's `/vault` screen offers only a "Tentar novamente" biometric-retry button — no PIN entry exists, so a biometric decline/cancel/OS-lockout has no real fallback.

**Approach:** Replace the retry button with a real PIN keypad (Tela 0.1b/0.1c): any biometric failure (decline/cancel/`LocalAuthExceptionCode` lockout) falls through to the keypad+error copy; a new "Usar PIN" link reaches it directly. No PIN-creation screen exists anywhere in `docs/input/` (decide-and-proceed): first entry when no PIN is stored becomes the stored PIN; later entries verify against it.

## Boundaries & Constraints

**Always:** Every `authenticate()` failure (any code/lockout/`false`) shows the PIN keypad — never a second OS-retry affordance (AC2). `submitPin` success emits `VaultStatus.unlocked`, same as biometric; no new enum value. PIN compared as plain strings in `flutter_secure_storage` (Keychain-encrypted already; no new hash dependency — not pinned). PIN has no attempt cap — always retryable. Keypad: structural palette only, 4 dots, 350ms auto-advance, ≥44pt targets, no Dynamic-Type truncation (UX-DR14/21/22).

**Ask First:** None.

**Never:** No PIN-confirmation re-entry. No storage outside `flutter_secure_storage`. Don't reintroduce "Tentar novamente". Out of scope: 2.3 idle timeout, 2.4 preference persistence.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Biometric fails (decline/cancel/any `LocalAuthException`, incl. lockout) | `authenticate()` returns `Left` | Screen shows PIN keypad + "Não foi possível reconhecer — digite seu PIN"; screen-reader announces the transition | N/A |
| User taps "Usar PIN" from the biometric view | tap, no prior failure | PIN keypad shown, no error band | N/A |
| `submitPin`, no PIN stored yet | 4 digits entered | Stored as the new PIN, `unlocked`, `Right(unit)` | N/A |
| `submitPin`, stored PIN matches | 4 digits entered | `unlocked`, `Right(unit)` | N/A |
| `submitPin`, stored PIN mismatch | 4 digits entered | Stays `locked`, keypad clears for another attempt — never a dead end | `Left(Failure.malformedResponse(...))` |

</frozen-after-approval>

## Code Map

- `lib/features/vault/domain/repositories/vault_repository.dart` — add `Future<Either<Failure, Unit>> submitPin(String pin)`.
- `lib/features/vault/data/repositories/vault_repository_impl.dart:25-29,96` — add `FlutterSecureStorage` ctor param (mirrors `LocalAuthentication`); implement `submitPin` (key `'vault_pin'`, set-on-first-use/compare). Existing `authenticate()` catches already cover lockout generically — resolves spec-2-1's deferred finding since every failure now routes to the same PIN path, no code-specific branch needed.
- `lib/features/vault/vault_injection.dart:11-24` — pass `sl<FlutterSecureStorage>()` (already registered `injection_container.dart:31-33`) into `VaultRepositoryImpl`.
- `lib/features/auth/data/datasources/secure_storage_access_token_provider.dart` — `_storage.read(key:)`/`.write(key:,value:)` pattern to mirror.
- `lib/core/design_tokens.dart` — add PIN-keypad-only size constants (prototype-extract.md §3/§6 names the component, not its px).
- `lib/features/vault/presentation/widgets/pin_keypad.dart` (new) — 3×4 grid + backspace + 4 dots; owns its digit buffer; clears and calls `onSubmit(pin)` 350ms after the 4th digit.
- `lib/features/vault/presentation/screens/vault_lock_screen.dart` — drop the "Tentar novamente" `AppButton`; add "Usar PIN" ghost link (`AppButtonVariant.textGhost`, mirrors `auth_screen.dart`'s toggle link); add PIN-mode view (`PinKeypad` + conditional error band); wire `submitPin`; extend the existing `SemanticsService.sendAnnouncement` (`:68-74`) to PIN mismatch too.
- `test/features/vault/data/repositories/vault_repository_impl_test.dart` — add `submitPin` cases, mocked `FlutterSecureStorage`.
- `test/features/vault/presentation/widgets/pin_keypad_test.dart` (new) — entry/backspace/auto-advance/no-overflow at largest `TextScaler`.
- `test/features/vault/presentation/screens/vault_lock_screen_test.dart` — swap obsolete retry-button cases for: fail→keypad+error; "Usar PIN" reachable pre-failure; correct/incorrect PIN.
- `test/core/navigation/app_router_test.dart:59-91`, `test/main_test.dart:64-93` — add `submitPin` override to both `_FakeVaultRepository`s.

## Tasks & Acceptance

**Execution:**
- [x] `vault_repository.dart` -- add `submitPin` -- RNF09 `Either<Failure, Unit>`.
- [x] `vault_repository_impl.dart` -- implement `submitPin` via `FlutterSecureStorage` -- per I/O matrix.
- [x] `vault_injection.dart` -- inject `sl<FlutterSecureStorage>()` -- reuses existing singleton.
- [x] `design_tokens.dart` -- add PIN keypad tokens -- RNF08.
- [x] `pin_keypad.dart` -- create keypad widget -- UX-DR14.
- [x] `vault_lock_screen.dart` -- swap retry button for PIN-mode view + "Usar PIN" -- AC1/AC2.
- [x] `vault_repository_impl_test.dart` -- add `submitPin` coverage.
- [x] `pin_keypad_test.dart` -- create; cover grid/backspace/auto-advance/Dynamic-Type.
- [x] `vault_lock_screen_test.dart` -- replace retry-button cases with PIN-flow cases.
- [x] `app_router_test.dart`, `main_test.dart` -- add `submitPin` override to both fakes.

**Acceptance Criteria:**
- Given Face ID/Touch ID fails to recognize me, when the failure is reported, then "Não foi possível reconhecer — digite seu PIN" appears with the PIN keypad always reachable — never a dead end.
- Given repeated biometric failures trigger an OS-level lockout, when that lockout is detected, then the app shows the PIN keypad rather than offering any biometric-retry affordance.
- Given the PIN keypad, when I enter the 4th digit, then the app auto-advances 350ms later with no explicit confirm tap, the transition is announced to screen readers, and the digits stay legible at the largest Dynamic Type size.

### Review Findings

- [x] [Review][Decision] `VaultRepository.submitPin(String pin)` has no format/length validation at the domain/data boundary — only `PinKeypad` enforces exactly 4 digits; the repository accepts any string, including empty or non-numeric, and the first-ever call becomes the permanent stored PIN. The spec's own I/O matrix never defines behavior for non-4-digit input. [lib/features/vault/data/repositories/vault_repository_impl.dart:131] [lib/features/vault/domain/repositories/vault_repository.dart:48] — resolved: keep as-is. The sole real caller (`PinKeypad`) already enforces 4 digits; adding domain-level validation now would widen the contract beyond this story's frozen scope with no spec-defined error copy to back it (AGENTS.md: decide-and-proceed on a silent point, decided toward minimal scope).
- [x] [Review][Patch] `PinKeypad` accepts and silently drops a second 4-digit entry while a prior `submitPin()` call is still in flight — the `_submittingPin` guard returns early with zero feedback, and stale error text stays on screen unchanged through the new attempt with no visual sign anything is processing. [lib/features/vault/presentation/screens/vault_lock_screen.dart:109] — fixed: `PinKeypad` now takes an `enabled` flag; `VaultLockScreen` passes `enabled: !_submittingPin`, so no tap is even accepted (let alone dropped) while a submission is in flight.
- [x] [Review][Patch] If `VaultRepository.submitPin()` never resolves (e.g. a secure-storage channel hang), `_submittingPin` is never reset — the `finally` block never runs because execution is suspended at the `await` — permanently blocking every future PIN attempt, contradicting the spec's own "keypad clears for another attempt — never a dead end" boundary. [lib/features/vault/presentation/screens/vault_lock_screen.dart:109] — fixed: `submitPin(pin).timeout(_submitPinTimeout)` (10s) bounds the wait; a `TimeoutException` shows a retryable error and the `finally` always runs.
- [x] [Review][Patch] The widget test named "an OS-lockout failure (any authenticate() Left) routes to the same PIN keypad as a plain decline..." never actually configures a `LocalAuthExceptionCode.lockedOut`/`biometryLockout` — it reuses the identical generic fake-decline setup as the preceding plain-decline test, so its name overclaims coverage that doesn't exist. [test/features/vault/presentation/screens/vault_lock_screen_test.dart:188] — fixed: the fake now exposes `authenticateFailureMessage` so the test configures a distinct lockout-flavored failure; a matching real `LocalAuthExceptionCode.biometricLockout` case was also added to `vault_repository_impl_test.dart`.
- [x] [Review][Patch] No test verifies the actual screen-reader announcement content for the biometric-failure/PIN-mismatch transitions — nothing in the repo mocks `SystemChannels.accessibility`, so `_announce()` could be deleted, given the wrong message, or have its guard inverted, and every existing test would still pass green, silently regressing AC3's "transition is announced to screen readers" requirement. [lib/features/vault/presentation/screens/vault_lock_screen.dart:134] — fixed: a new "AC3 — screen-reader announcements are actually observed" group mocks `SystemChannels.accessibility` directly and asserts the real announcement content on both transitions, and silence on the "Usar PIN" pre-failure tap.
- [x] [Review][Patch] `deferred-work.md`'s "lockout-vs-other-failure distinction" entry (filed against spec-2-1) is not marked resolved, even though this spec's own Code Map claims the diff "resolves spec-2-1's deferred finding since every failure now routes to the same PIN path." [_bmad-output/implementation-artifacts/deferred-work.md:85] — fixed: added a `resolved_by` note to that entry.
- [x] [Review][Patch] `test-summary.md`'s newly-added "Story 2.1" section documents `vault_lock_screen_test.dart`'s "Tentar novamente" retry-loop tests as current coverage, but this same diff deletes those exact tests and replaces them with PIN-keypad tests; there is no corresponding "Story 2.2" section documenting the tests actually added. [_bmad-output/implementation-artifacts/tests/test-summary.md:272] — fixed: added a "Superseded by Story 2.2" note plus a full "Story 2.2" section.
- [x] [Review][Patch] Tapping "Usar PIN" switches to the PIN keypad but never cancels or acknowledges the still-pending native `authenticate()` call; `local_auth` exposes no cancel API, so the OS Face ID/Touch ID sheet may still be visible underneath the app's own PIN keypad — an undocumented known limitation. [lib/features/vault/presentation/screens/vault_lock_screen.dart:102] — fixed: documented as a new entry in `deferred-work.md` (no code-level fix available — `local_auth` has no cancel API).
- [x] [Review][Patch] `spec-2-1-biometric-pin-app-access-gate.md`'s "Review Findings" section marks three items as fixed during story 2.1's own review, but `git show 815e7cc` (2.1's closing commit) shows none of the three existed there — the generic `catch`, `test/main_test.dart`'s `dispose:` callback, and the `SemanticsService.sendAnnouncement` pairing are all introduced for the first time in this diff (story 2.2's), misattributing the audit trail about what shipped when. [_bmad-output/implementation-artifacts/spec-2-1-biometric-pin-app-access-gate.md:72] — fixed: added a correction note to that section attributing the fixes to story 2.2.

## Design Notes

No PIN-creation screen exists anywhere ("PIN inicial"/"PIN após falha" are both entry screens) — set-on-first-use is this spec's own resolution. `flutter_secure_storage` already encrypts at rest and is pinned; `package:crypto` is not, so the PIN is compared as the plain stored string rather than adding a dependency.

## Verification

**Commands:**
- `fvm flutter analyze` -- expected: zero issues.
- `fvm flutter test` -- expected: all pass, including new/updated vault and keypad tests.

**Manual checks (if no CLI):**
- No device/simulator exists yet (AGENTS.md) — the real OS biometric-lockout trigger is unverifiable until one does; pre-existing gap, not introduced here.

## Suggested Review Order

**Domain contract and fallback semantics**

- The new fallback entry point: `Either<Failure, Unit>`, no attempt cap, same unlock path as `authenticate()`.
  [`vault_repository.dart:48`](../../lib/features/vault/domain/repositories/vault_repository.dart#L48)

- `biometricOnly: true` stays unchanged from spec-2-1 — PIN is Cerne's own screen, never the OS's.
  [`vault_repository.dart:28`](../../lib/features/vault/domain/repositories/vault_repository.dart#L28)

**`submitPin` implementation — set-on-first-use**

- Entry point: read-check-write against `flutter_secure_storage`, no PIN-creation screen exists anywhere so first entry becomes the PIN.
  [`vault_repository_impl.dart:131`](../../lib/features/vault/data/repositories/vault_repository_impl.dart#L131)

- Constructor now also takes `FlutterSecureStorage`, mirroring `LocalAuthentication`'s injection.
  [`vault_repository_impl.dart:40`](../../lib/features/vault/data/repositories/vault_repository_impl.dart#L40)

- DI reuses the existing singleton (no second secure-storage instance).
  [`vault_injection.dart:29`](../../lib/features/vault/vault_injection.dart#L29)

**Lock screen — biometric-failure fallback and re-entrancy**

- `_submitPin`'s re-entrancy guard — added in review: `PinKeypad` accepts new taps before the prior call resolves.
  [`vault_lock_screen.dart:109`](../../lib/features/vault/presentation/screens/vault_lock_screen.dart#L109)

- Every biometric failure routes here instead of a second OS-retry affordance (AC2) — no code-specific lockout branch needed.
  [`vault_lock_screen.dart:23`](../../lib/features/vault/presentation/screens/vault_lock_screen.dart#L23)

- Live-region wrapper removed in review — it was re-announcing on every digit tap, not just real transitions.
  [`vault_lock_screen.dart:152`](../../lib/features/vault/presentation/screens/vault_lock_screen.dart#L152)

**`PinKeypad` — new component**

- `_onBackspaceTap` cancels the pending auto-advance timer unconditionally — added in review, fixes a stale-submit bug.
  [`pin_keypad.dart:71`](../../lib/features/vault/presentation/widgets/pin_keypad.dart#L71)

- `PinKeypad` itself: owns its digit buffer, 350ms auto-advance, no explicit confirm tap (UX-DR14).
  [`pin_keypad.dart:26`](../../lib/features/vault/presentation/widgets/pin_keypad.dart#L26)

- Grid layout + structural-palette-only buttons, each ≥44pt (UX-DR23).
  [`pin_keypad.dart:134`](../../lib/features/vault/presentation/widgets/pin_keypad.dart#L134)

- Digit glyphs `FittedBox`-wrapped so Dynamic Type never truncates (UX-DR22).
  [`pin_keypad.dart:206`](../../lib/features/vault/presentation/widgets/pin_keypad.dart#L206)

- New size tokens for the keypad — prototype names the component but gives no px values.
  [`design_tokens.dart:301`](../../lib/core/design_tokens.dart#L301)

**Tests (peripherals)**

- Backspace-during-auto-advance regression — proves the review-round fix actually prevents a stale submit.
  [`pin_keypad_test.dart`](../../test/features/vault/presentation/widgets/pin_keypad_test.dart)

- Re-entrancy guard proof — a fast second PIN entry never reaches the repository a second time.
  [`vault_lock_screen_test.dart:41`](../../test/features/vault/presentation/screens/vault_lock_screen_test.dart#L41)

- PIN-mismatch error copy assertion — added in review after the original test omitted it.
  [`vault_lock_screen_test.dart:282`](../../test/features/vault/presentation/screens/vault_lock_screen_test.dart#L282)

- `authenticate()`'s generic (non-`LocalAuthException`) catch branch, now exercised.
  [`vault_repository_impl_test.dart:206`](../../test/features/vault/data/repositories/vault_repository_impl_test.dart#L206)

- `submitPin`'s own I/O matrix: no-PIN-yet, match, mismatch, storage-exception fail-closed.
  [`vault_repository_impl_test.dart:298`](../../test/features/vault/data/repositories/vault_repository_impl_test.dart#L298)

- Both pre-existing `_FakeVaultRepository`s updated with a `submitPin` override for the interface change.
  [`app_router_test.dart`](../../test/core/navigation/app_router_test.dart)
