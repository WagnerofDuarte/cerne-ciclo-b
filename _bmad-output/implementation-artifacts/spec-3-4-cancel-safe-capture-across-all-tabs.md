---
title: 'Story 3.4: Cancel-Safe Capture Across All Tabs'
type: 'feature'
created: '2026-11-04'
status: 'done'
review_loop_iteration: 1
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

### Review Findings

- [x] [Review][Decision] Undisclosed scope deviation — an `amplitudeStream` error-handling test (plus the new `_FakeMicRecorder.amplitudeController` fixture field) was added in this diff but is not named anywhere in this story's Tasks & Acceptance, Code Map, or Suggested Review Order, and is unrelated to FR-11/cancel-safety — it strains the frozen Boundaries' "no new cancel logic, this story only verifies/documents 3.1–3.3" framing in spirit. **Resolved:** accepted as a disclosed deviation (real coverage value, same precedent as spec-3-3's bundled additions) — logged below in Spec Change Log. [test/features/capture/presentation/widgets/insertion_modal_audio_test.dart:45,276-313]
- [x] [Review][Patch] `deferred-work.md`'s new entry misattributes the `amplitudeStream` test's provenance — it claims the test is "pre-existing (spec-3-3-round-2)" and "predates [story 3.4]," but `git show 58107bb:test/.../insertion_modal_audio_test.dart` proves neither the test nor its `amplitudeController` field existed before this commit (1e52ae5) — both were authored fresh here. — fixed: attribution corrected in place. [_bmad-output/implementation-artifacts/deferred-work.md:223-224]
- [x] [Review][Patch] This spec file had no `### Review Findings` section and its own frontmatter `review_loop_iteration` was still `0`, even though its "Suggested Review Order" already named a "Review-added hardening (patch findings)" subsection presupposing a completed review round — same inconsistency this codebase's own history (spec-2-3, spec-2-4) already caught and fixed by bumping the iteration and populating this section. — fixed: `review_loop_iteration` bumped to `1`; this section populated. [spec-3-4-cancel-safe-capture-across-all-tabs.md frontmatter]
- [x] [Review][Patch] "Suggested Review Order"'s "Review-added hardening" bullet cites `insertion_modal_audio_test.dart:521` for the `tester.takeException()` assertions, but line 521 is `fakePhotoPicker.cameraGate!.complete();` — the real three `takeException()` calls are at lines 488, 534, and 595. — fixed: citation corrected. [insertion_modal_audio_test.dart:521]
- [x] [Review][Patch] `_FakePhotoPicker.cameraCalls`, added "for parity" with `_FakeMicRecorder`, is never asserted anywhere — including in the two new tests whose entire premise is that a pick is genuinely in flight when the tab switch interrupts it ("mid-pick" currently rests only on the gate `Completer`'s existence, not an observed call). — fixed: `expect(fakePhotoPicker.cameraCalls, 1);` added right after tapping "Câmera" in both the "Foto→Áudio mid-pick switch" and chained tests. [insertion_modal_audio_test.dart:507,564]
- [x] [Review][Patch] The `main()` doc comment claims Story-3.4's cross-tab tests "configure `_FakePhotoPicker.nextCameraResult`/`cameraGate`," but the first new test ("Áudio→Foto mid-recording switch") never touches Foto's picker fields at all — it switches to an idle Foto tab. — fixed: comment tightened to name only the two tests that actually configure the gate. [insertion_modal_audio_test.dart:242-247]
- [x] [Review][Patch] The amplitude-error test's own description says "the waveform just stays frozen on its last sample," but its only assertion (`find.text('00:00')`) checks the elapsed-timer label, not the waveform/amplitude state — the test doesn't verify the behavior it claims to prove. (`_Waveform`'s `onError: (_) {}` also has no `cancelOnError`, so whether the stream resumes delivering samples after the error is untested either way.) — fixed: assertion strengthened to compare the waveform's last `AnimatedContainer` height before/after the error, proving it's actually frozen. [insertion_modal_audio_test.dart:276-313]
- [x] [Review][Patch] `_FakePhotoPicker.pickFromCamera()` now returns `null` silently by default instead of throwing `UnimplementedError`, for any test that never configures `nextCameraResult`/`cameraGate` — a future regression causing an unintended camera-pick call in an unrelated test would now go unnoticed instead of failing loudly. — fixed: restored the loud-failure default (`throw UnimplementedError`) unless a test explicitly configures `cameraGate` or `nextCameraResult`. [insertion_modal_audio_test.dart:81-99]

## Spec Change Log

- **Accepted deviation (code review, 2026-11-04):** an `amplitudeStream` error-handling test (`insertion_modal_audio_test.dart:280`) plus its supporting `_FakeMicRecorder.amplitudeController` fixture field were bundled into this commit alongside the three named cross-tab tests. Neither was listed in this spec's original Tasks & Acceptance/Code Map — they verify `_Waveform`'s `onError` guard against a native amplitude-stream error, unrelated to FR-11/cancel-safety. Accepted as valuable coverage rather than reverted or split out, same precedent as spec-3-3's own bundled additions.

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
  [`insertion_modal_audio_test.dart:488,534,595`](../../test/features/capture/presentation/widgets/insertion_modal_audio_test.dart#L488)

- The chained test's final gate-completion now `pump()`s before asserting — the modal/`PhotoEntryCubit` is already closed at that point, so any exception from the completion must surface here, not leak into a later test.
  [`insertion_modal_audio_test.dart:592`](../../test/features/capture/presentation/widgets/insertion_modal_audio_test.dart#L592)

**Doc-comment fix**

- `TextEntryCubit.selectTab()`'s doc comment — corrected to point at `insertion_modal.dart`'s tab-switch dispatch as the cross-tab rule's real home, removing the stale "Story 3.4's scope" framing.
  [`text_entry_cubit.dart:75`](../../lib/features/capture/presentation/cubit/text_entry_cubit.dart#L75)

**Test fixture changes (supporting)**

- `_FakePhotoPicker` — `pickFromCamera()` made configurable/gateable (`nextCameraResult`, `cameraGate`) instead of always throwing, plus a `cameraCalls` counter added for parity with `_FakeMicRecorder`.
  [`insertion_modal_audio_test.dart:81`](../../test/features/capture/presentation/widgets/insertion_modal_audio_test.dart#L81)
