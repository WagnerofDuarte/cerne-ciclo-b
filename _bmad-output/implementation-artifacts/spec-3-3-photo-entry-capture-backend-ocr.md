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
