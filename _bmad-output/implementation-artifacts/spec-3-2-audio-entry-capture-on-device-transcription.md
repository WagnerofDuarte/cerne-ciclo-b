---
title: 'Story 3.2: Audio Entry Capture & On-Device Transcription'
type: 'feature'
created: '2026-11-04'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '8e92fd7273e4e66736635cb77d2ffc44d58a88e5'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The Áudio tab is still an idle placeholder (`_IdleTabPlaceholder`) — recording, on-device transcription, and saving a `source=audio` Entry don't exist, and the app has no audio-recording package or microphone-permission handling at all.

**Approach:** Add a new `AudioEntryCubit` (its own sealed state, separate from `TextEntryCubit`) driving the 4-state pipeline — recording → processing → transcribed → error — backed by two new `capture/domain` ports: `MicRecorder` (`record` package) and `AudioTranscriber` (`whisper_ggml`). Extend `Entry`/`EntriesRepository.create` with the optional `mediaDurationSeconds` field the backend contract already reserves. Wire tab switching into/out of Áudio to start/stop the recorder.

## Boundaries & Constraints

**Always:**
- `record: ^6.0.0` (new dependency) handles mic capture and permission (`hasPermission()`) — no separate `permission_handler`. Two new `capture/domain` ports, `MicRecorder` and `AudioTranscriber`, decouple the cubit from both packages (Code Map has the exact files).
- `AudioTranscriber.transcribe()` returns `String?` — `null` means failure, a local-only outcome never wrapped in `Failure` (RNF09 scopes `Failure` to repository/backend calls).
- `AudioEntryCubit` (new, own sealed `AudioCaptureState`, separate from `TextEntryState`) drives: idle → recording → processing → transcribed/error. Recording starts/stops from `InsertionModal`'s existing tab-switch listener. The recorded file is never deleted on a transcription or permission failure; "Tentar novamente" retries in place (re-transcribe the same file, or re-request permission if none was ever recorded).
- `Entry`/`EntriesRepository.create`/its DTO/datasource/impl all gain an optional `int? mediaDurationSeconds` (sent/decoded only when non-null) — already reserved in `openapi.yaml`'s entries-create contract. `AudioEntryCubit.save()` calls `create(source: EntrySource.audio, ...)`, mirroring `TextEntryCubit.save()`'s `isClosed`/no-double-submit guards.
- Every transition gets a screen-reader announcement, same `_announce` helper. `InsertionModal` provides both cubits (`MultiBlocProvider`) and closes both in `show()`'s `finally`.

**Ask First:** none identified.

**Never:**
- Implement the full cross-tab cancel-safety rule (Story 3.4) — this story's trivial case: `create` only fires on explicit Salvar, and leaving the Áudio tab mid-recording stops the recorder (resource safety only, not 3.4's full choreography).
- Send audio bytes to the backend in any call — transcription is 100% on-device (FR-12); only the resulting text reaches `entries-create`.
- Build Story 3.3's Foto tab or touch its placeholder.
- Add `permission_handler` or any separate permission package.
- Write an automated test exercising the real `record`/`whisper_ggml` native plugins (no device/simulator exists, AGENTS.md) — both are mocked (mocktail) in `AudioEntryCubit` tests, same convention as `EntriesRepository` in `TextEntryCubit` tests.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Happy path | Switch to Áudio, record, stop, review text, tap Salvar | Waveform animates while recording; freezes at 35% opacity while transcribing; text editable once transcribed; `POST /entries` (`source: audio`, `mediaDurationSeconds`) fires; success closes modal | N/A |
| Transcription fails | `AudioTranscriber.transcribe` returns `null` | `AudioError` shown, audio file preserved, "Tentar novamente" re-transcribes the same file | No auto-retry |
| Mic permission denied | `MicRecorder.start()` permission check fails | `AudioError` with permission-specific message; "Tentar novamente" re-requests permission | No file to preserve |
| Save fails (incl. offline) | Salvar tapped from `AudioTranscribed`, `create` returns a `Failure` | Inline message from `Failure.message`; Salvar re-enabled, text/audio preserved | `Failure.fromCode`, no auto-retry |
| Leave tab mid-recording | Switch to Texto/Foto while `AudioRecording`/`AudioProcessing` | Recorder stopped/released; no `POST /entries` fires | N/A |

</frozen-after-approval>

## Code Map

- `pubspec.yaml:52` -- add `record: ^6.0.0` beneath `whisper_ggml`.
- `lib/features/capture/domain/services/mic_recorder.dart` (new) -- abstract `MicRecorder` (start/stop→`(path, duration)`/cancel/amplitude stream) -- mirrors `EntriesRepository`'s port convention.
- `lib/features/capture/domain/services/audio_transcriber.dart` (new) -- abstract `AudioTranscriber { Future<String?> transcribe(String audioPath); }`.
- `lib/features/capture/data/services/record_mic_recorder.dart` (new) -- wraps `package:record`'s `AudioRecorder` (aliased import, name clash), writes a temp-dir `.wav` (`path_provider`'s `getTemporaryDirectory()`, already transitive via `hive_ce_flutter`).
- `lib/features/capture/data/services/whisper_audio_transcriber.dart` (new) -- wraps `whisper_ggml`'s `WhisperController` (`downloadModel`+`transcribe`, `lang: 'pt'`, `WhisperModel.base`), catches any exception into `null`.
- `lib/features/capture/presentation/cubit/audio_entry_cubit.dart` (new) -- `AudioEntryCubit` state machine: `AudioIdle` → `AudioRecording(elapsed)` → `AudioProcessing(path, duration)` → `AudioTranscribed(path, duration, text, saving)` / `AudioError(path, duration, message)`.
- `lib/features/capture/capture_injection.dart:13-16` -- register `AudioEntryCubit`, `MicRecorder`, `AudioTranscriber`.
- `lib/features/capture/presentation/widgets/insertion_modal.dart:33-91` (`show`/`build`) -- accept a second `audioCubit`, `MultiBlocProvider`, close both in `show()`'s `finally`.
- `lib/features/capture/presentation/widgets/insertion_modal.dart:150-182` (listener) -- extend tab-switch detection to call `AudioEntryCubit.startRecording()`/`.cancel()`; add Audio's own Saved→announce→pop listener.
- `lib/features/capture/presentation/widgets/insertion_modal.dart:222-235` (`switch (state.activeTab)`) -- replace the `CaptureTab.audio` placeholder with a new `_AudioTab` widget (mirrors `_TextoTab:417-497`).
- `lib/core/navigation/placeholder_screens.dart:96` -- resolve `sl<AudioEntryCubit>()` too, pass to `InsertionModal.show`.
- `lib/features/entries/domain/entities/entry.dart`, `entries_repository.dart:17-20`, `data/models/entry_dto.dart` (+ `.g.dart`), `data/datasources/entries_remote_data_source.dart:20-27`, `data/repositories/entries_repository_impl.dart:30-60` -- thread optional `int? mediaDurationSeconds` through entity/port/DTO/datasource/impl, sent/decoded only when non-null (`openapi.yaml:345-358,439` already reserves it).
- `docs/input/backend/fixtures/README.md`/`expected-transcription.md`/`media/audio_fixture_01.wav` -- manual-verification fixture only (no device to run real whisper in automated tests).
- `lib/core/design_tokens.dart:51` (`colorError`), `:158` (`textMonoCaption`) -- reuse for the stop-button/waveform accent and timer/duration labels; no new token needed.
- `test/features/capture/**`, `test/features/entries/**` -- mirror 3.1's layout for the new cubit/services/port-extension tests.

## Tasks & Acceptance

**Execution:**
- [x] `pubspec.yaml` -- add `record: ^6.0.0` -- new mic-capture dependency.
- [x] `lib/features/capture/domain/services/mic_recorder.dart` (new) -- abstract `MicRecorder` port.
- [x] `lib/features/capture/domain/services/audio_transcriber.dart` (new) -- abstract `AudioTranscriber` port.
- [x] `lib/features/capture/data/services/record_mic_recorder.dart` (new) -- `record`-backed implementation.
- [x] `lib/features/capture/data/services/whisper_audio_transcriber.dart` (new) -- `whisper_ggml`-backed implementation.
- [x] `lib/features/capture/presentation/cubit/audio_entry_cubit.dart` (new) -- `AudioEntryCubit` + `AudioCaptureState` hierarchy.
- [x] `lib/features/capture/capture_injection.dart` -- register `AudioEntryCubit`/`MicRecorder`/`AudioTranscriber`.
- [x] `lib/features/entries/domain/entities/entry.dart`, `entries_repository.dart`, `entry_dto.dart` (+ generated), `entries_remote_data_source.dart`, `entries_repository_impl.dart` -- add `mediaDurationSeconds`.
- [x] `lib/features/capture/presentation/widgets/insertion_modal.dart` -- wire second cubit, tab-switch start/cancel, new `_AudioTab` widget, Saved→pop listener.
- [x] `lib/core/navigation/placeholder_screens.dart` -- resolve and pass `AudioEntryCubit`.
- [x] Unit/widget tests under `test/features/capture/`, `test/features/entries/` covering the I/O matrix above.

**Acceptance Criteria:**
- Given the Áudio tab, when I switch into it, then recording starts immediately with an animated waveform and monospace running timer.
- Given recording stops, when `whisper_ggml` transcribes on-device, then the waveform freezes at 35% opacity during processing and no network call in this pipeline ever carries audio bytes.
- Given transcription completes, when I review the text, then it is editable before Salvar, and the resulting Entry carries `source: audio` and `mediaDurationSeconds`.
- Given `fvm flutter analyze` and `fvm flutter test`, then both report zero issues / all green.

### Review Findings

**Patch:**
- [x] [Review][Patch] `AudioEntryCubit.cancel()` never deletes the temp recording file for `AudioTranscribed`/a file-carrying `AudioError` — dismissing the whole modal (not a tab switch) while reviewing transcribed text or after a failed save permanently orphans that `.wav` file, since `close()` runs right after and nothing will ever clean it up. `cancel()` only has cleanup branches for `AudioRecording`/`AudioProcessing`. Decision: patch now (extend `cancel()`'s cleanup to these two states). Fixed via a new `cancel({bool discardPreserved = false})` param; `InsertionModal.show()`'s `finally` now passes `discardPreserved: true`. [lib/features/capture/presentation/cubit/audio_entry_cubit.dart:330]
- [x] [Review][Patch] No test exercises full-modal dismiss (e.g. "x" tap) while `AudioRecording`/`AudioProcessing`, so the existing `audioCubit.cancel()` call in `InsertionModal.show()`'s `finally` has no regression coverage [lib/features/capture/presentation/widgets/insertion_modal.dart:94]
- [x] [Review][Patch] No test asserts "Salvando registro" is announced while an audio save is in flight (the Texto tab's equivalent has one) [lib/features/capture/presentation/widgets/insertion_modal.dart:263]
- [x] [Review][Patch] `_deleteRecordingFile` cleanup after a successful save or an abandoned mid-processing recording is never verified against a real file — every cubit/widget test uses fake paths that silently no-op the delete [lib/features/capture/presentation/cubit/audio_entry_cubit.dart:437]
- [x] [Review][Patch] `stopRecording()` reads `_generation` but never bumps it on entry (unlike `startRecording()`) — a rapid double-tap on the stop control before the UI rebuilds can let a second, stale `_micRecorder.stop()` call overwrite a valid `AudioProcessing`/transcription result with a bogus `AudioError`. Fixed with a `_stopping` re-entry guard rather than a generation bump (bumping alone would have let the wrong call's result win). [lib/features/capture/presentation/cubit/audio_entry_cubit.dart:208]
- [x] [Review][Patch] `MicRecorder` native calls (`hasPermission`/`start`/`stop`/`cancel`) are never wrapped in try/catch — a thrown `PlatformException` escapes uncaught; inside `InsertionModal.show()`'s `finally`, that would also skip the following `audioCubit.close()` [lib/features/capture/presentation/cubit/audio_entry_cubit.dart:161]
- [x] [Review][Patch] `_Waveform`'s `amplitudeStream.listen()` has no `onError` handler — an error from the native amplitude stream becomes an uncaught async exception [lib/features/capture/presentation/widgets/insertion_modal.dart:945]
- [x] [Review][Patch] `RecordMicRecorder.stop()` computes `durationSeconds` via `DateTime.now().difference(startedAt).inSeconds` with no floor — a backward clock adjustment mid-recording yields a negative value, which the backend's `mediaDurationSeconds: minimum 0` contract will reject, turning an otherwise-successful recording into a save failure. Fixed by flooring at 0 (no dedicated regression test — exercising a real backward clock jump isn't practically simulable without a clock-injection refactor out of scope for this patch). [lib/features/capture/data/services/record_mic_recorder.dart:73]
- [x] [Review][Patch] `AudioIdle` is the one `AudioCaptureState` transition never announced to screen readers (`case AudioIdle(): break;`) — masked today only because its one reachable path (tab-switch away while recording) coincides with the separate tab-switch announcement [lib/features/capture/presentation/widgets/insertion_modal.dart:278]
- [x] [Review][Patch] No test covers `cancel()` racing a `retry()`-triggered re-transcription — appears already safe via `_transcribe`'s own state-based guard, but unverified by any test [lib/features/capture/presentation/cubit/audio_entry_cubit.dart:282]

**Defer:**
- [x] [Review][Defer] No maximum recording duration is enforced anywhere — the elapsed-timer `MM:SS` label has no cap past 99 minutes and nothing bounds an unboundedly long on-device transcription; not called for anywhere in the spec's I/O matrix, a product/UX decision rather than a technical one [lib/features/capture/presentation/widgets/insertion_modal.dart:694] — deferred, out of this story's scope
- [x] [Review][Defer] `WhisperAudioTranscriber.transcribe()` calls `downloadModel()` on every invocation, including every "Tentar novamente" retry, with no cached-already-downloaded short-circuit in this wrapper — likely benign (the underlying package most likely no-ops once cached) but unverified third-party behavior [lib/features/capture/data/services/whisper_audio_transcriber.dart:14] — deferred, low-confidence/unverified

## Spec Change Log

## Design Notes

- **Two cubits, one modal:** `TextEntryCubit` stays the modal's `activeTab` source of truth; `AudioEntryCubit` only owns the audio pipeline — avoids rearchitecting `TextEntryCubit` or merging unrelated state shapes.
- **`WhisperModel.base`, `lang: 'pt'`, lazy download inside `transcribe()`:** balances accuracy/size; a missing model + no connectivity just surfaces through the same generic error/retry path as any other transcription failure — no new state needed.
- **`mediaDurationSeconds` lands now, not "later":** `entry.dart`'s own Story 3.1 comment named it as deferred to "later epics" — this is that story.

## Verification

**Commands:**
- `fvm flutter pub get` -- resolves `record` with no conflicts.
- `fvm flutter pub run build_runner build --delete-conflicting-outputs` -- regenerates `entry_dto.g.dart` with the new field.
- `fvm flutter analyze` -- zero issues.
- `fvm flutter test` -- all green.

**Manual checks (if no CLI):**
- On a real device/simulator (none exists yet, AGENTS.md): record a short Portuguese phrase, confirm it transcribes and an `audio`-sourced Entry saves; optionally compare against `docs/input/backend/fixtures/media/audio_fixture_01.wav` + `expected-transcription.md` for rough transcription-quality sanity, not exact match.

## Suggested Review Order

**Audio capture state machine**

- The pipeline's own sealed states and the 3 failure-row shapes (`AudioError`'s permission/transcription/save variants) — the main architectural bet of this story.
  [`audio_entry_cubit.dart:16`](../../lib/features/capture/presentation/cubit/audio_entry_cubit.dart#L16)

- `_generation` — review-added guard so `cancel()` running mid-await (tab switch during `startRecording()`/`stopRecording()`) can't leave the recorder running or resurrect a dropped flow.
  [`audio_entry_cubit.dart:134`](../../lib/features/capture/presentation/cubit/audio_entry_cubit.dart#L134)

- `startRecording()` — only (re)starts from `AudioIdle` or a permission-denied `AudioError`; review-added guard against silently discarding `AudioTranscribed`/`AudioError` work on re-entry.
  [`audio_entry_cubit.dart:152`](../../lib/features/capture/presentation/cubit/audio_entry_cubit.dart#L152)

- `stopRecording()` — the post-`stop()` generation check that stops a stale result from resurrecting a canceled flow.
  [`audio_entry_cubit.dart:204`](../../lib/features/capture/presentation/cubit/audio_entry_cubit.dart#L204)

- `save()` — review-added: now also retries from a save-failure `AudioError`, not only `AudioTranscribed`; deletes the temp file on success.
  [`audio_entry_cubit.dart:372`](../../lib/features/capture/presentation/cubit/audio_entry_cubit.dart#L372)

- `cancel()` — the I/O matrix's "Leave tab mid-recording" row; review-added file cleanup for the abandoned mid-processing case.
  [`audio_entry_cubit.dart:330`](../../lib/features/capture/presentation/cubit/audio_entry_cubit.dart#L330)

**MicRecorder / AudioTranscriber ports**

- The abstract port `AudioEntryCubit` depends on instead of `package:record` directly — decouples the cubit from the native plugin.
  [`mic_recorder.dart:20`](../../lib/features/capture/domain/services/mic_recorder.dart#L20)

- `RecordMicRecorder` — wraps `package:record`'s `AudioRecorder`; review-added: `cancel()` now deletes the file itself rather than solely trusting the plugin's own contract.
  [`record_mic_recorder.dart:67`](../../lib/features/capture/data/services/record_mic_recorder.dart#L67)

- `WhisperAudioTranscriber` — wraps `whisper_ggml`'s `WhisperController`, lazy `downloadModel` + `transcribe(lang: 'pt')`, `null` on any failure.
  [`whisper_audio_transcriber.dart:14`](../../lib/features/capture/data/services/whisper_audio_transcriber.dart#L14)

**Insertion Modal wiring**

- `show()` — review-added: `audioCubit.cancel()` before `close()`, so dismissing the whole modal (not just switching tabs) actually releases the mic.
  [`insertion_modal.dart:35`](../../lib/features/capture/presentation/widgets/insertion_modal.dart#L35)

- `build()` — review-added: `isSaving` now also reads `AudioEntryCubit`'s own saving flag, closing the race that let the tab bar/close button stay tappable mid-audio-save.
  [`insertion_modal.dart:284`](../../lib/features/capture/presentation/widgets/insertion_modal.dart#L284)

- `_onAudioStateChange`/tab-switch listener — drives `startRecording()`/`cancel()` from the same place `TextEntryCubit`'s own tab-switch detection already lives.
  [`insertion_modal.dart:247`](../../lib/features/capture/presentation/widgets/insertion_modal.dart#L247)

- `_AudioTab` — the 5-state `switch` driving the tab's UI, mirroring `_TextoTab`'s own structure.
  [`insertion_modal.dart:625`](../../lib/features/capture/presentation/widgets/insertion_modal.dart#L625)

- `_Waveform` — the amplitude-bar visualizer; no prototype mock exists for this, a "decide and proceed" call (Design Notes).
  [`insertion_modal.dart:921`](../../lib/features/capture/presentation/widgets/insertion_modal.dart#L921)

**Entries port extension**

- `EntriesRepository.create` — the optional `mediaDurationSeconds` param `entry.dart`'s own Story 3.1 comment already flagged as deferred to this story.
  [`entries_repository.dart:17`](../../lib/features/entries/domain/repositories/entries_repository.dart#L17)

- `Entry`/`EntryDto` — the 9th field, sent/decoded only when non-null (`@JsonKey(includeIfNull: false)`).
  [`entry.dart:48`](../../lib/features/entries/domain/entities/entry.dart#L48)

**Wiring**

- `registerCaptureFeature()` — `MicRecorder`/`AudioTranscriber` as lazy singletons (one real recorder for the app's lifetime), `AudioEntryCubit` as a factory like `TextEntryCubit`.
  [`capture_injection.dart:25`](../../lib/features/capture/capture_injection.dart#L25)

- The "+" FAB now resolves and passes both cubits to `InsertionModal.show`.
  [`placeholder_screens.dart:96`](../../lib/core/navigation/placeholder_screens.dart#L96)

- `NSMicrophoneUsageDescription` — required for `record` to request mic access on a real device.
  [`Info.plist:31`](../../ios/Runner/Info.plist#L31)

**Tests**

- The full I/O-matrix coverage plus the review-added regression tests (save-retry-after-failure, re-entry-after-transcribed, in-flight-save disables chrome).
  [`insertion_modal_audio_test.dart:1`](../../test/features/capture/presentation/widgets/insertion_modal_audio_test.dart#L1)

- Cubit-level unit tests, including the two `_generation` race fixes.
  [`audio_entry_cubit_test.dart:1`](../../test/features/capture/presentation/cubit/audio_entry_cubit_test.dart#L1)

- Review-added: extends the DI bootstrap test for `AudioEntryCubit`/`MicRecorder`/`AudioTranscriber`, faking `record`'s native channel the same way secure storage already is.
  [`bootstrap_integration_test.dart:163`](../../test/core/di/bootstrap_integration_test.dart#L163)

- Review-added: `cancel()` now asserted to actually delete the in-progress file, not just call the plugin.
  [`record_mic_recorder_test.dart:131`](../../test/features/capture/data/services/record_mic_recorder_test.dart#L131)
