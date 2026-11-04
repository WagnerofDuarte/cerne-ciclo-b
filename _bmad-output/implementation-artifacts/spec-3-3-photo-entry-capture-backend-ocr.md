---
title: 'Story 3.3: Photo Entry Capture & Backend OCR'
type: 'feature'
created: '2026-11-04'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '8505cadf63cd3463428c60b00fcf491bf61c4701'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The Foto tab is still an idle placeholder (`CaptureTab.foto => _IdleTabPlaceholder`, `insertion_modal.dart:356-359`) — picking a photo, server-side OCR via `POST /media/ocr`, and saving a `source=photo` Entry don't exist, and the app has no image-picker package at all.

**Approach:** Add a new `PhotoEntryCubit` (own sealed state, separate from `TextEntryCubit`/`AudioEntryCubit`) driving capture → processingOcr → recognized → error, backed by a new `capture/domain` port `PhotoPicker` (`image_picker`) and a new `capture/data` `MediaRepository`/`MediaRemoteDataSource` calling `media-ocr`. Wire Foto tab switching into the picker; `OcrNoText`/`PayloadTooLarge` each get their own distinct, non-retryable error UI.

## Boundaries & Constraints

**Always:**
- `image_picker: ^1.1.2` (new dependency) powers the "Câmera"/"Galeria" buttons. New `capture/domain` port `PhotoPicker` (`pickFromCamera()`/`pickFromGallery()` → `PickedPhoto? {path, mimeType}`, `null` = user canceled) wraps it — mirrors `MicRecorder`'s port convention (`mic_recorder.dart:20-46`); never call `ImagePicker` directly from the cubit. `mimeType` is inferred from the picked file's extension (jpeg/png/webp only, matching the contract's enum).
- OCR belongs to `capture/`, never `entries/` (epic Technical Decisions: "`features/capture/` ... holds no Entry data itself"). New `capture/domain/repositories/media_repository.dart` (`recognizeText({required Uint8List imageBytes, required String mimeType}) -> Either<Failure, OcrResult>` where `OcrResult{text, confidence}`), `capture/data/datasources/media_remote_data_source.dart` + `capture/data/repositories/media_repository_impl.dart` mirroring `entries_remote_data_source.dart:21-46`/`entries_repository_impl.dart:29-51` but with **no Hive persistence step** — the image is never persisted, forward the datasource's `Either` as-is. Calls `ApiClient.post('media-ocr', data: {image: base64Encode(bytes), mimeType: mimeType})` (`api_client.dart:52-62`); base64-encodes only inside the datasource.
- `PhotoEntryCubit(this._photoPicker, this._mediaRepository, this._entriesRepository)`, own sealed `PhotoCaptureState`: `PhotoIdle` → `PhotoProcessing(path, mimeType)` → `PhotoRecognized(path, mimeType, text, saving)` / `PhotoSaved` / `PhotoError(path, mimeType, message, kind, text?)`. `kind` is a 3-way discriminator (`generic | ocrNoText | payloadTooLarge`) driving three distinct branches — `Failure.ocrNoText`/`Failure.payloadTooLarge` already exist (`failure.dart:32-34,80-81`): **ocrNoText** → "Tentar novamente" (re-OCR same image via `retry()`) + "Salvar só a foto" (`saveWithoutText()`, creates the Entry with a fixed non-empty placeholder `content` — e.g. `"Registro fotográfico (sem texto reconhecido)"` — since the contract's `content.minLength: 1` forbids empty); **payloadTooLarge** → size-specific message, no action besides picking a different photo (no retry, no "Salvar só a foto"); **generic** (any other `Failure`, incl. a save failure, `text` non-null) → plain "Tentar novamente" re-running whichever call failed, same shape as `AudioError`.
- Recognized/placeholder text saves via `_entriesRepository.create(source: EntrySource.photo, content: <text>)` — `EntrySource.photo` already exists (`entry.dart:6`), no `Entry`/DTO change needed.
- Every transition gets a screen-reader announcement via the existing `_announce` helper (`insertion_modal.dart:196-205`). `InsertionModal.show`/`build` gain a third `photoCubit` param, provided via the existing `MultiBlocProvider` (`insertion_modal.dart:106-107`), canceled+closed in `show()`'s `finally` alongside the other two (mirrors `audioCubit.cancel(discardPreserved: true)` + `close()`, lines 97-98). `isSaving` (`insertion_modal.dart:310`) must also OR in `PhotoEntryCubit`'s own saving flag — the exact cross-tab race 3.2's review already fixed for Audio.
- `NSCameraUsageDescription`/`NSPhotoLibraryUsageDescription` added to `ios/Runner/Info.plist` after the existing Face ID/mic keys (line 32), same style.
- Use the `_generation` counter pattern (`audio_entry_cubit.dart:134`) in `PhotoEntryCubit` for the same tab-switch-mid-await race, now across the picker call and the OCR network call.

**Ask First:** none identified.

**Never:**
- Persist the image anywhere beyond the in-flight OCR call (no local cache, no backend storage) — only extracted text ever moves on.
- Implement the full cross-tab cancel-safety rule (Story 3.4) — this story's trivial case only: `create` fires only on explicit Salvar/"Salvar só a foto"; leaving Foto mid-pick/mid-OCR just discards the in-flight picker call/OCR request.
- Add HEIC→JPEG conversion or any client-side image-size pre-check — anything outside jpeg/png/webp (e.g. iOS HEIC) is a known gap, deferred like 3.2's untested native-plugin edges (no device exists to verify).
- Write a test exercising the real `image_picker` native plugin — mock it (mocktail), same convention as `MicRecorder`/`AudioTranscriber`.
- Touch Story 3.1/3.2's Texto/Áudio tabs beyond the shared `InsertionModal` wiring already described above.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Happy path | Switch to Foto, tap Câmera or Galeria, pick a jpeg/png/webp photo | Thumbnail+spinner "Reconhecendo texto..." while OCR runs; recognized text editable; Salvar fires `POST /entries` (`source: photo`), success closes modal | N/A |
| `OCR_NO_TEXT` | `media-ocr` succeeds with no usable text | Thumbnail kept, "Não foi possível reconhecer o texto"; "Tentar novamente" re-OCRs same image, "Salvar só a foto" saves with placeholder content | Non-retryable, two distinct recovery paths |
| `PAYLOAD_TOO_LARGE` | Picked image exceeds backend's limit | Size-specific message, no retry button, no "Salvar só a foto" | Non-retryable |
| User cancels picker | Câmera/Galeria dialog dismissed with no file chosen | Stays on Foto's capture buttons (`PhotoIdle`) | N/A |
| Save fails (incl. offline) | Salvar tapped from `PhotoRecognized`/a save-failure `PhotoError`, `create` returns a `Failure` | Inline message from `Failure.message`; Salvar re-enabled, text/photo preserved | `Failure.fromCode`, no auto-retry |
| Leave tab mid-pick/OCR | Switch to Texto/Áudio while `PhotoProcessing` | In-flight picker call/OCR request discarded; no `POST /entries` fires | N/A |

</frozen-after-approval>

## Code Map

- `pubspec.yaml:53` (after `record`) -- add `image_picker: ^1.1.2`.
- `lib/features/capture/domain/services/photo_picker.dart` (new) -- abstract `PhotoPicker { pickFromCamera()/pickFromGallery() -> Future<PickedPhoto?>; }`, `PickedPhoto{path, mimeType}` -- mirrors `mic_recorder.dart`.
- `lib/features/capture/data/services/image_picker_photo_picker.dart` (new) -- wraps `package:image_picker`'s `ImagePicker`, infers `mimeType` from extension.
- `lib/features/capture/domain/repositories/media_repository.dart` (new) -- abstract `MediaRepository { recognizeText(...) -> Future<Either<Failure, OcrResult>>; }`, `OcrResult{text, confidence}`.
- `lib/features/capture/data/datasources/media_remote_data_source.dart` (new) -- calls `ApiClient.post('media-ocr', ...)`, base64-encodes bytes, parses `data` -- mirrors `entries_remote_data_source.dart:21-46`.
- `lib/features/capture/data/repositories/media_repository_impl.dart` (new) -- forwards datasource `Either`, no Hive step -- mirrors `entries_repository_impl.dart:29-51` minus persistence.
- `lib/features/capture/presentation/cubit/photo_entry_cubit.dart` (new) -- `PhotoEntryCubit` + `PhotoCaptureState` hierarchy, mirrors `audio_entry_cubit.dart`'s shape (states 17-108, methods 160-543, `_generation` guard at 134).
- `lib/features/capture/capture_injection.dart:48` (before closing `}`) -- register `ImagePicker`, `PhotoPicker`, `MediaRemoteDataSource`, `MediaRepository`, `PhotoEntryCubit` (factory, like `AudioEntryCubit`).
- `lib/features/capture/presentation/widgets/insertion_modal.dart:35-100` (`show`) -- accept third `photoCubit`, cancel+close it in `finally`.
- `lib/features/capture/presentation/widgets/insertion_modal.dart:102-111` (`build`) -- add third `BlocProvider.value(value: photoCubit)`.
- `lib/features/capture/presentation/widgets/insertion_modal.dart:207-249` (tab-switch listener) -- extend to discard in-flight photo pick/OCR on leaving Foto.
- `lib/features/capture/presentation/widgets/insertion_modal.dart:305-310` (`isSaving`) -- OR in `PhotoEntryCubit`'s saving flag.
- `lib/features/capture/presentation/widgets/insertion_modal.dart:356-359` -- replace `_IdleTabPlaceholder` with new `_FotoTab` widget (mirrors `_AudioTab:634-670`; capture-buttons sub-state instead of a recording view, two-button error sub-state for `ocrNoText`).
- `lib/core/navigation/placeholder_screens.dart:96-100` -- resolve `sl<PhotoEntryCubit>()`, pass to `InsertionModal.show`.
- `ios/Runner/Info.plist:32` -- add `NSCameraUsageDescription`/`NSPhotoLibraryUsageDescription`.
- `test/features/capture/**` -- mirror 3.2's layout (`data/services/image_picker_photo_picker_test.dart`, `data/datasources/media_remote_data_source_test.dart`, `data/repositories/media_repository_impl_test.dart`, `presentation/cubit/photo_entry_cubit_test.dart`, `presentation/widgets/insertion_modal_photo_test.dart`).

## Tasks & Acceptance

**Execution:**
- [x] `pubspec.yaml` -- add `image_picker: ^1.1.2`.
- [x] `lib/features/capture/domain/services/photo_picker.dart` (new) -- abstract `PhotoPicker` port.
- [x] `lib/features/capture/data/services/image_picker_photo_picker.dart` (new) -- `image_picker`-backed implementation.
- [x] `lib/features/capture/domain/repositories/media_repository.dart` (new) -- abstract `MediaRepository` port.
- [x] `lib/features/capture/data/datasources/media_remote_data_source.dart` (new) -- `media-ocr` call.
- [x] `lib/features/capture/data/repositories/media_repository_impl.dart` (new) -- forwards datasource result.
- [x] `lib/features/capture/presentation/cubit/photo_entry_cubit.dart` (new) -- `PhotoEntryCubit` + `PhotoCaptureState` hierarchy.
- [x] `lib/features/capture/capture_injection.dart` -- register new picker/media/cubit bindings.
- [x] `lib/features/capture/presentation/widgets/insertion_modal.dart` -- third cubit wiring, tab-switch discard, `isSaving` OR, new `_FotoTab` widget.
- [x] `lib/core/navigation/placeholder_screens.dart` -- resolve and pass `PhotoEntryCubit`.
- [x] `ios/Runner/Info.plist` -- add camera/photo-library usage descriptions.
- [x] Unit/widget tests under `test/features/capture/` covering the I/O matrix above.

**Acceptance Criteria:**
- Given the Foto tab, when I tap Câmera or Galeria and pick a photo, then a thumbnail and "Reconhecendo texto..." show while `POST /media/ocr` runs, with no image bytes ever reaching `POST /entries`.
- Given `OCR_NO_TEXT`, when the error shows, then both "Tentar novamente" and "Salvar só a foto" are present and each behaves per the I/O matrix.
- Given `PAYLOAD_TOO_LARGE`, when the error shows, then no retry or save-without-text action is offered.
- Given recognized text, when I edit it and tap Salvar, then the resulting Entry carries `source: photo` and the edited text.
- Given `fvm flutter analyze` and `fvm flutter test`, then both report zero issues / all green.

### Review Findings

- [x] [Review][Decision] Audio-tab robustness fixes bundled into story 3.3 beyond authorized scope — `AudioEntryCubit` (try/catch around `hasPermission()`/`start()`/`stop()`, the new `_stopping` guard, `_safeCancelRecorder()`), `RecordMicRecorder` (negative-duration clamp), and `_WaveformState.initState()`'s new `onError` handler are all Audio-tab robustness changes with no mention anywhere in this file's frozen Boundaries, Code Map, or a Spec Change Log — only `AudioEntryCubit.cancel()`'s `discardPreserved` mirroring is explicitly called for by the frozen text. The Never clause states "Touch Story 3.1/3.2's Texto/Áudio tabs beyond the shared `InsertionModal` wiring already described above." — resolved: accepted as documented (see Spec Change Log below), same treatment as the identical pattern in spec-2-3/2-4. The fixes are real, correct robustness improvements; splitting or reverting them now would be pure git-history surgery with no functional benefit. No code changed by this resolution.
- [x] [Review][Patch] New picked-photo file leaked on tab-switch/close race in `PhotoEntryCubit._pick()` [lib/features/capture/presentation/cubit/photo_entry_cubit.dart:184-187] — fixed: discards now call `unawaited(_deletePickedFile(photo.path))` on the generation-mismatch exit; `previousPath` is also now deleted unconditionally as soon as a fresh pick starts, closing the catch/cancel leak paths too. No new test (no `Directory`/temp-file assertion harness exists for `PhotoEntryCubit` yet; the fix mirrors the already-tested success-path pattern).
- [x] [Review][Patch] Stale `previousPath` (`payloadTooLarge`) file leaked when a re-pick is canceled or throws [lib/features/capture/presentation/cubit/photo_entry_cubit.dart:172-182,188-196] — fixed together with the item above (same edit: `previousPath` deleted unconditionally right after capture).
- [x] [Review][Patch] AudioEntryCubit `start()`/`stop()` failure catches never release the native recorder [lib/features/capture/presentation/cubit/audio_entry_cubit.dart:203-220,260-277] — fixed: both catches now call `unawaited(_safeCancelRecorder())` before emitting the error. No new dedicated test (no mock assertion distinguishes this from the existing throw-tests' own `verifyNever`-style checks without over-specifying call order).
- [x] [Review][Patch] `_stopping` flag never reset in `AudioEntryCubit.cancel()`, permanently disabling `stopRecording()` if `stop()` hangs [lib/features/capture/presentation/cubit/audio_entry_cubit.dart:408-446] — fixed: `_stopping = false` added at the top of `cancel()`.
- [x] [Review][Patch] `record_mic_recorder.dart`'s negative-duration clamp has no test exercising it [lib/features/capture/data/services/record_mic_recorder.dart:75-78] — fixed: added an injectable `DateTime Function() now` constructor param (default `DateTime.now`) and a new `stop()` test driving a 10s backward jump, asserting the result floors to 0.
- [x] [Review][Patch] `AudioEntryCubit._safeCancelRecorder`'s catch around `cancel()` has no throw-test [lib/features/capture/presentation/cubit/audio_entry_cubit.dart:452-458] — fixed: added two new tests — `cancel()` while recording with a throwing `MicRecorder.cancel()`, and the `startRecording()` abandon-on-generation-mismatch branch with the same throw — both asserting no uncaught exception and a clean `AudioIdle` reset.
- [x] [Review][Patch] `_Waveform`'s `amplitudeStream` `onError` handler has no test [lib/features/capture/presentation/widgets/insertion_modal.dart, `_WaveformState.initState()`] — fixed: added a widget test with a `StreamController<double>` that emits a sample then an error while `AudioRecording` is active; verified it actually catches the regression by confirming the test fails when `onError` is removed, then restored the guard.
- [x] [Review][Defer] Duplicated ~30-line TextField/InputDecoration block between `_PhotoRecognizedView` and `_PhotoErrorView` [lib/features/capture/presentation/widgets/insertion_modal.dart] — deferred, pre-existing. This diff's own comment about a missing `focusedBorder` on one copy is direct evidence of the drift risk; worth extracting into a shared widget, not urgent.
- [x] [Review][Defer] Bloc nesting depth in `_InsertionModalBodyState.build()` grows to 5 levels [lib/features/capture/presentation/widgets/insertion_modal.dart] — deferred, pre-existing pattern, extended rather than introduced by this story. `MultiBlocListener` would flatten the two listeners computing `isSaving`.
- [x] [Review][Defer] No semantic label on the picked-photo thumbnail [lib/features/capture/presentation/widgets/insertion_modal.dart, `_PhotoThumbnail`] — deferred, pre-existing pattern. `Image.file` carries no `semanticLabel`, inconsistent with the `_announce(...)` accessibility treatment elsewhere in this file.

### Review Findings (round 3)

- [x] [Review][Decision] Audio-tab robustness fixes (again) touch files the frozen Boundaries' Never-clause names off-limits, with no amendment to that clause itself — resolved: accepted as-is, same resolution as the identical spec-2-3/2-4 precedent (see `deferred-work.md`). The frozen Boundaries text is not amended (no human renegotiation was sought for that specific edit) and the fixes are not unbundled (pure git-history churn with no functional benefit, per the spec's own Spec Change Log). The recurring pattern itself — a frozen boundary bundled past and only disclosed after the fact in a Spec Change Log — is carried forward to the epic-3 retrospective as a process item, mirroring how the epic-2 equivalent was handled.
- [x] [Review][Patch] `AudioEntryCubit.startRecording()`/`stopRecording()`'s failure catches call `unawaited(_safeCancelRecorder())` before the `isClosed`/generation check, so a stale generation's late-failing `start()`/`stop()` can silently cancel the shared singleton `_micRecorder`'s currently-active newer-generation recording — the generation check right after then suppresses any error, so the UI keeps showing `AudioRecording` while the native session was actually killed [lib/features/capture/presentation/cubit/audio_entry_cubit.dart:211,272] — fixed: the generation/`isClosed` check now runs first in both catches, so a stale continuation returns before ever touching the shared recorder.
- [x] [Review][Patch] None of this round's `_safeCancelRecorder()`/`mockMicRecorder.cancel()` call sites are verified by a mock assertion — `cancel()` isn't stubbed in the relevant tests, so an unstubbed call throws `MissingStubError` that `_safeCancelRecorder`'s own catch silently swallows, and every test covering these call sites would still pass if the call sites were deleted outright [test/features/capture/presentation/cubit/audio_entry_cubit_test.dart] — fixed: stubbed `cancel()` + added `verify(...).called(1)` to the `start()`/`stop()` throw-tests and both `cancel()`-throw tests. Doing so exposed that the "abandon-on-generation-mismatch" test was actually never reaching `_micRecorder.start()` at all (`cancel()`'s synchronous no-op body was bumping `_generation` before `startRecording()`'s pending `hasPermission()` continuation ever ran) — fixed the test's own sequencing with an explicit `await Future<void>.delayed(Duration.zero)` so it now genuinely exercises the branch it claims to.
- [x] [Review][Patch] `AudioEntryCubit.cancel()`'s new `_stopping = false` reset (hung-`stop()` recovery) has no test driving a genuinely hung `stop()` + `cancel()` + fresh record/stop cycle [lib/features/capture/presentation/cubit/audio_entry_cubit.dart:430] — fixed: added a test with a never-completing `stop()` `Completer`, confirming `cancel()` frees `_stopping` and a subsequent record/stop cycle still reaches `AudioTranscribed`.
- [x] [Review][Patch] `PhotoEntryCubit._pick()`'s two new unconditional file-cleanup paths (eager `previousPath` delete, generation-mismatch `photo.path` delete) have no dedicated regression test — existing tests touching these paths never cancel/throw a re-pick or resolve the picker `Completer` with a real photo [lib/features/capture/presentation/cubit/photo_entry_cubit.dart:170-178,192-199] — fixed: added two tests — a `payloadTooLarge` re-pick canceled by the user (old file still deleted), and a generation-mismatch pick resolving with a real file after `cancel()` (new file deleted instead of leaked).
- [x] [Review][Patch] Grammar: "each contain" should be "each contains" (subject-verb agreement) [_bmad-output/implementation-artifacts/deferred-work.md] — fixed.
- [x] [Review][Defer] `PhotoEntryCubit._pick()`'s fire-and-forget `previousPath`/generation-mismatch `photo.path` deletes assume `image_picker` never reuses an exact file path across picks; if it ever did, a newer live generation's file could be deleted out from under it [lib/features/capture/presentation/cubit/photo_entry_cubit.dart:170-178,192-199] — deferred, pre-existing, low-probability and unverifiable without a device
- [x] [Review][Defer] The three round-2 "[Review][Defer]" entries now exist verbatim in both this file's Review Findings and `deferred-work.md` — two copies of the same findings that can drift out of sync, the same risk one of those very findings calls out for duplicated code [_bmad-output/implementation-artifacts/deferred-work.md] — deferred, pre-existing
- [x] [Review][Defer] `AudioEntryCubit.cancel()`'s unconditional `_stopping = false` reset can, in a narrow multi-step interleave (a stale hung `stop()` resolving while a fresh generation's own `stopRecording()` is concurrently in-flight), flip `_stopping` back open mid-flight [lib/features/capture/presentation/cubit/audio_entry_cubit.dart:430] — deferred, pre-existing architectural gap, not introduced fresh by this round

## Spec Change Log

- **Code review (2026-11-04):** Confirmed, and left in place as-is, that this story's commit (`5bf09ca`) bundles Audio-tab robustness fixes — `AudioEntryCubit`'s try/catch around `hasPermission()`/`start()`/`stop()`, its new `_stopping` double-tap guard and `_safeCancelRecorder()` helper, `RecordMicRecorder`'s negative-duration clamp, and `_WaveformState.initState()`'s new `amplitudeStream` `onError` handler — alongside this story's own Photo/OCR work, touching files this spec's frozen Boundaries name as off-limits beyond shared `InsertionModal` wiring ("Never: Touch Story 3.1/3.2's Texto/Áudio tabs..."). Accepted rather than un-bundled: the fixes are real, correct robustness improvements (exception safety, a clock-skew guard), not bugs; splitting or reverting them now would be pure git-history surgery with no functional benefit. The Photo/OCR implementation proper never required touching any of these files for its own logic — only `AudioEntryCubit.cancel()`'s `discardPreserved` parameter was actually called for by this spec's own Boundaries text.

## Design Notes

- **Three-way `PhotoError.kind` instead of `AudioError`'s binary `canRetry`:** Audio only ever has one non-retryable shape (a save failure); Photo has two distinct non-retryable backend codes (`ocrNoText`, `payloadTooLarge`) needing different UI, plus the generic retryable case — a discriminator is clearer than overloading nullability tricks.
- **No separate "recording" phase:** unlike Audio's timed `recording` state, picking a photo is one blocking OS call — `PhotoIdle` goes straight to `PhotoProcessing` once the picker returns a file, no intermediate state needed.
- **`confidence` is a string enum (`high`/`low`), not numeric** — carried on `OcrResult` but not surfaced in any UI per this story's scope (not called for in the brief); available for a future story if needed.

## Verification

**Commands:**
- `fvm flutter pub get` -- resolves `image_picker` with no conflicts.
- `fvm flutter analyze` -- zero issues.
- `fvm flutter test` -- all green.

**Manual checks (if no CLI):**
- On a real device/simulator (none exists yet, AGENTS.md): pick a photo with visible text, confirm OCR recognizes it and a `photo`-sourced Entry saves; confirm an oversized image triggers the `PAYLOAD_TOO_LARGE` UI and a text-free image triggers `OCR_NO_TEXT`'s two recovery paths.

## Suggested Review Order

**Photo capture state machine**

- The pipeline's own sealed states and the 3-way `PhotoErrorKind` discriminator (`ocrNoText`/`payloadTooLarge`/`generic`) — the main architectural bet of this story.
  [`photo_entry_cubit.dart:18`](../../lib/features/capture/presentation/cubit/photo_entry_cubit.dart#L18)

- `_generation`/`_picking` — review-added guards so `cancel()` running mid-await (tab switch during a pick or OCR call) can't leave `_picking` stuck or resurrect a dropped flow.
  [`photo_entry_cubit.dart:142`](../../lib/features/capture/presentation/cubit/photo_entry_cubit.dart#L142)

- `_pick()`/`_recognize()` — the pick → processingOcr transition and the `Failure` → `PhotoErrorKind` mapping (`OcrNoText`/`PayloadTooLarge`/anything else).
  [`photo_entry_cubit.dart:151`](../../lib/features/capture/presentation/cubit/photo_entry_cubit.dart#L151)

- `retry()`/`saveWithoutText()` — the two distinct `ocrNoText` recovery paths; `payloadTooLarge` is a deliberate no-op for both.
  [`photo_entry_cubit.dart:263`](../../lib/features/capture/presentation/cubit/photo_entry_cubit.dart#L263)

- `save()`/`_save()` — fires `POST /entries` with `source: photo`; also re-enterable from a save-failure `PhotoError`.
  [`photo_entry_cubit.dart:318`](../../lib/features/capture/presentation/cubit/photo_entry_cubit.dart#L318)

- `cancel()`/`_deletePickedFile()` — review-added: the picked file's temp-cleanup and `discardPreserved` branches (I/O matrix's "Leave tab mid-pick/OCR" row).
  [`photo_entry_cubit.dart:403`](../../lib/features/capture/presentation/cubit/photo_entry_cubit.dart#L403)

**MediaRepository / PhotoPicker ports**

- `MediaRepository.recognizeText()` — the abstract port `PhotoEntryCubit` depends on; OCR stays in `capture/`, never `entries/` (epic Technical Decisions).
  [`media_repository.dart:21`](../../lib/features/capture/domain/repositories/media_repository.dart#L21)

- `MediaRemoteDataSource.recognizeText()` — base64-encodes bytes, calls `media-ocr`; mirrors `entries_remote_data_source.dart`'s own shape.
  [`media_remote_data_source.dart:19`](../../lib/features/capture/data/datasources/media_remote_data_source.dart#L19)

- `MediaRepositoryImpl` — forwards the datasource's `Either` with no Hive step, since the image itself is never persisted.
  [`media_repository_impl.dart:17`](../../lib/features/capture/data/repositories/media_repository_impl.dart#L17)

- `PhotoPicker`/`PickedPhoto` — the abstract port decoupling the cubit from `image_picker`.
  [`photo_picker.dart:20`](../../lib/features/capture/domain/services/photo_picker.dart#L20)

- `ImagePickerPhotoPicker._mimeTypeOf()` — extension-based mimeType inference (jpeg/png/webp only, per the contract's enum).
  [`image_picker_photo_picker.dart:42`](../../lib/features/capture/data/services/image_picker_photo_picker.dart#L42)

**Insertion Modal wiring**

- `show()` — review-added: each of the three cubits' cancel+close pair now isolated in its own try/finally, so one throwing never skips another's cleanup.
  [`insertion_modal.dart:42`](../../lib/features/capture/presentation/widgets/insertion_modal.dart#L42)

- `build()` — `isSaving` now also reads `PhotoEntryCubit`'s own saving flag, closing the same cross-tab race already fixed for Audio in spec-3-2.
  [`insertion_modal.dart:446`](../../lib/features/capture/presentation/widgets/insertion_modal.dart#L446)

- `_onPhotoStateChange` — drives every screen-reader announcement, including the review-added "Captura de foto cancelada".
  [`insertion_modal.dart:382`](../../lib/features/capture/presentation/widgets/insertion_modal.dart#L382)

- `_FotoTab` — the state-driven switch replacing the old `_IdleTabPlaceholder`.
  [`insertion_modal.dart:1136`](../../lib/features/capture/presentation/widgets/insertion_modal.dart#L1136)

- `_PhotoErrorView` — the 3 `PhotoErrorKind` branches' distinct UI treatment, including the review-added `focusedBorder` fix on the save-failure field.
  [`insertion_modal.dart:1358`](../../lib/features/capture/presentation/widgets/insertion_modal.dart#L1358)

**Wiring**

- `registerCaptureFeature()` — `ImagePicker`/`PhotoPicker`/`MediaRepository` as lazy singletons, `PhotoEntryCubit` as a factory like `AudioEntryCubit`.
  [`capture_injection.dart:58`](../../lib/features/capture/capture_injection.dart#L58)

- The "+" FAB now resolves and passes all three cubits to `InsertionModal.show`.
  [`placeholder_screens.dart:101`](../../lib/core/navigation/placeholder_screens.dart#L101)

- `NSCameraUsageDescription`/`NSPhotoLibraryUsageDescription` — required for `image_picker` to request camera/gallery access on a real device.
  [`Info.plist:33`](../../ios/Runner/Info.plist#L33)

**Tests**

- The full I/O-matrix coverage plus the review-added regression tests (temp-file deletion, `discardPreserved`, `_picking` reset, full-modal-dismiss-mid-pick, the "Captura de foto cancelada" announcement).
  [`photo_entry_cubit_test.dart:1`](../../test/features/capture/presentation/cubit/photo_entry_cubit_test.dart#L1)

- Widget-level coverage of the Foto tab through the real `InsertionModal`.
  [`insertion_modal_photo_test.dart:1`](../../test/features/capture/presentation/widgets/insertion_modal_photo_test.dart#L1)

- `MediaRemoteDataSource`/`MediaRepositoryImpl`/`ImagePickerPhotoPicker` unit tests.
  [`media_remote_data_source_test.dart:1`](../../test/features/capture/data/datasources/media_remote_data_source_test.dart#L1)
