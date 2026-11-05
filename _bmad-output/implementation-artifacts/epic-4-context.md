# Epic 4 Context: Timeline & History

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Users can see every Entry they've ever captured, from any source (text, audio, photo), in one chronological view grouped by date, each carrying a live per-entry sync status — and never lose track of something they wrote, even offline or mid-session-expiry. This is the first independently demoable milestone built on top of the `entries` feature Epic 3 introduced: a working, origin-marked timeline with reconciling sync badges, with no search or filtering yet (that's Epic 5). Depends on Epic 3 (there is nothing to list until Entries exist).

## Stories

- Story 4.1: Chronological Entry List with Origin Marking
- Story 4.2: Per-Entry Sync Badge
- Story 4.3: Empty-State Handling
- Story 4.4: Entry Detail View

## Requirements & Constraints

- All Entries from every source are listed together in one list, grouped by date, each visually marked with its origin.
- A list load that exceeds the loading-indicator threshold (300ms) shows a skeleton loading state; under that threshold, no loading UI appears at all.
- Zero Entries renders a dedicated empty state with a path back to capture — never a blank list.
- A single Entry can be opened to view its full content; there is no edit affordance anywhere on that screen, and no update/delete capability exists for Entries at all — read-only, permanently.
- A detail request for an Entry that doesn't exist or belongs to another user returns a generic not-found outcome, never a distinguishable permission-denied code; the UI must treat both identically.
- The sync badge has exactly three states (Synchronizing / Synchronization error / Synchronized), derived client-side only — the backend has no sync-status field. A freshly created Entry starts Synchronizing until the write is confirmed, then flips to Synchronized. A failed write (network or any error code) shows Synchronization error until a later successful write reconciles it.
- Tapping an error badge retries that Entry's write when the underlying error is retryable; when it isn't, it shows an inline explanation instead — never a dead retry button.
- The sync-badge update stream is fully independent of the auth/session stream: a pending sync transition is never blocked, delayed, or cleared by session-expiry handling, and the session-expiry overlay must be able to appear over this screen without crashing or losing scroll position.
- This feature's screen composes three data streams (auth status, sync-badge state, Entry data) only through the domain layer — no BLoC/Cubit here ever references another BLoC/Cubit directly.
- No swipe gesture is implemented on a record card (Entries are immutable, so no gesture may imply an edit/delete that doesn't exist).
- Color is never the sole carrier of sync-badge state — always paired with an accessible label, and the retry hit area must be ≥44pt even though the dot itself is small.

## Technical Decisions

- `entries/domain` (introduced in Epic 3) already owns the `Entry` entity, the `EntriesRepository` port, and the Hive box; this epic extends that same port with read/list operations rather than introducing a second Entry model or owner.
- `EntriesRepository` exposes create and read only, permanently — no update/delete method is ever added, matching the backend's lack of a mutating entries endpoint.
- One single derivation function lives in `entries/domain` computing the sync badge from `Entry.serverRevision`, `Entry.updatedAt`, and transient per-entry write state (no pending write → Synchronized; write in flight → Synchronizing; failed write → Synchronization error). Every screen that ever renders this badge (this timeline now, chat's save confirmation later) consumes that one function's output — none recomputes it inline.
- This screen's composite state (auth × sync × data) is its own sealed state class, not the shared generic single-fetch `Resource<T>` type used elsewhere — it has a composite, multi-stream lifecycle `Resource<T>` isn't meant for.
- Reads fall back transparently to the local Hive cache when offline; the cache stores exactly what the server returned, keyed by id — never locally filtered, joined, sorted, or re-derived. Pagination uses the server's own cursor convention verbatim, cached alongside the box it pages.
- A badge retry re-attempts the same underlying write call that originally failed; there is no separate retry endpoint for entries.

## UX & Interaction Patterns

- Record card spine color encodes origin: manual = primary color, audio = olive green, photo = gray (chat's accent color is reserved for Epic 6's chat-saved entries).
- The prototype shows the record card as otherwise display-only — tapping it previously did nothing beyond surfacing the badge's retry affordance in the error state. The detail view this epic adds (FR-18) has no prototype precedent; build it minimal and strictly read-only, consistent with the record card's established "no edit/expand implied" convention.
- Skeleton rows use the shared skeleton-loading component (never a spinner) and only appear past the 300ms threshold.
- Empty state must offer a concrete CTA back into the capture flow (opens the Insertion Modal), not just explanatory copy.

## Cross-Story Dependencies

- Depends on Epic 3: the `entries` feature, `Entry` entity, `EntriesRepository.create`, and the entries Hive box must already exist; this epic only adds read/list.
- Reuses Epic 1's session-expiry overlay (FR-2) as-is for mid-timeline session expiry — no new overlay is built here.
- The sync-badge derivation function built in Story 4.2 is a shared dependency: Epic 6 (chat's save-to-journal confirmation) consumes the same function rather than building its own.
- Epic 5 (Semantic Search & Filtering) is built directly on top of this epic's timeline surface and extends the same `EntriesRepository` port further with search — do not duplicate list/display logic there.
