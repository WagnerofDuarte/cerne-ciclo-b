# Reconciliation: original unit breakdown vs. prd.md + addendum.md

Input compared: `original-unit-breakdown.md` (11 units: F000, RF03, RF01, RF02, RF07, RF06, RF04, RF10, RF08, RF05, RF09) against `prd.md` and `addendum.md` in this folder.

## 1. Endpoint coverage

All endpoints named in the original breakdown were checked against prd.md's FR-1..FR-42 and the README's path→function map (`docs/input/backend/README.md`) for ground truth on what each endpoint is actually for.

**Covered (endpoint → FR):**
- `POST /auth/signup`, `POST /auth/login`, `POST /auth/refresh`, `GET /auth/session` → FR-1
- `PATCH /account/settings` → FR-7 (biometric pref), FR-40 (display name)
- `POST /auth/logout` → FR-41
- `POST /entries` (manual/audio/photo/chat) → FR-8, FR-9, FR-10, FR-27
- `POST /media/ocr` → FR-13
- `GET /entries` → FR-14 (list), referenced again for FR-19 filters
- `GET /entries/search` → FR-18
- `POST /chat/sessions`, `GET /chat/sessions` → FR-23/FR-24
- `POST /chat/sessions/:id/messages` (SSE) → FR-22
- `POST /chat/sessions/:id/messages/:userMessageId/retry` → FR-25
- `POST /chat/sessions/:id/insight` → FR-30
- `POST /export/summary`, `GET /export/:jobId/status`, `GET /export/:jobId/download` → FR-33/FR-34/FR-35
- `GET /dashboard/aggregate`, `GET /dashboard/narrative` → FR-37/FR-38
- `DELETE /account` → FR-42

**GAP — no corresponding FR found:**
- **`GET /entries/:id`**. It's named explicitly in the original breakdown's RF07 backend list, and `requirements.md` §6.2 confirms it maps to RF07. Grepped `prd.md` for `entries/:id`, `entries/{id}`, "entry detail" — zero hits. §4.5 (RF07: FR-14 chronological list, FR-15 sync badge, FR-16 empty state, FR-17 session-expiry resilience) never describes a single-entry detail view or any other use of this endpoint. There is no UJ, FR, or IA mention of tapping an entry to see it individually. This looks like a silently dropped endpoint, not a deliberate scope decision (no `[OPEN]`/`[ASSUMPTION]` tag covers it).

**Soft/minor note (not counted as a gap):**
- `GET /chat/sessions/:id/messages` (loading a session's message history on switch) has no FR of its own; it's only implied inside FR-23 ("listed and switchable from the side menu"). Reasonable to read as covered, but it's never named explicitly the way the other chat endpoints are in FR-22/FR-25.
- RF06's original backend list is `GET /entries/search, GET /entries` — implying metadata-only filters (FR-19) go through plain `GET /entries` with query params, while text search (FR-18) goes through `/entries/search`. FR-19 never states which endpoint it uses. Low severity since the endpoint itself is still named elsewhere (FR-14), but downstream architecture work will need to disambiguate.

## 2. Prototype-state coverage

Checked every named state/screen in the original breakdown against prd.md (UJs, FRs, Information Architecture section).

All of the following resolved to a clear PRD location — **no missing states found**:
- Tela 0 (splash) → IA section + UJ-1
- Tela 0.1a (Entrar/Criar conta) → IA section ("Login/Signup, single screen, toggled") + FR-1
- Tela 0.1 Biometria, 0.1b PIN inicial, 0.1c PIN após falha → UJ-1 edge case + FR-4/FR-5 (FR-5 names "Tela 0.1c" literally)
- Insertion Modal Texto/Áudio-Gravando/Foto-Captura → FR-8/FR-9/FR-10, UJ-1
- Áudio Processando/Transcrito/Erro, Foto Processando OCR/Reconhecido/Erro → FR-12/FR-13 (four-state pattern, incl. OCR_NO_TEXT)
- Tela 4 Meus Registros (default/Vazio) → FR-14/FR-16, IA section
- Tela 4 Sheet de filtro / Filtros ativos → FR-19/FR-21, UJ-4
- Tela 1 Home/Chat default/Streaming/Falha ao gerar resposta/Offline → FR-22/FR-25/FR-26, UJ-2
- Tela 3 Menu lateral → FR-23/FR-24, IA section
- Tela 1 Bookmark sub-states → FR-27/FR-28/FR-29, UJ-3
- Tela 1 Insight → FR-30/FR-32
- Export sheet Pendente/Processando/Concluído/Erro/Período vazio → FR-34 names all five literally, FR-36
- Tela 6 Configurações four dashboard variations → split across FR-37 (zero/one/>30 entries = 3 states) + FR-38 (narrative-failed = the 4th, cross-cutting state) — together these account for all four, just not phrased as "four variations" in one place
- Tela 6 Confirmar exclusão de conta → FR-42

Minor style note: the PRD mostly drops literal "Tela N" labels once past F000/RF03 (e.g. no literal "Tela 4" or "Tela 6" string anywhere in prd.md — verified by grep), describing screens by feature name instead (Meus Registros, Configurações). This is a traceability style choice, not a content gap — every state is still locatable, just not by the same ID string a reviewer might grep for.

## 3. "Do not" boundaries

Checked §5 (Non-Goals) and §6.2 (Out of Scope for MVP) against the three repeated boundaries (don't implement later units, don't build extension features, don't change backend), and checked each feature section's FRs for creep into another unit's territory.

- **Backend boundary**: preserved. §5 and Constraints/Guardrails both state the backend/contract/config is frozen and never modified.
- **Extension-feature boundary**: preserved. §5 explicitly tags the three extension features `[ext]` (categorization, goal extraction, persona adjustment) as inert placeholders, matching `requirements.md` §2 and AGENTS.md policy.
- **No-reordering / no-early-implementation boundary**: preserved via §6.2 ("Any feature reordering outside the delivery sequence... later units assume earlier ones exist").
- **Scope-creep check per FR set** (spot-checked the specific examples the task raised):
  - F000 (§4.1, FR-1..FR-3): FR-3 explicitly requires RF01–RF10 placeholders to be "clearly marked" and "visually distinguishable from finished screens" — no real RF01-RF10 behavior leaks in.
  - RF07 (§4.5, FR-14..FR-17): no search/filter logic appears here; FR-14/FR-16/FR-17 stay to listing/empty-state/session-resilience. RF06 (§4.6) is explicitly framed as sitting "over the timeline from §4.5" rather than redefining it. No creep found.
  - RF01 vs RF02: RF01's FR-9/FR-10 correctly defer processing ("once processed (RF02)") rather than implementing transcription/OCR themselves.
  - RF04 vs RF08/RF10: FR-22 explicitly carves out the RF10 exception ("Chat Messages never automatically create Entries — RF10 is the sole, explicit exception") rather than building RF10's bookmark logic inline.

No scope-creep violations found. One documentation inconsistency worth flagging: explicit "Depends on X" lines are written for RF10, RF08, RF05, RF09 sections but omitted in prose for F000, RF03, RF01, RF02, RF07, RF06, RF04 — not a contradiction (the §6.1 ordered list carries the real chain), but inconsistent enough that a reader skimming only the feature-section descriptions won't see RF07's or RF04's dependencies stated there.

## 4. Dependency chain

Original per-unit "Depends on" lines, reconstructed:
F000 (root) → RF03 (F000) → RF01 (F000, RF03) → RF02 (RF01) → RF07 (F000, RF01) → RF06 (RF07) → RF04 (F000, RF03) → RF10 (RF01, RF04) / RF08 (RF04) → RF05 (RF07) → RF09 (F000, RF01).

PRD §6.1: "F000 (Foundation) → RF03 → RF01 → RF02 → RF07 → RF06 → RF04 → RF10 → RF08 → RF05 → RF09, in that order."

- Order is a valid topological sort of the original chain (RF10 before RF08 is an arbitrary-but-valid choice since the original only groups them as "RF10/RF08" after RF04; RF05 and RF09 correctly land after their prerequisites RF07/RF01).
- **RF10's double dependency is correctly and explicitly preserved**: §4.8 states "Depends on RF01 and RF04" verbatim — this was the specific risk the task flagged (a PRD might silently drop to just one), and it did not happen here.
- Minor discrepancy: §4.11 (RF09) states "Depends on RF01" only, omitting the "F000" half of the original's "Depends on: F000, RF01." Low severity — F000 precedes everything in §6.1's ordered list regardless — but it's an inexact restatement of the original's own dependency line.

## 5. Test-material references

Grepped `prd.md` and `addendum.md` for "fixture" and "seeded" — **zero hits in both files.**

- `docs/input/backend/fixtures/` (RF02 test material) — not mentioned anywhere.
- `docs/input/backend/fixtures/seeded-search-entries.md` (RF06 test material) — not mentioned anywhere.

This is a confirmed gap. Neither prd.md's RF02 section (§4.4) nor its RF06 section (§4.6), nor addendum.md's "Corrections carried forward" section (which does cite other backend docs like `sync-badge.md`, `error-taxonomy.md`, `openapi.yaml`) points downstream QA/architecture work at these fixture files. Even a one-line pointer in each feature section (or in addendum.md's corrections list) would close this.

## Summary of gaps found

1. **`GET /entries/:id` has no corresponding FR** — RF07's FR set (FR-14..FR-17) never describes a single-entry detail view, though the endpoint is named in the original breakdown and confirmed by `requirements.md` §6.2 to belong to RF07.
2. **No mention of `docs/input/backend/fixtures/`** (RF02 test material) anywhere in prd.md or addendum.md.
3. **No mention of `docs/input/backend/fixtures/seeded-search-entries.md`** (RF06 test material) anywhere in prd.md or addendum.md.
4. **RF09's dependency line omits F000** — PRD says "Depends on RF01," original says "Depends on: F000, RF01." Low severity, doesn't break the delivery order in §6.1.
5. (Minor, not a hard gap) RF19's metadata-filter FR doesn't specify whether it calls `GET /entries` (query params) vs. `/entries/search` — the original breakdown's RF06 backend list implies the former, but FR-19 is silent on which endpoint it uses.

No endpoint-coverage gaps beyond #1, no prototype-state coverage gaps, and no boundary/scope-creep violations were found — those three checks came back clean.
