---
title: "Addendum: Cerne Product Brief"
status: draft
created: "2026-10-25"
updated: "2026-10-25"
---

# Addendum: Cerne Product Brief

Supporting depth that doesn't earn a place in the brief itself but belongs to a downstream reader (PRD, architecture, written defense). Source artifacts referenced here are not duplicated — they stay canonical where they are.

## Source artifacts for this brief

- `_bmad-output/planning-artifacts/prfaq-cerne-ciclo-b.md` (+ `-distillate.md`) — Working Backwards PRFAQ; persona reconstruction, competitive positioning, press-release framing options.
- `_bmad-output/forge/f000-foundation-decisions/forged-idea.md` — F000 technical decisions (Hive, get_it, dio, go_router, Failure hierarchy, RNF09 test harness).
- `_bmad-output/planning-artifacts/research/technical-flutter-package-selection-for-f000-and-r-2026-10-25/research.md` — original Flutter package research.
- `docs/input/requirements.md` — frozen product spec (do not edit).

## Competitive landscape (PRFAQ research)

- Digital journal app market: $5.69B (2025) → $6.34B (2026), ~11.4% CAGR, projected $9.64B by 2030. Mobile is >60% of usage — supports the mobile-first bet, though this project does not pursue market share.
- Mindsera: feature-sprawl, reads as gimmicky.
- Rosebud: therapist-designed framing risks implying clinical utility — a trap Cerne deliberately avoids.
- Reflectly: shallow mood-tracking, blurs into mental-health claims.
- Day One / Journey / Stoic: AI bolted on as a paywalled add-on, not core to the product.
- Regulatory backdrop: Italy fined Replika's maker (Luka) €5M; California's 2026 law mandates companion-chatbot disclosure. Strengthens the case for Cerne's explicit non-clinical positioning as a timing advantage rather than only a constraint.

## Rejected framings (PRFAQ press-release stage)

- Headline "Cerne Lets You Actually Talk to Your Own Diary — Privately, and It Remembers" — rejected: too long, stacks unproven claims ("actually," "privately") directly in the headline.
- Any "AI companion" / "AI friend" framing — rejected deliberately to stay clear of the companion-chatbot category currently under regulatory and reputational pressure.
- Leading with the on-device-privacy angle instead of the memory angle — rejected as the primary hook; "AI forgets me / generic responses" tested as the louder, more universal pain point. Privacy is used as a supporting proof point, not the headline.

## Local-cache package resolved (F000 forge session)

An earlier research pass (`research.md`) recommended `drift` (SQLite) for the local cache. The subsequent F000 forge session (`forged-idea.md`) overrode this to **Hive**, with an explicit confirmation: every filter/search/pagination dimension (`source`, `dateFrom`, `dateTo`, semantic search) is a server-side query parameter — the client never filters, joins, or sorts cached data, so a relational engine on-device buys nothing. `research.md` should be read with that override in mind rather than as a live recommendation.

## Corrections carried forward (F000 forge session)

- `requirements.md` §8 lists an `entries.sync_status` column; this contradicts `docs/input/backend/sync-badge.md`. Per `requirements.md`'s own precedence rule, the backend docs win — the sync badge is a client-computed function of `serverRevision` + `updatedAt` + pending-local-write state, never a server-supplied field.
- `requirements.md` §11's error table is a 10-of-13 excerpt; `docs/input/backend/error-taxonomy.md` is the complete closed list and is what any Failure hierarchy must be built from.
- `AUTH_INVALID`'s "invalid credentials / biometrics" wording (§11) is imprecise — no biometric call ever reaches the server, so this code can only originate from `POST /auth/login`.
