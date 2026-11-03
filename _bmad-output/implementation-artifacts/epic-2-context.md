# Epic 2 Context: Biometric Authentication Vault

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Put a device-validated access barrier in front of every screen that shows user data: Face ID or Touch ID with a PIN fallback, cold-start and after a fixed idle timeout, with zero lockout path and zero biometric data or call ever reaching the backend. This closes the one entry point into the app that Epic 1 left as a placeholder, and every later feature's data is only ever reachable once this gate has passed.

## Stories

- Story 2.1: Biometric/PIN App-Access Gate
- Story 2.2: Biometric-Failure Fallback to PIN
- Story 2.3: Fixed 5-Minute Idle Re-Authentication Timeout
- Story 2.4: Biometric Preference Persistence

## Requirements & Constraints

- No screen other than the vault/login screen is reachable before authentication succeeds, on cold start and after the idle timeout.
- Biometric validation is 100% on-device; no biometric data or biometric call ever reaches the backend. `AuthInvalid` can only ever originate from password login — never from a local vault/PIN check, so no vault failure is ever mapped to that Failure subtype.
- A failed biometric attempt always offers a PIN entry path — never a dead end, never a lockout. An OS-level lockout from repeated biometric failures is detected and routed to the app's own PIN fallback, not retried against the OS.
- The idle re-authentication timeout is exactly 5 minutes, fixed and not user-configurable: resuming before 5 minutes prompts nothing; resuming at or after 5 minutes always prompts re-authentication, regardless of any user setting.
- The biometric on/off preference is persisted server-side via `PATCH /account/settings` (surfacing the standard Failure contract on error), not cached only on-device — it is re-fetched from the account on every app load, including after reinstall. Disabling biometrics still leaves PIN as the access method; the vault itself can never be fully turned off.
- Performance floor applies as elsewhere: local UI interactions <100ms; any network call >300ms shows a loading indicator.

## Technical Decisions

- New module `features/vault/` owns this epic. It exposes a `VaultStatus` stream from `features/vault/domain`, mirroring how `features/auth/domain` exposes `SessionStatus` — registered once in DI as a singleton, same pattern, no second instance.
- The single `go_router` top-level redirect (already scaffolded by Epic 1/F000 for `SessionStatus`) is extended, not rebuilt: it composes exactly two gates in fixed order — `VaultStatus` first, then `SessionStatus` — because the vault gates whether anything may be shown at all, before any network/session state is considered. Neither gate ever makes a network call to validate itself.
- Biometrics via `local_auth` (^3.0.2); any local secret (e.g. PIN) via `flutter_secure_storage` (^11.2.0). `NSFaceIDUsageDescription` is required in `Info.plist` for Face ID (not for Touch ID). `local_auth`'s `biometryLockout`/`lockedOut` error has no programmatic reset — catch it and fall through to the app's own PIN path. `stickyAuth` behavior is relevant to resuming an in-flight check when the app returns to foreground.
- The 5-minute idle timeout is app logic (lifecycle observation on backgrounding/resuming), not plugin-provided, and must be implemented as a fixed parameter living inside `features/vault/domain` — explicitly not a shared `core/` constant — and is never re-tuned by any later story.
- The biometric preference toggle itself is persisted through `PATCH /account/settings`, which belongs to `features/account/` (not `features/vault/`) — story 2.4 is the point where a minimal Configurações screen is introduced (replacing Epic 1's placeholder) containing only this toggle; Epic 8 later extends the same screen with profile editing, dashboard, and account actions, so it is never recreated from scratch.
- Standard project-wide rules apply: domain layer imports neither `package:flutter` nor `data/`; repositories return `Either<Failure, T>`; no hardcoded visual values outside `design_tokens.dart`.

## UX & Interaction Patterns

- PIN keypad: numeric 3×4 grid + backspace, progress dots above, rendered entirely in the structural palette (no accent color on digits).
- PIN entry auto-advances 350ms after the 4th digit is entered — no explicit "confirm" tap.
- Biometric-failure copy: "Não foi possível reconhecer — digite seu PIN."
- Screen-reader labels must announce the failure transition (state changes, not just static state).
- The PIN keypad is one of the tightest-fit surfaces for Dynamic Type — digits must not truncate at the largest accessibility text size.
- Tap targets ≥44pt.

## Cross-Story Dependencies

- Depends on Epic 1/F000: the `go_router` redirect skeleton and the `SessionStatus` stream already exist (stories 1.5/1.6). This epic plugs the `VaultStatus` half into that same redirect rather than building a second, competing gate.
- Story 2.4 depends on `features/account/`'s `PATCH /account/settings` and introduces the Configurações screen shell that Epic 8 later extends — that screen must not be rebuilt from scratch in Epic 8.
- Within the epic, 2.1 (the gate itself) must exist before 2.2 (its failure fallback) and 2.3 (its timeout trigger) make sense; 2.4's persisted preference governs whether 2.1's gate is biometric-first or PIN-only, so it reads that preference at startup regardless of build order.
