# Epic 8 Context: Evolution Dashboard & Account Management

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Users can see an on-demand chart of their journaling activity with an independent AI narrative, edit their display name, log out, and permanently delete their account and all associated data. This is the final build unit in the delivery order — it assumes every earlier unit (entries, auth, chat, export) already exists, since the dashboard has nothing to aggregate without entries and account actions rely on the auth session already established in F000.

## Stories

- Story 8.1: On-Demand Dashboard Aggregation Across Entry Counts
- Story 8.2: Independent Narrative Text & Narrative-Unavailable State
- Story 8.3: Profile Name Editing
- Story 8.4: Logout
- Story 8.5: Account Deletion

## Requirements & Constraints

- The evolution chart is computed fresh every time the settings screen opens — never served from a stale local cache — and must render correctly at exactly three entry-count scenarios: zero, one, and more than thirty. These counts are fixed and not re-tunable.
- The narrative paragraph is a separate network call from the chart data, by design: the two must never be coupled so that a narrative failure cannot block or hide a chart that has valid data.
- Aggregation must recalculate whenever a new entry is created anywhere in the app; because entries are immutable (never edited), invalidation only ever needs to trigger on create.
- Account deletion is a hard, permanent delete of the account and all associated data (LGPD-driven) — not a soft delete or deactivation.
- No dedicated "account deleted" confirmation screen exists for this delivery; both logout and account deletion dead-end at the same login/vault destination.
- The persona selector shown on this screen is a cosmetic, non-functional placeholder only (an extension feature) — it must never appear to change assistant behavior.
- Every acceptance criterion for this epic's FRs must pass as the primary success measure; no automated performance instrumentation is required beyond a manual spot-check against the product's general UI-latency thresholds.
- Standard cross-cutting rules apply: no Clean Architecture layer violations, repository methods return `Either<Failure, T>` with no unmapped exceptions, and no visual value is hardcoded outside the design-tokens source.

## Technical Decisions

- Two features own this epic's work: a `dashboard` feature (chart + narrative aggregation/rendering) and a separate `account` feature (persona-toggle placeholder, profile edit, logout, delete account). Both are thin — standard layer-dependency and Either-error-channel rules apply, nothing feature-specific beyond that.
- The dashboard screen uses the shared `Resource<T>` (`idle`/`loading`/`data`/`error`) view-state type, since it is a single-source, single-fetch-lifecycle screen — do not build a one-off state shape for it, and do not force the narrative fetch into the same `Resource<T>` instance as the chart (they are independent fetches, each can be its own `Resource<T>` if a second one is needed).
- The dashboard is explicitly excluded from the local offline-cache pattern used by entries/chat — it has no `hive_ce` box and is never served from cache; each screen visit is a live fetch. Cache-invalidation behavior for the chart (recalculating after a new entry) is a presentation-layer concern owned by whoever builds this epic, not a shared local-cache mechanism.
- This epic extends the minimal settings-screen stub already scaffolded earlier in the project rather than recreating the screen.
- The 52px avatar shown here reuses the same avatar component already built earlier (previously only used at a 40px size) — do not reimplement it.
- Charting uses `fl_chart` (already pinned for the project).

## UX & Interaction Patterns

- Dashboard empty/sparse states: zero entries shows a placeholder chart icon and "Comece a registrar..." with no summary text at all (nothing to summarize, not a failure); exactly one entry shows a single bar with "Ainda é cedo pra ver um padrão..."; more than thirty entries shows a 10-bar chart with the AI narrative paragraph below it.
- Narrative-unavailable is a distinct visual state from the zero-entries empty state: when only the narrative call fails, the chart still renders normally and a clear "narrative unavailable" message appears in its place — never a blank space, never conflated with having no data.
- Profile name editing: tapping the pencil icon beside the name switches it to an inline editable field and the pencil icon itself changes to a check icon — the only place in the product where an icon's meaning changes rather than just its color. Confirming saves and reverts to display mode; tapping away without confirming also reverts to display mode. There is no separate "edit profile" screen.
- The account-deletion confirmation dialog uses a red (`colorError`) title — the only product-wide pattern where title color (not just an icon or badge) is the signal distinguishing an irreversible action from a routine interruption like session expiry (which uses a neutral title). This color must never be muted or reused for non-destructive confirmations.
- The account-deletion dialog traps focus until dismissed or confirmed, reusing the same focus-trap overlay behavior already used by the session-expired overlay — no interacting with the scrim-covered screen underneath while it's open.
- General overlay conventions apply: a scrim fades in first, the dialog/sheet sits at most one level deep over the base screen, and under reduced-motion settings the scrim/entrance animation is skipped in favor of showing the final state immediately.

## Cross-Story Dependencies

- Story 8.2's narrative text is fetched independently alongside Story 8.1's chart, but visually appears only once the chart from 8.1 is already rendering — 8.1 must ship the chart and its three entry-count states before 8.2's narrative/unavailable states are meaningful to build on top of.
- Story 8.3 depends on the avatar component already built in an earlier epic; it must be reused at a new fixed size, not reimplemented.
- Story 8.5's focus-trap dialog behavior depends on the same focus-trap pattern already implemented for the session-expired overlay elsewhere in the app; reuse it rather than building a second implementation.
- Stories 8.4 and 8.5 both route to the same post-action destination (the login/vault screen) — keep that destination logic shared rather than duplicated between logout and account deletion.
- The whole epic depends on entries existing (for the dashboard to have anything to aggregate) and on the auth session mechanism built in the foundation unit (for logout/deletion to have a session to end).
