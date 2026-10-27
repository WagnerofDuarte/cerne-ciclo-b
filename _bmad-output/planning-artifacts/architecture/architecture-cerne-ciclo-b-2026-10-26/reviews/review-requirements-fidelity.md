# Requirements Fidelity Review — ARCHITECTURE-SPINE.md vs requirements.md

**Verdict: MINOR GAPS** — no outright contradictions found; delivery order, Fixed/Free stack split, extension-feature scoping, and several subtle ACs (RF02's four states, RF05's zero-entries export failure, RF06's AND-logic nuance, the `sync_status` correction) are all faithfully preserved. The gaps are a cluster of silently-dropped numeric constants and two under-specified acceptance criteria that the spine's AD/Convention/Deferred structure never mentions, not even as an explicit "left to feature build time" note.

---

## Findings

### 1. Three of eight "Fixed — not to be reinterpreted" config parameters (sec.10) have zero representation in the spine

- **requirements.md says:** sec.10 lists 8 parameters explicitly marked "Fixed values — not to be reinterpreted": 5-min background timeout (RF03), 300 ms search debounce (RF06), N=5/T=2min insight trigger (RF08), 0/1/>30-entry dashboard rendering scenarios (RF09), ≥80% domain coverage (RNF07), <100ms local UI latency (RNF01), >300ms loading-indicator threshold (RNF01), 15 network-error-scenario matrix (RNF09).
- **The spine says:** only 3 of the 8 are elevated anywhere into an AD, Convention, or Structural Seed line — the 5-min timeout appears in the Structural Seed (`vault/ … 5-min background timeout`), the 80% coverage gate and the 15-scenario matrix both appear in the Consistency Conventions table. The other 5 — the 300 ms search debounce, the N=5/T=2min insight-trigger values, the 0/1/>30 dashboard-rendering scenario counts, and RNF01's two latency thresholds (<100ms / >300ms) — appear nowhere: not in an AD, not in a Convention row, not even as a one-line Deferred acknowledgment that they're intentionally left to feature-level implementation.
- **Why it matters:** the spine explicitly treats "Fixed value, not to be reinterpreted" parameters as worth promoting into durable artifacts when they have cross-cutting weight (it did this for the 5-min timeout, the coverage gate, and the error-matrix count). Dropping the other five with no trace at all — rather than an explicit Deferred line like it used for other open items — creates a risk that a later build unit (e.g., whoever builds RF08's insight trigger, or RF09's dashboard renderer) has no architectural anchor for these fixed numbers and no signal that the spine considered and intentionally excluded them versus simply missed them.

### 2. RF10's idempotency acceptance criterion is not addressed by AD-6 (or anywhere else)

- **requirements.md says:** RF10's AC: "Saving the same message twice does not create duplicate entries (idempotency)."
- **The spine says:** AD-6 ("Cross-feature access only through a domain-layer port") is the only AD bound to RF10, and it governs exclusively the import-boundary problem (chat must call `entries/domain`'s `SaveEntryUseCase`, never `entries/data` directly). It says nothing about how double-invocation of that use case is prevented — whether via a client-side check-before-create, a dedup key derived from `chatMessageId`, or reliance on an (undocumented in the spine) backend-side uniqueness constraint. Neither AD-13 nor the Deferred section mentions idempotency either.
- **Why it matters:** AD-6 is the AD a future reader would look to for "what does RF10's architecture guarantee," and because it is RF10's only governing AD, its silence on idempotency could be misread as "idempotency is not an architectural concern" — when in fact the dedup mechanism (does `SaveEntryUseCase` take `chatMessageId` and treat it as an idempotency key? is there a local already-saved flag on the message?) is exactly the kind of cross-layer design decision a port signature should settle once, not leave to whichever unit implements RF10 to improvise.

### 3. RF08's trigger-mechanism acceptance criteria are only half-covered

- **requirements.md says:** RF08's AC has two parts: (a) "Trigger after N = 5 user messages OR T = 2 min of inactivity — fires exactly once per satisfied condition," and (b) "If insight generation fails … the main chat keeps working normally."
- **The spine says:** AD-13 ("`isolatedSideEffect` contract") addresses only part (b) — the failure-isolation half shared with RF10. Part (a) — the counting/timer logic that decides *when* to fire, and the "exactly once per satisfied condition" de-dup guarantee — is not mentioned by any AD, Convention, or Deferred entry. The Capability → Architecture Map lists RF08 as governed only by AD-13.
- **Why it matters:** "exactly once per satisfied condition" is a stateful guarantee (needs to track whether N or T has already fired this session) that interacts with the chat feature's state machine; leaving it fully unaddressed means a reader can't tell whether the spine considered it out of architectural scope on purpose or simply didn't carry it over from requirements.md's sec.10 "Fixed" table (see Finding 1).

### 4. RF09's Deferred note covers only one of its two AAC nuances — the 0/1/>30 rendering scenarios are dropped where cache-invalidation was kept

- **requirements.md says:** RF09 has two distinct AC clusters: "renders correctly in three scenarios: zero entries, one entry, more than 30 entries" and, separately, "the aggregation recalculates correctly after an entry is created (cache-invalidation test)."
- **The spine says:** the Deferred section explicitly carries forward the cache-invalidation nuance ("Dashboard cache-invalidation behavior (RF09 AC) — a presentation-layer concern for whichever unit builds RF09, not a local-cache architecture decision") but never mentions the 0/1/>30-entries rendering-scenario requirement at all, despite it being the other AC in the same requirement and one of the 8 sec.10 fixed parameters (see Finding 1).
- **Why it matters:** this shows the drop in Finding 1 isn't just an oversight at the table level — the spine's author was actively curating which RF09 nuances to preserve in Deferred, and chose to keep one and silently drop the other, which is exactly the kind of "terse AD flattening a quiet requirement" pattern this review was asked to catch.

---

## Confirmed clean (no issues found)

- Delivery order: the spine's Capability → Architecture Map row order and AD-13's explicit "RF04 → RF10 → RF08" sub-ordering both match sec.12's `F000 → RF03 → RF01 → RF02 → RF07 → RF06 → RF04 → RF10 → RF08 → RF05 → RF09` exactly.
- Sec.13 Fixed items (flutter_bloc, Clean Architecture, fpdart/`Either`, mocktail, whisper_ggml, design_tokens.dart, iOS-portrait-only, folder convention) are all honored without substitution; Free items (routing, HTTP client, cache, DI, secure storage, biometrics, charts) are the only slots where the spine commits to concrete packages (go_router, dio, hive_ce, get_it, flutter_secure_storage, local_auth, fl_chart) — and the one substitution (Hive → hive_ce) is explicitly logged as a correction, as expected.
- Extension features (dynamic categorization/manual tags, action plans, persona toggle) are correctly kept inert — Deferred explicitly disclaims architecture ownership of persona wiring and manual-tag UI; no AD assigns them real logic.
- RF02's four capture states and RF07/RF09's exclusion/inclusion in `Resource<T>` (AD-12) correctly mirror requirements.md's named states.
- RF05's "zero-entries export must be a handled error, not an empty PDF or crash" is directly represented by the `ExportEmptyPeriod` Failure subtype in AD-3.
- RF06's AND-logic-between-filters vs. still-open search+filter combination is correctly split between "fixed" and "open PRD question" in the Deferred section, matching requirements.md's own framing.
- The retryable-code set in AD-4 (6 codes) matches sec.11's `retryable: yes` codes exactly.
- The `sync_status` correction (AD-10) is not a fidelity violation — requirements.md sec.8 itself states "where this table differs from the API contract, the contract prevails," so the spine is following requirements.md's own precedence rule, not overriding it.
