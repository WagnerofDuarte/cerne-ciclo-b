# Epic 1 Context: Foundation & Session Management

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic delivers the scaffold every other feature depends on: the pinned-stack project setup with its core infrastructure verified working together, the full visual design-token system, email/password authentication with silent session refresh, the session-expiry recovery overlay, and a base navigation shell with placeholders for everything not yet built. It is delivered first because every later epic assumes this foundation — DI, networking, error handling, session state, design tokens, and navigation — already exists and is stable. Users come away able to create an account, log in, stay logged in across restarts, recover gracefully if their session expires mid-use, and navigate the whole app shell even though most feature screens are still placeholders.

## Stories

- Story 1.1: Project Scaffold, Stack Integration & Core Infrastructure
- Story 1.2: Design Token System & Core Component Library
- Story 1.3: Account Creation and Login
- Story 1.4: Silent Session Refresh & Persistence
- Story 1.5: Expired-Session Recovery Overlay
- Story 1.6: Base Navigation Shell with Feature Placeholders

## Requirements & Constraints

- Account creation and login round-trip through the backend with exactly two fields (email, password) — no password confirmation, no display-name field at signup. Login/signup/refresh are the only calls using the anon key; every other call uses the user's access token.
- A valid, unexpired session must persist across app restarts with no re-prompt; nearing/past-expiry sessions refresh silently with no visible loading UI unless the call exceeds 300ms.
- When the backend reports an expired session, an overlay appears over whatever screen is active (never a navigation away); the underlying screen's state/scroll position is preserved; "Entrar novamente" leads to biometric/PIN re-auth, not a login form.
- All four base destinations (Home/Chat, side menu, Meus Registros, Configurações) must be reachable from launch; any destination whose feature isn't built yet shows a visually distinct, fully-polished placeholder — never a broken link and never a visibly "unfinished" look.
- Local UI interactions must respond in <100ms; any network call >300ms shows a loading indicator (manual timing spot-check, no automated perf tooling).
- Zero Clean Architecture layer violations: domain imports neither Flutter nor anything from a data layer.
- ≥80% domain-layer test coverage; the write-failure matrix (5 write endpoints × 3 failure types: timeout, malformed response, no connection = 15 scenarios) must be fully handled with zero unhandled exceptions — this epic builds the one shared, reusable test helper every later feature's write-endpoint tests reuse.
- Zero hardcoded visual values outside the design-tokens file; every control must honor Dynamic Type without truncating.
- An integration spike, before any other building, must prove `dio` + `flutter_secure_storage` + `get_it` work together in one bootstrap — this combination is otherwise unverified.

## Technical Decisions

- Single DI container: exactly one `get_it` instance registered at bootstrap; `dio` is configured through it; secrets (`FUNCTIONS_BASE_URL`, `SUPABASE_ANON_KEY`) load via `flutter_dotenv` from a gitignored `.env`, never hardcoded.
- One sealed `Failure` hierarchy, exactly 14 subtypes (13 from the backend's error taxonomy plus a local-only `MalformedResponse`), defined once and never redefined/subset per feature; every repository method returns `Future<Either<Failure, T>>` (or a `Stream` for SSE), with no native/dio exception ever escaping unmapped.
- One retry interceptor on the `dio`/`ApiClient` layer retries only the 6 server-marked `retryable:true` codes; every other failure surfaces once, unretried.
- One URL builder maps every operation to `{FUNCTIONS_BASE_URL}/<x-cerne-function>/<path-params>` (never the literal OpenAPI REST path); one interceptor owns headers — `apikey` on every call, anon-key bearer token only on signup/login/refresh, user access token on everything else.
- Exactly one `SessionStatus` stream is exposed from the auth feature's domain layer and registered once in DI as a singleton; every later consumer (including RF07/Epic 4) injects/listens to it rather than re-deriving session validity from a raw 401 or a second stream.
- This epic builds the `go_router` redirect skeleton composing session state; Epic 2 (RF03) later plugs a local vault-status gate into the same redirect, checked before session status — this epic should leave that composition point open rather than hardcoding a session-only redirect.
- Strict layer direction applies project-wide: only `data/` imports `dio`/`hive_ce`/platform plugins; `presentation/` never imports any feature's `data/` directly; a BLoC/Cubit constructor never takes another BLoC/Cubit as a dependency.
- Structural seed to scaffold: `lib/core/{design_tokens.dart, network/, failure/, di/, cache/, resource.dart, isolated_side_effect.dart, session/}` and `lib/features/{auth, vault, entries, capture, chat, export, dashboard, account}/`, each pre-wired for `data/domain/presentation`.
- Full stack is pinned (Flutter 3.47.x via `fvm`; `flutter_bloc`, `go_router`, `dio`, `hive_ce`, `get_it`, `fpdart`, `freezed`, `json_serializable`, `mocktail`, `fl_chart`, `local_auth`, `flutter_secure_storage`, `flutter_dotenv`, `whisper_ggml` — exact versions in the architecture spine's stack-pins table) and must resolve with no conflicts before anything else is built.
- Design tokens (`colors`, `typography`, `rounded`, `spacing`, `components`, plus the two elevation constants) are implemented verbatim, camelCase, as the single source of truth; every other file reads from them, never redefines a value.

## UX & Interaction Patterns

- Single fixed frame: 390×844 logical points, portrait only, light mode only — no breakpoint, landscape, or dark-mode path anywhere in the app.
- Buttons and text fields come from one shared component set: disabled buttons always render `colorBorder` background + `colorTextSecondary` text (never dimmed opacity); text fields show distinct default/focused(`colorPrimary`, 1.5px)/error(`colorError`) border states.
- The side menu is the sole navigation hub (plus back arrows and sheet "x" closes) — no drawer-within-drawer, no tab bar. It must resolve all four destinations (chat session switching, Meus Registros, Configurações, Planos de Ação) without a 404 or crash.
- The Planos de Ação placeholder (an explicit, never-implemented extension feature) must still look fully finished — same visual polish as real screens, no graying-out, no backend calls, no drag/drop logic.
- The avatar component (solid `colorPrimary` circle, 1–2 uppercase initials, 40px) is built here for reuse, not reimplementation, when Configurações needs its 52px variant later (Epic 8).
- The "Sessão expirada" overlay is a scrim over the current screen using the confirmation-dialog component with a neutral (`colorTextPrimary`) title — never the red destructive-title variant. It traps focus until dismissed/actioned, is the only overlay allowed on screen at a time (never stacks on another open overlay), and its entrance uses only the `scrimIn` (0.18s) choreography — no other motion exists in the system besides `sheetUp` for bottom sheets.
- Copy for the overlay must avoid any language implying data loss or starting over; history and scroll position are understood by the user to be preserved.

## Cross-Story Dependencies

- Story 1.1 (DI, API client, Failure hierarchy, URL builder, retry interceptor, shared failure-matrix test helper) is a hard prerequisite for every other story in this epic and for every later epic's write-endpoint tests.
- Story 1.2's design tokens and base components (buttons, text fields, avatar) are consumed by Story 1.3's login/signup screen, Story 1.5's overlay, and Story 1.6's navigation shell/placeholders.
- Story 1.4 depends on Story 1.3's auth calls and exposes the singleton `SessionStatus` stream that Story 1.5 listens to and that the `go_router` redirect skeleton composes.
- Story 1.5's "Entrar novamente" action routes to the biometric/PIN re-auth flow that is not built until Epic 2 — this epic should wire the route target without implementing that flow.
- Story 1.6's `go_router` redirect skeleton is extended by Epic 2 (RF03), which plugs in the local vault-status gate ahead of the session gate already built here, in a fixed order (vault checked first).
- Story 1.6's avatar component and placeholder-styling pattern are reused as-is by Epic 8 (Configurações' 52px avatar, other placeholder surfaces).
