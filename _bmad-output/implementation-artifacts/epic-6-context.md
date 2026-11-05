# Epic 6 Context: Conversational Memory, Save-to-Journal & Insights

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Users hold a persistent, multi-session conversation with an assistant whose answers are grounded in semantic retrieval over their own past Entries — not generic replies — can turn their own reflective chat messages into real journal Entries with one tap, and occasionally receive an unprompted insight about a pattern in their own writing. None of this (dropped streams, save failures, insight-generation failures) may ever block, corrupt, or freeze the core chat experience. This epic is the product's central differentiator: proving the memory-over-own-history bet end-to-end against the real backend.

## Stories

- Story 6.1: Send Message & Receive RAG-Grounded Streaming Response
- Story 6.2: Multi-Session Chat History & New Conversation
- Story 6.3: Dropped-Stream Resilience & Offline Composer Lock
- Story 6.4: Bookmark a Chat Message into an Entry
- Story 6.5: Proactive Insight Injection & Failure Isolation

## Requirements & Constraints

- Chat responses stream via SSE and must be grounded in retrieval over the user's own Entries; exactly three visible states exist for a response: streaming/processing, error, complete — no others.
- A Chat Message never auto-creates an Entry; saving one to the journal (this epic's story 6.4) is the sole explicit exception.
- A user holds multiple named Chat Sessions, switchable and startable from the side menu; starting a new session requires connectivity (blocked offline, consistent with the offline composer lock). A returning session restores its last scroll position.
- A dropped response stream keeps the partial message on screen with a failure indicator (never clears bubble content) and is recoverable via a dedicated retry call that regenerates without duplicating the original question.
- Offline disables the message composer (and the new-session entry point) with an offline banner, while existing history remains fully visible/scrollable.
- The save-to-journal (bookmark) affordance appears only on the user's own messages, never on AI responses; it creates an Entry carrying a reference back to the source chat message, through the same shared entries-feature use case introduced earlier in delivery — never by importing the entries repository/data source directly.
- Saving the same message twice is idempotent: no duplicate Entry, no conflict surfaced to the user (success, not error).
- A save failure never freezes the chat session or the button — the button returns to a retryable state and the rest of the session stays usable.
- An Insight is injected into the active session on exactly one trigger per satisfied window — either N user messages sent or a fixed inactivity timeout, whichever comes first — never both, never twice for the same window.
- An Insight-generation failure is silent to the user: no error overlay, composer stays enabled, ordinary chat keeps working. Insight quality/content is explicitly outside acceptance scope — only the trigger/injection/failure-isolation mechanism is graded.
- Dismissing an Insight never affects scroll position or any other conversation state.

## Technical Decisions

- Feature lives at `features/chat/`; it consumes `features/entries/`'s abstract save/create-entry port from `entries/domain` only — never anything from `entries/data/` or `entries/presentation/` (layering invariant, zero violations tolerated).
- Repositories return `Future<Either<Failure, T>>`, except the chat response itself, which is `Stream<Either<Failure, T>>` given its SSE nature. The closed, 14-member `Failure` hierarchy (13 server codes + a local-only malformed-response code) is shared from `core/` and never redefined per feature.
- Chat holds no local write queue: a send attempted with no connectivity resolves immediately to a `networkOffline` failure, never queued. Plain history reads (sessions, messages) transparently fall back to the local cache; retry logic for retryable failure codes lives once in the shared API client, not reimplemented per feature.
- Chat's message/streaming state is its own sealed state class (append-only, streaming-aware) — explicitly excluded from the shared generic `Resource<T>` single-fetch state pattern, because it isn't a single fetch.
- The proactive-insight overlay is a value appended onto the existing chat state from story 6.1, never a second parallel state container.
- A never-throws `core/isolated_side_effect.dart` helper (`Future<Either<Failure, T>> Function(Future<T> Function())`-shaped) ships with this epic's first consumer (the save-to-journal story) and is reused unawaited (fire-and-forget) by the insight story so a slow/failed insight never blocks or delays the chat stream.
- No BLoC/Cubit ever takes another BLoC/Cubit as a constructor dependency, in this feature or across features; independent state sources compose via injected domain streams/use-cases or `BlocListener`, never a direct BLoC-to-BLoC reference.
- The entries-owning feature's save port is idempotent on the save-to-journal identifier at the implementation level (not just the type signature) — a repeat save for the same source message never creates a second Entry.
- Session/message/sync-badge local caching follows the same per-feature local-cache-box convention used by other features; cursor-based pagination for session and message lists follows the server's own cursor convention verbatim.

## UX & Interaction Patterns

- Chat bubbles: user (sage, squared bottom-right corner) vs. AI (ivory, squared bottom-left, resting elevation). A streaming AI bubble adds a blinking cursor at the text's end and nothing else changes visually while generating; under Reduce Motion the cursor blink is skipped and final text shows immediately instead.
- A dropped/failed response replaces the bubble's timestamp slot with red retry copy; bubble text itself is never cleared.
- Bookmark button: four states on every user message only — idle (outline) / saving (spinner, or a static label under Reduce Motion) / saved (ochre check) / error (red warning). Tapping an already-saved message is a no-op. State must be carried by icon + color together, never color alone. Tap target ≥44pt.
- Insight card: ochre left spine, mono "INSIGHT" label, dismiss "x" — the spine is the only accent-colored element inside the chat stream itself.
- Offline banner disables sending only; conversation history stays scrollable and readable underneath it. A session-expired overlay (re-auth) can appear over chat without losing scroll position or in-memory history.
- A new session opens with the composer focused and only the placeholder "Escreva uma mensagem..." — no invented greeting copy.
- No swipe gestures, no nested overlays, no pull-to-refresh beyond what the session/message endpoints already govern.

## Cross-Story Dependencies

- Story 6.1 establishes the chat stream/state machine that 6.2 (sessions), 6.3 (retry/offline), 6.4 (bookmark), and 6.5 (insight overlay) all build on or append to.
- Story 6.4 is this epic's (and the codebase's) first consumer of the shared `isolated_side_effect` helper; Story 6.5 reuses that same helper fire-and-forget.
- Story 6.4 depends on the entries feature's save/create-entry port already existing from earlier delivery work; it must not introduce a second entry model or reach into entries' data layer.
- Story 6.5's insight overlay is layered onto 6.1's chat state rather than a separate state container, so it cannot be built independently of 6.1's state shape.
