---
title: 'Story 1.3: Account Creation and Login'
type: 'feature'
created: '2026-10-27'
status: 'done'
review_loop_iteration: 0
baseline_commit: '1c7fb1537a707c504ed7dc6696402c0b4919943a'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
  - '{project-root}/docs/input/backend/api/openapi.yaml'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** No `features/auth/` exists. `main.dart` is a static placeholder; `core/` only has the token-storage port and header policy waiting for a real caller.

**Approach:** Build the `auth` feature (data/domain/presentation) behind Tela 0.1a: signup/login via the existing `ApiClient`, an `AuthRepository` returning `Either<Failure, AuthenticatedUser>`, local validation, a Cubit-driven screen reusing `AppTextField`/`AppButton` unchanged. On success, save the token and move past the screen via a throwaway placeholder (no nav shell until Story 1.6).

## Boundaries & Constraints

**Always:**
- Signup/login post exactly `{email, password}` — no confirmation/display-name field (epics.md Story 1.3 AC, PRD OQ-2).
- Reuse `ApiClient`/`HeaderInterceptor` unchanged — already in `anonKeyOnlyFunctions`.
- On success, call `AccessTokenProvider.saveAccessToken` before returning `right(...)`. Refresh-token persistence is Story 1.4's job.
- `AUTH_INVALID`: fields keep typed values, both get the error border, message shown once.
- Malformed email blocks submit locally (pure validator), before any network call.
- Domain layer imports neither `flutter` nor `data/` (RNF06).

**Never:**
- No go_router / `SessionStatus` / silent refresh — Story 1.4/1.6 scope.
- No new params on `AppButton`/`AppTextField`.
- No "usar biometria" link — Epic 2 vault isn't built; omit rather than ship dead.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Valid login | registered email+password | `auth-login` succeeds, token saved, past the screen | N/A |
| Valid signup | any email+password, signup mode | `auth-signup` called with exactly 2 fields, token saved | N/A |
| Invalid credentials | wrong password/unknown email | `AuthInvalid` → both fields bordered, message once, values kept | inline, no retry |
| Malformed email | e.g. `nao-e-email`, submit tapped | blocked pre-network, inline "E-mail inválido" | local only |
| Network failure | timeout/offline/malformed | `Failure.message` shown as the same inline error | no manual retry |

</frozen-after-approval>

## Code Map

Reused as-is: `api_client.dart`/`header_interceptor.dart` (already anon-keyed, AD-5); `access_token_provider.dart` (`saveAccessToken`); `failure.dart` (`AuthInvalid`/`Validation`/`fromCode` already closed); `app_button.dart`/`app_text_field.dart` (`obscureText`, `errorText: ''` = border-only). Ground truth: `openapi.yaml:19-98` (`{email,password}` → `{data:{session:{accessToken,...}, user:{id,email}}}`); `epics.md:333-356` (AC, authoritative); `write_failure_matrix_helper.dart` (`runWriteFailureMatrix`).

Edited: `lib/main.dart` (home = auth screen + throwaway post-auth placeholder); `lib/core/di/injection_container.dart` (call `registerAuthFeature()`).

New, under `lib/features/auth/`:
- `domain/entities/authenticated_user.dart` -- plain `{id, email}`, no freezed.
- `domain/repositories/auth_repository.dart` -- `Future<Either<Failure, AuthenticatedUser>> signUp/logIn({email, password})`.
- `domain/validators/auth_validators.dart` -- pure `validateEmail`/`validatePassword` (RNF06/07).
- `data/models/auth_response_dto.dart` -- `@JsonSerializable()` response DTOs.
- `data/datasources/auth_remote_data_source.dart` -- `ApiClient.post('auth-signup'|'auth-login')`.
- `data/repositories/auth_repository_impl.dart` -- DTO→entity, saves token on success.
- `presentation/cubit/auth_state.dart`, `auth_cubit.dart` -- mode/fields/errors/`Resource<Unit>`; calls `AuthRepository` directly, no use-case.
- `presentation/screens/auth_screen.dart` -- Tela 0.1a: 2×`AppTextField` + `AppButton` + ghost toggle.
- `auth_injection.dart` -- `registerAuthFeature()`, lazy singletons in `sl`.

## Tasks & Acceptance

**Execution:**
- [x] `domain/entities/authenticated_user.dart`, `domain/repositories/auth_repository.dart` -- entity + abstract port (RNF09)
- [x] `domain/validators/auth_validators.dart` -- email regex + non-empty password
- [x] `data/models/auth_response_dto.dart` -- response DTOs, json_serializable per AGENTS.md
- [x] `data/datasources/auth_remote_data_source.dart` -- the 2 write calls
- [x] `data/repositories/auth_repository_impl.dart` -- mapping + token save
- [x] `presentation/cubit/auth_state.dart`, `auth_cubit.dart` -- drives the screen
- [x] `presentation/screens/auth_screen.dart` -- Tela 0.1a
- [x] `auth_injection.dart` + `lib/core/di/injection_container.dart` -- DI wiring
- [x] `lib/main.dart` -- home = `AuthScreen` + throwaway post-auth placeholder
- [x] `test/features/auth/domain/validators/auth_validators_test.dart` -- valid/invalid cases
- [x] `test/features/auth/data/repositories/auth_repository_impl_test.dart` -- `runWriteFailureMatrix` ×2 + success mapping + token-save assertion
- [x] `test/features/auth/presentation/cubit/auth_cubit_test.dart` -- toggle, validation-blocks-submit, success, `AuthInvalid`
- [x] `test/features/auth/presentation/screens/auth_screen_test.dart` -- I/O matrix rows + Dynamic Type

**Acceptance Criteria:**
- Given login/signup mode, when submitted, then `auth-login`/`auth-signup` is called with exactly `{email, password}` — no extra field anywhere.
- Given a successful call, when the repository returns, then the access token is persisted before the UI moves past the screen.

## Design Notes

- **Post-auth destination:** `SessionStatus` (1.4) / `go_router` (1.6) don't exist yet — success swaps `main.dart`'s screen to a small inline placeholder via `Navigator.pushReplacement`, deleted wholesale by Story 1.6.
- **No `AppButton` loading param:** submit disables mid-request, label swaps to "Entrando…"/"Criando conta…", reusing the disabled-visual rule for RNF01's indicator — no shared-widget change.

## Verification

**Commands:**
- `fvm flutter pub get` -- resolves, no conflicts
- `fvm flutter pub run build_runner build --delete-conflicting-outputs` -- generates the new DTOs' `.g.dart`
- `fvm flutter test` -- all tests pass
- `fvm flutter analyze` -- zero issues
- `grep -rn "Color(0x\|fontSize:\|EdgeInsets\.\(all\|symmetric\|only\)(" lib/features/auth --include=*.dart` -- expected: no matches (RNF08)

## Suggested Review Order

**Domain contract (entry point)**

- The two write calls as an abstract port — `Either<Failure, AuthenticatedUser>`, no confirmation/display-name field anywhere.
  [`auth_repository.dart:10`](../../lib/features/auth/domain/repositories/auth_repository.dart#L10)

**Local validation**

- Email: trims for the shape check only — the trimmed value isn't what gets sent (that's the cubit's job, see below).
  [`auth_validators.dart:12`](../../lib/features/auth/domain/validators/auth_validators.dart#L12)
- Password: the backend only requires non-empty, so no stronger rule is invented here.
  [`auth_validators.dart:23`](../../lib/features/auth/domain/validators/auth_validators.dart#L23)

**Data layer**

- `_post` posts exactly `{email, password}`, maps parse failures to `MalformedResponse` — no exception escapes.
  [`auth_remote_data_source.dart:28`](../../lib/features/auth/data/datasources/auth_remote_data_source.dart#L28)
- `_authenticate`'s token-save is now try/catch-guarded — a secure-storage throw maps to `Left`, patched post-review (RNF09).
  [`auth_repository_impl.dart:57`](../../lib/features/auth/data/repositories/auth_repository_impl.dart#L57)

**Cubit (state & submit flow)**

- `submit()`: local validation first (each error single-field), then the e-mail is trimmed only at the network boundary.
  [`auth_cubit.dart:60`](../../lib/features/auth/presentation/cubit/auth_cubit.dart#L60)
- `passwordError` patched post-review: an empty-password check no longer borders the (valid) e-mail field too.
  [`auth_state.dart:41`](../../lib/features/auth/presentation/cubit/auth_state.dart#L41)

**Screen (Tela 0.1a)**

- E-mail border logic: only `emailError` or a backend `formError` triggers it — never a password-only local error.
  [`auth_screen.dart:108`](../../lib/features/auth/presentation/screens/auth_screen.dart#L108)
- Senha shows whichever of `formError`/`passwordError` applies — the one place either channel surfaces as text.
  [`auth_screen.dart:110`](../../lib/features/auth/presentation/screens/auth_screen.dart#L110)

**Wiring (DI & app shell)**

- `registerAuthFeature()` — lazy singletons, no second `get_it` container.
  [`auth_injection.dart:12`](../../lib/features/auth/auth_injection.dart#L12)
- Called once from core bootstrap, after `ApiClient`/`AccessTokenProvider` exist.
  [`injection_container.dart:63`](../../lib/core/di/injection_container.dart#L63)
- `main.dart`'s new home + throwaway post-auth placeholder — deleted wholesale by Story 1.6.
  [`main.dart:39`](../../lib/main.dart#L39)
- `screenPadding` — the one new design token this story needed, grouped with the existing layout-insets.
  [`design_tokens.dart:234`](../../lib/core/design_tokens.dart#L234)

**Tests (peripherals)**

- DI composition patched post-review: forces the whole `AuthCubit → ... → ApiClient` chain to actually resolve.
  [`bootstrap_integration_test.dart:98`](../../test/core/di/bootstrap_integration_test.dart#L98)
- The 2-endpoint write-failure matrix plus the token-save-exception regression test.
  [`auth_repository_impl_test.dart:166`](../../test/features/auth/data/repositories/auth_repository_impl_test.dart#L166)
- Validator edge cases (valid/invalid e-mail shapes, empty password).
  [`auth_validators_test.dart:1`](../../test/features/auth/domain/validators/auth_validators_test.dart#L1)
- Cubit: toggle, local-validation-blocks-submit (now single-field), trim-before-send, success, `AUTH_INVALID`.
  [`auth_cubit_test.dart:1`](../../test/features/auth/presentation/cubit/auth_cubit_test.dart#L1)
- Screen: every I/O-matrix row end-to-end, plus the patched empty-password-doesn't-border-email case.
  [`auth_screen_test.dart:1`](../../test/features/auth/presentation/screens/auth_screen_test.dart#L1)
