# Epic 5 Context: Semantic Search & Filtering

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Users can find any Entry again by meaning rather than exact keyword match, and narrow results by source and date range, with search input debounced and filter-clearing restoring the full list without a reload. This epic realizes journey UJ-4 (finding a past entry by meaning, then narrowing with filters) and depends on Epic 4's timeline screen (Meus Registros) as the surface search and filtering mount onto. It extends the same `EntriesRepository` port Epic 3 introduced with `list`/`search` capabilities — it introduces no second Entry model — but stands as its own epic because it is its own user-facing milestone, not a structural completion of Epic 4's job.

## Stories

- Story 5.1: Semantic Search with Debounced Input
- Story 5.2: Metadata Filters
- Story 5.3: Combined Search + Filter & Non-Disruptive Clearing

## Requirements & Constraints

- Search is meaning-based, not literal: a query for one word must surface entries that only use a semantically related word, never requiring exact text match.
- Search input is debounced 300ms client-side before any request fires — the backend performs no throttling of its own, so the debounce is entirely the app's responsibility.
- Filtering is limited to source (manual/audio/photo/chat) and date range (`dateFrom`/`dateTo`) only. There is no tag/category filter anywhere — tags exist only as a read-only, embedded field on an Entry (populated by seed data, never user-created or filterable).
- Filtering with no active search term queries the plain entries-list; filtering combined with an active search term queries the semantic-search endpoint, carrying the same filter parameters. Multiple simultaneous filters (and a search term, when present) combine with AND semantics only — never OR.
- Clearing active filters restores the full unfiltered list in place, without a full screen reload or re-mount.
- The app is cloud-only: offline permits viewing already-cached entries but never writing. After a reconnect, the local cache must stay duplicate-free — no entry appears twice.
- A loading indicator appears only once a request exceeds ~300ms; faster responses show no loading UI at all.

## Technical Decisions

- Call the backend only via its function name, never the literal REST path: entries-list at `{FUNCTIONS_BASE_URL}/entries-list` (used for `GET /entries` with `source`/`dateFrom`/`dateTo`/`cursor`/`limit`) and entries-search at `{FUNCTIONS_BASE_URL}/entries-search` (used for `GET /entries/search` with `q`/`source`/`dateFrom`/`dateTo`/`limit`, capped at 50). Note entries-search has **no** `cursor` parameter — unlike entries-list, it is not paginated.
- Extend the existing `EntriesRepository` port (owned by `entries/domain`, introduced in Epic 3) with `list` and `search` methods; the port still exposes create and read only in spirit — no update/delete is ever added, and no second Entry model is created for search results.
- Offline carve-out: semantic search has no client-side vector index, so a search attempted offline resolves immediately to `Failure.networkOffline`, exactly like a write — it is never served from the local cache. Plain filtered list reads, by contrast, may still fall back to the cached Hive box.
- Every query dimension (source, date range, the search term itself) must be a server-side query parameter; the Hive box continues to store exactly what the server returned, keyed by id — no local filtering, joining, sorting, or re-deriving of the cached collection is ever implemented client-side.
- Screens in this epic that are single-data-source, single-fetch-lifecycle use the shared generic `Resource<T>` (`idle`/`loading`/`data`/`error`) state wrapper from `core/`, rather than defining a feature-specific sealed state class.
- Repository methods still return `Either<Failure, T>`, consistent with the rest of the app's resilience contract.

## UX & Interaction Patterns

- Search bar: paper-elevated input with a trailing funnel icon, permanently docked at the top of Meus Registros; it is never submitted via a button — only the debounced live query matters.
- Filter chips: sage background, dark-olive text, fully rounded. Single-choice (date range) and multi-choice (source) filters look visually identical and differ only in underlying behavior.
- Filter sheet: a `radiusLg`/`elevation2` bottom sheet with filter groups labeled in the mono-caption text style.
- Representative flow from the design walkthrough: a user searches "ansiedade" and sees results that only mention a related word ("nervosismo"); she then opens the filter sheet and narrows to a date range plus the audio source, and results re-narrow with AND logic.
- Entrance choreography is limited to the two system-wide animations (`sheetUp` for the bottom sheet, `scrimIn` for any scrim) — no other motion is introduced.
- Filter chips and the search/filter surfaces are a tight-fit area for Dynamic Type — verify text does not truncate or clip at the largest accessibility size.

## Cross-Story Dependencies

- Depends on Epic 4: search and filtering operate over the Meus Registros timeline screen and the entries Hive cache Epic 4 already built; there is nothing to search or filter before that exists.
- Depends on Epic 3's `EntriesRepository` port (introduced under `entries/domain`) being extended here rather than replaced — Story 5.1/5.2 add `search`/`list` capabilities to that one existing port.
- Story 5.3 depends on both 5.1 (search) and 5.2 (filters) being in place, since it is specifically the combined-query and clearing behavior layered on top of both.
