# Epic 7 Context: Personal Summary Export

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Users can request an AI-generated narrative summary plus a raw-data export for any date period from Meus Registros, and track its progress through to completion. The core guarantee is independence: the user's raw data must never be held hostage by the AI narrative step — it downloads as soon as it's ready regardless of whether the narrative is still generating, has failed, or was skipped, and a period with zero Entries is reported as a clear, non-crashing "nothing to export" state rather than an empty file or dead end. Realizes UJ-5 (a user exporting a multi-month summary before a personal check-in). Depends on Epic 4's timeline surface (export operates over the same Entry history and is launched from Meus Registros). The scope is job mechanism, file delivery, and failure handling only — the quality of the generated narrative text is explicitly outside acceptance scope.

## Stories

- Story 7.1: Request a Period Export & Job Status Tracking
- Story 7.2: Narrative-Independent Raw-Data Download
- Story 7.3: Empty-Period Handling

## Requirements & Constraints

- Requesting an export is synchronous-on-enqueue: the create call returns a `jobId` and an initial `pending` status immediately; all progress after that is observed by polling a status endpoint (no push/streaming for export).
- The job's own `status` and the AI narrative's `narrativeStatus` are reported independently by the status endpoint, together with an entry count, per-leg error codes, and an explicit "download available" flag — the UI must branch on both fields together, never infer one from the other.
- Five user-visible states cover every combination: preparing (no download), generating summary (no download), a hybrid "data ready, summary still generating" state (raw download already enabled while narrative keeps processing underneath — this combination is not one of the five states shown in the prototype itself but is required by the live contract), done-with-summary (both PDF and raw download), and done-or-error-with-narrative-only-failure (raw download only, error copy framed around the narrative, never around the whole job).
- An export requested over a period with zero Entries surfaces as its own terminal state ("Período vazio") — no download offered, no crash — and the copy should suggest adjusting the period/filter rather than leaving a dead end.
- The narrative step uses a hosted AI model server-side; the app never calls it directly and never grades or asserts on the generated text's content.
- Downloading a finished artifact (PDF or raw) resolves through a redirect to a signed storage URL, not a direct JSON payload.
- Every export error still carries the shared `{ code, message, retryable }` shape; `EXPORT_EMPTY_PERIOD` is non-retryable, so it is never fed into generic retry handling.

## Technical Decisions

- Export lives in its own feature slice, following the same layer direction and `Either<Failure, T>` repository boundary used everywhere else; it introduces no new error-signaling shape.
- The closed, shared `Failure` hierarchy already carries a dedicated case for the empty-period error; export must map onto that existing case rather than defining a feature-local error type.
- The job's progress (pending → processing → data-ready/done/error, with narrative status layered on top) is its own small sealed state class, not forced into the shared single-fetch `idle/loading/data/error` resource pattern — this mirrors how other multi-stage async flows (capture processing, chat streaming) in this codebase already get their own state machine rather than reusing the generic one.
- Retry behavior for the underlying HTTP calls is not reimplemented per feature — the shared API client already retries the handful of server codes marked retryable, and export's status/download calls follow that same single retry path rather than adding a second one.
- Calls are made by function name, never the literal REST path: export's three operations (create job, poll status, download) each resolve to their own named endpoint, with the job id appended as a trailing path segment where required.
- Prefer one export surface with an internal status enum over separate routes per stage — the underlying job has five+ states but is one continuously-updating surface, not five screens.

## UX & Interaction Patterns

- Entry point is a download icon in the Meus Registros header; it opens a bottom sheet — the heaviest sheet surface in the product short of a full-screen modal — using the same rise-from-bottom entrance timing as other sheets (skipped under Reduce Motion, final state shown immediately instead).
- Each stage transition replaces the sheet's content in place; the sheet itself never closes and reopens mid-job, and every state keeps a "Fechar" dismiss affordance.
- State copy is plain and factual, never celebratory: preparing shows a spinner ("Preparando exportação..."); generating shows a progress bar ("Gerando resumo com IA..."); the hybrid state shows the raw-data download already enabled with summary-progress text still visible underneath; full success shows a confirmation plus both download actions (PDF primary, raw data secondary); a narrative-only failure keeps just the raw-data action with error copy scoped to the narrative; the empty-period state shows explanatory copy and a suggestion to adjust the period, with no download action at all.
- No swipe gestures and no nested overlays — the export sheet sits alone on the scrim over Meus Registros, never stacking on another sheet.

## Cross-Story Dependencies

- Story 7.1 establishes the export request + status-polling state machine; Stories 7.2 and 7.3 are both refinements of states that machine must already be able to represent (the data-ready hybrid state, and the empty-period terminal state), not independent flows.
- The epic depends on Meus Registros (Epic 4) already existing as the launch surface and as the source of the period/filter the export is requested over.
