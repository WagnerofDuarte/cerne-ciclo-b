import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/failure/failure.dart';
import '../../../entries/domain/entities/entry.dart';
import '../../../entries/domain/services/pending_entry_write_tracker.dart';
import '../../domain/repositories/media_repository.dart';
import '../../domain/services/photo_picker.dart';

/// `PhotoEntryCubit`'s own sealed state hierarchy — separate from
/// `TextEntryState`/`AudioCaptureState` (Boundaries: "own sealed
/// `PhotoCaptureState`"). No common base-class field, same rationale as
/// `AudioCaptureState`: [PhotoIdle] has nothing in common with
/// [PhotoRecognized], for instance.
sealed class PhotoCaptureState {
  const PhotoCaptureState();
}

/// The state immediately after the modal opens on the Foto tab, after
/// leaving mid-pick/mid-OCR (Never: this story's trivial cross-tab
/// case), and the state a fresh `PhotoEntryCubit` always starts in.
/// `InsertionModal`'s own `_FotoTab` renders the Câmera/Galeria capture
/// buttons for this state.
class PhotoIdle extends PhotoCaptureState {
  const PhotoIdle();
}

/// A photo was picked, `MediaRepository.recognizeText()` in flight —
/// `_FotoTab` shows a thumbnail + "Reconhecendo texto..." for the whole
/// duration of this state (Acceptance Criteria). No separate "recording"-
/// style intermediate phase (Design Notes): picking is one blocking OS
/// call, so [PhotoIdle] goes straight here once the picker returns a file.
class PhotoProcessing extends PhotoCaptureState {
  const PhotoProcessing({required this.path, required this.mimeType});

  final String path;
  final String mimeType;
}

/// OCR succeeded with usable text — [text] is editable before Salvar
/// (Acceptance Criteria), mirrored by [PhotoEntryCubit.updateText].
/// [saving] folds `TextEntrySaving`'s role into this same state, same
/// convention as `AudioTranscribed.saving`.
class PhotoRecognized extends PhotoCaptureState {
  const PhotoRecognized({
    required this.path,
    required this.mimeType,
    required this.text,
    required this.saving,
  });

  final String path;
  final String mimeType;
  final String text;
  final bool saving;

  PhotoRecognized copyWith({String? text, bool? saving}) => PhotoRecognized(
    path: path,
    mimeType: mimeType,
    text: text ?? this.text,
    saving: saving ?? this.saving,
  );
}

/// A save attempt succeeded — `InsertionModal`'s listener reacts to this
/// exactly like `TextEntrySaved`/`AudioSaved` (announce, then pop).
/// Terminal, same rationale as those two states' own docs.
class PhotoSaved extends PhotoCaptureState {
  const PhotoSaved();
}

/// The 3-way discriminator driving `_FotoTab`'s three distinct error
/// branches (Design Notes: "a discriminator is clearer than overloading
/// nullability tricks" — unlike `AudioError`'s binary `canRetry`, Photo
/// has two distinct non-retryable backend codes needing different UI).
enum PhotoErrorKind {
  /// `Failure.ocrNoText` — "Tentar novamente" (re-OCRs the same image)
  /// and "Salvar só a foto" (saves a fixed placeholder) are both offered.
  ocrNoText,

  /// `Failure.payloadTooLarge` — no retry, no save-without-text; the only
  /// way forward is picking a different photo.
  payloadTooLarge,

  /// Any other `Failure` — a generic OCR-call failure ([text] `null`,
  /// "Tentar novamente" re-OCRs) or a save failure ([text] non-null,
  /// re-running the failed call means tapping Salvar again, same shape
  /// as `AudioError`).
  generic,
}

/// The last attempt failed — covers every failure row of the I/O matrix:
/// `OCR_NO_TEXT`, `PAYLOAD_TOO_LARGE`, a generic OCR-call failure, or a
/// save failure (non-null [text]).
class PhotoError extends PhotoCaptureState {
  const PhotoError({
    required this.path,
    required this.mimeType,
    required this.message,
    required this.kind,
    this.text,
  });

  final String path;
  final String mimeType;
  final String message;
  final PhotoErrorKind kind;

  /// Non-null only for a save failure ([PhotoErrorKind.generic]) — lets
  /// `_FotoTab` keep rendering the editable text field under the inline
  /// error, same as `AudioError.text`/`TextEntryError`'s own rendering.
  final String? text;
}

/// Drives the Foto tab's pick -> processingOcr -> recognized/error
/// pipeline (Intent). A fresh, `get_it`-factory-scoped instance per "+"
/// tap, same convention as `TextEntryCubit`/`AudioEntryCubit` —
/// [PhotoPicker]/[MediaRepository] themselves stay long-lived `get_it`
/// singletons (`capture_injection.dart`).
class PhotoEntryCubit extends Cubit<PhotoCaptureState> {
  PhotoEntryCubit(this._photoPicker, this._mediaRepository, this._tracker)
    : super(const PhotoIdle());

  final PhotoPicker _photoPicker;
  final MediaRepository _mediaRepository;

  /// spec-4-2 — the shared [PendingEntryWriteTracker], swapped in for a
  /// direct `EntriesRepository` dependency (identical `create()` contract,
  /// Code Map: "no call-site logic change").
  final PendingEntryWriteTracker _tracker;

  static const _noTextPlaceholder =
      'Registro fotográfico (sem texto reconhecido)';

  /// Bumped by [cancel] (and by every pick/retry attempt) so an in-flight
  /// picker/OCR continuation can tell "the user already left the Foto tab"
  /// apart from "nothing has changed since I started" — same role
  /// `AudioEntryCubit._generation` plays for the picker call and the OCR
  /// network call here (Boundaries).
  int _generation = 0;

  /// Guards against a second overlapping picker call (e.g. a fast
  /// double-tap on Câmera before the UI rebuilds past [PhotoIdle]).
  bool _picking = false;

  Future<void> pickFromCamera() => _pick(_photoPicker.pickFromCamera);

  Future<void> pickFromGallery() => _pick(_photoPicker.pickFromGallery);

  Future<void> _pick(Future<PickedPhoto?> Function() pick) async {
    final current = state;
    final canPick =
        !_picking &&
        (current is PhotoIdle ||
            (current is PhotoError &&
                current.kind == PhotoErrorKind.payloadTooLarge));
    if (!canPick) {
      return;
    }
    // A fresh pick replacing a previous `payloadTooLarge` error's own
    // (never-OCR'd, now-abandoned) file — Review finding: without this,
    // that file leaked on disk forever once this new pick's own file
    // takes over `state`. Deleted unconditionally right away (Review
    // finding): this old file is abandoned the moment a new pick starts,
    // regardless of whether that new pick succeeds, is canceled, or
    // throws — the earlier code only deleted it on success, leaking it
    // on every other exit path.
    final previousPath = current is PhotoError ? current.path : null;
    if (previousPath != null) {
      unawaited(_deletePickedFile(previousPath));
    }
    _picking = true;
    final generation = ++_generation;
    PickedPhoto? photo;
    try {
      photo = await pick();
    } catch (_) {
      // A thrown PlatformException (native-side error) must never escape
      // uncaught — treated the same as a plain user cancel, since this
      // story offers no dedicated "picker failed" UI (not in the I/O
      // matrix).
      _picking = false;
      if (isClosed || generation != _generation) {
        return;
      }
      emit(const PhotoIdle());
      return;
    }
    _picking = false;
    if (isClosed || generation != _generation) {
      // Review finding: without this, a photo picked just as the user
      // left the tab (or closed the whole modal) was discarded with no
      // cleanup — its OS temp file leaked forever.
      if (photo != null) {
        unawaited(_deletePickedFile(photo.path));
      }
      return;
    }
    if (photo == null) {
      // I/O matrix: "User cancels picker" -> stays on PhotoIdle's capture
      // buttons. If the re-pick was attempted from a `payloadTooLarge`
      // error, drop that stale error too rather than leaving it on
      // screen with nothing that produced it anymore.
      if (current is PhotoError) {
        emit(const PhotoIdle());
      }
      return;
    }
    emit(PhotoProcessing(path: photo.path, mimeType: photo.mimeType));
    await _recognize(photo.path, photo.mimeType, generation);
  }

  Future<void> _recognize(String path, String mimeType, int generation) async {
    Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } catch (_) {
      if (isClosed || generation != _generation) {
        return;
      }
      emit(
        PhotoError(
          path: path,
          mimeType: mimeType,
          message: 'Não foi possível ler a foto selecionada.',
          kind: PhotoErrorKind.generic,
        ),
      );
      return;
    }
    final result = await _mediaRepository.recognizeText(
      imageBytes: bytes,
      mimeType: mimeType,
    );
    // Guards a tab switch away mid-OCR (`cancel()`, below) that already
    // reset the state by the time this resolves — without this, a stale
    // OCR result would still land and resurrect a flow the user left.
    if (isClosed || generation != _generation) {
      return;
    }
    result.match(
      (failure) => emit(
        PhotoError(
          path: path,
          mimeType: mimeType,
          message: failure.message,
          kind: switch (failure) {
            OcrNoText() => PhotoErrorKind.ocrNoText,
            PayloadTooLarge() => PhotoErrorKind.payloadTooLarge,
            _ => PhotoErrorKind.generic,
          },
        ),
      ),
      (ocr) => emit(
        PhotoRecognized(
          path: path,
          mimeType: mimeType,
          text: ocr.text,
          saving: false,
        ),
      ),
    );
  }

  /// "Tentar novamente" — re-OCRs the same image for an [OcrNoText]
  /// error or a generic OCR-call failure ([PhotoError.text] `null`). A
  /// no-op for [PhotoErrorKind.payloadTooLarge] (I/O matrix: no retry
  /// offered) and for a generic *save* failure (non-null [PhotoError.
  /// text]) — that case's own retry is tapping Salvar again, handled by
  /// [save] directly, mirroring `AudioEntryCubit.retry()`.
  Future<void> retry() async {
    final current = state;
    if (current is! PhotoError ||
        current.text != null ||
        current.kind == PhotoErrorKind.payloadTooLarge) {
      return;
    }
    final generation = ++_generation;
    emit(PhotoProcessing(path: current.path, mimeType: current.mimeType));
    await _recognize(current.path, current.mimeType, generation);
  }

  /// "Salvar só a foto" — only valid from an [OcrNoText] error; saves the
  /// fixed, non-empty placeholder content (the contract's
  /// `content.minLength: 1` forbids an empty save).
  Future<void> saveWithoutText() async {
    final current = state;
    if (current is! PhotoError || current.kind != PhotoErrorKind.ocrNoText) {
      return;
    }
    await _save(
      path: current.path,
      mimeType: current.mimeType,
      text: _noTextPlaceholder,
    );
  }

  /// Mirrors the Texto/Áudio fields' own `updateText` — keeps the
  /// recognized text editable before Salvar, and keeps a save-failure
  /// retry's text editable too (same as `AudioEntryCubit.updateText`'s
  /// own `AudioError` branch).
  void updateText(String text) {
    final current = state;
    if (current is PhotoRecognized && !current.saving) {
      emit(current.copyWith(text: text));
    } else if (current is PhotoError &&
        current.kind == PhotoErrorKind.generic &&
        current.text != null) {
      emit(
        PhotoError(
          path: current.path,
          mimeType: current.mimeType,
          message: current.message,
          kind: current.kind,
          text: text,
        ),
      );
    }
  }

  /// I/O matrix's "Happy path"/"Save fails" rows: fires `POST /entries`
  /// with `source: photo` for the current (possibly edited) recognized
  /// text. Also callable from a save-failure [PhotoError] (non-null
  /// [PhotoError.text]), mirroring `AudioEntryCubit.save()`'s own
  /// re-save-on-retry behavior.
  Future<void> save() async {
    final current = state;
    final String path;
    final String mimeType;
    final String text;
    if (current is PhotoRecognized && !current.saving) {
      path = current.path;
      mimeType = current.mimeType;
      text = current.text.trim();
    } else if (current is PhotoError &&
        current.kind == PhotoErrorKind.generic &&
        current.text != null) {
      path = current.path;
      mimeType = current.mimeType;
      text = current.text!.trim();
    } else {
      return;
    }
    if (text.isEmpty) {
      return;
    }
    await _save(path: path, mimeType: mimeType, text: text);
  }

  Future<void> _save({
    required String path,
    required String mimeType,
    required String text,
  }) async {
    emit(
      PhotoRecognized(path: path, mimeType: mimeType, text: text, saving: true),
    );
    final result = await _tracker.create(
      content: text,
      source: EntrySource.photo,
    );
    // Mirrors `AudioEntryCubit.save()`'s own `isClosed` guard — this
    // cubit's `close()` can race the awaited call above (e.g. the
    // modal's barrier is dismissed mid-save).
    if (isClosed) {
      return;
    }
    result.match(
      (failure) => emit(
        PhotoError(
          path: path,
          mimeType: mimeType,
          message: failure.message,
          kind: PhotoErrorKind.generic,
          text: text,
        ),
      ),
      (_) {
        // Review finding: the picked photo's temp file (written by
        // `image_picker` itself, not by this class, but still this
        // cubit's responsibility to clean up once it's done with it)
        // was never deleted after a successful save — fire-and-forget,
        // a deletion failure must never block the modal from closing.
        unawaited(_deletePickedFile(path));
        emit(const PhotoSaved());
      },
    );
  }

  /// Called when the Foto tab loses focus mid-pick/mid-OCR
  /// (`InsertionModal`'s tab-switch listener) — I/O matrix's "Leave tab
  /// mid-pick/OCR" row: the in-flight picker/OCR call is discarded, no
  /// `create()` ever fires. A no-op for every other state when
  /// [discardPreserved] is `false` (the default) — in particular
  /// [PhotoRecognized]/[PhotoError], where the Never clause's trivial
  /// scope (resource safety only, not full Story 3.4 cancel-safety)
  /// means a tab switch must preserve the result rather than discard it
  /// — mirrors `AudioEntryCubit.cancel()`'s own `discardPreserved`
  /// convention exactly.
  ///
  /// [discardPreserved] — `InsertionModal.show()`'s `finally` also calls
  /// this (before `close()`) when the *whole modal* is dismissed (✕/
  /// swipe-down/barrier tap), not just the tab. In that case there's no
  /// "switch back to the tab later" to preserve for — the cubit is about
  /// to be closed — so a preserved [PhotoRecognized]/[PhotoError]'s
  /// picked-photo temp file would otherwise never be cleaned up and leak
  /// on disk forever (Review finding — the comment this replaced
  /// incorrectly claimed Foto "never creates a temp file of its own";
  /// `image_picker` does, every pick). Pass `true` only from that call
  /// site.
  Future<void> cancel({bool discardPreserved = false}) async {
    // Bumped unconditionally — including when the state below doesn't
    // match — so an in-flight `_pick`/`_recognize`/`retry` continuation
    // still sees the mismatch and aborts itself even while still awaiting
    // (Review-finding rationale mirrored from `AudioEntryCubit.cancel()`).
    _generation++;
    // Review finding: without this, leaving the Foto tab while the
    // native picker call itself (not yet `PhotoProcessing`) was still in
    // flight left `_picking` stuck `true` forever — the `_generation`
    // bump above already makes that stale continuation a no-op, so
    // resetting this eagerly is always safe.
    _picking = false;
    final current = state;
    if (current is PhotoProcessing) {
      unawaited(_deletePickedFile(current.path));
      emit(const PhotoIdle());
    } else if (discardPreserved) {
      final path = switch (current) {
        PhotoRecognized(path: final p) => p,
        PhotoError(path: final p) => p,
        _ => null,
      };
      if (path != null) {
        unawaited(_deletePickedFile(path));
      }
    }
  }

  /// Best-effort cleanup for a picked-photo temp file this cubit is done
  /// with (saved successfully, abandoned for good by [cancel], or
  /// replaced by a fresh pick in [_pick]) — deletion failures are
  /// swallowed since nothing in the UI depends on this succeeding,
  /// mirroring `AudioEntryCubit._deleteRecordingFile()`.
  Future<void> _deletePickedFile(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Best-effort — a missing/already-deleted file, or a transient
      // disk error, is never worth surfacing to the user.
    }
  }
}
