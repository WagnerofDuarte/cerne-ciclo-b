- source_spec: `_bmad-output/implementation-artifacts/spec-1-1-project-scaffold-stack-integration-core-infrastructure.md`
  summary: No portrait-only orientation lock is enforced anywhere in the app shell (`ios/Runner/Info.plist` still lists landscape orientations alongside portrait).
  evidence: `docs/input/requirements.md` fixes the app to a single 390x844 portrait-only frame with no landscape path, but Story 1.1 is core infrastructure only (no screens/app-shell UI) and the architecture spine doesn't assign this lock to any specific story. Likely belongs to Story 1.6 (Base Navigation Shell with Feature Placeholders), the first story that builds real app-shell UI — should be picked up there rather than silently falling through the cracks.

- source_spec: `_bmad-output/implementation-artifacts/spec-1-2-design-token-system-core-component-library.md`
  summary: `lib/core/widgets/avatar.dart`'s `Avatar` renders raw initials text with no `Semantics` wrapper, so a screen reader announces e.g. "W D" instead of something like "Avatar, Wagner Duarte".
  evidence: Accessibility semantics were never required by Story 1.2's spec (no boundary, acceptance criterion, or epic-context requirement mentions it) and the prototype gives no guidance either, so adding it now would be scope creep beyond the frozen intent. Worth a deliberate pass across all shared widgets (button/text-field/avatar) once an accessibility requirement exists, rather than bolting it onto one widget ad hoc.

## Deferred from: code review of story-1-2-design-token-system-core-component-library (2026-10-27)

- `AppButton` has no loading/busy state, even though most of its real call sites (login submit, insertion-modal "Salvar", export actions) are async network calls. Not required by Story 1.2's boundaries (§6's button component table lists only normal/pressed/disabled variations) — pick up when the first async-submit screen (Story 1.3) needs it, rather than letting each feature improvise its own busy treatment.
- `AppTextField` exposes no `enabled`/`readOnly`, `onSubmitted`, `autofocus`, `textCapitalization`, or `inputFormatters` — all plausible needs for the upcoming login/signup and inline-name-edit screens. Not required by Story 1.2's acceptance criteria; let Story 1.3 (its first real consumer) request exactly what it needs instead of speculatively widening the shared primitive now.
- `lib/core/design_tokens.dart` now imports `package:flutter/widgets.dart` (needed for `Color`/`TextStyle`/`EdgeInsets`/`BoxShadow`), but nothing in the repo (lint rule or architecture test) would catch a future `domain/` layer importing it for a color/style constant, which would transitively violate RNF06. No domain code exists yet to violate this, so it's not a bug today — worth a lint rule or architecture test once the first feature's `domain/` layer is scaffolded.

## Deferred from: code review of story-1-3-account-creation-and-login (2026-10-27)

- source_spec: `_bmad-output/implementation-artifacts/spec-1-3-account-creation-and-login.md`
  summary: `Failure.message` is rendered verbatim as the inline form error on `AuthScreen`, but `ApiClient`'s own fallback messages (`'Empty response body'`, `'Malformed response'`, raw `DioException.message`, `'Unknown error'`) are hardcoded English technical strings, so a user can see raw English on an otherwise all-Portuguese screen.
  evidence: Root cause is in `lib/core/network/api_client.dart` (Story 1.1), not this story's diff — `AuthScreen` is simply the first screen to render `Failure.message` directly to an end user, surfacing a pre-existing gap. No `Failure`→localized-copy mapping layer exists anywhere in the project; worth addressing once more than one screen needs to render failures, rather than inventing a one-off mapping for auth alone.

- source_spec: `_bmad-output/implementation-artifacts/spec-1-3-account-creation-and-login.md`
  summary: Neither `AppTextField` on Tela 0.1a reacts to the keyboard's "done"/"next" action to submit the form, and both fields stay fully editable while a signup/login request is in flight (the submitted values can be edited before the response returns).
  evidence: Fixing either requires extending `AppTextField` with `onSubmitted` and `enabled`/`readOnly` params, which this story's frozen spec explicitly rules out ("No new params on `AppButton`/`AppTextField`"). Story 1.2 already flagged both gaps and deferred them to "whichever story needs them first" — Story 1.3 needs them but deliberately didn't request the widening to stay in scope; revisit when a story is willing to extend the shared text field.

- source_spec: `_bmad-output/implementation-artifacts/spec-1-3-account-creation-and-login.md`
  summary: Neither the e-mail nor senha `AppTextField` on Tela 0.1a sets `autofillHints` (`AutofillHints.email`/`.password`), so iOS's Keychain/password-manager autofill won't surface suggestions on this screen.
  evidence: Not required by any requirement or acceptance criterion; a minor iOS-platform completeness gap worth picking up alongside the `AppTextField` widening above rather than as a one-off change now.

## Deferred from: code review of spec-1-2-design-token-system-core-component-library, round 2 (2026-10-27)

- source_spec: `_bmad-output/implementation-artifacts/spec-1-2-design-token-system-core-component-library.md`
  summary: The new `test/core/widgets/component_library_interaction_test.dart` harness sets `textInputAction: TextInputAction.done` on the senha field, but `AppTextField` exposes no `onSubmitted` param to wire a handler to it.
  evidence: Same pre-existing gap already tracked under "Deferred from: code review of story-1-3-account-creation-and-login" above (`AppTextField` widening deliberately deferred to whichever story is willing to extend the shared primitive) — not a new gap, just re-surfaced by this new test harness.

## Deferred from: code review of story-1-4-silent-session-refresh-persistence (2026-10-27)

- source_spec: `_bmad-output/implementation-artifacts/spec-1-4-silent-session-refresh-persistence.md`
  summary: `AuthCubit.toggleMode()`'s uncommitted fix (switched from a raw `AuthState(...)` constructor to `state.copyWith(...)` so an in-flight `status` survives a mode toggle) has no test that can actually observe the regression it fixes — every existing `toggleMode()` call site in the test suite toggles while `status` is already the default idle value.
  evidence: Root cause is in `lib/features/auth/presentation/cubit/auth_cubit.dart`, pre-existing uncommitted work carried over from story 1.3's review loop, not touched by story 1.4's diff — surfaced incidentally by story 1.4's review because the dirty working tree put it in the reviewed diff. Needs a test that calls `submit()` to put `status` in a non-idle state, then `toggleMode()`, then asserts `status` is unchanged.

- source_spec: `_bmad-output/implementation-artifacts/spec-1-4-silent-session-refresh-persistence.md`
  summary: `AuthCubit.passwordChanged()`'s uncommitted fix (now also clears `emailError`, matching `emailChanged`'s existing symmetric clear) has no test asserting it actually clears a pre-existing e-mail error.
  evidence: Same pre-existing-uncommitted-work category as the `toggleMode` entry above (`lib/features/auth/presentation/cubit/auth_cubit.dart`, carried over from story 1.3's review loop) — not caused by story 1.4. Needs a test that first drives `emailError` non-null (e.g. a failed local-validation submit with a malformed e-mail), then calls `passwordChanged`, then asserts `emailError` is now null.
