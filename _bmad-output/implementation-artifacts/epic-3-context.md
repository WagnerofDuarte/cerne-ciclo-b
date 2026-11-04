# Epic 3 Context: Multimodal Capture & Processing

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Users capture a journal Entry through one shared Insertion Modal in three ways — typed text, recorded audio, or a photo — and every modality ends up as the same persisted `Entry` shape. Audio is transcribed entirely on-device; a photo's text is recognized server-side via OCR before the Entry exists. Text and audio/photo stay merged into one epic because an un-transcribed audio Entry or un-OCR'd photo Entry is not a usable product outcome on its own — "capture" and "process" are one milestone here, not two. The epic also guarantees interrupting any capture (switching tabs, backing out, stopping early) never leaves a stray partial or empty Entry behind. This is the first epic to introduce `features/entries/`, which every later epic that creates or reads an Entry (Timeline, Search, Chat save-to-journal) will consume through its port — so decisions made here about that port's shape are load-bearing for the rest of the app.

## Stories

- Story 3.1: Text Entry Capture & Insertion Modal Shell
- Story 3.2: Audio Entry Capture & On-Device Transcription
- Story 3.3: Photo Entry Capture & Backend OCR
- Story 3.4: Cancel-Safe Capture Across All Tabs

## Requirements & Constraints

- All three capture modalities (text, audio, photo) must produce the same persisted Entry shape; `source` is `manual`/`audio`/`photo` respectively, and each `POST /entries` call must carry the correct one.
- Audio and photo Entries are only "complete" once processed: audio via on-device transcription, photo via backend OCR. The transcribed/recognized text is editable before the user taps Salvar; the Entry is only created on explicit save, not automatically after processing finishes.
- Audio transcription runs 100% on-device via `whisper_ggml`; no call in this pipeline may ever contain audio bytes. The audio pipeline has exactly four states in sequence: recording → processing → transcribed → (on failure) error with retry; the recorded media is never discarded on a transcription failure.
- Photo OCR calls the backend before the Entry is created, mirroring the same four-state shape: capture → processing OCR → recognized → error. `OCR_NO_TEXT` is a distinct, non-retryable outcome with two recovery paths: "Tentar novamente" (retry OCR on the same photo) and "Salvar só a foto" (save with no extracted text) — never a single generic failure message. An oversized photo returns non-retryable `PAYLOAD_TOO_LARGE` (413); show a size-specific message with no retry button.
- Cancel-safety (FR-11) is absolute: interrupting a capture before Salvar — closing the modal, switching Insertion Modal tabs, backing out mid-photo, stopping a recording early — must never fire `POST /entries`. Opening the modal always resets all three tabs to idle/empty; switching tabs mid-capture cancels the in-flight capture outright (resolved ambiguity — the prototype itself left this undefined).
- Offline: the "+" entry point is disabled with the same offline-banner treatment as chat send. Capture requires a live `POST /entries` round trip (PII check + embedding), so there is no local-only queued write — a write attempted with no connectivity resolves immediately to `NetworkOffline`, never queued.
- Every screen-reader-relevant state transition needs an announced label ("Gravando," "Transcrevendo," "Erro ao transcrever, toque para tentar novamente," etc.) — color/animation alone never carries state.

## Technical Decisions

- Two feature modules split the work: `features/entries/` owns the `Entry` entity, the `EntriesRepository` port (`create` + `read` only — no update/delete ever), and the entries `hive_ce` box. `features/capture/` owns the Insertion Modal UI, the on-device Whisper STT flow, and the OCR call, and holds no Entry data itself — it only consumes the abstract port from `entries/domain` (never imports `entries/data/` or `entries/presentation/`). This port is exactly what RF10 (Epic 6, save chat message as entry) and RF06/RF07 (Search, Timeline) will extend/reuse later — get its shape right here, not provisionally.
- `create` on the port is idempotent on `(origin, chatMessageId)`, though that specific guard only matters starting with RF10; this epic just needs to not violate the port's shape.
- Backend calls for this epic: `POST /entries` → function `entries-create`; `POST /media/ocr` → function `media-ocr` (the photo itself is not persisted server-side, only the extracted text comes back). Both calls follow the standard header rules (`apikey` always, `Authorization: Bearer <user token>`, since neither operation is one of the three `security: []` exceptions).
- Error handling: map the 13 backend error codes (plus the local-only `MalformedResponse`) to the one sealed `Failure` hierarchy already defined in `core/failure/`. For this epic specifically: `OcrNoText` and `PayloadTooLarge` are both non-retryable and need their own distinct UI treatment, not a generic error state. The retry interceptor fires only for the 6 server `retryable:true` codes — OCR/payload failures are never auto-retried.
- The capture feature defines its own sealed state class for its multi-step audio/OCR state machines — it is explicitly excluded from using the shared generic `Resource<T>` type (`Resource<T>` is reserved for RF06/RF09's simpler single-fetch screens).
- The Insertion Modal's three tabs are internal states of one bottom sheet, never nested sheets; its entrance animation is the shared `sheetUp` (0.2s) choreography, with no other motion invented.

## UX & Interaction Patterns

- Insertion Modal: three equal-width tabs (Texto/Áudio/Foto); only the active tab gets a filled `colorPrimary` background. A close ("x") control is always present. The modal opens on Texto by default.
- Audio tab: an animated multi-bar waveform with a monospace running timer while recording; on stop, the waveform freezes at 35% opacity with a "Transcrevendo..." label while processing (no spinner needed beyond that). Once transcribed, text is editable and "Salvar" enables; the original audio duration shows in monospace.
- Photo tab: thumbnail + spinner + "Reconhecendo texto..." while OCR runs. Once recognized, text is editable before Salvar.
- Dynamic Type and tap-target rules (≥44pt, no truncation at largest accessibility text size) apply to all controls built here, same as everywhere else in the app.
- Reduce Motion: this epic has no cursor-blink (that's Chat), but still must honor the `sheetUp`/`scrimIn`-only animation rule and skip it when Reduce Motion is on.

## Cross-Story Dependencies

- Story 3.1 is the first consumer of `features/entries/` and must stand up the `Entry` entity, `EntriesRepository` port (`create`), and the entries Hive box — Stories 3.2 and 3.3 build on top of this rather than creating their own local Entry model.
- Story 3.4 (cancel-safety) is a cross-cutting rule that applies to the tab/state machines built in 3.1–3.3; it's written as its own story but has no independent UI surface — it hardens behavior already present in the other three.
- This epic depends on Epic 2 (Biometric Vault): the Insertion Modal is only reachable once the vault is unlocked.
- Everything this epic builds in `features/entries/` is a hard dependency for Epic 4 (Timeline), Epic 5 (Search), and Epic 6's RF10 (save-to-journal) — those epics extend this port rather than replacing it.
