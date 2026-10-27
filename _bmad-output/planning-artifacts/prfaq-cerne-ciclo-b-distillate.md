---
title: "PRFAQ Distillate: cerne-ciclo-b"
type: llm-distillate
source: "prfaq-cerne-ciclo-b.md"
created: "2026-10-25T20:36:00Z"
purpose: "Token-efficient context for downstream PRD creation"
---

## Concept type
Academic capstone (TCC) built and evaluated with commercial-product customer-first discipline — no unit economics or customer-acquisition targets apply; the calibration used was feasibility, delivery-order fit, and scope-discipline-under-deadline-pressure instead.

## Customer & problem (reconstructed — not stated anywhere in docs/input/)
- `docs/input/requirements.md` never names a customer or persona; it's organized entirely around RF01–RF10/screens. The persona below is a reconstruction from UI language (Portuguese), architectural choices, and explicit non-goals — flag this to any downstream PRD author as inferred, not sourced.
- Persona: a Brazilian Portuguese-speaking person who has already tried journaling (paper, Notes, Day One) and quit, or who uses a general-purpose chatbot (ChatGPT) to process their day and is frustrated it forgets everything between sessions.
- Problem: wants an AI that genuinely recalls and connects their own past entries (not generic "how did that make you feel" loops), without fear their private writing is mined, sold, or mistaken for a mental-health signal.
- Stakes: alternative today is journaling into a void that never responds, or using a memoryless, privacy-ambiguous general AI tool.

## Core differentiator (validated against real 2025-2026 competitive research)
- "Generic AI response" fatigue is the #1 complaint across AI-journaling competitors (Reflectly, Day One AI, Mindsera) — Cerne's RAG-over-own-entries is positioned directly against this, not against feature count.
- Digital journal app market: $5.69B (2025) → $6.34B (2026), ~11.4% CAGR, projected $9.64B by 2030 — healthy, growing category; mobile is >60% of usage, validating the Flutter mobile-first bet.
- Real competitors with gaps worth knowing: Mindsera (feature-sprawl, gimmicky), Rosebud (therapist-designed framing risks implying clinical utility), Reflectly (mood-tracking-shallow, blurs into mental-health claims), Day One/Journey/Stoic (AI bolted on as paywalled add-on, not core).
- Regulatory climate rewards strict non-clinical positioning: Italy fined Replika's maker (Luka) €5M; California's 2026 law mandates companion-chatbot disclosure. Cerne's explicit non-clinical scope is a timing advantage, not just a constraint.

## Honest, unresolved tension (the single most important thing for downstream PRD/architecture work to carry forward)
RF05, RF08, RF09 each explicitly scope grading to "mechanism only, never the quality of the generated narrative text" — meaning the dimension that actually determines whether a real user would stay (is the AI's insight good, or generic/canned) is never verified by this project's own acceptance criteria. This is a legitimate engineering-scope boundary, but it must be stated explicitly in any written defense/documentation — left implicit, it reads as an unexamined gap rather than a deliberate one.

## Scope signals — in, out, and why
- IN (core, already specified): multimodal capture (RF01), STT/OCR (RF02), biometric vault (RF03), RAG chat (RF04), semantic search/filter (RF06), timeline history (RF07), save-chat-as-entry (RF10), proactive insight trigger mechanism only (RF08), AI summary export mechanism only (RF05), temporal dashboard (RF09).
- OUT (explicit extension features, never implement per AGENTS.md policy): dynamic AI categorization of entries (reduced to manual tags), autonomous AI goal extraction (reduced to static kanban with example cards), dynamic AI persona adjustment (reduced to a cosmetic settings toggle). These were deliberately cut for a solo/timeline-bound build, not because they lacked value — worth remembering if scope ever gets re-opened.
- OUT (hard non-goal, stated policy): any risk-signal detection (self-harm, suicidal ideation). Product is explicitly not framed as a mental-health app. No code path should ever imply otherwise.
- OUT (architectural constraint, not a product choice): per-entry edit/delete — entries are immutable; no `PATCH`/`DELETE /entries/:id` exists in the frozen backend. Real adoption-friction point for any future real-world use; cannot be changed within this project.
- OUT: offline writes — architecture is cloud-only; offline permits only viewing cached data, never creating entries.

## Technical context / constraints for downstream architecture work
- Flutter/BLoC/Clean Architecture, iOS portrait-only, frozen Supabase backend (23 endpoints via `x-cerne-function` naming, never literal REST paths).
- AI split (server-side only, app never calls a provider directly): Claude Sonnet 5 for chat, Claude Haiku 4.5 for vision/OCR/PII-scrub/summaries/insights/dashboard narrative, Voyage AI voyage-4 for embeddings.
- Privacy/compliance baked into architecture: on-device Whisper STT (raw audio never leaves device — only the transcribed text syncs to the cloud), zero AI-pipeline data retention (RNF03), row-level security (RNF04), LGPD hard-delete (RNF05).
- RNF06: domain layer must import neither `package:flutter` nor anything from `data/`. RNF07: domain-layer test coverage ≥80%. RNF09: 5 write endpoints × 3 failure types = 15 tested network-failure scenarios.
- Delivery order (confirmed from requirements.md section 12): F000 → RF03 → RF01 → RF02 → RF07 → RF06 → RF04 → RF10 → RF08 → RF05 → RF09.
- **Unresolved contradiction, needs a decision before F000 implementation:** `_bmad-output/planning-artifacts/research/technical-flutter-package-selection-.../research.md` recommends `drift` (SQLite) for local cache; `_bmad-output/forge/f000-foundation-decisions/forged-idea.md` overrides it to `Hive`, reasoning all filtering/pagination is server-side so no relational engine is needed on-device. Fix: explicitly mark `drift` as superseded in the research artifact.
- Hardest unbuilt technical problems: RF07's history screen depends on three independently-changing streams (auth, sync-badge, entry data) while BLoCs may not import each other directly; RF08's proactive-insight trigger must fire exactly once per satisfied condition (5 messages OR 2 min inactivity) without double-firing or missing the window.

## Resource & timeline (open, not estimated)
No deadline date, hours-per-week budget, or buffer exists anywhere in `docs/input/` or `_bmad-output/`. This is a genuine open question for the user (course calendar / defense date), not something inferable from the input package. Feasibility of the delivery order against RNF07/RNF09's testing bars cannot be assessed until this is known.

## Rejected framings (press release stage)
- Headline candidate "Cerne Lets You Actually Talk to Your Own Diary — Privately, and It Remembers" — rejected as too long, stacking unproven claims ("actually," "privately") directly in the headline.
- Any "AI companion" / "AI friend" framing — rejected deliberately, to stay clear of the companion-chatbot category currently under regulatory/reputational pressure (Replika-class fines and lawsuits).
- Leading with the on-device-privacy angle instead of the memory angle — rejected as the headline hook because "AI forgets me / generic responses" tested as the louder, more universal pain point in research; privacy is used as a supporting proof point instead.

## Known gaps flagged during Customer/Internal FAQ (actionable items)
- **Fast-follow, low cost:** add a static crisis-resources disclaimer/link — requires no detection logic, doesn't contradict the non-clinical scope, closes an uncomfortable silent gap (no mental-health signposting at all today).
- **Accepted trade-off, not fixable within this project:** per-entry immutability (no edit/delete); cloud-only writes (no offline capture); no automatic entry categorization.
- **Process fix, cheap:** reconcile the drift-vs-Hive contradiction before F000 starts.
- **Documentation fix, not a code change:** the written defense must explicitly name the mechanism-vs-quality scope boundary (see "Honest, unresolved tension" above) rather than leaving it implicit.
- **Undecided, needs the user's explicit call:** whether Cerne is a one-time academic artifact or is meant to survive into a job-application portfolio — changes how much distribution/"Getting Started" planning matters going forward.

## Verdict summary
Forged in steel: the memory/RAG differentiator (research-validated against real competitor gaps), the precisely-qualified privacy architecture, the non-clinical positioning as a timing advantage, and the already-demonstrated resource discipline (three extension features concretely cut, on record). Needs more heat: timeline/deadline (completely unknown), post-defense fate of the project, two cheap unactioned fixes (drift/Hive, crisis disclaimer). Cracks in the foundation: the quality-of-AI-insight scope boundary must be stated explicitly in the defense or it reads as an unexamined gap rather than a deliberate one; entry immutability is a real adoption-friction point that should be named as a known limitation rather than silently discovered later.
