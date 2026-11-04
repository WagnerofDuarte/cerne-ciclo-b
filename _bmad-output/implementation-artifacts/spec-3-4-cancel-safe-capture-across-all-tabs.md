---
title: 'Story 3.4: Cancel-Safe Capture Across All Tabs'
type: 'feature'
created: '2026-11-04'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '5bf09cae75e081b1b6ead57d3952d5bb02b4c83e'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** FR-11's cancel-safety guarantee is already implemented structurally across Texto/Áudio/Foto (fresh factory-scoped cubits per modal open, `cancel()` fired on every outgoing tab, a `finally`-guarded close path) but no test proves the three acceptance criteria hold for tab-pairs other than to/from Texto, or when multiple modalities are interrupted in sequence before the modal closes — and `text_entry_cubit.dart`'s own doc comment still frames the rule as unimplemented "Story 3.4 scope".

**Approach:** Add direct Áudio↔Foto cross-tab tests and one chained multi-modality interruption-then-close test proving zero `POST /entries` end-to-end; correct the stale comment. No new cancel logic — this story verifies and documents behavior stories 3.1–3.3 already built.

## Boundaries & Constraints

**Always:**
- No change to `AudioEntryCubit.cancel()`, `PhotoEntryCubit.cancel()`, or the tab-switch dispatch in `insertion_modal.dart:290-317` — verified already correct (`_generation` guards, `discardPreserved`, fresh factory-scoped instances per "+" tap). This story adds proof via tests, not new cancel logic.
- New tests live in `insertion_modal_audio_test.dart` — it already has fakes for all three cubits (`_FakePhotoPicker`/`_FakeMediaRepository` at lines 79/89, plus the mic/transcriber fakes). Reuse its existing `_openModal` helper and `fakeRepository.createCallCount`; no new test file, no new fake classes.
- Cover: (a) Áudio→Foto mid-recording switch cancels audio and never auto-starts anything on Foto; (b) Foto→Áudio mid-pick switch discards the pick and immediately starts recording; (c) one chained flow — record audio, switch to Foto (cancels audio), start a photo pick, switch to Texto (cancels the pick), type text, close the modal via the close control (not Salvar) — asserting `fakeRepository.createCallCount == 0` after every interruption and after close.
- Update `text_entry_cubit.dart:74-77`'s doc comment: remove the "Story 3.4's scope" framing; state that the cross-tab rule lives in `insertion_modal.dart`'s tab-switch dispatch, and Texto needs no `cancel()` because no async op ever precedes Salvar.

**Ask First:** If any new assertion in the chained test actually fails (a real behavioral gap, not just missing coverage) — HALT and ask the human before touching cancel logic, since that would contradict the epic context's premise that this story has no independent UI surface.

**Never:**
- Add a new test harness/file or new fake classes.
- Touch `TextEntryCubit.selectTab()`'s text-preservation behavior — exempt from AC1 (confirmed correct: Texto has no async op to cancel).
- Touch Photo/Audio production cancel logic beyond the one doc-comment fix named above.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Áudio→Foto mid-recording | Switch tabs while `AudioRecording` | Mic recorder's cancel fires once; Foto shows idle capture buttons, nothing auto-starts; `createCallCount` stays 0 | N/A |
| Foto→Áudio mid-pick | Switch tabs while a photo pick is in flight | Pick discarded; recording starts immediately; `createCallCount` stays 0 | N/A |
| Chained interrupt + close | Record → switch Foto → pick → switch Texto → type → close (not Salvar) | `createCallCount` stays 0 at every step and after close | N/A |

</frozen-after-approval>

## Code Map

- `lib/features/capture/presentation/widgets/insertion_modal.dart:290-317` -- `_onTextEntryStateChange`'s tab-switch dispatch (cancels audio leaving `audio`, cancels photo leaving `foto`, starts recording entering `audio`) — read-only reference, the behavior under test.
- `lib/features/capture/presentation/cubit/audio_entry_cubit.dart:425-471` -- `cancel()` + `_generation` guard — read-only reference.
- `lib/features/capture/presentation/cubit/photo_entry_cubit.dart:413-439` -- `cancel()` + `_generation` guard — read-only reference.
- `lib/features/capture/presentation/cubit/text_entry_cubit.dart:74-77` -- stale doc comment on `selectTab()` to correct; the only production-code edit in this story.
- `test/features/capture/presentation/widgets/insertion_modal_audio_test.dart:79-146` -- existing `_FakePhotoPicker`/`_FakeMediaRepository`/`_openModal`/`fakeRepository` to reuse as-is.
- `test/features/capture/presentation/widgets/insertion_modal_audio_test.dart:412-437` -- existing "Leave tab mid-recording: switching to Texto..." test — the pattern the new Áudio↔Foto tests mirror.
- `test/features/capture/presentation/widgets/insertion_modal_photo_test.dart:464-490` -- existing "Leave tab mid-pick: switching to Texto..." test — mirrored from the Foto side.

## Tasks & Acceptance

**Execution:**
- [x] `test/features/capture/presentation/widgets/insertion_modal_audio_test.dart` -- add "Áudio→Foto mid-recording switch cancels the recorder, never auto-starts Foto" -- closes AC1's untested tab-pair.
- [x] `test/features/capture/presentation/widgets/insertion_modal_audio_test.dart` -- add "Foto→Áudio mid-pick switch discards the pick and starts recording immediately" -- closes the reverse pair.
- [x] `test/features/capture/presentation/widgets/insertion_modal_audio_test.dart` -- add one chained test: record → switch Foto → pick → switch Texto → type → close without Salvar, asserting `createCallCount == 0` at each interruption and after close -- proves the combined end-to-end guarantee (ACs 1–3) in one flow.
- [x] `lib/features/capture/presentation/cubit/text_entry_cubit.dart:74-77` -- rewrite the doc comment to state the cancel-safety rule already lives in `insertion_modal.dart`'s tab-switch dispatch, and Texto needs no `cancel()` since no async op precedes Salvar -- removes the misleading "Story 3.4's scope" framing now that 3.4 exists.

**Acceptance Criteria:**
- Given `AudioRecording`, when I switch directly to Foto, then the mic recorder's cancel fires once, no capture/pick auto-starts on Foto, and `createCallCount` stays 0.
- Given a photo pick in flight, when I switch directly to Áudio, then the pick is discarded, recording starts immediately, and `createCallCount` stays 0.
- Given a chain of Áudio→Foto→Texto interruptions followed by closing the modal without tapping Salvar, when the modal closes, then `POST /entries` never fired at any point in the chain.
- Given `fvm flutter analyze` and `fvm flutter test`, then both report zero issues / all green.

## Spec Change Log

## Verification

**Commands:**
- `fvm flutter test` -- all green (new + existing).
- `fvm flutter analyze` -- zero issues.

## Suggested Review Order

**Cross-tab cancel-safety tests**

- "Áudio→Foto mid-recording switch" — the untested tab-pair this story's AC1 targets; confirms a direct Áudio→Foto switch cancels the recorder and auto-starts nothing on Foto.
  [`insertion_modal_audio_test.dart:459`](../../test/features/capture/presentation/widgets/insertion_modal_audio_test.dart#L459)

- "Foto→Áudio mid-pick switch" — the reverse pair; a gated in-flight pick is discarded while recording starts immediately, with the stale pick resolving to a no-op afterward.
  [`insertion_modal_audio_test.dart:493`](../../test/features/capture/presentation/widgets/insertion_modal_audio_test.dart#L493)

- Chained Áudio→Foto→Texto interruption, then close without Salvar — the main architectural bet: proves the combined end-to-end zero-`create()` guarantee (ACs 1-3) in one flow instead of three isolated assertions.
  [`insertion_modal_audio_test.dart:539`](../../test/features/capture/presentation/widgets/insertion_modal_audio_test.dart#L539)

**Review-added hardening (patch findings)**

- `tester.takeException()` assertions closing each of the 3 tests above — catches a regression that throws inside a cancelled cubit's async continuation instead of letting it pass silently.
  [`insertion_modal_audio_test.dart:521`](../../test/features/capture/presentation/widgets/insertion_modal_audio_test.dart#L521)

- The chained test's final gate-completion now `pump()`s before asserting — the modal/`PhotoEntryCubit` is already closed at that point, so any exception from the completion must surface here, not leak into a later test.
  [`insertion_modal_audio_test.dart:592`](../../test/features/capture/presentation/widgets/insertion_modal_audio_test.dart#L592)

**Doc-comment fix**

- `TextEntryCubit.selectTab()`'s doc comment — corrected to point at `insertion_modal.dart`'s tab-switch dispatch as the cross-tab rule's real home, removing the stale "Story 3.4's scope" framing.
  [`text_entry_cubit.dart:75`](../../lib/features/capture/presentation/cubit/text_entry_cubit.dart#L75)

**Test fixture changes (supporting)**

- `_FakePhotoPicker` — `pickFromCamera()` made configurable/gateable (`nextCameraResult`, `cameraGate`) instead of always throwing, plus a `cameraCalls` counter added for parity with `_FakeMicRecorder`.
  [`insertion_modal_audio_test.dart:81`](../../test/features/capture/presentation/widgets/insertion_modal_audio_test.dart#L81)
