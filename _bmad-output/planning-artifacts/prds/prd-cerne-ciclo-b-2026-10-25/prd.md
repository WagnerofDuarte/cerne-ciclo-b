---
title: Cerne
status: final
created: 2026-10-25
updated: 2026-10-26
---

# PRD: Cerne

## 0. Document Purpose

This PRD defines the product the Cerne Flutter app must become, built on `docs/input/requirements.md` (the frozen product specification), `docs/input/prototype/` (the frozen visual/screen reference), and `docs/input/backend/` (the frozen, already-built API contract). It also builds on three prior planning artifacts for this project — a product brief, a Working-Backwards PRFAQ, and an F000 technical-decisions forge session — without duplicating them; where those documents already settled something, this PRD states the conclusion and points back rather than re-deriving it. Implementation-level rationale (package choices, rejected alternatives, market-sizing detail, regulatory citations) lives in `addendum.md`, not here.

The document is structured so downstream work — UX specification, architecture, and epic/story breakdown — can reference it by stable ID: Functional Requirements are numbered globally (FR-1 through FR-43) regardless of which feature section they sit in, User Journeys are numbered UJ-1 through UJ-6, and Success Metrics SM-1 onward. Terms introduced in §3 Glossary are used verbatim everywhere else in this document.

Audience: the solo author, acting across PM/UX/architecture/dev roles for this capstone (TCC) project, and the academic reviewers who evaluate it. `[ASSUMPTION: ...]` tags mark places this PRD inferred something the source documents left unstated; see §9 for the full index.

The single most consequential unknown for downstream sequencing: no project timeline, deadline, or defense date is stated anywhere in the source documents (§8 OQ-1).

## 1. Vision

Cerne is a reflective-journaling mobile app whose AI assistant actually remembers the user. The user captures their day by text, voice, or photo; a conversational agent then answers using retrieval-augmented generation over that person's own past entries — not the stateless, generically-worded responses that dominate the AI-journaling category today. The product's bet is narrow and deliberate: not a bigger feature set than competitors, but a better memory.

Cerne is explicitly not a mental-health or clinical tool. It makes no diagnostic claims, detects no risk signals (self-harm or suicidal ideation), and is positioned so a user processing their day through writing is never made to feel they are being monitored or clinically assessed. This is a product stance, not just a legal fence — current regulatory pressure on "AI companion" chatbots makes a non-clinical, non-companion framing a timing advantage as well as a safety one.

Within this project's boundary, "done" means a working, fully tested iOS app that proves the RAG-memory differentiator end-to-end against the real (frozen) backend — covering capture, processing, chat, search, export, and account management — while leaving three named extension features (§5) as inert placeholders rather than attempting partial, half-working versions of them.

## 2. Target User

### 2.1 Jobs To Be Done

`[ASSUMPTION: reconstructed from the product brief and PRFAQ, not stated verbatim in docs/input — confirm or replace.]`

The target user is a Portuguese-speaking adult already in the habit of processing their day through writing or talking to an AI, frustrated that neither medium remembers them between sessions.

- **Functional** — capture what happened today in whichever mode is fastest in the moment (typing, speaking, or photographing a physical note/receipt-like artifact), without re-explaining context the app should already have.
- **Emotional** — feel understood in light of one's own history, not answered with a generic response that could apply to anyone.
- **Social/contextual** — maintain a private record that stays private; a quiet fear this persona carries is that a personal diary could be mined, sold, or silently reinterpreted as a mental-health signal.
- **Explicitly not** — seeking therapy, diagnosis, or a "companion" relationship with the AI; this user would be put off by anything implying they need clinical help.

### 2.2 Non-Users (v1)

- Users seeking a clinical, diagnostic, or crisis-support tool — out of scope by design (§5).
- Users who need to edit or delete past Entries, or journal fully offline — Entries are immutable and writes are cloud-only (backend constraint; see §5, §8 OQ-5).
- Android users — platform is iOS, portrait-only, for this delivery.
- Users seeking AI-automated organization (auto-categorization, auto-extracted goals) — these exist only as static placeholders (§5).

### 2.3 Key User Journeys

- **UJ-1. Mara unlocks the app and captures her day before bed.**
  - **Persona + context:** `[ASSUMPTION]` Mara, journals most nights, phone always nearby, wants capture to take under 30 seconds.
  - **Entry state:** app backgrounded since this morning (>5 min), biometric vault active.
  - **Path:** opens app → Tela 0 splash auto-advances → Tela 0.1 Biometria prompts Face ID → succeeds → Home/Chat. Taps "+" → Insertion Modal opens on the Texto tab → she switches to Áudio, records 40 seconds → recording stops → "Processando" → on-device transcription completes → "Transcrito" text shown → taps Salvar.
  - **Climax:** the Entry appears, saved, with no round-trip to a server required for the transcription step itself.
  - **Resolution:** modal closes, she's back on Home/Chat; the Entry now exists for RF07 (timeline) and RF06 (search) to surface later.
  - **Edge case:** Face ID fails twice → "Usar PIN" link → Tela 0.1b/0.1c PIN flow, no lockout (FR-5).

- **UJ-2. Mara asks the assistant about a pattern she's noticed.**
  - **Entry state:** authenticated, on Home/Chat, has weeks of prior entries.
  - **Path:** types a question referencing something she wrote about weeks ago → sends → streaming response begins, grounded in RAG over her own Entries (not a generic answer) → response completes.
  - **Climax:** the response correctly surfaces something specific from her own history — the core differentiator (§1) made concrete.
  - **Resolution:** conversation continues naturally; she can keep chatting or start a new conversation from the side menu.
  - **Edge case:** the stream can drop mid-response, and separately her session can expire mid-conversation — either way she can recover (retry, or "Entrar novamente") without losing the thread of what she was saying (FR-2, FR-26).
  - **RF08 note:** this same conversation surface is also where an Insight (RF08) can arrive unprompted, without Mara having asked for it — the mechanism realizes this journey rather than a separate one.

- **UJ-3. Mara saves something she said in chat as a proper journal entry.**
  - **Entry state:** mid-conversation, has just written a reflective message of her own.
  - **Path:** taps the bookmark affordance on her own message (never available on the AI's replies) → saving state shown → saved.
  - **Climax:** the message now exists as a real Entry (source=`chat`), reachable later from the timeline and search, without her having to retype it.
  - **Resolution:** chat continues uninterrupted either way.
  - **Edge case:** tapping save twice, or a save that fails, both leave the chat fully usable and recoverable (FR-29, FR-30).

- **UJ-4. Mara looks for everything she wrote about feeling anxious before a specific event.**
  - **Entry state:** on Meus Registros (timeline), has Entries from text, audio, and photo sources.
  - **Path:** types a word like "ansiedade" into the search bar → results return Entries that used related but different wording (e.g. "nervosismo") because the match is semantic, not literal → she narrows further with the filter sheet (date range, source) → active filters shown as removable chips.
  - **Climax:** she finds Entries she could not have found with exact-keyword search, from an origin (audio transcript) she'd forgotten she used.
  - **Resolution:** clears filters → full list restored without a screen reload.
  - **Edge case:** no results for the period → the screen's empty state, distinct from the "no entries at all" empty state (§4.5 FR-16), still offers a path back to capture.

- **UJ-5. Mara exports a narrative summary of her last three months before a personal check-in with herself.**
  - **Entry state:** on Meus Registros, taps the download icon.
  - **Path:** selects a period → export sheet shows "Pendente" → "Processando" → either "Concluído" (both PDF narrative and raw data downloadable) or, if only the AI narrative step failed, raw data remains downloadable while the narrative is marked unavailable — the job is never blocked end-to-end by a narrative failure.
  - **Climax:** she gets a readable, honest reflection of her last three months, or at minimum her raw data, every time she asks.
  - **Resolution:** closes the sheet via "Fechar."
  - **Edge case:** she picks a period with zero Entries → "Período vazio" state, no crash, no download offered (FR-37).

- **UJ-6. Mara checks her settings Dashboard, then eventually decides to leave.**
  - **Entry state:** on Configurações.
  - **Path:** Dashboard renders a chart + narrative computed on demand; she edits her display name inline; much later, in a separate session, she decides to stop using the app and taps "Apagar conta," confirms in the red dialog.
  - **Climax:** her account and data are hard-deleted, consistent with the "this is genuinely mine to remove" expectation a journaling app sets.
  - **Resolution:** routed back to the Biometric Vault / login screen, same as logout (no dedicated confirmation screen exists for either flow — §8 OQ-4).
  - **Edge case:** Dashboard has data but the AI-generated narrative specifically failed to generate — a distinct state from "zero Entries," since the chart still renders (FR-39).

## 3. Glossary

- **Entry** — A persisted journal record created via one of four sources: `manual` (text), `audio`, `photo`, or `chat` (via RF10). Immutable once created — no edit or delete operation exists. Always created through `POST /entries`.
- **Chat Session** — A persistent, named conversation thread with the AI assistant. A user may hold multiple sessions, switchable from the side menu.
- **Chat Message** — A single turn within a Chat Session; distinct from an Entry unless explicitly saved via RF10 (Save Chat Message as Entry).
- **Insertion Modal** — The bottom-sheet UI, opened from the "+" control on Home/Chat, through which all Entries are captured (Texto / Áudio / Foto tabs).
- **Sync Badge** — A per-Entry UI indicator with exactly three states: *Synchronizing*, *Synchronization error*, *Synchronized*. Derived entirely client-side from `Entry.updatedAt` and `Entry.serverRevision`; the backend has no `sync_status` field.
- **Insight** — An AI-generated message the assistant injects into a Chat Session unprompted, per RF08's trigger conditions.
- **Export Job** — An asynchronous job (RF05) producing a narrative PDF and/or raw-data download for a date period; tracked by independent `status` (job) and `narrativeStatus` (AI summary) fields.
- **Dashboard** — The evolution chart + narrative text on the Configurações screen (RF09), computed on demand when the screen opens.
- **Biometric Vault** — The RF03 access barrier (Face ID / Touch ID / PIN) gating the whole app, validated on-device; has no backend counterpart beyond a stored preference.
- **Extension feature** `[ext]` — A feature named in requirements.md §2 as explicitly out of scope for this delivery; its UI exists only as an inert placeholder (§5).
- **Failure contract** — The `{ code, message, retryable }` shape returned by every backend error (13 closed codes; see §Cross-Cutting NFRs), consumed by every repository as `Either<Failure, T>`.

## Information Architecture

- **Entrance/auth surfaces:** Splash (auto-advance) → Biometric Vault (Face ID/Touch ID, PIN fallback) → Login/Signup (single screen, toggled).
- **Home/Chat** is the base authenticated surface, with three overlays that can appear on top of it without navigating away: the Sessão Expirada overlay (FR-2), an offline banner (FR-27), and the Insertion Modal (§4.3). The side menu (☰), opened from here, leads to Chat Session switching, Meus Registros, Configurações, and Planos de Ação `[ext]`.
- **Meus Registros (timeline)** carries its own overlay: the Export sheet (§4.10), plus an inline filter sheet and search bar (§4.6).
- **Configurações** hosts the dashboard (§4.11), inline profile editing, and the account-deletion confirmation dialog (§8 OQ-4).

## 4. Features

*Where an FR's testable condition is a single, self-evident clause, it is folded into the FR's statement itself rather than broken out into a separate Consequences block; the separate block is used once an FR needs more than one distinct, checkable condition.*

### 4.1 Foundation & Session Management

**Description:** The scaffold every other feature depends on: an authenticated-session lifecycle, the app shell and base navigation, and the one cross-cutting overlay — the Sessão Expirada overlay — that can interrupt any screen. Delivered first (F000) because every unit after it assumes these exist. Realizes UJ-1, UJ-2 (edge case).

#### FR-1: Account creation and authentication

A user can create an account and log in with email/password, and the app can silently refresh or verify the session without forcing a re-login on every app open.

**Consequences (testable):**
- Signup, login, refresh, and session-check each round-trip through their respective backend operations and surface the Failure contract on error.
- A valid, unexpired session persists across app restarts without re-prompting for credentials.
- `[ASSUMPTION]` Signup collects email + password only, matching the single-screen toggle shown in the prototype (no password-confirmation or display-name field) — see §8 OQ-2.

#### FR-2: Expired-session recovery overlay

When the backend reports an expired session, the app shows a "Sessão expirada" overlay on top of the current screen rather than navigating away from it.

**Consequences (testable):**
- The screen underneath (including scroll position and in-progress state, e.g. an open chat) is preserved while the overlay is shown.
- "Entrar novamente" routes to the biometric/PIN re-auth flow (RF03), not a full logout-and-login form.
- The overlay can appear while viewing the timeline (RF07, called out explicitly in requirements.md as session-dependent) or chat (RF04, shown as the "Sessão expirada" state in `prototype-extract.md`).

#### FR-3: Base navigation shell

The app provides navigation between Home/Chat, the side menu, Meus Registros, and Configurações, with clearly marked placeholders for RF01–RF10 functionality not yet built in this unit.

**Consequences (testable):**
- All four surfaces are reachable from app launch without requiring any RF01–RF10 feature to be implemented.
- Placeholders are visually distinguishable from finished screens (no silent dead ends that look complete).

---

### 4.2 Biometric Authentication Vault (RF03)

**Description:** A device-validated access barrier in front of all user data. Realizes UJ-1 (entry + edge case).

#### FR-4: App-access gate

The app requires Face ID, Touch ID, or PIN before showing any user data, on cold start and after the idle timeout (FR-6).

**Consequences (testable):**
- No screen other than the vault/login screen is reachable before authentication succeeds.
- No biometric data or biometric call ever reaches the backend — validation is 100% on-device.

#### FR-5: Biometric-failure fallback to PIN

A failed biometric attempt offers PIN entry as an alternative and never locks the user out of their own app.

**Consequences (testable):**
- After a biometric failure, a PIN entry path is always reachable (Tela 0.1c).
- Repeated biometric failures that trigger an OS-level lockout are detected and routed to the app's own PIN fallback rather than retried against the OS.

#### FR-6: Fixed idle re-authentication timeout

Returning to the app from the background after 5 minutes requires re-authentication; this value is fixed, not user-configurable.

**Consequences (testable):**
- Resuming before 5 minutes elapsed does not prompt re-authentication.
- Resuming after 5 minutes always prompts re-authentication, regardless of any user setting.

#### FR-7: Biometric preference persistence

The user's choice to enable/disable biometric gating is saved server-side via `PATCH /account/settings` and survives both app restarts and reinstalls, since the value is fetched from the account, not cached only on-device.

**Consequences (testable):**
- Disabling biometrics still leaves PIN as the access method — the vault itself cannot be turned off entirely.

---

### 4.3 Multimodal Capture (RF01)

**Description:** The single entry point for creating a journal Entry, in text, audio, or photo form, all through the Insertion Modal. Realizes UJ-1.

#### FR-8: Text Entry capture

A user can type free text in the Insertion Modal and save it as an Entry (source=`manual`).

#### FR-9: Audio Entry capture

A user can record audio in the Insertion Modal; the raw recording becomes the basis of an Entry (source=`audio`) once processed (RF02).

#### FR-10: Photo Entry capture

A user can capture or select a photo in the Insertion Modal; it becomes the basis of an Entry (source=`photo`) once processed (RF02).

**Consequences (testable, FR-8 through FR-10):**
- All three modalities produce the same persisted Entry shape — none is structurally special-cased after capture.
- Each call to `POST /entries` carries the correct `source` value for its modality.

#### FR-11: Cancel-safe capture

Interrupting a capture in progress (e.g., stopping a recording before saving, backing out mid-photo) never creates a partial or empty Entry.

**Consequences (testable):**
- No `POST /entries` call fires for an abandoned capture.
- `[OPEN]` Switching tabs mid-recording (e.g. Áudio → Foto) is undefined behavior in the current prototype — see §8 OQ-3.

---

### 4.4 Speech-to-Text / OCR Processing (RF02)

**Description:** Turns raw audio into text on-device, and raw photos into text via the backend, before an Entry is persisted. Realizes UJ-1.

#### FR-12: On-device audio transcription

Recorded audio is transcribed to text entirely on-device via `whisper_ggml`; the audio file itself is never sent to the backend.

**Consequences (testable):**
- Exactly four visible states occur in sequence or on failure: recording → processing → transcribed → (on failure) error with retry, media never discarded.
- No network call containing audio bytes is made at any point in this pipeline.

#### FR-13: Backend OCR for photos

A captured photo is sent to `POST /media/ocr` to extract text before the Entry is created.

**Consequences (testable):**
- Mirrors FR-12's four-state pattern: capture → processing OCR → recognized → (on failure) error with retry, photo never discarded.
- On OCR failure, the user has two recovery paths, not one: retry the OCR step, or save the Entry with no extracted text ("Salvar só a foto") — both are shown in the prototype's OCR-failure state.
- `OCR_NO_TEXT` (no extractable text found) is handled as a distinct, user-visible outcome, not a generic failure.

**Notes:** Test material for both pipelines — sample audio, OCR test images, and expected transcription output — lives in `docs/input/backend/fixtures/`.

---

### 4.5 Multi-Source History / Timeline (RF07)

**Description:** A chronological view of every Entry regardless of origin, each carrying a Sync Badge. Realizes UJ-1 (as the destination for captured entries) and UJ-4 (as the surface search/filter operates on).

#### FR-14: Chronological Entry list

All Entries, from any source, are listed together grouped by date, each visually marked with its origin.

#### FR-15: Per-entry Sync Badge

Each Entry shows one of three Sync Badge states, derived client-side from `updatedAt`/`serverRevision` and local pending-write state — the backend exposes no `sync_status` field.

**Consequences (testable):**
- A freshly created Entry shows "Synchronizing" until the server's write confirmation is reconciled, then "Synchronized."
- A write that fails (network or any Failure-contract code) shows "Synchronization error" until a subsequent successful write reconciles it.
- The badge's update stream runs independently of the auth/session stream — a pending sync-badge transition is never blocked, delayed, or cleared by session-expiry handling (FR-17).
- `[OPEN]` No retry affordance is visible on the error state in the current prototype — see §8 OQ-6.

#### FR-16: Empty-state handling

With zero Entries, the screen shows a dedicated empty state with a path back to capture, not a blank list.

#### FR-17: Session-expiry resilience mid-view

If the session expires while viewing the timeline, the FR-2 overlay appears without crashing or losing scroll position.

#### FR-18: Entry detail view

A user can open a single Entry from the timeline to see its full content, via `GET /entries/:id`.

**Consequences (testable):**
- Opening an Entry never mutates it — there is no edit affordance, consistent with Entries being immutable (§3 Glossary).
- A detail request for an Entry that doesn't exist or belongs to another user returns `NOT_FOUND` (RNF04), not a permission-denied code.

**Feature-specific NFRs:** No BLoC in this feature imports another BLoC directly — the three streams this screen composes (auth status, Sync Badge state, and Entry data) combine only through the domain layer, never via a direct BLoC-to-BLoC reference.

---

### 4.6 Semantic Search / Filter (RF06)

**Description:** Meaning-based search plus metadata filters over the timeline from §4.5. Realizes UJ-4.

#### FR-19: Semantic search

A user can search Entries by meaning, not just literal keyword match (e.g. "ansiedade" matches an entry that only used "nervosismo"), via `GET /entries/search`.

#### FR-20: Metadata filters

A user can filter by source and date range (`dateFrom`/`dateTo`); no tag/category filter exists, since categorization is an extension feature (§5). Filtering with no active search term queries `GET /entries`; filtering combined with an active search term queries `GET /entries/search`, carrying the same filter parameters.

**Consequences (testable, FR-19/FR-20):**
- Multiple active filters combine with AND semantics.
- `[OPEN]` How an active text search and active filters interact when both are set simultaneously is unspecified in the prototype — see §8 OQ-7.

#### FR-21: Debounced search input

Search input is debounced by 300ms before firing a request.

#### FR-22: Non-disruptive filter clearing

Clearing active filters restores the full list in place, without a full screen reload, and the cache stays duplicate-free after a reconnect (cloud-only; offline is view-only for this screen).

**Notes:** Test material (a seeded set of entries with known semantic relationships, for verifying true meaning-based matches) lives in `docs/input/backend/fixtures/seeded-search-entries.md`.

---

### 4.7 Interactive Chat with Memory / RAG (RF04)

**Description:** The core differentiator (§1): a persistent, multi-session conversation where the assistant answers using RAG over the user's own Entries. Realizes UJ-2.

#### FR-23: Send message, receive RAG-grounded streaming response

A user sends a Chat Message and receives a streamed response grounded in semantic retrieval over their own Entries, via SSE on `POST /chat/sessions/:id/messages`.

**Consequences (testable):**
- Exactly three visible states exist: streaming/processing, error, complete.
- Chat Messages never automatically create Entries — RF10 is the sole, explicit exception.

#### FR-24: Multi-session chat history

A user can hold multiple named Chat Sessions, listed and switchable from the side menu.

#### FR-25: New-conversation action

A user can start a new Chat Session from the side menu.

**Consequences (testable):**
- `POST /chat/sessions` is blocked offline — starting a new Chat Session requires connectivity, consistent with the offline composer lock on existing conversations (FR-27).

#### FR-26: Dropped-stream resilience

If a response stream drops mid-generation, the partial message stays on screen with a failure indicator; the user can retry via `POST /chat/sessions/:id/messages/:userMessageId/retry`, which regenerates without duplicating the original question.

#### FR-27: Offline composer lock

When offline, the message composer is disabled while the existing conversation history remains visible and navigable.

---

### 4.8 Save Chat Message as Entry (RF10)

**Description:** Lets a user turn their own Chat Message into a real Entry. Realizes UJ-3. Depends on RF01 and RF04.

#### FR-28: Bookmark a user message into an Entry

A "save" affordance appears only on the user's own Chat Messages (never on AI responses) and, when used, creates an Entry (source=`chat`, carrying `chatMessageId`) through the same shared entries use case RF01 defines — never by importing the entries repository or data source directly (RNF06).

#### FR-29: Idempotent save

Saving the same Chat Message more than once does not create a duplicate Entry and never surfaces a conflict error (the backend returns 200, not 409).

#### FR-30: Save-failure isolation

If the save fails, the surrounding Chat Session remains fully usable, and the save affordance resets to a retryable state rather than freezing.

---

### 4.9 Proactive Insights (RF08)

**Description:** The mechanism by which the assistant injects an unprompted suggestion into the conversation. Scope is the trigger/injection mechanism only — the quality of the generated Insight text is explicitly out of scope for acceptance testing. Realizes UJ-2 (the unprompted-Insight moment within an ongoing conversation). Depends on RF04.

#### FR-31: Unprompted Insight injection

An Insight is injected into the active Chat Session once per satisfied condition — triggered by either 5 user messages sent or 2 minutes of inactivity, whichever occurs first — via `POST /chat/sessions/:id/insight`.

#### FR-32: Insight failure isolation

A failure to generate an Insight does not interrupt or break the main chat experience.

**Consequences (testable):**
- The message composer remains enabled and no error overlay appears over the conversation when Insight generation fails.
- The user can keep sending and receiving ordinary Chat Messages (FR-23) uninterrupted; only the Insight itself is absent.

#### FR-33: Non-disruptive dismissal

Dismissing an Insight does not affect scroll position or any other conversation state.

---

### 4.10 Personal Summary Export (RF05)

**Description:** On-demand generation of a narrative PDF summary plus an always-available raw-data download. Scope is job/file/failure handling only — the quality of the generated narrative text is explicitly out of scope for acceptance testing. Realizes UJ-5. Depends on RF07.

#### FR-34: Request a period export

A user can request an export for a chosen date period via `POST /export/summary`.

#### FR-35: Job status across five screen states

The export sheet reflects the job's progress across five states — Pendente, Processando, Concluído, Erro, Período vazio — via `GET /export/:jobId/status`, which reports `status` (job) and `narrativeStatus` (AI summary) independently.

#### FR-36: Narrative-independent raw-data download

Raw data is downloadable via `GET /export/:jobId/download` as soon as it's ready, even if the AI narrative step is still processing, has failed, or was skipped — the narrative never blocks the data download.

#### FR-37: Empty-period handling

Requesting an export for a period with zero Entries surfaces "Período vazio" with no download offered and no crash.

---

### 4.11 Temporal Summaries / Dashboard & Account (RF09)

**Description:** The Configurações screen's evolution Dashboard, plus the profile and account actions that live there. Scope for the Dashboard is aggregation/rendering only — AI narrative text quality is explicitly out of scope for acceptance testing. Realizes UJ-6. Depends on F000, RF01.

#### FR-38: On-demand dashboard aggregation

Opening Configurações computes and renders an evolution chart via `GET /dashboard/aggregate`, correctly at zero, one, and more-than-thirty Entries.

#### FR-39: Independent narrative text

A separate narrative text is fetched via `GET /dashboard/narrative`; its failure is a distinct, chart-still-renders state, never blocking the chart (two independent endpoints by design).

#### FR-40: Cache invalidation on new Entry

The dashboard's aggregation recalculates after a new Entry is created elsewhere in the app; since Entries are immutable, invalidation only ever needs to trigger on create, never on edit.

#### FR-41: Profile name editing

A user can edit their display name inline on Configurações via `PATCH /account/settings`.

#### FR-42: Logout

"Sair" ends the session (`POST /auth/logout`) and returns to the Biometric Vault / login screen.

#### FR-43: Account deletion

"Apagar conta" shows a confirmation dialog; on confirmation, the account and all associated data are hard-deleted (`DELETE /account`, LGPD-driven), and the user is routed to the same destination as logout.

**Notes:** `[NOTE FOR PM]` No dedicated "account deleted" confirmation screen exists in the current prototype (§8 OQ-4) — revisit if post-defense polish time exists.

## 5. Non-Goals (Explicit)

- **Dynamic AI categorization of Entries** `[ext]` — downgraded to manual, user-created tags on Meus Registros; no AI logic behind it.
- **Autonomous AI goal extraction** `[ext]` — exists only as a static Action Plans Kanban screen with no underlying logic.
- **Dynamic AI persona adjustment** `[ext]` — exists only as a cosmetic Settings selector (Analítico/Empático/Socrático) that does not change assistant behavior in this delivery.
- **Any risk-signal detection** (self-harm, suicidal ideation) — a deliberate scope exclusion tied to the product's non-clinical stance (§1), not an oversight. A low-cost static crisis-resources disclaimer is a candidate fast-follow, not committed (§8 OQ-8).
- **Entry editing or deletion** — no such backend operation exists; Entries are permanent once created.
- **Offline Entry creation** — all writes are cloud-only; offline mode is view-only for already-synced data.
- **Android, or any platform beyond iOS portrait** for this delivery.
- **Any change to the backend, its contract, or its configuration** — consumed exactly as documented.
- **Any direct call to an AI provider (Claude, Voyage AI) from the app** — every AI-touching operation goes through the backend.
- **Grading or verifying the quality of AI-generated text** (Insights, export narratives, dashboard narrative) — RF05/RF08/RF09 are scoped to mechanism, failure-handling, and UI-safety only; generated-content quality is explicitly out of acceptance scope per requirements.md. (RF04's chat responses and RF06's search-result relevance carry no such explicit exclusion in requirements.md — see §8 OQ-10.)

## 6. MVP Scope

### 6.1 In Scope

- F000 (Foundation) → RF03 → RF01 → RF02 → RF07 → RF06 → RF04 → RF10 → RF08 → RF05 → RF09, in that order (requirements.md §12).
- All 43 FRs in §4, plus the feature-specific NFRs called out alongside them, to their stated acceptance criteria.

### 6.2 Out of Scope for MVP

- Everything listed in §5.
- Any feature reordering outside the delivery sequence in §6.1 — later units assume earlier ones exist (e.g. RF10 assumes RF01 and RF04 are both done).

## 7. Success Metrics

*This is an academic capstone with no customer-acquisition or adoption target; success is defined by specification conformance, not usage.* Stated plainly: this PRD's graded metrics (SM-1–3) can only confirm the RAG-memory mechanism is wired correctly end-to-end — whether the memory bet (§1) actually pays off for a real user is not a graded surface for this delivery (SM-5 is deliberately informal and uninstrumented; see also §8 OQ-10).

**Primary**
- **SM-1**: Every acceptance criterion stated per-RF in requirements.md §1 passes. Validates FR-1 through FR-43, the feature-specific NFRs called out in §4 (e.g. the BLoC-composition rule under §4.5 FR-18), and RNF01's performance thresholds (manual timing spot-check per module, not automated).
- **SM-2**: Zero Clean Architecture layer violations (RNF06) and ≥80% domain-layer test coverage (RNF07), verified across all 11 feature modules.
- **SM-3**: All 15 required network-failure scenarios (5 write endpoints × 3 failure types) are handled per the Failure contract, with zero unhandled exceptions (RNF09).

**Secondary**
- **SM-4**: Zero hardcoded visual values outside `design_tokens.dart` (RNF08), verified by inspection.
- **SM-5** *(qualitative, informal)*: the assistant surfaces something true from weeks earlier without being asked to, and the act of writing starts to feel worth repeating. No instrumentation planned to measure this for v1 — it is a design intent, not a graded criterion.

**Counter-metrics (do not optimize)**
- **SM-C1**: Scope creep into AI-generated content *quality* work (better prompts, better narratives) — explicitly out of grading scope (§5) and would divert effort from the mechanism work that is actually graded. Counterbalances SM-1.
- **SM-C2**: Test coverage inflated with trivial/tautological tests to hit the RNF07 80% number — the metric is domain-layer correctness, not a percentage. Counterbalances SM-2.

## 8. Open Questions

1. **No project timeline, deadline, or defense date is stated anywhere in the source documents.** This blocks any confident sequencing/pacing judgment for downstream epics work. *(Flagged by the PRFAQ distillate as the single biggest open input.)*
2. **Signup field set is underspecified.** The prototype shows one screen toggled between Entrar/Criar conta with only email+password fields visible — no password confirmation, no display-name capture at signup. Confirm this is intentional before building FR-1. *(blocks F000 — build unit 1 of 11)*
3. **Tab-switching mid-capture in the Insertion Modal is undefined** (e.g., switching from Áudio to Foto while a recording is in progress) — decide: discard, warn, or persist the in-progress capture (affects FR-11). *(blocks RF01 — build unit 3 of 11)*
4. **No "account deleted" or "signed out" confirmation screen exists** — both flows dead-end at the Biometric Vault screen. Decide whether this is acceptable for v1 or needs even a lightweight confirmation (affects FR-42/FR-43). *(blocks RF09 — build unit 11 of 11; lowest urgency of the sequenced OQs)*
5. **(Already resolved, kept here only for visibility — not a live open question.)** Cloud-only, immutable-entry design is a backend constraint, not a product choice: there is no appetite to request a contract change (confirmed — none per `AGENTS.md`); recorded so it isn't silently re-discovered as a "bug" later.
6. **The Sync Badge error state has no visible retry affordance in the current prototype** — decide whether the badge needs one, or whether reconciliation on the next successful write is sufficient (affects FR-15). *(blocks RF07 — build unit 5 of 11)*
7. **Combined search + filter behavior is unspecified** — when both a search term and active filters are set, decide the intended interaction (AND-combine vs. one overriding the other) (affects FR-19/FR-20). *(blocks RF06 — build unit 6 of 11)*
8. **A static, no-logic crisis-resources disclaimer was recommended (PRFAQ) as a low-cost way to close the "silent gap" left by having no risk-signal detection**, without contradicting the non-clinical stance (§1, §5). Not yet decided for inclusion.
9. **Whether Cerne continues as a maintained portfolio piece after the defense, or ends as a one-time academic artifact**, is unresolved and would change how much polish-time investment in OQ-2/OQ-4/OQ-6/OQ-7 is worth it.
10. **Whether RF04's chat-response quality, and separately RF06's search-result quality, should carry the same "mechanism only, never graded" boundary that requirements.md states explicitly for RF05/RF08/RF09 is unstated for both.** Treated here as a genuine gap for each, not silently extended or silently dropped (§5, §Constraints and Guardrails). *(blocks grading boundary for RF04 — build unit 7 of 11 — and RF06 — build unit 6 of 11)*
11. **"Cerne" is a working title** — confirm or replace.

## 9. Assumptions Index

- §2.1/§2.3 — The target-user persona (functional/emotional/social JTBD, the "Mara" journeys) is reconstructed from the product brief and PRFAQ, not stated verbatim in `docs/input/`.
- §4.1 FR-1 — Signup is assumed to collect only email + password (see OQ-2 for the decision this depends on).

## Cross-Cutting NFRs

- **RNF01 (performance):** Local UI interactions respond in <100ms; any network call taking >300ms shows a loading indicator. Verified via manual timing spot-checks during each feature module's QA pass (SM-1) — no automated performance instrumentation is planned for this delivery.
- **RNF02 (PII handling)** `[inherited, not verified by this delivery]`: PII stripping runs via a Claude Haiku 4.5 structured prompt/tool-use step (not a dedicated NER model), server-side only.
- **RNF03 (data retention)** `[inherited, not verified by this delivery]`: Zero data retention by upstream AI providers.
- **RNF04 (data isolation):** Row Level Security (Supabase) enforces per-user data isolation; the client never needs its own authorization logic for cross-user access — the backend uniformly returns `NOT_FOUND` (never a permission-denied code) for any resource that doesn't belong to the requesting user, so existence of other users' data is never revealed.
- **RNF05 (account deletion):** Hard delete of account and all associated data on request (LGPD).
- **RNF06 (architecture):** Zero Clean Architecture layer violations — the domain layer imports neither `package:flutter` nor anything from a `data/` layer, in any of the 11 feature modules.
- **RNF07 (test coverage):** ≥80% domain-layer test coverage.
- **RNF08 (visual fidelity):** Visual fidelity to the prototype (color, typography, spacing); zero hardcoded visual values outside `design_tokens.dart`.
- **RNF09 (resilience):** Every repository returns `Either<Failure, T>`; 5 write endpoints × 3 failure types (timeout, malformed response, no connection) = 15 tested failure scenarios, zero unhandled exceptions.

**The Failure contract** — every backend error has the shape `{ code, message, retryable }`, drawn from a closed set of 13 codes (the one extra client-only case, a malformed/unparseable response, is handled identically but never retryable):

| Code | Retryable | Meaning |
|---|---|---|
| AUTH_EXPIRED | no | access token expired — triggers the FR-2 overlay |
| AUTH_INVALID | no | invalid credentials (password login only — never originates from biometrics, since biometric validation is on-device) |
| NETWORK_TIMEOUT | yes | request timed out |
| NETWORK_OFFLINE | yes | connection ended with no HTTP response at all — must be handled as a distinct "no response received" branch, not dispatched on a status code |
| VALIDATION_ERROR | no | malformed request payload |
| PII_CHECK_FAILED | yes | server-side PII scan step failed |
| EMBEDDING_FAILED | yes | embedding generation failed |
| AI_GENERATION_TIMEOUT | yes | AI generation step timed out |
| NOT_FOUND | no | resource missing, or belongs to another user (RNF04) |
| RATE_LIMITED | yes | too many requests |
| EXPORT_EMPTY_PERIOD | no | export requested for a period with no Entries (FR-37) |
| PAYLOAD_TOO_LARGE | no | upload exceeds size limit |
| OCR_NO_TEXT | no | OCR found no extractable text (FR-13) |

## Constraints and Guardrails

Privacy, safety, and platform constraints are stated once each, at the FR/NFR/Non-Goal that owns them, rather than restated here. Index:

- **Privacy** — on-device-only audio and biometrics (FR-12, FR-4), zero AI-provider data retention (RNF03), server-side PII stripping (RNF02), RLS-enforced data isolation (RNF04).
- **Safety** — non-clinical framing and no risk-signal detection (§1, §5), the mechanism-only AI-content-quality boundary and its two open exceptions, RF04 and RF06 (§5, §8 OQ-10).
- **Platform** — iOS portrait-only, frozen backend contract, no direct AI-provider calls from the app (§5).

## Aesthetic and Tone

The prototype (`docs/input/prototype/prototype-extract.md` §3) defines a named visual token system — color, typography, spacing, radii, elevation, and iconography — that `lib/core/design_tokens.dart` must be the single source of truth for; no visual value may appear hardcoded anywhere else in the app (RNF08). Interface copy throughout the product is in Brazilian Portuguese. Tone follows directly from §1's stance: reflective and private, never clinical, never styled as a "companion" the user is meant to bond with.

---
*Addendum: `addendum.md` in this folder holds implementation-level decisions (routing, HTTP client, local cache, DI, package choices and rejected alternatives), competitive-landscape and market-sizing detail, regulatory citations, and corrections-carried-forward from prior planning sessions — none of it duplicated here.*
