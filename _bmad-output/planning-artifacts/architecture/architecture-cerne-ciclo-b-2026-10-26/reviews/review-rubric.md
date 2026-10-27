# Rubric Walk — ARCHITECTURE-SPINE.md (Cerne)

**Verdict:** CONDITIONAL PASS — the spine is accurate and well-verified everywhere it speaks (AD-3/AD-4/AD-10's factual claims all check out against `error-taxonomy.md`, `sync-badge.md`, and `openapi.yaml`), but it leaves one of its 11 bound build units (RF03) with no real governing decision behind a false citation, and is self-contradictory about whether the env-loading mechanism is decided or open.

Reviewed as a fresh reader, independent of the drafting session. Checked: `ARCHITECTURE-SPINE.md` in full, `docs/input/requirements.md`, `docs/input/backend/error-taxonomy.md`, `sync-badge.md`, `README.md`, `api/openapi.yaml` (grep spot-check), and `_bmad-output/forge/f000-foundation-decisions/forged-idea.md`.

---

## Critical

### C1 — RF03 (vault) has zero governing AD, and its one citation is fabricated
The Capability → Architecture Map's RF03 row reads: `Governed by: AGENTS.md vault policy (local-only, zero Either plumbing)`. There is no such section, sentence, or policy anywhere in `AGENTS.md` — I read the file in full; it covers layout, policy bullets (docs/input immutability, backend-contract conventions, design tokens, RF10's port rule) and nothing about biometrics, PIN, vault, or local-only state. This is a citation to a document that doesn't contain the claim.

Worse, the actual decision this row is gesturing at already exists and is more specific than what's cited: `_bmad-output/forge/f000-foundation-decisions/forged-idea.md` line 8 states *"Both paths [biometric and PIN] owned by one vault state machine"* — a real architectural constraint (one state machine must own both the biometric and PIN-fallback flows, because PIN-checking needs the stored hash and that hash must not be gated behind the biometric success it's standing in for). That is exactly the kind of rule this spine exists to carry forward as an enforceable AD (it fits the AD-7/AD-8 pattern precisely: "one state machine, not two divergent ones"), and it isn't — it's just quietly dropped.

Compounding this: RF03 is the build unit immediately after F000 in the delivery order, and the vault screen (0.1) gates *every* other screen. F000 owns `go_router`'s redirect (AD-8, keyed to `SessionStatus` only). Nothing in the spine says how the vault's lock state composes with that redirect — whether vault is a second redirect guard, a route wrapper, or folded into `SessionStatus` somehow. Given AD-7 explicitly forbids BLoC-to-BLoC composition, and AD-8 explicitly scopes to auth-session validity, a vault-built-later session has no rule at all to follow here. This is precisely the "two independently-built units diverge" failure mode the rubric asks about, on a dimension (app-wide access gating) that is unambiguously this altitude's job.

**Fix:** add an AD for the vault state machine (binds: RF03, F000's router) codifying "one local-only state machine owns both biometric and PIN-fallback paths; gates routing via a second redirect input alongside `SessionStatus`, never merged into it" (or whatever the intended composition is), and correct/remove the false `AGENTS.md` citation.

---

## High

### H1 — Env-loading mechanism is simultaneously "deferred" and firmly adopted
The Deferred section lists *"Env-loading mechanism (`flutter_dotenv` vs. `--dart-define-from-file`) is this spine's own `[ASSUMPTION]`... Correct in review if `--dart-define` is preferred"* — framed as genuinely open. But the same document treats `flutter_dotenv` as already locked everywhere else: it's pinned in the Stack table (`flutter_dotenv ^6.0.1`), stated unconditionally in the Consistency Conventions table ("`.env` ... loaded via `flutter_dotenv`"), and drawn into the Structural Seed's infra diagram (`Env -.-> App`, labelled "loaded via flutter_dotenv") with no hedge.

A build-unit session reading only the Stack table or the diagram has no signal this is still negotiable; a session reading only the Deferred section might think no commitment exists yet and pick differently. Since every unit that touches config (effectively all of them, via the DI bootstrap) depends on this choice being singular, an actually-open item here is a real cross-unit divergence risk — which contradicts the spine's own practice elsewhere of resolving "free choice" items into one committed line (e.g., it did this correctly for cache/DI/routing, ratifying the F000 forge session's choices). This item should either be stated as decided (drop it from Deferred, keep the `[ASSUMPTION]` tag as "decided-but-flaggable" the way AD-3/AD-4/AD-9/AD-12/AD-13 use `[ADOPTED]`) or the Stack/Conventions/Diagram should all hedge consistently.

**Fix:** pick one framing. Either promote this to a short AD (`[ASSUMPTION]`-tagged, consistent with how AD-9/AD-10/AD-12/AD-13 already handle "decided now, open to correction") so every other mention can state it unconditionally, or soften the Stack table, Conventions table, and diagram to flag it as provisional everywhere it appears.

---

## Medium

### M1 — Pagination/cursor convention is only decided for chat, not for entries lists or search
`core/cache` in the Structural Seed lists `chat_sessions + cursor` as the only cursor-bearing box. RF06 (`GET /entries/search?...&limit=`) and RF07 (`GET /entries?...`) both page over a `limit` param per `openapi.yaml`/`requirements.md` §6, but the spine gives no convention for how those two screens (built in different units, RF07 then RF06, back-to-back in delivery order) should manage pagination/scroll-position state — AD-12 only settles *which* state-shape wrapper to use (`Resource<T>` for RF06, custom for RF07), not how either paginates. Given RF07's own AC explicitly calls out "without losing scroll position," and RF06 and RF07 share the same underlying list UI pattern, a shared pagination convention (or an explicit note that it's screen-local and each unit decides independently) would close a real gap. As written it's silent, not deferred-with-reasoning like the other open items.

### M2 — Diagram 1's subgraph-to-node edge (`Feature --> Core`) is syntactically unusual
In the Design Paradigm mermaid diagram, `Feature` is a `subgraph` ID and the edge `Feature --> Core` draws directly from the subgraph compound node rather than from a specific child node. Modern Mermaid flowchart renderers do support edges on subgraph IDs, so this likely renders, but it's a less common idiom than drawing the edge from a representative member node (e.g. `DA --> Core`), and worth a second look during the next diagram pass since it's the one place this spine's diagrams deviate from "edges between leaf nodes."

---

## Low

### L1 — Routing/navigation structure beyond the auth redirect is unaddressed and not flagged
Beyond AD-8's `SessionStatus`-keyed redirect, the spine says nothing about route table shape, modal vs. full-route presentation (Screen 2's Insertion Modal), or deep-linking — plausibly a lower-altitude, single-unit-owned concern (mostly F000's to decide once), so this is low-tier rather than a real divergence risk, but it's also not listed under Deferred the way the spine lists its other genuinely-skipped items. A one-line Deferred entry ("per-screen navigation structure beyond the auth/vault redirect — F000's call, revisit only if a later unit needs cross-screen nav state") would make the omission legible rather than silent.

### L2 — `AUTH_INVALID`'s imprecision (requirements.md §11: "invalid credentials / biometrics") isn't corrected in the spine
The F000 forge session explicitly flagged this as wrong — no biometric call ever reaches the server, so `AUTH_INVALID` can only originate from `POST /auth/login` — but the spine's AD-3 just lists the bare code name without carrying that correction forward the way it explicitly did for the `sync_status` mistake (AD-10) and the "10-of-13" error-table mistake (AD-3's own prose). Minor, since the code list itself is correct, but it's an inconsistency in how thoroughly the spine ratifies vs. silently drops the forge session's corrections.

---

## What's solid (for calibration, not part of the "findings" tally)
- AD-3's 14-subtype enumeration, AD-4's 6-retryable-code list, and AD-10's sync-badge derivation were all independently verified against `error-taxonomy.md`, `sync-badge.md`, and `openapi.yaml` and are exact.
- The Capability → Architecture Map covers all 11 bound build units (F000, RF01–RF10) in delivery order, plus RNF05, with no unit missing except RF03's AD column being empty (see C1).
- Deferred items other than env-loading (H1) are each scoped to a single build unit or genuinely project-level (CI/CD, exact fvm patch) and correctly reasoned as safe to defer.
- The two mermaid diagrams are syntactically plausible and each convey real, non-trivial structure (layer dependency direction + cross-feature port; full infra/provider map including the "never calls directly" AI-provider policy).
- Where the spine disagrees with `requirements.md` (sync badge, §8's `sync_status` field), it says so explicitly and cites the winning source per the project's own precedence rule — good practice, just inconsistently applied (see L2).
