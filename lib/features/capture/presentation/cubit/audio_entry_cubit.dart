import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../entries/domain/entities/entry.dart';
import '../../../entries/domain/repositories/entries_repository.dart';
import '../../domain/services/audio_transcriber.dart';
import '../../domain/services/mic_recorder.dart';

/// `AudioEntryCubit`'s own sealed state hierarchy — separate from
/// `TextEntryState` (Boundaries: "own sealed `AudioCaptureState`,
/// separate from `TextEntryState`"). Unlike `TextEntryState`, no common
/// base-class field: the 5 variants don't share a uniform shape the way
/// every `TextEntryState` always carries `activeTab`/`text` — [AudioIdle]
/// genuinely has nothing in common with [AudioTranscribed], for instance.
sealed class AudioCaptureState {
  const AudioCaptureState();
}

/// The state immediately after the modal opens on the Áudio tab exits
/// (Never: this story's trivial cross-tab case), and the state a fresh
/// `AudioEntryCubit` always starts in.
class AudioIdle extends AudioCaptureState {
  const AudioIdle();
}

/// Recording in progress — [elapsedSeconds] backs the running monospace
/// timer (Acceptance Criteria) and ticks once per second via
/// `AudioEntryCubit`'s own internal `Timer.periodic`.
class AudioRecording extends AudioCaptureState {
  const AudioRecording({required this.elapsedSeconds});

  final int elapsedSeconds;
}

/// Recording stopped, `AudioTranscriber.transcribe()` in flight —
/// `InsertionModal`'s own `_AudioTab` freezes the waveform at 35% opacity
/// for the whole duration of this state (Acceptance Criteria).
class AudioProcessing extends AudioCaptureState {
  const AudioProcessing({required this.path, required this.durationSeconds});

  final String path;
  final int durationSeconds;
}

/// Transcription succeeded (even to an empty string) — [text] is editable
/// before Salvar (Acceptance Criteria), mirrored into this state by
/// `AudioEntryCubit.updateText` the same way `TextEntryCubit.updateText`
/// mirrors the Texto field. [saving] is this story's `TextEntrySaving`
/// equivalent folded into one state instead of a separate sibling class —
/// both [path]/[durationSeconds] (needed for the eventual `create()` call)
/// stay fixed across a save attempt, so there's nothing a sibling state
/// would add that a boolean field doesn't already cover just as clearly.
class AudioTranscribed extends AudioCaptureState {
  const AudioTranscribed({
    required this.path,
    required this.durationSeconds,
    required this.text,
    required this.saving,
  });

  final String path;
  final int durationSeconds;
  final String text;
  final bool saving;

  AudioTranscribed copyWith({String? text, bool? saving}) => AudioTranscribed(
    path: path,
    durationSeconds: durationSeconds,
    text: text ?? this.text,
    saving: saving ?? this.saving,
  );
}

/// A save attempt from [AudioTranscribed] succeeded — `InsertionModal`'s
/// listener reacts to this exactly like `TextEntrySaved` (announce, then
/// pop). Terminal, same rationale as `TextEntrySaved`'s own doc.
class AudioSaved extends AudioCaptureState {
  const AudioSaved();
}

/// The last attempt failed — covers all 3 failure rows of the I/O matrix:
/// - Mic permission denied -> [path]/[durationSeconds] both `null` ("No
///   file to preserve"); [AudioEntryCubit.retry] re-requests permission.
/// - Transcription failed -> [path]/[durationSeconds] carry the preserved
///   file; [AudioEntryCubit.retry] re-transcribes it, never re-records.
/// - Save failed (incl. offline) -> same preserved [path]/
///   [durationSeconds]/[text] semantics as `TextEntryError`; the modal's
///   `_AudioTab` keeps showing the editable text with Salvar re-enabled
///   rather than routing back through [AudioEntryCubit.retry].
class AudioError extends AudioCaptureState {
  const AudioError({
    required this.path,
    required this.durationSeconds,
    required this.message,
    this.text,
  });

  final String? path;
  final int? durationSeconds;
  final String message;

  /// Non-null only for a save failure — lets `_AudioTab` keep rendering
  /// the editable text field under the inline error, same as
  /// `TextEntryError`'s own `_TextoTab` rendering.
  final String? text;
}

/// Drives the Áudio tab's recording -> processing -> transcribed/error
/// pipeline (Intent). A fresh, `get_it`-factory-scoped instance per "+"
/// tap, same convention as `TextEntryCubit` — [MicRecorder]/
/// [AudioTranscriber] themselves stay long-lived `get_it` singletons
/// (`capture_injection.dart`), shared across every modal open the way
/// `EntriesRepository` already is for `TextEntryCubit`.
class AudioEntryCubit extends Cubit<AudioCaptureState> {
  AudioEntryCubit(this._micRecorder, this._audioTranscriber, this._repository)
    : super(const AudioIdle());

  final MicRecorder _micRecorder;
  final AudioTranscriber _audioTranscriber;
  final EntriesRepository _repository;

  Timer? _elapsedTimer;

  /// Bumped by [cancel] so an in-flight [startRecording]/[stopRecording]
  /// continuation can tell "the user already left the Áudio tab while I
  /// was awaiting" apart from "nothing has changed since I started" —
  /// the same role `isClosed` already plays for `close()`, but for a tab
  /// switch that doesn't close the cubit itself (Review finding: without
  /// this, `cancel()` running mid-await either left the recorder running
  /// unobserved, or let a stale `stop()`/transcription result resurrect a
  /// flow the user already left).
  int _generation = 0;

  /// Forwarded straight from [MicRecorder.amplitudeStream] — lets
  /// `_AudioTab`'s waveform animate without ever importing `package:record`
  /// itself (Boundaries).
  Stream<double> get amplitudeStream => _micRecorder.amplitudeStream;

  /// Starts recording — called from `InsertionModal`'s tab-switch
  /// listener the instant the Áudio tab becomes active (Acceptance
  /// Criteria: "recording starts immediately"), and again by [retry] when
  /// the last attempt failed before any file ever existed (permission
  /// denied). Ignored while a recording is already in progress, and —
  /// Review finding — ignored once the pipeline has moved past recording
  /// ([AudioProcessing]/[AudioTranscribed]/an [AudioError] that still
  /// carries a file): without this, re-entering the Áudio tab after a
  /// completed transcription silently discarded the transcribed text and
  /// started a brand-new recording over it. Only [AudioIdle] (fresh) or
  /// an [AudioError] with no file (nothing to discard) actually start.
  Future<void> startRecording() async {
    final current = state;
    final canStart =
        current is AudioIdle ||
        (current is AudioError && current.path == null);
    if (!canStart) {
      return;
    }
    final generation = ++_generation;
    final hasPermission = await _micRecorder.hasPermission();
    if (isClosed || generation != _generation) {
      return;
    }
    if (!hasPermission) {
      emit(
        const AudioError(
          path: null,
          durationSeconds: null,
          message:
              'Permissão de microfone negada. Toque em "Tentar novamente" '
              'para permitir o acesso.',
        ),
      );
      return;
    }
    await _micRecorder.start();
    if (isClosed || generation != _generation) {
      // Review finding: `cancel()` bumped `_generation` (the user already
      // left the Áudio tab) while `start()` was in flight — stop/discard
      // the session we just started instead of leaving a live, unobserved
      // recording running.
      unawaited(_micRecorder.cancel());
      return;
    }
    _startElapsedTimer();
    emit(const AudioRecording(elapsedSeconds: 0));
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    var elapsed = 0;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed++;
      if (state is AudioRecording) {
        emit(AudioRecording(elapsedSeconds: elapsed));
      }
    });
  }

  /// Stops recording and immediately kicks off transcription — the I/O
  /// matrix's "Happy path"/"Transcription fails" rows. Ignored outside
  /// [AudioRecording] (e.g. a stray second tap on the stop control).
  Future<void> stopRecording() async {
    if (state is! AudioRecording) {
      return;
    }
    final generation = _generation;
    _elapsedTimer?.cancel();
    final recording = await _micRecorder.stop();
    // Review finding: without the `_generation` check, a `cancel()` that
    // ran while `_micRecorder.stop()` was in flight (tab switch right
    // after tapping stop) already reset the cubit to `AudioIdle` — this
    // continuation must not resurrect the flow with a stale
    // `AudioProcessing`/`AudioError` emission on top of that reset.
    if (isClosed || generation != _generation) {
      return;
    }
    if (recording == null) {
      // Stopped with nothing actually captured — the I/O matrix has no
      // dedicated row for this (it should be unreachable in practice: the
      // recorder was just started above), but `AudioError` with no file
      // still gives the user a path back in via retry's permission-
      // re-request branch rather than leaving the cubit stuck mid-flow.
      emit(
        const AudioError(
          path: null,
          durationSeconds: null,
          message: 'Não foi possível gravar o áudio.',
        ),
      );
      return;
    }
    emit(
      AudioProcessing(
        path: recording.path,
        durationSeconds: recording.durationSeconds,
      ),
    );
    await _transcribe(recording.path, recording.durationSeconds);
  }

  Future<void> _transcribe(String path, int durationSeconds) async {
    final text = await _audioTranscriber.transcribe(path);
    if (isClosed) {
      return;
    }
    // Guards a tab switch away mid-processing (`cancel()`, below) that
    // already reset the state to `AudioIdle` by the time this resolves —
    // without this, the eventual transcription result would still land
    // and resurrect a flow the user already left.
    if (state is! AudioProcessing ||
        (state as AudioProcessing).path != path) {
      return;
    }
    if (text == null) {
      emit(
        AudioError(
          path: path,
          durationSeconds: durationSeconds,
          message: 'Não foi possível transcrever o áudio.',
        ),
      );
      return;
    }
    emit(
      AudioTranscribed(
        path: path,
        durationSeconds: durationSeconds,
        text: text,
        saving: false,
      ),
    );
  }

  /// "Tentar novamente" — re-requests permission when no file was ever
  /// recorded, or re-transcribes the same preserved file otherwise (I/O
  /// matrix: never re-records, never auto-retries on its own). A no-op
  /// outside [AudioError], or for a save failure (non-null [AudioError.
  /// text]) — that case's own retry is just tapping Salvar again, handled
  /// by [save] directly, not this method.
  Future<void> retry() async {
    final current = state;
    if (current is! AudioError || current.text != null) {
      return;
    }
    final path = current.path;
    final durationSeconds = current.durationSeconds;
    if (path == null || durationSeconds == null) {
      await startRecording();
      return;
    }
    emit(AudioProcessing(path: path, durationSeconds: durationSeconds));
    await _transcribe(path, durationSeconds);
  }

  /// Mirrors the Texto field's own `updateText` — keeps the transcribed
  /// text editable before Salvar (Acceptance Criteria). Ignored while a
  /// save is already in flight, same rationale as `TextEntryCubit.
  /// updateText`.
  void updateText(String text) {
    final current = state;
    if (current is AudioTranscribed && !current.saving) {
      emit(current.copyWith(text: text));
    } else if (current is AudioError && current.text != null) {
      // Review finding: a save failure (`AudioError` with non-null
      // `text`) renders the same editable field as `AudioTranscribed`
      // (`_AudioErrorView`'s non-retry branch) — without this branch,
      // typing there updated the `TextField`'s own controller visually
      // but never the cubit's record of the text, so a retried `save()`
      // would silently resend the stale pre-failure text.
      emit(
        AudioError(
          path: current.path,
          durationSeconds: current.durationSeconds,
          message: current.message,
          text: text,
        ),
      );
    }
  }

  /// Called when the Áudio tab loses focus mid-recording/mid-processing
  /// (`InsertionModal`'s tab-switch listener) — the I/O matrix's "Leave
  /// tab mid-recording" row: stops/releases the recorder, no `create()`
  /// ever fires. A no-op for every other state — in particular
  /// [AudioTranscribed]/[AudioError], where the Never clause's trivial
  /// scope (resource safety only, not full Story 3.4 cancel-safety) means
  /// leaving the tab must preserve the result rather than discard it.
  Future<void> cancel() async {
    // Bumped unconditionally — including when the state below doesn't
    // match either branch — so an in-flight `startRecording()`/
    // `stopRecording()` continuation still sees the mismatch and aborts
    // itself (Review finding: previously only invalidated a flow already
    // visible in `state`, missing the window while those methods were
    // still awaiting).
    _generation++;
    final current = state;
    if (current is AudioRecording) {
      _elapsedTimer?.cancel();
      await _micRecorder.cancel();
      if (isClosed) {
        return;
      }
      emit(const AudioIdle());
    } else if (current is AudioProcessing) {
      // The recorder itself is already stopped by the time this state is
      // reached (`stopRecording` stops it before emitting `AudioProcessing`)
      // — only resetting the cubit's own state is left, so the pending
      // `_transcribe` continuation's own `state is! AudioProcessing` guard
      // (above) drops its result instead of resurrecting this flow. Review
      // finding: the already-recorded file is abandoned for good at this
      // point (nothing will ever retry it), so it must be deleted here —
      // the other orphan-file case `_micRecorder.cancel()` above already
      // handles on its own.
      unawaited(_deleteRecordingFile(current.path));
      emit(const AudioIdle());
    }
  }

  /// I/O matrix's "Happy path"/"Save fails" rows: fires `POST /entries`
  /// with `source: audio` and `mediaDurationSeconds` for the current
  /// transcribed text. Mirrors `TextEntryCubit.save()`'s `isClosed`/
  /// no-double-submit guards exactly (Boundaries).
  ///
  /// Review finding: also callable from an [AudioError] save failure
  /// (non-null [AudioError.text]) — `_AudioErrorView`'s non-retry branch
  /// re-renders the editable field and calls this same method for its
  /// "Salvar" button, but the original guard only matched
  /// [AudioTranscribed], making a retry after any save failure a
  /// permanent no-op.
  Future<void> save() async {
    final current = state;
    final String path;
    final int durationSeconds;
    final String text;
    if (current is AudioTranscribed && !current.saving) {
      path = current.path;
      durationSeconds = current.durationSeconds;
      text = current.text.trim();
    } else if (current is AudioError &&
        current.text != null &&
        current.path != null &&
        current.durationSeconds != null) {
      path = current.path!;
      durationSeconds = current.durationSeconds!;
      text = current.text!.trim();
    } else {
      return;
    }
    if (text.isEmpty) {
      return;
    }
    emit(
      AudioTranscribed(
        path: path,
        durationSeconds: durationSeconds,
        text: text,
        saving: true,
      ),
    );
    final result = await _repository.create(
      content: text,
      source: EntrySource.audio,
      mediaDurationSeconds: durationSeconds,
    );
    // Mirrors `TextEntryCubit.save()`'s own `isClosed` guard — this
    // cubit's `close()` can race the awaited call above (e.g. the modal's
    // barrier is dismissed mid-save).
    if (isClosed) {
      return;
    }
    result.match(
      (failure) => emit(
        AudioError(
          path: path,
          durationSeconds: durationSeconds,
          message: failure.message,
          text: text,
        ),
      ),
      (_) {
        // Review finding: the recorded temp file was never deleted after
        // a successful save — fire-and-forget, a deletion failure must
        // never block the modal from closing.
        unawaited(_deleteRecordingFile(path));
        emit(const AudioSaved());
      },
    );
  }

  /// Best-effort cleanup for a temp recording file this cubit is done
  /// with (saved successfully, or abandoned for good by [cancel] mid-
  /// processing) — deletion failures are swallowed since nothing in the
  /// UI depends on this succeeding (Review finding: previously never
  /// called at all, leaking a `.wav` file per recording indefinitely).
  Future<void> _deleteRecordingFile(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Best-effort — a missing/already-deleted file, or a transient
      // disk error, is never worth surfacing to the user.
    }
  }

  @override
  Future<void> close() {
    _elapsedTimer?.cancel();
    return super.close();
  }
}
