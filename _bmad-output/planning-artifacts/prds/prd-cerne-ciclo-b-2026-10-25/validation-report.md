# Validation Report — Cerne

- **PRD:** `_bmad-output/planning-artifacts/prds/prd-cerne-ciclo-b-2026-10-25/prd.md`
- **Rubric:** `.claude/skills/bmad-prd/assets/prd-validation-checklist.md`
- **Run at:** 2026-10-26T00:00:00
- **Grade:** Fair

## Overall verdict

Unusually honest, well-disciplined PRD for its academic/TCC-rigorous stakes — Open Questions, `[ASSUMPTION]` tags, and Non-Goals do real work rather than performing completeness, and IDs/glossary/cross-refs are clean for downstream use. The two soft spots the rubric found are done-ness (a few FRs and one NFR have no settled acceptance path despite `status: final`) and strategic coherence (one feature with no User-Journey anchor, breaking an otherwise-complete thesis→UJ→feature chain).

A second, independent pass checked the PRD against the frozen `docs/input/` sources specifically for drift introduced by the two polish passes that ran after the original reconciliation. Fidelity is strong overall — delivery order, extension non-goals, error taxonomy, and the AI-provider/on-device-STT constraints all match exactly — but it surfaced one high-severity dropped prototype behavior (an OCR-failure recovery path the prototype documents that the PRD's FR-13 omits) plus a handful of smaller drift items. Combined with the rubric's RNF01 finding, the report carries two high-severity findings, which is what pulls the grade to Fair rather than Good — neither is expensive to close.

## Dimension verdicts
- Decision-readiness — strong
- Substance over theater — strong
- Strategic coherence — adequate
- Done-ness clarity — adequate
- Scope honesty — strong
- Downstream usability — strong
- Shape fit — strong

## Findings by severity

### High (2)

**[Done-ness clarity]** — RNF01 has no mapped Success Metric or verification method (Cross-Cutting NFRs / §7)
RNF01 ("<100ms" local UI, "300ms" loading-indicator threshold) is the only one of nine Cross-Cutting NFRs with no mapped SM, and §7 gives no instrumented or manual verification method.
Fix: Add an SM (or a line under SM-1) naming how RNF01 gets verified, or state explicitly that it's unverified-by-design.

**[Input-fidelity reviewer]** — Dropped "Salvar só a foto" OCR-failure fallback (§4.4 FR-13 vs. prototype-extract.md §2.3/§4)
prototype-extract.md documents a save-without-text recovery path on OCR failure, distinct from retry; FR-13's consequences omit it entirely, so acceptance testing would miss a documented state.
Fix: Add a consequence to FR-13: "On OCR failure, in addition to retry, the user can save the Entry with no extracted text ('Salvar só a foto')."

### Medium (6)

**[Decision-readiness]** — Open Questions aren't sequenced against the delivery order they constrain (§8, §6.1)
OQ-3 blocks FR-11 (build unit 2 of 11) and OQ-7 blocks FR-19/20 (unit 6), but §8 lists all eleven OQs flat and unprioritized.
Fix: Tag each OQ with the earliest build unit it blocks, or sort §8 by urgency against §6.1's order.

**[Strategic coherence]** — RF08 Proactive Insights has no "Realizes UJ-X" linkage (§4.9 / FR-31–33)
Every other §4 section states one; RF08 says "Depends on RF04" and stops, leaving FR-31–33 structurally un-anchored to any user journey.
Fix: Add a UJ realized by RF08, or state explicitly that it's UJ-less by design and why.

**[Done-ness clarity]** — Three FRs have a literal unresolved sub-behavior at status: final (FR-11, FR-15, FR-20)
Each carries an honest `[OPEN]` tag, but an engineer building RF01 (unit 2) or RF06 (unit 6) cannot fully determine "done" without first resolving OQ-3/OQ-6/OQ-7.
Fix: No PRD change needed beyond §8 — but sequence these against build order (see the Decision-readiness finding above).

**[Done-ness clarity]** — FR-19 search quality has no mechanism-only carve-out (FR-19 / §5 / OQ-10)
Unlike RF05/RF08/RF09, RF06 search-result quality has no explicit "mechanism only" scope carve-out, and OQ-10 raises this exact boundary question only for RF04.
Fix: Extend OQ-10 (or add an OQ-12) to cover RF06 search-quality alongside RF04 chat-quality.

**[Input-fidelity reviewer]** — Unsupported reinstall caveat on biometric preference (§4.2 FR-7)
FR-7 claims the biometric toggle "survives app restarts (but not reinstalls)," but the preference is stored server-side via PATCH /account/settings, so a reinstall would still retrieve it on re-login — in tension with the cited mechanism.
Fix: Remove the reinstall caveat, or replace with an `[ASSUMPTION]` tag if a specific client-side caching behavior is intended.

**[Input-fidelity reviewer]** — New Chat Session creation's offline restriction dropped (§4.7 FR-25/FR-27)
requirements.md §6.3 states POST /chat/sessions is blocked offline, but FR-27's offline composer lock only covers existing conversations; FR-25 (new-conversation action) has no offline consequence.
Fix: Add a consequence to FR-25 or FR-27 stating POST /chat/sessions is blocked offline.

### Low (6)

**[Decision-readiness]** — OQ-5 is not actually open (§8)
It's answered in the same sentence that poses it ("there is none per AGENTS.md"); the PRD is self-aware about this, so the risk is cosmetic but inflates the "genuinely open" count.
Fix: Move OQ-5 to a "decisions already settled, recorded for visibility" note.

**[Done-ness clarity]** — RNF02/RNF03 are inherited backend/vendor facts, not app-testable requirements (Cross-Cutting NFRs)
They sit in the same list as app-behavior NFRs (RNF01/04/05-09), blurring what this delivery is actually on the hook for.
Fix: Mark them "inherited, not verified by this delivery," or move them to the addendum's backend-context section.

**[Input-fidelity reviewer]** — Overstated citation on session-expiry overlay coverage (§4.1 FR-2)
Only RF07 explicitly states session-dependency in requirements.md text; the chat case is sourced from prototype-extract.md, not requirements.md's RF04 text.
Fix: Reword to cite both sources correctly.

**[Input-fidelity reviewer]** — Prototype/backend conflict on profile editing not flagged (§4.11 FR-41)
The prototype shows an "editable e-mail" affordance that openapi.yaml's PATCH /account/settings explicitly rejects. FR-41 correctly omits it, but the conflict is never documented, risking reintroduction later.
Fix: Add a line to addendum.md's "Corrections carried forward" noting the prototype's email-edit affordance is not buildable.

## Mechanical notes
- Casing drift: "Entry" and "Dashboard" drift to lowercase in §5/§4.11/UJ-6 despite being capitalized Glossary terms elsewhere.
- Unnumbered sections: Information Architecture and the three trailing sections (Cross-Cutting NFRs, Constraints and Guardrails, Aesthetic and Tone) carry no section numbers, inconsistent with the rest of the document's numeric cross-referencing.
- §4.5's BLoC-composition rule has no stable ID of its own, unlike the global RNF01–09.
- Assumptions Index and ID continuity otherwise check out clean on spot-check.

## Reviewer files
- `review-rubric.md`
- `review-input-fidelity.md`
