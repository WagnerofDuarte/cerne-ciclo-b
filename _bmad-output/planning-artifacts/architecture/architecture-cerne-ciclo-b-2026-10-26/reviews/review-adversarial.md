---
name: review-adversarial
reviews: ARCHITECTURE-SPINE.md (architecture-cerne-ciclo-b-2026-10-26)
lens: adversarial — two-units-one-level-down incompatibility hunt
created: 2026-10-26
---

# Adversarial Review — Architecture Spine (Cerne)

**Verdict: real holes.** Four of the six attack pairs below produce concrete, letter-compliant-yet-incompatible builds; two are already closed (confirmed, with evidence) and are recorded so a future reviewer doesn't re-raise them.

---

## 1. RF01 (capture) vs RF07 (entries) — two owners of the `Entry` entity and `POST /entries`

**Scenario.** Delivery order is `F000 → RF03 → RF01 → RF02 → RF07 → …`. RF01's own acceptance criteria ("Every capture becomes a persisted record (`POST /entries`)") makes RF01 — not RF07 — the first build unit that must create entries, and it is built two full units *before* `features/entries/` exists. Yet AD-6's example ("`entries/domain` exposes `SaveEntryUseCase`") and the Structural Seed both attribute `features/entries/` and its `SaveEntryUseCase` to **RF06/RF07**. The Capability → Architecture Map makes it worse: RF01's row lists only `AD-1, AD-2, AD-9` as governing ADs — AD-6 (cross-feature port) and AD-11 (entry create/read only) are never cited against RF01 at all.

A session building RF01 to the letter has no signal that it must scaffold `features/entries/domain/` first; the obvious, AD-1/AD-2/AD-9-compliant move is to build a `createEntry` call straight inside `features/capture/data` (own repository, own `Entry`-shaped DTO, own hive_ce box) because nothing tells it `features/entries/` is the *owning* feature for an entity capture is only using. Two units later, the RF07 session reads the Structural Seed, sees "`entries/` — RF06, RF07 … exposes `SaveEntryUseCase` (AD-6)," and — also fully AD-compliant — builds its *own* `EntriesRepository`/`Entry` model/hive_ce box from scratch for listing. Both are AD-1/AD-2/AD-6-literal. The result: two `Entry` models, two cache boxes, two repository owners of the same backend resource, and capture's writes never reach whatever cache/sync-badge state (AD-10) RF07 built, because RF07 didn't know capture already wrote one.

**Real or closed?** Real — and the most severe of the six; it's a direct "two owners of one entity" collision, worsened by the Capability Map actively omitting the AD-6 link on RF01's row.

**Proposed fix.** Tighten AD-6 (or add AD-6a): *"`features/entries/` — including `Entry`, `EntriesRepository` (create + read), and `SaveEntryUseCase` — is scaffolded at RF01 time, not RF07 time, because RF01's own AC requires `POST /entries`. RF01 is the first consumer of `SaveEntryUseCase`/`EntriesRepository.createEntry`; RF07 only adds the read/list/timeline methods to that already-existing repository. RF01's row in the Capability → Architecture Map must cite AD-6 and AD-11."* Also correct the Capability Map row for RF01 to add `AD-6, AD-11` and fix the Structural Seed comment on `entries/` to read `RF01, RF06, RF07`.

---

## 2. F000 (auth/session) vs RF03 (vault) — two independent navigation gates, one `go_router`

**Scenario.** F000 owns "base nav" and wires `go_router`'s redirect against the single `SessionStatus` stream (AD-8: authenticated/unauthenticated/expired → login redirect). RF03 (vault: biometric/PIN, 5-minute background timeout) is explicitly "local-only, zero `Either` plumbing" per the Capability Map, and is a *second*, independent gate: a valid Supabase session can still be sitting behind a locked vault after backgrounding. `go_router`'s top-level `redirect` callback is singular — composing two independent gating conditions onto it normally requires merging listenables (`Listenable.merge`) or chaining redirect logic. No AD says this.

F000, built first, has no reason to anticipate a second gate and may wire `redirect` as a plain closure over `SessionStatus` with no extension point. RF03, built right after and in a separate session with no visibility into F000's actual router wiring beyond what the spine documents (which says nothing about redirect composition), must now either (a) add a second competing `redirect` to the same `GoRouter` instance — which silently overrides or race-conditions with F000's — or (b) bypass routing entirely and gate via a global overlay/`builder`. Either choice is AD-8-compliant to the letter (AD-8 only pins *session* status, not vault-lock status, as the single source of truth) and neither is wrong per the ADs as written — but the two mechanisms were never required to compose, so whichever the RF03 session picks, F000 was never told to leave room for it.

**Real or closed?** Real. AD-8 binds F000's redirect and RF07's composite state to `SessionStatus`, but never mentions RF03's vault-lock state at all, and no other AD governs multi-gate composition on the router.

**Proposed fix.** New AD: *"App-level navigation gating is a single composed function, not one gate per feature. `core/` (or `features/auth/`) exposes one `Listenable`/stream that merges `SessionStatus` (AD-8) with the vault feature's lock state; `go_router`'s top-level `redirect` reads only that merged signal. RF03 does not add a second `redirect` callback or a parallel navigation-interception mechanism — it registers its lock state into the merge point F000 leaves for it."*

---

## 3. RF08 (proactive insights) vs RF10 (save-to-journal) — `isolatedSideEffect`'s signature pins types, not await semantics

**Scenario.** AD-13 fixes `isolatedSideEffect`'s signature (`Future<Either<Failure, T>> Function(Future<T> Function())`) and says it "ships with RF10 (first consumer)," with RF08 reusing it. But every repository method is *already* non-throwing by AD-2 (`Either` at the boundary) — so the signature alone doesn't say what `isolatedSideEffect` adds. The two plausible, both letter-compliant, implementations diverge exactly on the property AD-13 was written to standardize:

- RF10's save-to-journal only needs "never let a failed save crash the chat screen, just show a failed sync badge" — a session building this first could reasonably implement `isolatedSideEffect` as a synchronous `try/await` wrapper that still *awaits* the inner future before returning, just without rethrowing. That satisfies "never throws past itself" and every acceptance criterion RF10 has.
- RF08's proactive insight generation is described as a side channel that must not block the chat send/receive flow while the (potentially slow, Claude-backed) insight call runs. That needs genuine fire-and-forget semantics — kick off the future, return/continue immediately, surface the `Either` asynchronously later (e.g., via a stream) — not an awaited wrapper.

Both are "`Future<Either<Failure, T>> Function(Future<T> Function())`"-shaped. Nothing in AD-13 says whether the helper awaits before returning or detaches. If RF10 builds (and ships, per AD-13) the awaited version, RF08 either misuses it (blocking insight generation on the chat flow after all — the exact bug AD-13 exists to prevent) or has to build a second, incompatible variant anyway — defeating "RF08 reuses it from `core/` without a cross-feature import," which only works if the one implementation already does what RF08 needs.

**Real or closed?** Real. AD-13 closes "two different failure-isolation wrappers" at the type level but not at the concurrency-semantics level, which is the part that actually matters for RF08.

**Proposed fix.** Tighten AD-13: *"`isolatedSideEffect` does not await its inner future before returning to the caller; it schedules the future, returns immediately (`Future<Either<Failure,T>>` that completes independently of the caller's control flow), and never couples the caller's continuation to the side effect's completion. Any consumer that needs the resolved `Either` (e.g., to update a sync badge) subscribes to it as a separate, non-blocking completion — never by awaiting the wrapper inline in the main request path."*

---

## 4. RF04 (chat/RAG) vs RF08 (proactive insight) — no AD names RF04's state shape, so RF08 can't be sure what it's composing onto

**Scenario.** AD-12 is explicit that `Resource<T>` is used only for single-source/single-fetch screens, and explicitly carves out RF02 (capture state machine) and RF07 (composite auth×sync×data state) as needing their own sealed state. RF06 and RF09 are explicitly named as `Resource<T>` users. **RF04 (chat, with its SSE message stream and "AI status indicator") is named in neither list.** A chat SSE stream is multi-event and long-lived — arguably it should be excluded from `Resource<T>` the same way RF02 is, but AD-12's text doesn't say so, so an RF04 session reading AD-12 literally ("used only by screens with one data source and one fetch lifecycle") could defensibly go either way: treat the whole chat screen as one `Resource<T>` fetch (wrong fit, but not explicitly forbidden) or build a bespoke sealed class (not explicitly required either).

RF08, built immediately after RF04 and explicitly needing to overlay a proactive-insight signal onto the same chat screen without a BLoC-to-BLoC reference (AD-7), has to compose its insight stream with whatever RF04 chose. If RF04 picked `Resource<T>`'s 4-state enum for the whole screen, there is no slot for "insight arrived" that doesn't collide with `data`/`loading` for the primary message stream — RF08 then has no AD-sanctioned shape to merge into, and is forced into a workaround (e.g., a second parallel `Resource<T>` read by the widget tree) that AD-12 never anticipated and that two independently-built sessions would not converge on the same way.

**Real or closed?** Real, though milder than #1–#3 — it's an omission (RF04 missing from AD-12's named list) rather than a direct contradiction.

**Proposed fix.** Extend AD-12's rule to explicitly name RF04: *"RF04's chat/RAG screen (SSE message stream + AI status indicator) defines its own sealed state class, like RF02 and RF07, not `Resource<T>` — multi-event streams are categorically excluded from `Resource<T>`, not just the two named screens. RF08's proactive-insight signal is injected into RF04's chat BLoC as an additional domain-layer stream the BLoC listens to independently (per AD-7), not as a new enum case retrofitted onto RF04's existing state after the fact."*

---

## 5. RF06 (semantic search) vs `core/cache` (AD-9) — offline fallback semantics for search are undefined, and requirements.md itself is split

**Scenario.** AD-9 states a blanket rule: "Read operations transparently fall back to the local `hive_ce` cache." `GET /entries/search` is a read (`entries.search`, `bearerAuth`, `x-cerne-function: entries-search`). But requirements.md is internally inconsistent about what that means for *search* specifically: §6's RF06 AC says "Results from the local read cache stay consistent with the server after reconnection… offline allows only viewing already-cached data, not writing" (implying a cache-backed, degraded-but-present offline experience), while §13's error-taxonomy table lists `NETWORK_OFFLINE` as "action blocked (see RF04/**RF06**)" (implying search is simply blocked offline, like a write).

The spine never resolves this contradiction — AD-9 just repeats the generic "reads fall back to cache" rule without addressing that semantic search has no meaningful local fallback (there's no on-device embedding index; the cache only holds previously-*fetched* entries, not a search index). Two sessions building RF06 independently, both reading AD-9 literally, could land on:
- **Session A:** search is a "read," so it must fall back to cache like everything else — implemented as: on `NetworkOffline`, silently re-filter the last-fetched *unfiltered* entries list by a naive substring match and show that as "results," because that's the only thing the cache actually contains.
- **Session B:** search inherently requires a live embedding call it cannot serve from cache, so it should behave like a write under AD-9 — return `Either.left(NetworkOffline)` immediately, no cache attempt, matching the error-taxonomy table.

Both comply with AD-9's text; they produce opposite UX (silently-different "results" vs. an explicit blocked-action error), and whichever a given session picks, nothing in the spine would flag it as wrong — yet RF06's own AC explicitly anticipates this exact ambiguity.

**Real or closed?** Real — and already flagged as fuzzy by requirements.md itself, which makes it worse that the spine's AD-9 doesn't resolve it (the Deferred section even calls out the search+filter combination as open, but not this offline-semantics split).

**Proposed fix.** Tighten AD-9: *"AD-9's cache-fallback rule applies only to reads that return previously-synced records as-is (`entries.list`, `entries.get`, `chat.sessions.list`, `chat.messages.list`). Reads that require a live server-side computation with no on-device equivalent — `entries.search` (semantic embedding) foremost — are offline-blocked exactly like writes: `NetworkOffline` is returned immediately, with no cache-filtered substitute ever presented as 'results.' RF06's screen falls back only to redisplaying its own last-successful search result set (frozen, with an explicit stale/offline indicator), never to live-filtering the general entries cache."*

---

## 6. (Checked, not real) RF09 (dashboard) vs RF07 (entries/timeline) — entry aggregation

**Scenario considered.** RF09's dashboard needs period aggregates and a narrative; RF07 already owns the entries timeline/cache. The adversarial hypothesis was that RF09 would need to reach into `features/entries/` (via an AD-6 port) to compute aggregates client-side from the same entries RF07 already fetched/cached, risking a second, divergent aggregation path.

**Why it's not real.** Verified against `docs/input/backend/api/openapi.yaml`: `GET /dashboard/aggregate` (`dashboard-aggregate-get`) returns fully server-computed `buckets`/`totals` keyed by date and source, and `GET /dashboard/narrative` (`dashboard-narrative-get`) returns a server-generated `text`/`generatedAt` pair — neither response includes entry IDs or any field referencing the `Entry` entity. RF09 never needs to touch `features/entries/` at all; it talks to its own backend endpoints directly, exactly as AD-12 already assumes (RF09 named as a `Resource<T>`-eligible, single-fetch screen for each of the two calls). AD-6's cross-feature-port rule simply isn't triggered here. No fix needed; recorded so a future reviewer doesn't re-raise this pair without checking the contract first.

---

## Summary of proposed spine changes

| # | Pair | Status | Fix target |
| - | --- | --- | --- |
| 1 | RF01 vs RF07 (`Entry` ownership) | Real (severe) | Tighten AD-6 + fix Capability Map row for RF01 + fix Structural Seed `entries/` comment |
| 2 | F000 vs RF03 (nav gates) | Real | New AD on composed `go_router` redirect/listenable |
| 3 | RF08 vs RF10 (`isolatedSideEffect`) | Real | Tighten AD-13 to pin non-blocking/detached scheduling semantics |
| 4 | RF04 vs RF08 (chat state shape) | Real | Extend AD-12 to name RF04 explicitly and exclude multi-event streams generally |
| 5 | RF06 vs AD-9 (search offline semantics) | Real | Tighten AD-9 to scope cache-fallback to as-is reads only; search is offline-blocked |
| 6 | RF09 vs RF07 (entry aggregation) | Not real (confirmed via contract) | None |
