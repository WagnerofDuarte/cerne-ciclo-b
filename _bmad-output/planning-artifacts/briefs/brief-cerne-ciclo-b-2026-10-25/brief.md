---
title: "Product Brief: Cerne"
status: draft
created: "2026-10-25"
updated: "2026-10-25"
---

# Product Brief: Cerne

## Executive Summary

Cerne is a reflective-journaling mobile app whose AI assistant actually remembers the user — it answers using Retrieval-Augmented Generation (RAG) over the user's own past entries, instead of the stateless, generic-sounding responses that dominate the AI-journaling category today. The user captures their day by text, voice, or photo; the assistant surfaces connections across that personal record in conversation, offers occasional unprompted insight, and lets the user fold a chat realization straight into their journal with one tap.

The differentiator is narrow and deliberate: not a bigger feature set, but a better memory. Competitive research (see addendum) confirms that "generic AI response" fatigue is the single most common complaint against AI-journaling incumbents (Mindsera, Rosebud, Reflectly, Day One AI). Cerne is positioned directly against that gap, backed by an explicitly non-clinical stance that is a timing advantage rather than just a legal fence, given the current regulatory pressure on companion-chatbot framing.

[ASSUMPTION] This brief is being produced as a TCC (undergraduate capstone) deliverable: a bridge document that consolidates the problem/solution/scope already explored in the project's PRFAQ and F000 foundation-decision sessions into the shape the next BMad stage (PRD → architecture → build) expects, and that can also stand as the "what and why" section of the written defense. It is evaluated on engineering discipline under a frozen backend contract and a fixed delivery order, not on commercial traction — there are no unit economics or acquisition targets here, and none should be invented for this document.

## The Problem

**[ASSUMPTION — reconstructed, not stated in `docs/input/`]** `docs/input/requirements.md` specifies screens and endpoints, never a customer. The persona and problem below are inferred from UI language (Portuguese), architectural choices (on-device STT, zero AI-pipeline retention, explicit non-clinical scope), and the extension features that were deliberately cut; treat the persona and problem below as a working hypothesis for the brief and defense, not a sourced fact.

Someone who journals, or has tried to and quit — paper, Notes, Day One — or who already talks to a general-purpose chatbot (ChatGPT) to process their day. The chatbot forgets everything between sessions, so every conversation restarts from zero; the journal, when kept, is a one-way write into a void that never responds. Both leave the same need unmet: being understood *in light of one's own history*, not generically. A secondary, quieter fear sits underneath — that a private, emotionally loaded diary is being mined, sold, or silently reinterpreted as a mental-health signal.

## The Solution

Capture is multimodal and deliberately unceremonious — text, a voice note transcribed on-device, or a photo OCR'd server-side — and every capture becomes a durable entry, never a disposable chat turn. Chat is the daily surface: a continuous conversation where the assistant's answers are grounded in semantic search over the user's own entries (RAG), not canned reflection prompts. The two pipelines are deliberately decoupled — a chat message writes to the journal only when the user explicitly says so ("save to journal," RF10) — so the assistant can be talked to freely without every utterance becoming a permanent record.

## What Makes This Different

- **Memory, not mood-tracking.** The RAG-over-own-entries architecture is the whole bet — it's the one thing the "generic response" incumbents don't do, and it's validated against real competitor complaints, not assumed.
- **Non-clinical by design, not by omission.** No mood scoring, no risk-signal detection, no implied therapeutic claim. In a climate where companion-chatbot makers are drawing fines and mandated disclosures (Replika-class actions, California's 2026 disclosure law), an app that never pretends to be a clinician is a defensible position, not a missing feature.
- **Privacy architecture that matches the pitch.** Audio never leaves the device as audio (on-device Whisper STT); the AI pipeline retains zero data; everything is scoped by row-level security. The app can credibly say "we don't mine what you write" because the architecture forces that to be true.

## Who This Serves

A Brazilian Portuguese-speaking adult already in the habit of processing their day through writing or talking to an AI, frustrated that neither medium remembers them. They are not seeking therapy and would be put off by anything that implies they need it. Success for this person looks like: the assistant surfaces something true from three weeks ago without being asked to, and the act of writing starts to feel worth repeating.

## Scope

**In (this build, functional requirements RF01–RF10):**
- Multimodal capture (text / on-device-transcribed audio / OCR'd photo), each producing the same entry format
- Biometric/PIN vault gating all access, with a non-lockout PIN fallback
- RAG chat with memory, including mid-stream failure recovery
- Semantic + metadata search/filter and a multi-source timeline history
- Save-chat-message-as-entry, routed through a shared use case (never a direct cross-feature import)
- Proactive insight trigger, AI summary export, and temporal dashboard — **mechanism, job-handling and rendering only; the quality of the generated narrative text is explicitly out of scope for acceptance testing** (RF05/RF08/RF09). See "Known Tensions" below — this boundary must be stated, not discovered.

**Out — by deliberate product cut (`requirements.md` §2), reversible if scope reopens:**
- Dynamic AI categorization → manual tags only
- Autonomous goal extraction → static Kanban placeholder
- Dynamic persona adjustment → cosmetic settings toggle only

**Out — hard non-goal:** any detection of risk signals (self-harm, suicidal ideation) in entries or chat. The product is not framed as a mental-health app; no code path should imply otherwise.

**Out — architectural constraint, not a product choice:** entries are immutable (no edit/delete endpoint exists in the frozen backend) and writes are cloud-only (offline permits viewing cached data, never creating entries). Both are real adoption-friction points worth naming openly rather than letting a future reader discover them.

## Technical Foundation (fixed, not re-decided here)

Flutter / `flutter_bloc` / Clean Architecture, iOS portrait-only, against an already-built, frozen Supabase backend (23 endpoints, called only by their `x-cerne-function` name). Claude Sonnet 5 drives chat; Claude Haiku 4.5 handles vision/OCR/PII-scrub/summaries/insights/dashboard narrative; Voyage AI `voyage-4` generates embeddings — all server-side; the app never calls a provider directly. Delivery order is fixed: **F000 → RF03 → RF01 → RF02 → RF07 → RF06 → RF04 → RF10 → RF08 → RF05 → RF09.** F000's foundation decisions (Hive for local cache, `get_it`, `dio`, `go_router`, a 13-code sealed `Failure` hierarchy) are already forged — see `_bmad-output/forge/f000-foundation-decisions/forged-idea.md` — and are inputs to the next stage, not open questions for this brief.

## Success Criteria

This is an academic build, so "success" means meeting acceptance criteria and being ready for the defense, not hitting adoption metrics:
- Every RF01–RF10 acceptance criterion in `requirements.md` passes.
- RNF06 (zero domain-layer violations), RNF07 (≥80% domain test coverage), RNF08 (visual fidelity to the prototype, zero hardcoded design values), RNF09 (15/15 network-failure scenarios handled) are all met.
- The mechanism-vs-quality scope boundary (RF05/RF08/RF09) is stated explicitly in the written defense — left implicit, it reads as an unexamined gap rather than a deliberate one.

## Known Tensions & Open Questions

- **No timeline exists yet.** No deadline, hours-per-week budget, or buffer is recorded anywhere in `docs/input/` or `_bmad-output/`. This is the single biggest open input for sequencing the PRD/epics work and cannot be inferred — it needs the course calendar / defense date.
- **Post-defense fate is undecided.** Whether Cerne ends at the defense or is maintained as a portfolio piece changes how much "what happens after v1" planning is worth doing now. Not resolved here; flagged for the PRD stage.
- **Mechanism-vs-quality scope boundary** (RF05/RF08/RF09): a legitimate, deliberate engineering-scope cut, but it is the one thing that determines whether a real user would actually stay. Must be named explicitly wherever this project is defended or documented, not left to be noticed.
- **Fast-follow, low-cost, not yet scheduled:** a static crisis-resources disclaimer/link — adds no detection logic, doesn't contradict the non-clinical scope, closes an otherwise silent gap.

## Vision

Within this project's own boundary, "done" is a working, fully tested app that proves the RAG-memory differentiator end-to-end against a real (if frozen) backend. Beyond that boundary — a second iteration that lets AI insight quality itself be evaluated, decides whether the cut extension features (categorization, goal extraction, persona adjustment) earn their way back in, or repositions Cerne as a live portfolio artifact — is explicitly future scope, not a commitment made by this brief.
