# Reconciliation: requirements.md vs. prd.md

Source of truth: `docs/input/requirements.md`
Checked against: `_bmad-output/planning-artifacts/prds/prd-cerne-ciclo-b-2026-10-25/prd.md`
Date: 2026-10-25

## 1. Acceptance-criteria coverage, RF01–RF10

Method: every bullet under "Acceptance criteria:" in requirements.md §1 was matched against the "Consequences (testable)" bullets (or, where absent, the FR description text) under the PRD's corresponding FR group.

| RF | Criterion | PRD coverage |
|---|---|---|
| RF01 | Three modalities → same persisted-entry format | FR-8–10 consequences ✓ |
| RF01 | Cancelling midway creates no partial/empty entry | FR-11 ✓ |
| RF02 | Four visible states (recording/processing/transcribed/error) | FR-12 (audio), FR-13 (OCR, mirrored) ✓ |
| RF03 | Biometric failure → PIN fallback, no lockout | FR-5 ✓ |
| RF03 | 5-minute fixed background timeout | FR-6 ✓ |
| RF04 | Three UI states: streaming, error, complete | FR-22 ✓ |
| RF04 | Dropped stream → partial message stays visible with failure indication | FR-25 ✓ |
| RF05 | Zero-entry export → handled error, not empty PDF/crash | FR-36 ✓ |
| RF05 | Narrative-generation failure still allows raw-data download | FR-35 ✓ |
| RF06 | Semantic match without exact term ("ansiedade"/"nervosismo") | FR-18 ✓ |
| RF06 | 300ms debounce | FR-20 ✓ |
| RF06 | Cache stays consistent/non-duplicated after reconnect | FR-21 ✓ |
| RF06 | Two+ filters combine with AND | FR-19 consequences ✓ |
| RF06 | Clearing filters restores list without screen restart | FR-21 ✓ |
| RF07 | Session expiry mid-view → re-login prompt, no crash, scroll preserved | FR-17 ✓ |
| RF07 | Sync badge updates independently of the auth stream | FR-17 — **loose match, framing reversed.** Requirements.md frames it as "the badge keeps updating correctly independent of auth"; FR-17 instead frames it as "the expired-session overlay is independent of the Sync Badge's update stream." Same two-stream-independence idea but the subject/predicate are swapped. Acceptable as a loose match per the task's own bar, flagged for awareness. |
| RF07 | **No BLoC imports another BLoC directly** | **MISSING.** Not present under FR-14 through FR-17 (§4.5), not folded into the RNF06 restatement (which is specifically about the *domain* layer not importing `flutter`/`data/`, a different rule), and not mentioned anywhere else in the PRD (verified via full-text search for "BLoC" — the only hits are substring matches on "blocks"/"blocked"). This is a specific, testable, named architectural acceptance criterion from requirements.md that has no home anywhere in the PRD. |
| RF08 | Trigger at N=5 msgs OR T=2min, fires once per satisfied condition | FR-30 ✓ |
| RF08 | Insight-generation failure doesn't break main chat | FR-31 ✓ |
| RF08 | Dismissal doesn't change scroll/conversation state | FR-32 ✓ |
| RF09 | Renders correctly at 0 / 1 / >30 entries | FR-37 ✓ |
| RF09 | Aggregation recalculates after new entry (cache invalidation); entries immutable so only create-triggered | FR-39 ✓ |
| RF09 | AI narrative only checked for not breaking UI, never content | FR-38 + feature description scope note ✓ |
| RF10 | Entry creation via shared interface/use case, never direct repo import (ties to RNF06) | FR-27 ✓ |
| RF10 | Idempotent save (no duplicate on double-save) | FR-28 ✓ |
| RF10 | Save failure isolates chat; button returns to retryable state | FR-29 ✓ |
| RF10 | Only user messages get the button; AI responses never do | FR-27 ✓ |

**Net finding for §1:** one acceptance criterion (RF07's "no BLoC imports another BLoC directly") is dropped entirely — not stated, not implied, not substitutable by RNF06 since that rule covers a different layer boundary (domain vs. data/flutter, not BLoC-to-BLoC). Everything else in RF01–RF10 is covered, most of it precisely.

**Downstream consequence:** PRD §7 SM-1 states "Every acceptance criterion stated per-RF in requirements.md §1 passes. Validates FR-1 through FR-42." This claim is not quite accurate as written, since no FR in the §4 FR list carries the BLoC-import criterion forward — there is nothing for that criterion to be validated *by*.

## 2. NFR/RNF coverage (requirements.md §3–§5)

All nine RNFs (RNF01–RNF09) are present in the PRD's "Cross-Cutting NFRs" section with accurate restatements:

- RNF01 (latency: <100ms local / >300ms loading indicator) ✓ exact
- RNF02 (PII stripping via Claude Haiku 4.5 structured prompt/tool-use) ✓ — **minor drift:** requirements.md's phrasing includes the exclusion clause "not a dedicated NER model," which the PRD's restatement omits. Doesn't change the requirement's meaning (the technique described is still the structured-prompt approach) but loses a clarifying detail the source thought worth stating explicitly.
- RNF03 (zero data retention) ✓ — PRD adds "by upstream AI providers," a reasonable contextual gloss not literally in requirements.md §4's one-line phrase, but not a meaning change.
- RNF04 (RLS) ✓ — PRD substantially elaborates (NOT_FOUND-not-permission-denied behavior) beyond requirements.md's one-line statement; the elaboration is consistent with requirements.md §11's error-code table, not a fabrication.
- RNF05 (hard delete, LGPD) ✓ exact
- RNF06 (domain layer imports neither `flutter` nor `data/`) ✓ exact
- RNF07 (≥80% domain coverage) ✓ exact
- RNF08 (visual fidelity, zero hardcoded values) ✓ exact
- RNF09 (Either<Failure,T>, 5×3=15 scenarios) ✓ exact

No RNF is missing. No restatement changes a requirement's meaning; the two "minor drift" items above are omissions of clarifying detail, not contradictions.

## 3. Section 10 parameters

All eight tunables checked; all present with the correct number, located as follows:

| Parameter | requirements.md value | Found in PRD at |
|---|---|---|
| Background session timeout | 5 min | FR-6 |
| Search debounce | 300 ms | FR-20 |
| Proactive insight trigger | 5 messages OR 2 min inactivity | FR-30 |
| Dashboard rendering scenarios | 0 / 1 / >30 entries | FR-37 |
| Minimum domain test coverage | ≥80% | RNF07 (Cross-Cutting NFRs), SM-2 |
| Local UI latency | <100ms | RNF01 (Cross-Cutting NFRs) |
| Loading-indicator threshold | >300ms | RNF01 (Cross-Cutting NFRs) |
| Network-error scenarios tested | 5 endpoints × 3 failures = 15 | RNF09 (Cross-Cutting NFRs), SM-3 |

No gaps. No value stated differently anywhere.

## 4. Section 2 extension features (Non-Goals)

All three extension features are named correctly in PRD §5 Non-Goals, and in each case the PRD explicitly states there is no underlying AI/functional logic — it does not describe any of their mechanisms as in scope:

- Dynamic AI categorization → "downgraded to manual, user-created tags... no AI logic behind it." ✓
- Autonomous AI goal extraction → "static Action Plans Kanban screen with no underlying logic." ✓
- Dynamic AI persona adjustment → "cosmetic Settings selector... that does not change assistant behavior in this delivery." ✓ (Note: requirements.md §5.2 Screen 6 description says the persona selector "would only change the system-prompt string of RF04" — describing what it *would* do if implemented. The PRD correctly keeps this counterfactual/non-functional and does not promote it into an active FR.)

No FR in PRD §4 describes functional behavior for any of the three extension features. Clean — no gaps.

## 5. Tone / qualitative framing

- **"No clinical or diagnostic connotation"** — preserved and generalized: PRD §1 Vision ("Cerne is explicitly not a mental-health or clinical tool. It makes no diagnostic claims...") and Guardrails ("No clinical or diagnostic framing anywhere in the product"). Requirements.md attaches this specifically to RF05 (export); the PRD elevates it to a whole-product stance, which is a strengthening, not a narrowing.
- **Mechanism-vs-quality-of-generated-text boundary (RF05/RF08/RF09)** — preserved explicitly in each FR group's description (4.9, 4.10, 4.11) and again in §5 Non-Goals and in Guardrails. **One addition worth flagging:** PRD's Non-Goals bullet extends this boundary to include RF04 ("RF04/RF05/RF08/RF09 are scoped to mechanism, failure-handling, and UI-safety only"). Requirements.md never makes this claim for RF04 — RF04's acceptance criteria are about UI states and stream-drop handling, and nothing in requirements.md says the chat response's generated-text quality is explicitly out of scope the way it does, in matching language, for RF05/RF08/RF09. This is a reasonable inference (one wouldn't grade chat response quality either) but it is PRD-authored scope language attributed to requirements.md that requirements.md itself does not state for RF04.
- **Explicit non-goal of risk-signal detection** — preserved with its reasoning intact: PRD §1 ("detects no risk signals"), §5 Non-Goals ("a deliberate scope exclusion tied to the product's non-clinical stance... not an oversight"), and Guardrails. This matches requirements.md §4's "Known limitation" framing (explicit scope decision, not an absence by neglect).

## Summary of concrete gaps

1. **Dropped acceptance criterion:** RF07's "No BLoC imports another BLoC directly" does not appear anywhere in the PRD (not in FR-14–17, not folded into RNF06, not elsewhere). RNF06 is a different rule (domain layer vs. flutter/data imports) and cannot stand in for it.
2. **Downstream inaccuracy caused by #1:** SM-1's claim that "every acceptance criterion stated per-RF in requirements.md §1 passes... Validates FR-1 through FR-42" is not fully true, since the BLoC-import criterion has no corresponding FR to validate it.
3. **Loose/reversed restatement:** RF07's "sync badge updates independently of the authentication stream" is restated in FR-17 with the dependency direction reversed (overlay independent of badge, rather than badge independent of auth) — same spirit, different subject.
4. **Minor clarifying detail dropped:** RNF02's restatement omits the "(not a dedicated NER model)" exclusion present in requirements.md §4.
5. **Scope-boundary over-extension:** PRD's Non-Goals section attributes the mechanism-vs-quality acceptance-scope boundary to RF04 as well as RF05/RF08/RF09; requirements.md states this boundary explicitly only for RF05, RF08, RF09.

Everything else checked (all RF01–RF10 criteria save the one noted, all nine RNFs, all eight §10 parameters, all three extension features as Non-Goals, and the three qualitative/tone framings) is faithfully and accurately captured in the PRD.
