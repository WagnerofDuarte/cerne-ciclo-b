---
name: Cerne
status: final
updated: 2026-10-26
sources:
  - docs/input/requirements.md
  - docs/input/prototype/prototype-extract.md
  - docs/input/prototype/cerne-prototype.html
  - docs/input/backend/sync-badge.md
  - docs/input/backend/error-taxonomy.md
  - docs/input/backend/export-screen-states.md
---

# Cerne — Experience Spine

> Single-surface mobile (iOS, portrait only). Paired with `DESIGN.md`. The product spec and visual prototype are frozen and unusually complete — this spine resolves the handful of gaps the spec explicitly leaves open (marked `[ASSUMPTION]`) rather than inventing new UX surface. `Responsive & Platform` is omitted: there is exactly one form factor (390×844pt, portrait, iOS only).

## Foundation

Single-surface mobile, iOS only, portrait only, 390×844 logical points. No third-party UI system — fully custom per `DESIGN.md` tokens, implemented with Flutter + `flutter_bloc` + Clean Architecture (`docs/input/requirements.md` section 9/13). Language: Portuguese, single locale, no i18n layer. `DESIGN.md` is the visual-identity reference; this file is the experience — behavior, states, interaction, accessibility, flows. Light mode only; there is no dark-mode or theme-switching surface (see `DESIGN.md` Do's and Don'ts).

Three base screens hold almost everything; the rest are overlays on top of one of them, stacked at most one level deep:

- **Home/Chat** — default landing after auth.
- **Meus Registros** — consolidated timeline.
- **Configurações** — profile, dashboard, account.

## Information Architecture

| Surface | Reached from | Purpose | Backend-gated by |
|---|---|---|---|
| Splash (Tela 0) | Cold app launch | Checks session + syncs cache in background, auto-advances (1.8s) | `GET /auth/session` |
| Biometria / PIN (Tela 0.1) | Splash, "Sair," account deletion | Local access barrier before any user data is exposed | device-local; `POST /auth/login` only if the session fully expired |
| Entrar / Criar conta (Tela 0.1a) | "usar e-mail e senha" link on Biometria | Fallback credential auth, same screen toggled by mode | `POST /auth/login`, `POST /auth/signup` |
| Home/Chat (Tela 1) | Auth success, "Novo Chat," back from any overlay | Continuous conversation with the AI, entry point to capture | `POST/GET /chat/sessions`, `.../messages` |
| Insertion Modal (Tela 2) | "+" on Home/Chat | Multimodal capture — text / audio / photo — each produces a persisted entry, never a chat message | `POST /entries`, `POST /media/ocr` |
| Side menu (Tela 3) | ☰ on Home/Chat | Navigation hub: session history, My Records / Action Plans / Settings, new conversation | `GET /chat/sessions` |
| Meus Registros (Tela 4) | Side menu | Timeline, filter, search, export | `GET /entries`, `GET /entries/search`, `POST/GET /export/...` |
| Planos de Ação (Tela 5) `[ext]` | Side menu | Static 3-column kanban, placeholder only — no functional implementation | none (no backend calls) |
| Configurações (Tela 6) | Side menu | Profile editing, evolution dashboard, persona toggle `[ext]`, logout, account deletion | `GET /dashboard/...`, `PATCH /account/settings`, `DELETE /account`, `POST /auth/logout` |

No drawer-within-drawer, no tab bar — the side menu is the sole navigation hub besides the back arrow on Meus Registros and the "x" that closes any sheet/modal. Mirrors `docs/input/requirements.md` section 5.2 screen numbering and `prototype-extract.md` Tela numbering verbatim so both documents stay addressable by the same names.

→ **Composition reference:** `docs/input/prototype/cerne-prototype.html` — the frozen prototype is itself the 1:1, interactive visual reference for all 32 navigable states (`prototype-extract.md` sections 1-2); no separate static mock is generated, since it must never change. Open it directly and navigate by `screen` state/overlay flag to see any surface this table names. Spine wins on conflict.

## Voice and Tone

Microcopy only — brand posture and aesthetic register live in `DESIGN.md.Brand & Style`. Default voice leans **empático** — warm, validating, never clinical. `[ASSUMPTION]`: the prototype's three persona options (Analítico / Empático / Socrático) are a non-functional cosmetic toggle (`docs/input/requirements.md` section 2), so the product must ship with exactly one real voice regardless of which card looks selected.

| Do | Don't |
|---|---|
| "Não foi possível transcrever" / "Não foi possível reconhecer o texto" — exact prototype copy, factual, no blame | "Oops! Something went wrong 😢" |
| "Sessão expirada" with a plain explanation that history is kept | Any language implying data loss or starting over |
| Insight copy that surfaces a pattern ("parece que..., você mencionou...") without diagnosing or prescribing | Therapeutic framing, diagnostic language, or crisis-support claims — the product explicitly has no risk-signal protocol (`docs/input/requirements.md` section 4, known limitation) |
| "Resumo pronto" / "Baixar dados brutos" — plain, factual labels | Celebratory language around export or streaks around journaling frequency |
| Second person, direct ("Toque para desbloquear") | Infantilizing or over-familiar tone |

## Component Patterns

Behavioral; visual specs live in `DESIGN.md.Components`.

| Component | Use | Behavioral rules |
|---|---|---|
| Insertion modal tab bar | Texto / Áudio / Foto | Opening the modal always resets all three tabs to idle/empty. Switching tabs while a capture is actively in flight (recording, or OCR/transcription processing) **cancels that capture outright** — no partial entry is created, applying RF01's existing cancel-on-interrupt rule to this trigger. `[ASSUMPTION]` (prototype leaves this undefined). |
| Chat bubble / message | Home/Chat | User bubbles are static once sent. AI bubbles alone carry a state machine: streaming (`{colors.colorTextPrimary}` text revealed progressively behind a blinking cursor) → complete, or → failure (timestamp slot replaced by red retry copy, bubble content never cleared). |
| Bookmark button (RF10) | Every user chat message | idle → saving → saved/error. Tapping an already-`saved` message is a no-op (idempotent per RF10 AC — same message never creates a duplicate entry). `error` returns to a retryable idle-like state, never stuck. Only user messages carry the button — AI responses never do. |
| Insight card (RF08) | Interleaved in chat | Fires once per satisfied trigger (5 user messages OR 2 min inactivity) — never both, never twice for the same window. Dismiss ("x") never changes scroll position or chat state. Failure to generate is silent to the user — chat continues uninterrupted. |
| Sync badge | Record card (Meus Registros) | Tap on an `error` badge (`{colors.colorError}` dot) retries that entry's write. `[ASSUMPTION]`, grounded in `docs/input/backend/sync-badge.md`: the error means a local write was attempted and failed, so content is still held client-side and retry is meaningful. If the underlying error code is non-retryable (see State Patterns), show an inline explanation instead of a retry affordance. |
| Avatar — inline name editing | Configurações | Tapping the pencil beside the name/e-mail switches that field to an editable text input in place; the pencil icon becomes a check. Confirming commits via `PATCH /account/settings`; the field reverts to display mode either on save or on tapping elsewhere. No separate "edit profile" screen. |
| Record card | Meus Registros | Display-only — tapping a card does nothing beyond revealing its sync badge's retry affordance when in `error` state. No detail screen exists; entries are immutable, so no tap-to-edit or tap-to-expand behavior should be implied. |
| Search bar + filter sheet | Meus Registros | Query text and active filter chips combine with **AND** logic against the same `GET /entries/search` call — consistent with RF06's multi-filter AND rule. `[ASSUMPTION]` (prototype doesn't show them acting together). Clearing filters returns to the unfiltered list without re-mounting the screen (RF06 AC). |
| Export sheet | Meus Registros, download icon | 300ms debounce does not apply here (that's search only). Each stage change replaces the sheet content in place — the sheet itself never closes and reopens mid-job. |
| Offline banner / disabled send | Home/Chat | Disables sending only (`{colors.colorInfoOffline}` banner); history stays scrollable and readable. |
| Insertion modal, offline | "+" on Home/Chat while offline | Entry point is disabled with the same offline treatment as chat send — capture requires a live `POST /entries` round trip (PII check + embedding), so there is no local-only queued write. `[ASSUMPTION]`, grounded in RF06's AC ("offline allows only viewing cached data, not writing"). |
| Sign-up (Tela 0.1a, toggled) | "criar conta" link | Exactly two fields — email, senha — matching the prototype's login fields one-for-one. No name or password-confirmation field. `[ASSUMPTION]` (RNF08 visual fidelity; prototype shows no extra fields). |

## State Patterns

| State | Surface | Treatment |
|---|---|---|
| Biometric failure | Biometria | Falls through to PIN entry ("Não foi possível reconhecer — digite seu PIN") — never a dead end, never a lockout (RF03 AC). |
| Login/signup error | Entrar / Criar conta | `AUTH_INVALID` (wrong credentials, non-retryable) shows inline under the fields, same `{components.text-field.borderError}` treatment as any other validation error; `VALIDATION_ERROR` (malformed input, e.g. bad e-mail format) is caught before submit where possible. |
| New/empty chat | Home/Chat | Opened via "Novo Chat" with no messages yet — composer focused, no greeting copy invented beyond the placeholder "Escreva uma mensagem...". Distinct from a returning session, which restores the last conversation's scroll position. |
| Meus Registros — loading | Meus Registros | Skeleton rows (`DESIGN.md` skeleton component) only past the 300ms threshold (RNF01) while `GET /entries` resolves; under 300ms, no loading UI at all. |
| Session expired | Home/Chat (overlay) | Scrim over chat (still readable), card with lock icon, "Entrar novamente" → Biometria (not a full form). History and scroll position preserved in memory across re-auth. |
| Offline | Home/Chat | Send disabled, banner shown, history navigable. Same gating extends to the insertion-modal entry point (see Component Patterns). |
| Audio capture | Insertion modal, Áudio tab | Gravando → Processando (frozen/faded waveform) → Transcrito (editable) \| Erro ("Tentar novamente," audio never discarded). |
| Photo capture | Insertion modal, Foto tab | Captura → Processando OCR → Reconhecido (editable text) \| Erro (`OCR_NO_TEXT`, non-retryable — "Tentar novamente" re-invokes OCR on the same photo; secondary action "Salvar só a foto" saves the record with no extracted text). |
| Capture too large | Insertion modal, Áudio/Foto | `[ASSUMPTION]`: `PAYLOAD_TOO_LARGE` (413, non-retryable) has no dedicated prototype state — reuse the red-warning visual language with a size-specific message, no retry button (retrying the same oversized file cannot succeed). |
| Export — preparing | Meus Registros → export sheet | `status=pending`. Spinner, no download. |
| Export — generating summary | export sheet | `status=processing`, `narrativeStatus=processing`. Progress bar, no download yet. |
| Export — data ready, summary still generating | export sheet | `[ASSUMPTION]` hybrid state the prototype's 5 visual states don't show (`docs/input/backend/export-screen-states.md`): `status=data_ready`, `narrativeStatus=processing`. Show "Baixar dados brutos" immediately (download available) while the summary-progress text keeps showing underneath — the raw data is never withheld waiting on the AI narrative. |
| Export — done, with summary | export sheet | `status=done`, `narrativeStatus=done`. "Resumo pronto," both download buttons. |
| Export — done, summary failed/skipped | export sheet | `status=done`, `narrativeStatus=failed\|skipped`. Error copy framed around the narrative only; "Baixar dados brutos" still enabled — raw data is never blocked by an AI failure (RF05 AC). |
| Export — error | export sheet | `status=error`. Includes `EXPORT_EMPTY_PERIOD` (period had zero entries) as one concrete cause — no download button, suggestion to adjust the filter. |
| Dashboard — zero entries | Configurações | Placeholder chart icon, "Comece a registrar..."; no summary paragraph (there is nothing to summarize — distinct from a narrative failure). |
| Dashboard — one entry | Configurações | Single bar, "Ainda é cedo pra ver um padrão..." |
| Dashboard — > 30 entries | Configurações | 10-bar chart + AI narrative paragraph. |
| Dashboard — narrative unavailable | Configurações | Chart renders normally with data; only the AI summary paragraph failed — needs its own distinct error message, never silently blank and never confused with the zero-entries empty state. |
| Sync badge | Record card | Synchronizing (local write pending server confirmation) / Error (write attempted and failed, retry available unless the underlying code is non-retryable) / Synchronized (confirmed) — all three inferred client-side from `updatedAt`/`serverRevision`, never sent ready-made by the server. |
| Chat response | Home/Chat | Streaming (pulsing cursor) → Complete, or → Failure (`"Falha ao gerar resposta — toque para tentar novamente"` in place of the timestamp; partial text stays visible, retried via the dedicated retry endpoint without duplicating the user's question). |

## Interaction Primitives

- Tap to act; the composer's send icon and every button follow the same primary-tap model — no double-tap, no force-touch.
- Text streaming reveals progressively with a blinking cursor; this is the one place motion carries meaning (the AI is actively responding) rather than decoration.
- Bottom sheets rise from the bottom (`sheetUp`, 0.2s); any overlay opening fades a scrim first (`scrimIn`, 0.18s). Both are the *only* entrance choreography in the system.
- PIN entry auto-advances 350ms after the 4th digit — no explicit "confirm" tap.
- **Banned:** swipe-to-delete or any swipe gesture on record cards (entries are immutable — there is no delete or edit endpoint on `/entries/:id`, so no gesture should imply one exists). Nested overlays (a sheet opening another sheet). Pull-to-refresh invented beyond what the spec defines (`GET /auth/session` and the chat/session streams already govern staleness — don't add a second, undefined refresh gesture on top). Long-press repurposed for anything other than native text selection.

## Accessibility Floor

Behavioral; visual contrast lives in `DESIGN.md`. `[ASSUMPTION]`: WCAG AA adopted as the floor even though `docs/input/requirements.md` does not mandate it — journaling content is personal, even though the product is explicitly not a mental-health app (no risk-signal protocol).

- Every state that is currently color-only in the prototype (sync badge dot, bookmark states) must also carry an icon or an accessible label/announcement — color alone never carries state (see `DESIGN.md` Do's and Don'ts).
- Screen-reader labels announce transitions, not just static state: "Gravando," "Transcrevendo," "Erro ao transcrever, toque para tentar novamente."
- Dynamic type honored through `DESIGN.md` typography tokens; no control truncates at the largest accessibility text size (PIN keypad, filter chips and tab bar are the tightest-fit surfaces — verify first).
- Tap targets ≥ 44pt, including the bookmark icon and the sync-badge dot's tappable retry area (visually a small dot, hit area larger).
- Reduce Motion: skip the streaming cursor blink and `scrimIn`/`sheetUp` easing — show final state immediately; spinners become a static "carregando" label instead of a spin animation.
- Session-expired and account-deletion dialogs trap focus until dismissed or actioned — no interacting with the scrim-covered content underneath.

## Inspiration & Anti-patterns

- **Rejected — dynamic AI categorization:** simplified to manual, user-created tags (`docs/input/requirements.md` section 2). Don't reintroduce automatic tagging UI anywhere; tags are read-only, embedded, manual-only.
- **Rejected — autonomous goal extraction:** Planos de Ação is a static, non-functional kanban placeholder. Don't wire it to real data or real drag-and-drop — it exists only so the menu entry isn't broken.
- **Rejected — dynamic persona adjustment:** the three persona cards are a cosmetic toggle with no effect beyond (at most) a system-prompt string swap that isn't implemented. Don't let the UI imply the AI's behavior actually changes when a card is selected.
- **Rejected — clinical/therapeutic framing:** no mood tracking iconography, no "session" language borrowed from therapy apps, no crisis-support affordances — the product is explicit that it has no risk-signal detection and should not imply it does.
- **Rejected — gamification:** no streaks, no completion badges, no notification-driven re-engagement — none appear anywhere in the prototype or requirements, and introducing them would contradict the quiet, reflective posture in `DESIGN.md.Brand & Style`.

## Key Flows

### Flow 1 — Daily capture → reflection (Davi, after dinner, phone in hand)

1. Davi opens the app; Face ID passes him straight to Home/Chat (last conversation still on screen).
   - *Auth failure branch (RF03):* if Face ID doesn't recognize him (gloves, bad angle), the barrier falls through to PIN entry with "Não foi possível reconhecer — digite seu PIN" — he's never locked out, just redirected to the alternate path.
2. He taps "+", lands on the Áudio tab, records 40 seconds about his day.
3. Recording stops; "Transcrevendo..." shows over the frozen waveform; transcript appears, editable. He fixes one word and taps "Salvar."
4. Modal closes; the new entry is on its way into the conversation's context, not into the chat thread itself.
5. He types a question to the AI referencing something from last week; the response streams in, grounded in his past entries (RAG).
6. **Climax:** mid-response, an insight card appears — "parece que você tem mencionado o trabalho com mais frequência essa semana" — surfacing a pattern Davi hadn't named himself. He doesn't dismiss it; he taps the bookmark on his own last message instead, saving the moment he connected the dot.

Failure branch: if the transcription fails, the error state keeps the recorded audio and offers "Tentar novamente" — Davi never loses the 40 seconds he just spoke.

### Flow 2 — Recall and export (Luiza, three months in, prepping for a check-in with her therapist)

1. Luiza opens the side menu → Meus Registros.
2. She searches "ansiedade" in the search bar; results include an entry that only says "nervosismo" — semantic search surfaces it anyway.
3. She opens the filter sheet, narrows to "Este mês" + "áudio" — results re-narrow with AND logic; a "sincronizando" badge on her most recent card resolves to "sincronizado" moments later.
4. She taps the download icon → export sheet: "Preparando exportação..." → "Gerando resumo com IA..." with the raw-data download already available partway through.
5. **Climax:** "Resumo pronto." She downloads the PDF — a narrative summary of three months of entries, ready to bring into a conversation she'd been putting off.

Failure branch: if the AI narrative fails, the sheet still offers "Baixar dados brutos" — her data was never hostage to the model call.

### Flow 3 — Evolution check-in (Pedro, one month in, opens Settings out of curiosity)

1. Pedro taps the side menu → Configurações.
2. The evolution dashboard computes on demand (RF09): with roughly a dozen entries so far, he sees the populated bar chart, not the one-entry or zero-entries placeholder.
3. He reads the AI-generated narrative paragraph below the chart — a plain-language read of his own pattern, not a diagnosis.
4. **Climax:** he notices the chart updated to include the entry he saved earlier that same day — the aggregation recalculated the moment he created it, not on some stale cache — proof the dashboard reflects *today's* Pedro, not last week's.
5. He taps the pencil beside his name to fix a typo; the field becomes editable in place, pencil turns to a check, and reverts to display mode on save.

Failure branch: if the AI narrative fails independently of the chart, Pedro sees the populated chart with a distinct "narrative unavailable" message — never confused with having zero entries, and never a blank space where text should be.
