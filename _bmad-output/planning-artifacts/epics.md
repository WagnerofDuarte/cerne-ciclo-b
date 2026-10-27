---
stepsCompleted: [1, 2, 3, 4]
inputDocuments:
  - _bmad-output/planning-artifacts/prds/prd-cerne-ciclo-b-2026-10-25/prd.md
  - _bmad-output/planning-artifacts/architecture/architecture-cerne-ciclo-b-2026-10-26/ARCHITECTURE-SPINE.md
  - _bmad-output/planning-artifacts/ux-designs/ux-cerne-ciclo-b-2026-10-26/DESIGN.md
  - _bmad-output/planning-artifacts/ux-designs/ux-cerne-ciclo-b-2026-10-26/EXPERIENCE.md
---

# Cerne - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for Cerne, decomposing the requirements from the PRD, UX Design contract, and Architecture Spine into implementable stories.

## Requirements Inventory

### Functional Requirements

**4.1 Foundation & Session Management (F000)**

- FR-1: Account creation and authentication — signup, login, silent refresh/session-check, all round-tripping through the backend and surfacing the Failure contract on error; a valid session persists across app restarts without re-prompting. `[ASSUMPTION]` signup collects email + password only (PRD OQ-2).
- FR-2: Expired-session recovery overlay — a "Sessão expirada" overlay appears over the current screen (never navigates away) when the backend reports an expired session; "Entrar novamente" routes to the biometric/PIN re-auth flow (RF03), not a login form; screen state/scroll position preserved underneath.
- FR-3: Base navigation shell — navigation between Home/Chat, side menu, Meus Registros, and Configurações reachable from launch, with visually distinguishable placeholders for not-yet-built RF01–RF10 functionality.

**4.2 Biometric Authentication Vault (RF03)**

- FR-4: App-access gate — Face ID/Touch ID/PIN required before any user data is shown, on cold start and after the idle timeout (FR-6); no biometric data or call ever reaches the backend.
- FR-5: Biometric-failure fallback to PIN — a failed biometric attempt always offers a reachable PIN path; never locks the user out; an OS-level lockout is detected and routed to the app's own PIN fallback.
- FR-6: Fixed idle re-authentication timeout — 5 minutes backgrounded triggers re-auth on resume; fixed, not user-configurable.
- FR-7: Biometric preference persistence — enable/disable biometric gating is saved via `PATCH /account/settings`, survives restarts and reinstalls (fetched from account, not cached locally only); disabling biometrics still leaves PIN as the access method.

**4.3 Multimodal Capture (RF01)**

- FR-8: Text Entry capture — free text typed in the Insertion Modal saved as an Entry (`source=manual`).
- FR-9: Audio Entry capture — audio recorded in the Insertion Modal becomes the basis of an Entry (`source=audio`) once processed (RF02).
- FR-10: Photo Entry capture — a captured/selected photo becomes the basis of an Entry (`source=photo`) once processed (RF02). *(FR-8–10 consequence: all three modalities produce the same persisted Entry shape; each `POST /entries` call carries the correct `source`.)*
- FR-11: Cancel-safe capture — interrupting a capture in progress (stop before saving, back out mid-photo) never creates a partial/empty Entry; no `POST /entries` call fires for an abandoned capture. `[OPEN]` tab-switch mid-capture behavior (PRD OQ-3) — resolved by UX-DR25 below: cancels the in-flight capture outright.

**4.4 Speech-to-Text / OCR Processing (RF02)**

- FR-12: On-device audio transcription — audio is transcribed to text entirely on-device via `whisper_ggml`; the audio file itself is never sent to the backend. Four states in sequence: recording → processing → transcribed → (on failure) error with retry, media never discarded.
- FR-13: Backend OCR for photos — a captured photo is sent to `POST /media/ocr` to extract text before the Entry is created. Mirrors FR-12's four-state pattern; on failure, two recovery paths exist (retry OCR, or "Salvar só a foto" with no extracted text); `OCR_NO_TEXT` is a distinct, user-visible, non-retryable outcome.

**4.5 Multi-Source History / Timeline (RF07)**

- FR-14: Chronological Entry list — all Entries from any source listed together, grouped by date, each visually marked with its origin.
- FR-15: Per-entry Sync Badge — one of three states (Synchronizing / Synchronization error / Synchronized), derived client-side from `updatedAt`/`serverRevision` plus local pending-write state; the badge stream is independent of the auth/session stream. `[OPEN]` no retry affordance visible in the prototype (PRD OQ-6) — resolved by UX-DR30 below.
- FR-16: Empty-state handling — zero Entries shows a dedicated empty state with a path back to capture, not a blank list.
- FR-17: Session-expiry resilience mid-view — the FR-2 overlay appears over the timeline without crashing or losing scroll position.
- FR-18: Entry detail view — a single Entry can be opened from the timeline via `GET /entries/:id`; never mutates it (no edit affordance); a detail request for another user's/nonexistent Entry returns `NOT_FOUND` (RNF04). *Feature-specific NFR: no BLoC in this feature imports another BLoC directly — the auth-status, Sync-Badge-state, and Entry-data streams combine only through the domain layer.*

**4.6 Semantic Search / Filter (RF06)**

- FR-19: Semantic search — meaning-based search over Entries (not literal keyword match) via `GET /entries/search`.
- FR-20: Metadata filters — filter by source and date range (`dateFrom`/`dateTo`), no tag/category filter; no-search-term filtering queries `GET /entries`, filtering + active search term queries `GET /entries/search` with the same filter params. *(FR-19/20 consequence: multiple active filters combine with AND semantics.)* `[OPEN]` search+filter interaction (PRD OQ-7) — resolved by UX-DR29 below: AND-combine against `GET /entries/search`.
- FR-21: Debounced search input — 300ms debounce before firing a request.
- FR-22: Non-disruptive filter clearing — clearing filters restores the full list in place (no full reload); cache stays duplicate-free after a reconnect (cloud-only; offline is view-only here).

**4.7 Interactive Chat with Memory / RAG (RF04)**

- FR-23: Send message, receive RAG-grounded streaming response — via SSE on `POST /chat/sessions/:id/messages`; exactly three visible states (streaming/processing, error, complete); Chat Messages never automatically create Entries (RF10 is the sole exception).
- FR-24: Multi-session chat history — multiple named Chat Sessions, listed and switchable from the side menu.
- FR-25: New-conversation action — start a new Chat Session from the side menu; `POST /chat/sessions` is blocked offline.
- FR-26: Dropped-stream resilience — if a response stream drops mid-generation, the partial message stays on screen with a failure indicator; retryable via `POST /chat/sessions/:id/messages/:userMessageId/retry` without duplicating the original question.
- FR-27: Offline composer lock — composer disabled while offline; existing conversation history stays visible and navigable.

**4.8 Save Chat Message as Entry (RF10)** — depends on RF01, RF04

- FR-28: Bookmark a user message into an Entry — a "save" affordance on the user's own Chat Messages only (never AI responses) creates an Entry (`source=chat`, carrying `chatMessageId`) through the same shared entries use case RF01 defines, never by importing the entries repository/data source directly (RNF06).
- FR-29: Idempotent save — saving the same Chat Message more than once never creates a duplicate Entry and never surfaces a conflict error (backend returns 200, not 409).
- FR-30: Save-failure isolation — on save failure, the surrounding Chat Session stays fully usable; the save affordance resets to a retryable state rather than freezing.

**4.9 Proactive Insights (RF08)** — depends on RF04; scope is trigger/injection mechanism only, generated-text quality out of scope

- FR-31: Unprompted Insight injection — injected into the active Chat Session once per satisfied condition (5 user messages OR 2 minutes inactivity, whichever first) via `POST /chat/sessions/:id/insight`.
- FR-32: Insight failure isolation — a failed Insight generation never interrupts or breaks the main chat experience; composer stays enabled, no error overlay, ordinary chat messages keep working.
- FR-33: Non-disruptive dismissal — dismissing an Insight never affects scroll position or other conversation state.

**4.10 Personal Summary Export (RF05)** — depends on RF07; scope is job/file/failure handling only, generated-narrative quality out of scope

- FR-34: Request a period export — via `POST /export/summary` for a chosen date period.
- FR-35: Job status across five screen states — Pendente, Processando, Concluído, Erro, Período vazio — via `GET /export/:jobId/status`, reporting `status` (job) and `narrativeStatus` (AI summary) independently.
- FR-36: Narrative-independent raw-data download — raw data downloadable via `GET /export/:jobId/download` as soon as ready, even if the narrative step is still processing, failed, or skipped; the narrative never blocks the download.
- FR-37: Empty-period handling — an export request for a period with zero Entries surfaces "Período vazio," no download offered, no crash.

**4.11 Temporal Summaries / Dashboard & Account (RF09)** — depends on F000, RF01; Dashboard scope is aggregation/rendering only, narrative-text quality out of scope

- FR-38: On-demand dashboard aggregation — opening Configurações computes/renders an evolution chart via `GET /dashboard/aggregate`, correctly at zero, one, and >30 Entries.
- FR-39: Independent narrative text — fetched via `GET /dashboard/narrative`; its failure is a distinct, chart-still-renders state, never blocking the chart (two independent endpoints by design).
- FR-40: Cache invalidation on new Entry — dashboard aggregation recalculates after a new Entry is created elsewhere in the app; invalidation only ever triggers on create (Entries are immutable, never edited).
- FR-41: Profile name editing — inline display-name edit on Configurações via `PATCH /account/settings`.
- FR-42: Logout — "Sair" ends the session (`POST /auth/logout`) and returns to the Biometric Vault / login screen.
- FR-43: Account deletion — "Apagar conta" shows a confirmation dialog; on confirm, account and all data are hard-deleted (`DELETE /account`, LGPD-driven); routes to the same destination as logout. `[NOTE]` no dedicated "account deleted" confirmation screen exists (PRD OQ-4).

### NonFunctional Requirements

- RNF01 (performance): local UI interactions respond in <100ms; any network call taking >300ms shows a loading indicator. Verified by manual timing spot-check per feature module (no automated perf instrumentation planned).
- RNF02 (PII handling) `[inherited, not verified by this delivery]`: PII stripping runs server-side via a Claude Haiku 4.5 structured prompt/tool-use step.
- RNF03 (data retention) `[inherited, not verified by this delivery]`: zero data retention by upstream AI providers.
- RNF04 (data isolation): Row Level Security (Supabase) enforces per-user data isolation; client never needs its own cross-user authorization logic; the backend uniformly returns `NOT_FOUND` (never permission-denied) for another user's resource.
- RNF05 (account deletion): hard delete of account and all associated data on request (LGPD).
- RNF06 (architecture): zero Clean Architecture layer violations — the domain layer imports neither `package:flutter` nor anything from a `data/` layer, across all 11 feature modules.
- RNF07 (test coverage): ≥80% domain-layer test coverage.
- RNF08 (visual fidelity): visual fidelity to the prototype (color, typography, spacing); zero hardcoded visual values outside `design_tokens.dart`.
- RNF09 (resilience): every repository returns `Either<Failure, T>`; 5 write endpoints × 3 failure types (timeout, malformed response, no connection) = 15 tested failure scenarios, zero unhandled exceptions.

### Additional Requirements

*(from the Architecture Spine — cross-unit invariants and stack decisions that bound how stories must be implemented; binds column shows which build units each rule applies to)*

- Delivery order governs epic/story sequencing: F000 → RF03 → RF01 → RF02 → RF07 → RF06 → RF04 → RF10 → RF08 → RF05 → RF09 — later units assume earlier ones exist (e.g., RF10 assumes RF01 and RF04 are both done). No reordering.
- **Integration spike required first, inside F000, before any other building:** verify `dio` + `flutter_secure_storage` + `get_it` work together in one scaffold bootstrap — flagged as unverified in combination even though each package is independently current.
- AD-1 (binds: all) — strict layer dependency direction `presentation → domain ← data`; only `data/` imports `dio`/`hive_ce`/platform plugins; `presentation/` never imports any `data/` directly.
- AD-2 (binds: all repositories) — every repository method returns `Future<Either<Failure, T>>` (or `Stream<Either<Failure, T>>` for the chat SSE stream); no native/dio exception escapes unmapped.
- AD-3 (binds: all) — one sealed `Failure` class in `core/`, exactly 14 subtypes (13 from `error-taxonomy.md` + local-only `MalformedResponse`); never redefined or subset per feature; `AuthInvalid` only ever originates from `POST /auth/login`.
- AD-4 (binds: the API client) — retry logic implemented exactly once (the `dio` interceptor/`ApiClient` wrapper), fires only for the 6 server `retryable:true` codes; every other code surfaces once, unretried.
- AD-5 (binds: every network call) — one URL builder in `core/` maps each operation to `{FUNCTIONS_BASE_URL}/<x-cerne-function>/<path-params>`; one `dio` interceptor owns headers (`apikey` always; `Authorization: Bearer <anon key>` only on signup/login/refresh; `Authorization: Bearer <user token>` otherwise).
- AD-6 (binds: RF01 introduces `features/entries/`; RF10 and any future cross-feature dependency consume it) — `entries/domain` owns the `Entry` entity, the `EntriesRepository` port, and the Hive box; RF01's `capture` and RF10's `chat` are consumers only (import the abstract port, never `entries/data/` or `entries/presentation/`); RF06/RF07 extend the same port with `list`/`search`, never a second entry model; `create` is idempotent on `(origin, chatMessageId)`.
- AD-7 (binds: all) — a BLoC/Cubit constructor never takes another BLoC/Cubit as a dependency; composition via injected domain streams/use-cases or `BlocListener`/`MultiBlocListener`.
- AD-8 (binds: F000, RF07, any session-consuming feature) — exactly one `SessionStatus` stream from the auth feature's `domain/`, registered once in DI as a singleton; no consumer re-derives session state from a raw 401 or a second stream.
- AD-9 (binds: all repositories) — a write attempted with no connectivity resolves immediately to `Either.left(Failure.networkOffline)`, never queued; plain reads fall back to the local `hive_ce` cache; semantic search (`GET /entries/search`) has no client-side vector index, so it also resolves to `networkOffline` when offline, same as a write.
- AD-10 (binds: every screen rendering the sync badge) — one derivation function in `entries/domain`, computed from `Entry.serverRevision`, `Entry.updatedAt`, and transient per-entry write state; every screen consumes that function's output, none recomputes inline.
- AD-11 (binds: the entries feature) — `EntriesRepository` exposes create and read only; no update/delete method is ever added.
- AD-12 (binds: RF06, RF09 — explicitly not RF02/RF04/RF07) — generic `Resource<T>` (`idle`/`loading`/`data`/`error`) in `core/` used only by single-data-source, single-fetch-lifecycle screens; RF02, RF04, and RF07 each define their own sealed state class.
- AD-13 (binds: RF08, RF10) — `core/` holds a never-throws `isolatedSideEffect` helper (`Future<Either<Failure, T>> Function(Future<T> Function())`-shaped), ships with RF10 (first consumer); RF10 may `await` it, RF08 must call it fire-and-forget (without awaiting).
- AD-14 (binds: F000 builds the redirect skeleton + `SessionStatus` half; RF03 plugs in the vault half) — one `go_router` redirect composing exactly two gates in fixed order: `VaultStatus` first, then `SessionStatus`; neither gate ever reaches the server to validate itself.
- AD-15 (binds: `entries`, `chat` — every feature with a `hive_ce` box) — every query dimension (source, date range, semantic search, pagination cursor) is a server-side query parameter; a Hive box stores exactly what the server returned, keyed by id; no feature filters/joins/sorts/re-derives a cached collection locally.
- Stack pins (binding on F000, verified at scaffold time): Flutter SDK 3.47.x stable family (exact patch pinned via `fvm`), `flutter_bloc` ^9.1.1, `go_router` ^18.1.1, `dio` ^5.11.1, `hive_ce`/`hive_ce_flutter` ^2.22.0, `get_it` ^9.3.0, `fpdart` ^1.2.0, `freezed`/`freezed_annotation` ^4.0.3, `json_serializable` ^6.15.2, `build_runner` (latest compatible), `mocktail` ^1.0.5, `fl_chart` ^1.3.0, `local_auth` ^3.0.2, `flutter_secure_storage` ^11.2.0, `flutter_dotenv` ^6.0.1, `whisper_ggml` ^2.8.1.
- Structural seed (binding on F000, extended by each feature's own build unit): `lib/core/` (`design_tokens.dart`, `network/`, `failure/`, `di/`, `cache/`, `resource.dart`, `isolated_side_effect.dart`, `session/`) and `lib/features/{auth, vault, entries, capture, chat, export, dashboard, account}/`, each three-layered (`data/domain/presentation`).
- Config/secrets: `.env` (`FUNCTIONS_BASE_URL`, `SUPABASE_ANON_KEY`) loaded via `flutter_dotenv`; never committed, never hardcoded.
- Testing convention (binding at every feature's test suite): `mocktail` stubs one `ApiClient` interface per repository test; one shared table-driven helper drives the 15-scenario (5 write endpoints × 3 failure types) matrix; ≥80% line coverage gate on every `domain/`.
- No starter/greenfield template is specified — the app is scaffolded directly per the Structural Seed above, not from a community starter kit.

### UX Design Requirements

*(from `DESIGN.md` + `EXPERIENCE.md` — actionable design-token, component, accessibility, and interaction work; each item is specific enough to generate its own story-level acceptance criteria)*

**Design tokens**

- UX-DR1: Implement the full token set (`colors`, `typography`, `rounded`, `spacing`, `components`) from `DESIGN.md`'s frontmatter verbatim into `lib/core/design_tokens.dart` as the single source of truth (RNF08) — camelCase names map 1:1, zero translation step. Includes the two elevation values (`elevation1`, `elevation2`) inlined as literal shadow strings since they aren't in the frontmatter token categories.

**Reusable components (list all, not summarized)**

- UX-DR2: Button components — primary (filled, darkens on press), secondary (outline), text/ghost (no chrome); disabled state always `colorBorder` background + `colorTextSecondary` text, never a dimmed opacity of the active state.
- UX-DR3: Text field component with default/focused (`colorPrimary`, 1.5px)/error (`colorError`) border states.
- UX-DR4: Chat bubble components — user (sage, square bottom-right, static once sent) vs. AI (ivory, `elevation1`, square bottom-left, streaming state adds a blinking cursor at text end, no other visual change while generating).
- UX-DR5: Insight card component — ochre spine on the left edge (the only accent-colored element inside the chat stream), mono "INSIGHT" label, dismiss "x."
- UX-DR6: Bookmark button component — four states (idle/saving/saved/error) on every user message only, never on AI responses; state carried by icon + color together, never color alone; tapping an already-`saved` message is a no-op; `error` returns to a retryable idle-like state.
- UX-DR7: Sync badge component — small dot (green/ochre/red for synced/synchronizing/error), reinforced by an accessible label on tap/long-focus since dot color alone is insufficient; tap on `error` retries that entry's write when the underlying code is retryable, shows inline explanation instead when non-retryable (resolves PRD OQ-6).
- UX-DR8: Filter chip component — sage background, dark-olive text, fully rounded; single-choice (date range) and multi-choice (category/type) look visually identical, differ only in behavior.
- UX-DR9: Search bar component — paper-elevated input, trailing funnel icon button, permanently docked at top of Meus Registros, never submitted with a button, 300ms debounce.
- UX-DR10: Filter sheet component — `radiusLg`/`elevation2` bottom sheet, groups labeled in `textMonoCaption`.
- UX-DR11: Insertion-modal tab bar component — three equal-width segments (Texto/Áudio/Foto); active segment alone gets filled `colorPrimary` background.
- UX-DR12: Audio waveform component — animated bars in the structural palette while recording; frozen at 35% opacity while processing (no additional label needed beyond the "Transcrevendo..." text).
- UX-DR13: Avatar component — solid `colorPrimary` circle, 1–2 uppercase initials in `colorOnPrimary`, two fixed sizes (40px menu, 52px Settings), no photo avatars anywhere; in Configurações the pencil icon becomes a check icon in edit mode.
- UX-DR14: PIN keypad component — numeric 3×4 grid + backspace, progress dots above, structural palette only (no accent on digits), auto-advances 350ms after the 4th digit with no explicit confirm tap.
- UX-DR15: Export sheet component — heaviest surface after a full-screen modal (`radiusLg`+`elevation2`); each job-stage change replaces sheet content in place, the sheet itself never closes/reopens mid-job.
- UX-DR16: Confirmation dialog component — neutral title (`colorTextPrimary`) for session expiry, red title (`colorError`) for destructive deletion; title color is the only signal distinguishing the two, so it must never be muted; traps focus until dismissed/actioned.
- UX-DR17: Skeleton loading component — shown only past the 300ms threshold (RNF01), `colorBorder`-toned shimmer (never a spinner), for content loading only.
- UX-DR18: Record card component — spine colored by Entry origin (manual=`colorPrimary`, audio=olive green, photo=gray, chat=`colorAccent`); the only place color encodes a data dimension rather than a UI state.
- UX-DR19: Banner components — offline banner (`colorInfoOffline`, single-use, offline only) and send-error banner (muted red wash); never reuse the offline blue-gray for any other informational banner.

**Accessibility**

- UX-DR20: WCAG AA adopted as the accessibility floor (not mandated by requirements.md, adopted here); every currently color-only state (sync badge dot, bookmark states) also carries an icon or accessible label — color alone never carries state.
- UX-DR21: Screen-reader labels announce transitions, not just static state ("Gravando," "Transcrevendo," "Erro ao transcrever, toque para tentar novamente").
- UX-DR22: Dynamic type honored at every level; no control truncates/clips at the largest accessibility text size — PIN keypad, filter chips, and tab bar are the tightest-fit surfaces and must be verified first.
- UX-DR23: Tap targets ≥44pt, including the bookmark icon and the sync-badge dot's retry hit area (visually a small dot, hit area larger).
- UX-DR24: Reduce Motion support — skip the streaming cursor blink and `scrimIn`/`sheetUp` easing (show final state immediately); spinners become a static "carregando" label instead of a spin animation.
- UX-DR25: Session-expired and account-deletion dialogs trap focus until dismissed or actioned — no interacting with scrim-covered content underneath.

**Interaction patterns**

- UX-DR26: Insertion-modal tab-switch mid-capture cancels the in-flight capture outright (recording or OCR/transcription processing) — no partial entry created; opening the modal always resets all three tabs to idle/empty. Resolves PRD OQ-3.
- UX-DR27: Entrance choreography limited to exactly two animations system-wide: `sheetUp` (0.2s, bottom sheets) and `scrimIn` (0.18s, any overlay's scrim) — no other motion.
- UX-DR28: Banned gestures enforced everywhere: no swipe-to-delete (or any swipe) on record cards, no nested overlays (a sheet opening another sheet), no pull-to-refresh beyond the spec-defined refresh points, no long-press repurposed beyond native text selection.
- UX-DR29: Search bar query text + active filter chips combine with AND logic against the same `GET /entries/search` call; clearing filters returns to the unfiltered list without re-mounting the screen. Resolves PRD OQ-7.
- UX-DR30: Offline disables the insertion-modal "+" entry point with the same offline treatment as chat send (capture requires a live `POST /entries` round trip for PII check + embedding — no local-only queued write).
- UX-DR31: Signup screen has exactly two fields (email, senha), matching the prototype's login fields one-for-one — no name or password-confirmation field. Resolves PRD OQ-2.

**Visual/state standardization**

- UX-DR32: Extension/placeholder screens (Planos de Ação kanban, persona toggle cards) are styled with full visual polish — never marked as visibly "unfinished" or grayed-out, despite having no functional logic behind them.
- UX-DR33: Dashboard renders four distinct states: zero entries (placeholder icon + "Comece a registrar..."), one entry (single bar + "Ainda é cedo..."), >30 entries (10-bar chart + narrative), and narrative-unavailable (chart renders normally, only the AI summary paragraph shows a distinct failure message — never blank, never confused with zero-entries).
- UX-DR34: Export sheet renders the hybrid "data ready, summary still generating" state (`status=data_ready`, `narrativeStatus=processing`) not present in the prototype's original 5 visual states — "Baixar dados brutos" shown immediately while summary-progress text keeps showing underneath.
- UX-DR35: Single fixed frame 390×844 logical points, portrait only, single column, light mode only — no tablet/landscape/dark-mode layout to reconcile against.
- UX-DR36: Overlays stack at most one level deep — a bottom sheet or dialog sits on a darkened scrim over exactly one base screen; the insertion modal's three tabs are internal states of one sheet, not nested sheets.

### FR Coverage Map

FR-1: Epic 1 - Account creation and authentication
FR-2: Epic 1 - Expired-session recovery overlay
FR-3: Epic 1 - Base navigation shell
FR-4: Epic 2 - App-access gate
FR-5: Epic 2 - Biometric-failure fallback to PIN
FR-6: Epic 2 - Fixed idle re-authentication timeout
FR-7: Epic 2 - Biometric preference persistence
FR-8: Epic 3 - Text Entry capture
FR-9: Epic 3 - Audio Entry capture
FR-10: Epic 3 - Photo Entry capture
FR-11: Epic 3 - Cancel-safe capture
FR-12: Epic 3 - On-device audio transcription
FR-13: Epic 3 - Backend OCR for photos
FR-14: Epic 4 - Chronological Entry list
FR-15: Epic 4 - Per-entry Sync Badge
FR-16: Epic 4 - Empty-state handling
FR-17: Epic 4 - Session-expiry resilience mid-view
FR-18: Epic 4 - Entry detail view
FR-19: Epic 5 - Semantic search
FR-20: Epic 5 - Metadata filters
FR-21: Epic 5 - Debounced search input
FR-22: Epic 5 - Non-disruptive filter clearing
FR-23: Epic 6 - Send message, receive RAG-grounded streaming response
FR-24: Epic 6 - Multi-session chat history
FR-25: Epic 6 - New-conversation action
FR-26: Epic 6 - Dropped-stream resilience
FR-27: Epic 6 - Offline composer lock
FR-28: Epic 6 - Bookmark a user message into an Entry
FR-29: Epic 6 - Idempotent save
FR-30: Epic 6 - Save-failure isolation
FR-31: Epic 6 - Unprompted Insight injection
FR-32: Epic 6 - Insight failure isolation
FR-33: Epic 6 - Non-disruptive dismissal
FR-34: Epic 7 - Request a period export
FR-35: Epic 7 - Job status across five screen states
FR-36: Epic 7 - Narrative-independent raw-data download
FR-37: Epic 7 - Empty-period handling
FR-38: Epic 8 - On-demand dashboard aggregation
FR-39: Epic 8 - Independent narrative text
FR-40: Epic 8 - Cache invalidation on new Entry
FR-41: Epic 8 - Profile name editing
FR-42: Epic 8 - Logout
FR-43: Epic 8 - Account deletion

## Epic List

### Epic 1: Foundation & Session Management

Users can create an account, log in, and have their session silently maintained or gracefully recovered; the app shell navigates between all four base surfaces with clear placeholders for what isn't built yet. Realizes UJ-2 (expired-session edge case). Delivered first (F000) — every later epic assumes this scaffold, the auth session lifecycle, and base navigation already exist. **No prior epic.**
**FRs covered:** FR-1, FR-2, FR-3

### Epic 2: Biometric Authentication Vault

Users unlock the app with Face ID/Touch ID (or PIN fallback) before any personal data is ever shown, with no lockout path and no biometric data ever leaving the device. Realizes UJ-1 (entry + edge case). Depends on Epic 1 — plugs the vault half into the single `go_router` redirect whose skeleton F000 already built (AD-14); this is a planned, non-competing extension of one shared file, not file churn.
**FRs covered:** FR-4, FR-5, FR-6, FR-7

### Epic 3: Multimodal Capture & Processing

Users can capture a journal Entry as text, voice, or photo — with audio transcribed on-device and photos OCR'd server-side before the Entry is ever persisted — and interrupting a capture never leaves a stray partial Entry behind. Realizes UJ-1. Depends on Epic 2 (the Insertion Modal is only reachable once the vault is unlocked). RF01 and RF02 stay merged because an un-transcribed audio Entry or un-OCR'd photo Entry is not a complete feature on its own (FR-9/FR-10 explicitly define the Entry as only "complete once processed") — unlike the Epic 4/5 split below, there is no standalone milestone at the RF01-only boundary. Introduces `features/entries/` (AD-6) as the shared port every later epic that creates or reads an Entry will consume.
**FRs covered:** FR-8, FR-9, FR-10, FR-11, FR-12, FR-13

### Epic 4: Timeline & History

Users can see every Entry they've ever captured, from any source, in one chronological view with a live per-entry sync status — and never lose track of something they wrote, even offline or mid-session-expiry. Realizes UJ-1 (as the destination for captured entries). Depends on Epic 3 (there's nothing to list until Entries exist). Kept separate from Epic 5: unlike RF01/RF02, a plain chronological timeline with working sync badges is a complete, independently demoable milestone with no search or filtering at all — splitting here, rather than merging, is the one place "same feature module" was not sufficient justification to combine two RF units.
**FRs covered:** FR-14, FR-15, FR-16, FR-17, FR-18

### Epic 5: Semantic Search & Filtering

Users can find any Entry again by meaning — not just exact keyword match — and narrow results by source and date range, with search debounced and filters clearing back to the full list without a reload. Realizes UJ-4. Depends on Epic 4 (search and filter operate over the timeline surface Epic 4 built). Extends the same `EntriesRepository` port (AD-6) with `list`/`search`, introducing no second Entry model — but is its own epic because it is its own user-facing milestone and its own journey (UJ-4), not a structural completion of Epic 4's job the way RF02 completes RF01's.
**FRs covered:** FR-19, FR-20, FR-21, FR-22

### Epic 6: Conversational Memory, Save-to-Journal & Insights

Users can have a persistent, multi-session conversation with an assistant that answers grounded in their own past Entries, turn their own reflective messages into real Entries with one tap, and occasionally receive an unprompted insight about a pattern in their writing — none of which ever blocks or corrupts the core chat experience when it fails. Realizes UJ-2, UJ-3. Depends on Epic 3 (RF10's save-to-Entry reuses the entries port introduced there). RF04, RF10, and RF08 stay merged because they share one feature module and one screen (Home/Chat), and because RF08 fire-and-forget-consumes the `isolatedSideEffect` helper (AD-13) that ships as part of RF10's build inside this same epic — splitting them would scatter a hard build-order dependency across epic boundaries, unlike the Timeline/Search split above.
**FRs covered:** FR-23, FR-24, FR-25, FR-26, FR-27, FR-28, FR-29, FR-30, FR-31, FR-32, FR-33

### Epic 7: Personal Summary Export

Users can request a narrative PDF + raw-data export for any date period, and always get their raw data even if the AI-generated narrative fails or the period turns out to be empty. Realizes UJ-5. Depends on Epic 4 (export operates over the same Entry history Timeline surfaces).
**FRs covered:** FR-34, FR-35, FR-36, FR-37

### Epic 8: Evolution Dashboard & Account Management

Users can see an on-demand chart of their journaling activity with an independent AI narrative, edit their display name, log out, and permanently delete their account and all associated data. Realizes UJ-6. Depends on Epic 1 (session/logout) and Epic 3 (dashboard aggregation needs Entries to aggregate, and recalculates whenever a new one is created).
**FRs covered:** FR-38, FR-39, FR-40, FR-41, FR-42, FR-43

## Epic 1: Foundation & Session Management

Users can create an account, log in, and have their session silently maintained or gracefully recovered; the app shell navigates between all four base surfaces with clear placeholders for what isn't built yet.

### Story 1.1: Project Scaffold, Stack Integration & Core Infrastructure

As a developer,
I want the Flutter project scaffolded with the pinned stack and the `dio` + `flutter_secure_storage` + `get_it` integration verified working together in one bootstrap,
So that every feature built afterward has a stable, correctly-wired foundation instead of discovering an integration conflict mid-feature.

**Acceptance Criteria:**

**Given** a fresh checkout of the repository
**When** `fvm flutter pub get` and the build runner are executed
**Then** the project resolves all pinned dependencies (Flutter 3.47.x family, `flutter_bloc` ^9.1.1, `go_router` ^18.1.1, `dio` ^5.11.1, `hive_ce`/`hive_ce_flutter` ^2.22.0, `get_it` ^9.3.0, `fpdart` ^1.2.0, `freezed`/`freezed_annotation` ^4.0.3, `json_serializable` ^6.15.2, `mocktail` ^1.0.5, `fl_chart` ^1.3.0, `local_auth` ^3.0.2, `flutter_secure_storage` ^11.2.0, `flutter_dotenv` ^6.0.1, `whisper_ggml` ^2.8.1) with no version conflicts.

**Given** the `lib/` directory after scaffolding
**When** inspected
**Then** it matches the Structural Seed exactly: `lib/core/{design_tokens.dart, network/, failure/, di/, cache/, resource.dart, isolated_side_effect.dart, session/}` and `lib/features/{auth, vault, entries, capture, chat, export, dashboard, account}/`, each pre-wired for the `data/domain/presentation` split.

**Given** a gitignored `.env` holding `FUNCTIONS_BASE_URL` and `SUPABASE_ANON_KEY`
**When** the app boots
**Then** `flutter_dotenv` loads both values and no secret is hardcoded anywhere in source.

**Given** the DI bootstrap in `lib/core/di/`
**When** the app starts
**Then** exactly one `get_it` instance is registered, `dio` is configured through it, and an integration test proves `flutter_secure_storage` can be read/written through the same bootstrap — verifying the three packages work together before any feature is built on top of them.
**And** the sealed `Failure` hierarchy (AD-3, 14 subtypes) is defined in `lib/core/failure/`, the one retry interceptor (AD-4) retries only the 6 server `retryable:true` codes, and the one URL builder (AD-5) maps every operation to `{FUNCTIONS_BASE_URL}/<x-cerne-function>/<path-params>` with `apikey` sent on every call.
**And** one shared, table-driven `mocktail` test helper is built in `core/` that drives the 5-write-endpoint × 3-failure-type (timeout, malformed response, no connection) = 15-scenario matrix (RNF09) against a stubbed `ApiClient` — every later story that owns a write endpoint reuses this helper rather than building its own failure-matrix harness.

### Story 1.2: Design Token System & Core Component Library

As a developer,
I want the full visual token set and the generic button/text-field components implemented in `lib/core/design_tokens.dart` and a shared widgets layer,
So that every screen built afterward pulls its visual values and basic controls from one source, with zero hardcoded colors/fonts/spacing anywhere else in the app (RNF08).

**Acceptance Criteria:**

**Given** `DESIGN.md`'s frontmatter token set (colors, typography, rounded, spacing)
**When** `design_tokens.dart` is implemented
**Then** every token name matches `DESIGN.md` verbatim (camelCase), and `elevation1`/`elevation2` are defined as literal shadow constants alongside it (UX-DR1).

**Given** the app's single supported configuration
**When** any screen renders
**Then** it is laid out for a fixed 390×844 logical-point portrait frame, light mode only — no breakpoint, landscape, or dark-mode code path exists anywhere (UX-DR35).

**Given** the primary, secondary, and text/ghost button components
**When** a button is disabled
**Then** it renders `colorBorder` background with `colorTextSecondary` text — never a dimmed opacity of its active state (UX-DR2).

**Given** the text-field component
**When** it is empty, focused, or holding a validation error
**Then** it shows the default, `colorPrimary`-at-1.5px-focused, and `colorError`-bordered states respectively, with no literal color/width defined outside `design_tokens.dart` (UX-DR3).
**And** every control built from these tokens honors Dynamic Type at every size without truncating or clipping (UX-DR22).

### Story 1.3: Account Creation and Login

As a new or returning user,
I want to create an account or log in with my email and password,
So that I can access my private journal.

**Acceptance Criteria:**

**Given** the Entrar / Criar conta screen in login mode
**When** I submit a valid, registered email and password
**Then** `POST /auth/login` succeeds and I land on Home/Chat with a persisted session.

**Given** the same screen toggled to signup mode
**When** I submit an email and password
**Then** `POST /auth/signup` is called with exactly those two fields — no password-confirmation or display-name field exists anywhere on the screen (UX-DR31, resolves PRD OQ-2).

**Given** an invalid login attempt
**When** the backend returns `AUTH_INVALID`
**Then** the error shows inline under the fields using the text-field's error-border treatment, and the field is never cleared.

**Given** a malformed email
**When** I attempt to submit before any network call
**Then** client-side validation blocks the submit locally where possible, without a round trip.
**And** every call on this screen sends `apikey` plus `Authorization: Bearer <anon key>` per AD-5 — never a user token, since signup/login/refresh are the three `security: []` operations.

### Story 1.4: Silent Session Refresh & Persistence

As a returning user,
I want my session refreshed silently or remembered across app restarts,
So that I don't have to log in every time I open the app.

**Acceptance Criteria:**

**Given** a previously authenticated session with a valid, unexpired token
**When** I restart the app
**Then** I land on Home/Chat without being re-prompted for credentials.

**Given** a session nearing or past expiry on app foreground
**When** the app checks session validity
**Then** it calls the session-check/refresh operation silently, with no visible loading UI unless the call exceeds the 300ms threshold (RNF01).
**And** exactly one `SessionStatus` stream is exposed from `features/auth/domain/` and registered once in DI as a singleton (AD-8) — no other code path re-derives session validity from a raw 401 or a second stream.

### Story 1.5: Expired-Session Recovery Overlay

As a user whose session has expired while using the app,
I want a "Sessão expirada" overlay that lets me re-authenticate without losing my place,
So that I never lose my context or feel like I'm starting over.

**Acceptance Criteria:**

**Given** I am on any screen and the backend reports `AUTH_EXPIRED`
**When** the overlay appears
**Then** it renders as a scrim over the current screen (confirmation-dialog component, neutral `colorTextPrimary` title, UX-DR16) — the screen underneath, including scroll position, is preserved, never navigated away from.

**Given** the overlay is visible
**When** I tap "Entrar novamente"
**Then** I am routed to the biometric/PIN re-auth flow (built in Epic 2) — never a full login form.

**Given** the overlay is open
**When** I try to interact with anything underneath the scrim
**Then** focus is trapped on the overlay until it is dismissed or actioned (UX-DR25).
**And** its entrance uses only the `scrimIn` (0.18s) choreography, and it is the only overlay permitted on screen at a time — it never stacks on top of another open overlay (UX-DR27, UX-DR36).

### Story 1.6: Base Navigation Shell with Feature Placeholders

As a user,
I want to navigate between Home/Chat, the side menu, Meus Registros, and Configurações from the moment I open the app,
So that the whole app feels complete and navigable even while individual features are still being built.

**Acceptance Criteria:**

**Given** the app has launched
**When** I open the side menu (☰)
**Then** I can reach Chat Session switching, Meus Registros, Configurações, and Planos de Ação — all four destinations resolve to a screen, none 404s or crashes.

**Given** a destination whose RF unit is not yet built
**When** I navigate to it
**Then** it renders a visually distinct, clearly-marked placeholder — never a screen that looks finished but does nothing.

**Given** the Planos de Ação placeholder (an explicit extension feature, never implemented per project policy)
**When** I open it
**Then** it is styled with full visual polish per the design tokens — never grayed-out or visibly "unfinished" (UX-DR32) — with no backend calls and no interactive drag/drop logic behind it.
**And** the side-menu avatar component (solid `colorPrimary` circle, 1–2 uppercase initials, 40px) is implemented here for reuse — not reimplementation — when Configurações needs its 52px variant later (UX-DR13).

## Epic 2: Biometric Authentication Vault

Users unlock the app with Face ID/Touch ID (or PIN fallback) before any personal data is ever shown, with no lockout path and no biometric data ever leaving the device.

### Story 2.1: Biometric/PIN App-Access Gate

As a user,
I want the app to require Face ID, Touch ID, or PIN before showing any of my data,
So that my journal stays private even if someone else picks up my phone.

**Acceptance Criteria:**

**Given** the app is cold-started or resumed after the idle timeout
**When** the vault gate evaluates
**Then** no screen other than the vault/login screen is reachable until authentication succeeds.

**Given** the `go_router` redirect
**When** it evaluates on any navigation attempt
**Then** it composes exactly two gates in fixed order — `VaultStatus` first, then `SessionStatus` (AD-14) — and neither gate ever makes a network call to validate itself; biometric validation is 100% on-device, so no biometric data or call ever reaches the backend.

**Given** Face ID/Touch ID is available and enabled
**When** I open the app
**Then** the OS biometric prompt appears and, on success, routes me straight to Home/Chat.
**And** `features/vault/domain` exposes a `VaultStatus` stream the same way `features/auth/domain` exposes `SessionStatus` (AD-8 pattern), registered once in DI.

### Story 2.2: Biometric-Failure Fallback to PIN

As a user whose biometric check fails,
I want to fall back to entering a PIN,
So that I'm never locked out of my own journal.

**Acceptance Criteria:**

**Given** Face ID/Touch ID fails to recognize me
**When** the failure is reported
**Then** "Não foi possível reconhecer — digite seu PIN" appears with a PIN entry path always reachable — never a dead end.

**Given** repeated biometric failures trigger an OS-level lockout
**When** that lockout is detected
**Then** the app routes to its own PIN fallback rather than retrying against the OS.

**Given** the PIN keypad (3×4 grid + backspace, progress dots, structural palette only, UX-DR14)
**When** I enter the 4th digit
**Then** the app auto-advances 350ms later with no explicit "confirm" tap (UX-DR27).
**And** the screen-reader announces the failure transition per the Accessibility Floor (UX-DR21), and the keypad's digits remain legible at the largest Dynamic Type size without truncation (UX-DR22).

### Story 2.3: Fixed 5-Minute Idle Re-Authentication Timeout

As a user,
I want re-authentication required only after 5 minutes backgrounded,
So that casual app-switching doesn't interrupt me but a forgotten unlocked phone stays protected.

**Acceptance Criteria:**

**Given** the app is backgrounded for less than 5 minutes
**When** I resume it
**Then** no re-authentication is prompted.

**Given** the app is backgrounded for 5 minutes or more
**When** I resume it
**Then** re-authentication is always prompted, regardless of any user setting — this value is fixed, not user-configurable.
**And** this timeout is implemented as a fixed parameter within `features/vault/domain`, not as a shared `core/` constant, and is never re-tuned by any later story.

### Story 2.4: Biometric Preference Persistence

As a user,
I want to enable or disable the biometric gate from a setting that persists across restarts and reinstalls,
So that my preference travels with my account, not just my device.

**Acceptance Criteria:**

**Given** I toggle biometric gating on or off
**When** the toggle is changed
**Then** `PATCH /account/settings` persists the preference server-side, surfacing the Failure contract on error.

**Given** I disable biometrics
**When** I next open the app
**Then** PIN remains available as the access method — the vault itself can never be turned off entirely.

**Given** I reinstall the app or restart it after changing this setting elsewhere
**When** the app loads
**Then** the preference is fetched from the account, not read from a stale local-only cache.
**And** this story introduces a minimal Configurações screen (replacing Epic 1's placeholder) containing only this toggle — Epic 8 extends this same screen with profile editing, the dashboard, and account actions; it is never recreated from scratch.

## Epic 3: Multimodal Capture & Processing

Users can capture a journal Entry as text, voice, or photo — with audio transcribed on-device and photos OCR'd server-side before the Entry is ever persisted — and interrupting a capture never leaves a stray partial Entry behind.

### Story 3.1: Text Entry Capture & Insertion Modal Shell

As a user,
I want to open the "+" control and type free text to save as a journal Entry,
So that I can quickly capture what happened today in writing.

**Acceptance Criteria:**

**Given** I tap "+" on Home/Chat
**When** the Insertion Modal opens
**Then** it opens on the Texto tab by default with a three-segment tab bar (Texto/Áudio/Foto, UX-DR11) and all three tabs reset to idle/empty.

**Given** I type text and tap Salvar
**When** the save completes
**Then** `POST /entries` fires with `source=manual` and the modal closes, returning me to where I was.

**Given** `features/entries/` does not yet exist
**When** this story is built
**Then** it introduces `entries/domain` owning the `Entry` entity, the `EntriesRepository` port (`create`), and the entries Hive box (AD-6) — this story is the first consumer of that port, never building its own local Entry model.

**Given** the device is offline
**When** I tap "+"
**Then** the entry point is disabled with the same offline-banner treatment as chat send (UX-DR30, AD-9) — there is no local-only queued write.
**And** interrupting before Salvar (closing the modal, switching tabs) never fires `POST /entries` (FR-11 — see Story 3.4 for the full cross-tab rule).

### Story 3.2: Audio Entry Capture & On-Device Transcription

As a user,
I want to record audio in the Insertion Modal and have it transcribed on-device,
So that I can speak my day instead of typing it, without my voice ever leaving my phone.

**Acceptance Criteria:**

**Given** the Áudio tab
**When** I start recording
**Then** an animated waveform (UX-DR12) shows in the structural palette with a mono counter ticking up.

**Given** I stop recording
**When** `whisper_ggml` transcribes on-device
**Then** the waveform freezes at 35% opacity (UX-DR12) and exactly four states occur in sequence: recording → processing → transcribed → (on failure) error with retry — media is never discarded on failure.

**Given** transcription completes
**When** I review the text
**Then** it is editable before I tap Salvar, and the resulting Entry carries `source=audio`.

**Given** the audio file at any point in this pipeline
**When** any network call is inspected
**Then** no call ever contains audio bytes — transcription is 100% on-device (FR-12).
**And** the screen-reader announces each transition ("Gravando," "Transcrevendo," "Erro ao transcrever, toque para tentar novamente") per UX-DR21.

### Story 3.3: Photo Entry Capture & Backend OCR

As a user,
I want to capture or select a photo in the Insertion Modal and have its text recognized,
So that I can save a physical note or receipt-like artifact without retyping it.

**Acceptance Criteria:**

**Given** the Foto tab
**When** I capture or select a photo
**Then** it is sent to `POST /media/ocr` to extract text before the Entry is created, mirroring the audio pipeline's four-state pattern (capture → processing OCR → recognized → error).

**Given** OCR fails with `OCR_NO_TEXT`
**When** the error state shows
**Then** it is presented as a distinct, non-retryable outcome with two recovery paths — "Tentar novamente" (re-invokes OCR on the same photo) and "Salvar só a foto" (saves the record with no extracted text) — never a single generic failure.

**Given** recognized text
**When** I review it
**Then** it is editable before I tap Salvar, and the resulting Entry carries `source=photo`.

**Given** the photo exceeds the upload size limit
**When** `PAYLOAD_TOO_LARGE` (413, non-retryable) is returned
**Then** a size-specific error message is shown with no retry button, since retrying the same oversized file cannot succeed.

### Story 3.4: Cancel-Safe Capture Across All Tabs

As a user,
I want interrupting a capture in progress to never create a partial Entry,
So that I never end up with junk in my journal from a capture I abandoned.

**Acceptance Criteria:**

**Given** a recording or OCR/transcription in progress
**When** I switch to a different Insertion Modal tab
**Then** the in-flight capture is canceled outright — no partial Entry is created (resolves PRD OQ-3).

**Given** I back out of the modal mid-photo or stop a recording before tapping Salvar
**When** the modal closes
**Then** no `POST /entries` call fires for the abandoned capture.

**Given** any of the three tabs
**When** a capture is interrupted
**Then** it is the Insertion Modal's own internal tab state that resets — the three tabs remain internal states of one sheet, never nested sheets (UX-DR36).

## Epic 4: Timeline & History

Users can see every Entry they've ever captured, from any source, in one chronological view with a live per-entry sync status — and never lose track of something they wrote, even offline or mid-session-expiry.

### Story 4.1: Chronological Entry List with Origin Marking

As a user,
I want to see every Entry I've ever captured, from any source, in one chronological list grouped by date,
So that I never lose track of something I wrote.

**Acceptance Criteria:**

**Given** Entries from manual, audio, and photo sources
**When** Meus Registros loads
**Then** all Entries are listed together grouped by date, each visually marked with its origin via the record card's spine color (manual=`colorPrimary`, audio=olive green, photo=gray — chat=`colorAccent` reserved for Epic 6, UX-DR18).

**Given** the list is loading
**When** the `GET /entries` call takes longer than 300ms
**Then** skeleton rows show (UX-DR17); under 300ms, no loading UI appears at all (RNF01).

**Given** the session expires while I'm viewing this screen
**When** the FR-2 overlay (built in Epic 1) appears
**Then** it does so without crashing or losing my scroll position (FR-17).

**Given** the entries Hive box
**When** Entries are cached locally
**Then** it stores exactly what the server returned, keyed by id — no local filtering, joining, or sorting of the cached collection (AD-15).
**And** no swipe gesture is ever implemented on a record card — Entries are immutable, so no gesture may imply an edit or delete that doesn't exist (UX-DR28).

### Story 4.2: Per-Entry Sync Badge

As a user,
I want to see at a glance whether each Entry has synced,
So that I know whether my capture is safely saved.

**Acceptance Criteria:**

**Given** a freshly created Entry
**When** its write is in flight
**Then** its badge shows "Synchronizing" (ochre dot) until the server's write confirmation is reconciled, then flips to "Synchronized" (green dot).

**Given** a write fails (network or any Failure-contract code)
**When** the badge renders
**Then** it shows "Synchronization error" (red dot) until a subsequent successful write reconciles it.

**Given** the badge is in the error state
**When** I tap it
**Then** it retries that entry's write if the underlying code is retryable, or shows an inline explanation instead of a retry affordance if it is not (resolves PRD OQ-6).

**Given** one derivation function in `entries/domain`
**When** any screen renders a sync badge
**Then** it consumes that function's output, computed from `Entry.serverRevision`, `Entry.updatedAt`, and transient per-entry write state — no screen recomputes the badge inline (AD-10).
**And** the badge's dot color is always paired with an accessible label reachable on tap/long-focus, and its tappable retry area is ≥44pt even though the dot itself is small (UX-DR7, UX-DR23) — color never carries the state alone.
**And** the badge's update stream runs independently of the auth/session stream — a pending sync-badge transition is never blocked or cleared by session-expiry handling.

### Story 4.3: Empty-State Handling

As a user with no Entries yet,
I want a dedicated empty state instead of a blank list,
So that the app guides me back to capture rather than looking broken.

**Acceptance Criteria:**

**Given** zero Entries exist
**When** Meus Registros loads
**Then** a dedicated empty state renders — never a blank list.

**Given** the empty state
**When** I look for a way forward
**Then** it offers a path back to capture (a CTA that opens the Insertion Modal).

### Story 4.4: Entry Detail View

As a user,
I want to open a single Entry to see its full content,
So that I can review exactly what I wrote without any risk of accidentally changing it.

**Acceptance Criteria:**

**Given** an Entry in the list
**When** I open it
**Then** `GET /entries/:id` fetches and displays its full content with no edit affordance anywhere on the screen — Entries are immutable, and `EntriesRepository` exposes create and read only; no update/delete method is ever added (AD-11).

**Given** an Entry that doesn't exist or belongs to another user
**When** the detail request is made
**Then** the backend returns `NOT_FOUND`, never a permission-denied code, and the UI shows the same not-found treatment either way (RNF04).

**Given** this screen composes auth status, Sync Badge state, and Entry data
**When** those three streams are combined
**Then** they combine only through the domain layer — no BLoC in this feature imports another BLoC directly (AD-7, feature-specific NFR).

## Epic 5: Semantic Search & Filtering

Users can find any Entry again by meaning — not just exact keyword match — and narrow results by source and date range, with search debounced and filters clearing back to the full list without a reload.

### Story 5.1: Semantic Search with Debounced Input

As a user,
I want to search my Entries by meaning, not just exact words,
So that I can find things I wrote even if I phrased them differently.

**Acceptance Criteria:**

**Given** I type "ansiedade" into the search bar
**When** results return
**Then** they include an Entry that only used a related but different word (e.g., "nervosismo") because the match is semantic (`GET /entries/search`), not literal.

**Given** I am typing
**When** each keystroke lands
**Then** the request is debounced by 300ms before firing — no request fires on every keystroke.

**Given** the search bar component (UX-DR9)
**When** it renders
**Then** it is permanently docked at the top of Meus Registros with a trailing funnel icon and is never submitted with a button.

**Given** I am offline
**When** I attempt a semantic search
**Then** it resolves to `Failure.networkOffline` immediately — there is no client-side vector index to fall back to, so it is never served from cache, unlike plain entry reads (AD-9 search carve-out).

### Story 5.2: Metadata Filters

As a user,
I want to filter my Entries by source and date range,
So that I can narrow down to just the Entries I care about.

**Acceptance Criteria:**

**Given** no active search term
**When** I apply a source and/or date-range filter
**Then** `GET /entries` is queried with those filter parameters.

**Given** multiple active filters
**When** they combine
**Then** they use AND semantics — no tag/category filter exists, since categorization is an extension feature.

**Given** the filter chip component (UX-DR8) and filter sheet (UX-DR10)
**When** filters are active
**Then** chips render as removable, and the sheet itself is a `radiusLg`/`elevation2` bottom sheet with groups labeled in `textMonoCaption`.

### Story 5.3: Combined Search + Filter & Non-Disruptive Clearing

As a user,
I want my search term and my active filters to work together, and clearing them to feel instant,
So that filtering never feels like it's fighting my search.

**Acceptance Criteria:**

**Given** an active search term and active filters set simultaneously
**When** results are requested
**Then** `GET /entries/search` is queried carrying the same filter parameters, combined with AND logic (resolves PRD OQ-7, UX-DR29).

**Given** active filters
**When** I clear them
**Then** the full list is restored in place, without a full screen reload.

**Given** a reconnect after being offline
**When** the cache resyncs
**Then** it stays duplicate-free — no Entry appears twice because of a reconnect.

## Epic 6: Conversational Memory, Save-to-Journal & Insights

Users can have a persistent, multi-session conversation with an assistant that answers grounded in their own past Entries, turn their own reflective messages into real Entries with one tap, and occasionally receive an unprompted insight about a pattern in their writing — none of which ever blocks or corrupts the core chat experience when it fails.

### Story 6.1: Send Message & Receive RAG-Grounded Streaming Response

As a user,
I want to send a message to the assistant and get a response grounded in my own past Entries,
So that I feel genuinely understood rather than getting a generic reply.

**Acceptance Criteria:**

**Given** I type a message referencing something from weeks ago and send it
**When** the response streams in via SSE on `POST /chat/sessions/:id/messages`
**Then** it is grounded in semantic retrieval over my own Entries — not a stateless generic answer.

**Given** the response is streaming
**When** it renders
**Then** exactly three visible states exist: streaming/processing (progressively revealed text behind a blinking cursor, chat-bubble component UX-DR4), error, complete.

**Given** a Chat Message is sent
**When** it completes
**Then** it never automatically creates an Entry — RF10 (Story 6.4) is the sole, explicit exception.
**And** if Reduce Motion is enabled, the cursor-blink animation is skipped and the final text shows immediately instead (UX-DR24).

### Story 6.2: Multi-Session Chat History & New Conversation

As a user,
I want to hold multiple named conversations and start a new one whenever I want a fresh start,
So that my chat history stays organized by topic or moment.

**Acceptance Criteria:**

**Given** I have existing Chat Sessions
**When** I open the side menu
**Then** they are listed and I can switch between them.

**Given** I tap "Novo Chat" from the side menu
**When** a new session starts
**Then** it opens empty with the composer focused and the placeholder "Escreva uma mensagem..." — no greeting copy invented beyond that.

**Given** I am offline
**When** I attempt to start a new Chat Session
**Then** `POST /chat/sessions` is blocked, consistent with the offline composer lock on existing conversations.
**And** a returning (not new) session restores the last conversation's scroll position when I open it.

### Story 6.3: Dropped-Stream Resilience & Offline Composer Lock

As a user,
I want a dropped response or an offline moment to never cost me my place in the conversation,
So that a flaky connection never feels like data loss.

**Acceptance Criteria:**

**Given** a response stream drops mid-generation
**When** the failure is detected
**Then** the partial message stays on screen with a failure indicator (timestamp slot replaced by red retry copy, bubble content never cleared).

**Given** a dropped stream
**When** I tap retry
**Then** `POST /chat/sessions/:id/messages/:userMessageId/retry` regenerates the response without duplicating my original question.

**Given** I am offline
**When** I view Home/Chat
**Then** the composer is disabled with the offline banner shown (UX-DR19), while existing conversation history stays visible and fully navigable/scrollable.

### Story 6.4: Bookmark a Chat Message into an Entry

As a user,
I want to turn my own reflective chat message into a real journal Entry with one tap,
So that I don't have to retype something I already said well.

**Acceptance Criteria:**

**Given** one of my own Chat Messages (never an AI response)
**When** I tap the bookmark affordance
**Then** it creates an Entry (`source=chat`, carrying `chatMessageId`) through the same shared entries use case Epic 3 introduced — never by importing the entries repository or data source directly (RNF06, AD-6).

**Given** this story is the first consumer of `core/isolated_side_effect.dart`
**When** the save executes
**Then** it runs through the never-throws `isolatedSideEffect` helper (AD-13), awaited before the button's state updates.

**Given** the bookmark button's four states (idle/saving/saved/error, UX-DR6)
**When** I tap a message already in the `saved` state
**Then** it is a no-op — the backend returns 200, not 409, and no duplicate Entry is ever created (FR-29 idempotency).

**Given** a save fails
**When** the error state shows
**Then** the surrounding Chat Session remains fully usable and the button resets to a retryable state rather than freezing (FR-30).
**And** state is carried by icon + color together on the bookmark button, never color alone (UX-DR6, Accessibility Floor).

### Story 6.5: Proactive Insight Injection & Failure Isolation

As a user,
I want the assistant to occasionally point out a pattern in my own writing without me having to ask,
So that the memory the product promises actually becomes visible to me.

**Acceptance Criteria:**

**Given** either 5 user messages sent or 2 minutes of inactivity (whichever occurs first) within the active Chat Session
**When** that condition is satisfied
**Then** `POST /chat/sessions/:id/insight` injects an Insight once per satisfied condition — never both, never twice for the same window.

**Given** the Insight card (ochre spine, mono "INSIGHT" label, dismiss "x," UX-DR5)
**When** it appears
**Then** it is interleaved into the chat stream as the only accent-colored element inside it.

**Given** Insight generation fails
**When** the failure occurs
**Then** it is handled fire-and-forget via the `isolatedSideEffect` helper from Story 6.4 (AD-13) — the composer remains enabled, no error overlay appears, and ordinary chat messages (Story 6.1) keep working uninterrupted.

**Given** an Insight is visible
**When** I dismiss it
**Then** scroll position and all other conversation state are unaffected.
**And** this Insight overlay is a value appended onto the existing chat state from Story 6.1, never a parallel `Resource<T>` (AD-12).

## Epic 7: Personal Summary Export

Users can request a narrative PDF + raw-data export for any date period, and always get their raw data even if the AI-generated narrative fails or the period turns out to be empty.

### Story 7.1: Request a Period Export & Job Status Tracking

As a user,
I want to request an export for a chosen date period and see its progress,
So that I know what's happening while a narrative + data package is being prepared.

**Acceptance Criteria:**

**Given** I tap the download icon on Meus Registros and select a period
**When** I confirm
**Then** `POST /export/summary` creates the job and the export sheet opens (UX-DR15, `radiusLg`/`elevation2`).

**Given** the job is in progress
**When** I poll via `GET /export/:jobId/status`
**Then** the sheet reflects exactly five states — Pendente, Processando, Concluído, Erro, Período vazio — reporting `status` (job) and `narrativeStatus` (AI summary) independently.

**Given** a stage changes
**When** the sheet updates
**Then** it replaces its content in place — the sheet itself never closes and reopens mid-job.

### Story 7.2: Narrative-Independent Raw-Data Download

As a user,
I want my raw data available as soon as it's ready, even if the AI summary is still working or has failed,
So that my export is never held hostage by a model call.

**Acceptance Criteria:**

**Given** raw data finishes before the narrative
**When** this hybrid state occurs (`status=data_ready`, `narrativeStatus=processing`)
**Then** "Baixar dados brutos" is already enabled and downloadable via `GET /export/:jobId/download` while the summary-progress text keeps showing underneath — never withheld waiting on the narrative (UX-DR34).

**Given** the narrative step fails or is skipped
**When** the job otherwise completes (`status=done`)
**Then** "Baixar dados brutos" remains enabled and error copy is framed around the narrative only.

**Given** the narrative succeeds
**When** the job completes fully
**Then** "Resumo pronto" shows with both downloads (PDF narrative + raw data) available.

### Story 7.3: Empty-Period Handling

As a user who requests an export for a period with no Entries,
I want a clear "nothing to export" message instead of a crash or a silent failure,
So that I understand why there's nothing to download.

**Acceptance Criteria:**

**Given** I request an export for a period with zero Entries
**When** the job resolves
**Then** `EXPORT_EMPTY_PERIOD` surfaces as "Período vazio" with no download button offered and no crash.

**Given** this error state
**When** I view it
**Then** it suggests adjusting the filter/period rather than leaving me with a dead end.

## Epic 8: Evolution Dashboard & Account Management

Users can see an on-demand chart of their journaling activity with an independent AI narrative, edit their display name, log out, and permanently delete their account and all associated data.

### Story 8.1: On-Demand Dashboard Aggregation Across Entry Counts

As a user,
I want to see a chart of my journaling activity whenever I open Settings,
So that I can notice my own patterns over time.

**Acceptance Criteria:**

**Given** I open Configurações
**When** the screen renders
**Then** `GET /dashboard/aggregate` computes and renders an evolution chart on demand — not from a stale cache.

**Given** zero Entries exist
**When** the dashboard renders
**Then** it shows a placeholder chart icon and "Comece a registrar..." with no summary paragraph (there's nothing to summarize).

**Given** exactly one Entry exists
**When** the dashboard renders
**Then** it shows a single bar and "Ainda é cedo pra ver um padrão...".

**Given** more than 30 Entries exist
**When** the dashboard renders
**Then** it shows a 10-bar chart — the independent AI narrative paragraph is added alongside it by Story 8.2, not by this story.

**Given** a new Entry is created anywhere in the app
**When** I return to or am already on this screen
**Then** the aggregation recalculates — invalidation triggers only on create, since Entries are immutable and are never edited (FR-40).
**And** this story extends the minimal Configurações screen stub from Epic 2 (Story 2.4) rather than recreating it, adding the persona toggle placeholder (Analítico/Empático/Socrático cards) styled with full visual polish but with no effect on assistant behavior — a cosmetic extension-feature toggle only (UX-DR32); the screen uses `Resource<T>` (AD-12) since it is a single-source, single-fetch-lifecycle screen.

### Story 8.2: Independent Narrative Text & Narrative-Unavailable State

As a user,
I want a plain-language narrative alongside my chart, and a clear message if just the narrative fails,
So that I'm never confused about whether I have no data or just a broken summary.

**Acceptance Criteria:**

**Given** the chart has rendered with data
**When** `GET /dashboard/narrative` resolves
**Then** the narrative text appears below the chart as its own independent fetch.

**Given** the narrative call fails while the chart has data
**When** this happens
**Then** the chart still renders normally and a distinct "narrative unavailable" message shows — never a blank space, and never confused with the zero-Entries empty state (UX-DR33).

### Story 8.3: Profile Name Editing

As a user,
I want to fix my display name inline without leaving Settings,
So that a quick typo fix doesn't feel like a whole separate task.

**Acceptance Criteria:**

**Given** I tap the pencil icon beside my name
**When** the field becomes editable
**Then** the pencil icon becomes a check icon — the only place in the product where an icon itself changes meaning rather than just color (UX-DR13).

**Given** I edit the name and confirm
**When** I save
**Then** `PATCH /account/settings` commits the change and the field reverts to display mode.

**Given** I tap elsewhere without confirming
**When** focus leaves the field
**Then** it also reverts to display mode — no separate "edit profile" screen exists.
**And** the 52px Settings avatar reuses the same avatar component built in Epic 1 (Story 1.6), not a reimplementation, now at its second fixed size.

### Story 8.4: Logout

As a user,
I want to log out cleanly,
So that I can hand my phone to someone else or step away without leaving my journal open.

**Acceptance Criteria:**

**Given** I tap "Sair"
**When** the action completes
**Then** `POST /auth/logout` ends the session and I'm routed to the Biometric Vault / login screen.

### Story 8.5: Account Deletion

As a user,
I want to permanently delete my account and all my data,
So that I retain genuine control over something this personal.

**Acceptance Criteria:**

**Given** I tap "Apagar conta"
**When** the confirmation dialog appears
**Then** it uses the destructive variant (red `colorError` title, UX-DR16) — the title color is the only signal distinguishing this from a routine interruption like session expiry, so it must never be muted.

**Given** I confirm deletion
**When** `DELETE /account` completes
**Then** my account and all associated data are hard-deleted (LGPD-driven, RNF05) and I'm routed to the same destination as logout.

**Given** the confirmation dialog is open
**When** I try to interact with anything behind the scrim
**Then** focus is trapped until I dismiss or confirm (UX-DR25, reusing the same focus-trap behavior as Epic 1's session-expired overlay).
