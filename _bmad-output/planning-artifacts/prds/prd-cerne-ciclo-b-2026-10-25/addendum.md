# Addendum: Cerne PRD

Supporting depth that doesn't earn a place in the PRD body — implementation decisions, competitive/market context, regulatory citations, and corrections carried forward from prior planning sessions. Nothing here overrides `prd.md`; it explains *how* and *why* for things the PRD states only as *what*.

## Implementation decisions (F000 technical foundation)

Source: `_bmad-output/forge/f000-foundation-decisions/forged-idea.md`, which supersedes `_bmad-output/planning-artifacts/research/technical-flutter-package-selection-for-f000-and-r-2026-10-25/research.md` where the two disagree.

**Networking & data:**
- **Routing:** `go_router`, not `auto_route`. A single `redirect` callback keyed off one `SessionStatus` stream handles auth gating; no per-screen checks, no codegen. Revisit `auto_route` only if compile-time route-argument checking becomes worth a second codegen pipeline.
- **HTTP client:** `dio`, not `package:http` or `chopper`. One interceptor owns the `apikey`/`Authorization` headers. Retries are attempted only for server codes marked `retryable: true` (`NETWORK_TIMEOUT`, `NETWORK_OFFLINE`, `PII_CHECK_FAILED`, `EMBEDDING_FAILED`, `AI_GENERATION_TIMEOUT`, `RATE_LIMITED`) — never the 7 non-retryable codes.
- **Local cache:** **Hive** — a deliberate override of `research.md`'s own recommendation. The research scored `drift` highest and flagged Hive/Isar as a risk (both forks are now community-maintained: `hive_ce`, `isar_community`). `forged-idea.md` picked Hive anyway because the app never needs local filter/sort/join — all filtering, date-range, and semantic search are server-side query params (RF06/RF09); the client only ever caches by key. Three boxes (`entries` by id, `chat_messages` by session id, `chat_sessions` by id) plus a cached cursor string. This is a considered override, not a missed risk — re-check only if a future requirement ever needs local querying.
- **DTOs/entities:** `freezed` + `json_serializable`, justified by field count (Entry has 11 required fields) and used for sealed unions (`Failure`, `Resource`).

**Architecture & contracts:**
- **DI:** `get_it`, plain manual registration, one per-feature registration function called from `main`. No `injectable`/codegen. Runner-up considered and rejected: Riverpod-as-DI (no production precedent paired with `flutter_bloc` in this stack).
- **Failure hierarchy:** a sealed class with 13 server-mirrored subtypes plus one local-only `MalformedResponse` subtype (hardcoded `retryable: false`).
- **`isolatedSideEffect` contract:** a never-throws wrapper returning `Either<Failure, T>`, fixed as a contract now but its implementation deferred to RF10 (the shared entries use case that FR-28 depends on); must live in `core/`.
- **`Resource<T>` view-state generic:** restricted to single-source fetch screens only (RF06 results, RF09 dashboard). Explicitly rejected for RF02 (the capture pipeline, which has its own multi-stage state machine) and RF07 (which composes three independent streams — auth, sync, and entry data — that `Resource<T>` can't represent cleanly).

**Security:**
- **Secure storage + biometrics:** `flutter_secure_storage` + `local_auth`. Rejected `biometric_storage` because it can't satisfy the no-lockout fallback requirement (FR-5): biometric failure and PIN fallback are owned by a single state machine, since checking the PIN hash after a failed biometric attempt needs access that a biometric-gated storage API can't provide — and since repeated biometric failures can trigger an OS-level lockout clearable only by the user's *device* passcode (not the app's PIN), which the app cannot programmatically reset. The app must instead detect that lockout state and route to its own PIN fallback rather than keep retrying against the OS.

**UI:**
- **Chart package:** `fl_chart`.

**Testing:**
- **Test harness:** `mocktail` stubbing a single `ApiClient` interface per repository test; one shared table-driven helper covers the 5 endpoints × 3 failure types = 15 scenario matrix (RNF09).

**Open risk (not a decision):** the combination of `dio`, `flutter_secure_storage`, and `get_it` has not been pre-verified together; this is a flagged, accepted risk to resolve during F000's build, not a settled fact.

## Corrections carried forward (resolve before/during build, don't re-discover as new bugs)

- `requirements.md` §8's data model lists an `entries.sync_status` column. This directly contradicts `sync-badge.md`/`openapi.yaml`, which have no such field — the Sync Badge is purely client-derived from `updatedAt`/`serverRevision`. `requirements.md` itself states backend docs win on conflict; `forged-idea.md` already applied that precedence rule. Treat `sync-badge.md` as authoritative.
- `requirements.md` §11 lists only 10 of the 13 error-taxonomy codes — an incomplete excerpt, not the full set. `docs/input/backend/error-taxonomy.md` is the authoritative, closed 13-code list (reproduced in `prd.md`'s Cross-Cutting NFRs section).
- `requirements.md` §11's wording around `AUTH_INVALID` imprecisely implies it could relate to biometric failures. It can only originate from password-based login — biometric authentication never touches the backend.
- `prototype-extract.md` §2.6 shows the avatar area with an "editable name/e-mail" affordance, but `openapi.yaml`'s `PATCH /account/settings` has no `email` field and explicitly rejects email changes. `prd.md` FR-41 correctly scopes profile editing to display-name only; this note exists so the prototype's visual email field isn't reintroduced later by someone trusting the mockup literally.

## Competitive landscape and market context

*(Source: PRFAQ and its distillate — kept here in full since the PRFAQ itself is a working document, not a citable PRD section.)*

- **Named comparables:** Mindsera (criticized for feature-sprawl/gimmicky AI), Rosebud (therapist-designed framing risks implying clinical utility it doesn't have), Reflectly (mood-tracking-shallow, blurs into mental-health-adjacent claims), Day One / Journey / Stoic (AI bolted on as a paywalled add-on, not core to the product).
- **#1 cross-competitor complaint identified:** generic, context-free AI responses — directly the gap Cerne's RAG-memory bet is aimed at.
- **Market sizing (context only, not a target):** digital journal app market estimated at $5.69B (2025) → $6.34B (2026), ~11.4% CAGR → ~$9.64B by 2030; mobile >60% of usage. Used only to frame the category in the PRFAQ, not as an internal success metric — `prd.md` §7 explicitly has no adoption-based metrics.
- **Rejected framing — "AI companion/friend":** deliberately rejected to avoid the companion-chatbot category now under regulatory pressure — cited: Italy/Luka (Replika) €5M fine, and a 2026 California AI-companion disclosure law.
- **Headline test — memory-first vs. privacy-first:** a privacy-first headline was tested against a memory-first headline for the PRFAQ's mock press release; memory ("the AI that doesn't forget me") tested as the louder, more universal pain point, with privacy demoted to a supporting proof point rather than the lead.

## Tech stack already fixed upstream (server-side, not app decisions)

Named in the brief/PRFAQ as already-decided foundation, consistent with `AGENTS.md`'s "never call an AI provider directly" rule — all three run server-side only, never called from the app:
- **Claude Sonnet 5** — chat responses (RF04).
- **Claude Haiku 4.5** — vision/OCR (RF02), PII scrubbing (RNF02), export narrative (RF05), insight generation (RF08), dashboard narrative (RF09).
- **Voyage AI `voyage-4`** — embeddings (RF01 capture pipeline, RF06 semantic search).
