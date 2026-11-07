// The constructor keeps the public named param (`repository`) distinct
// from the private field it initializes, matching `session_repository_
// impl.dart`'s/`auth_repository_impl.dart`'s documented convention.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../entities/entry.dart';
import '../entities/pending_entry_write.dart';
import '../repositories/entries_repository.dart';

/// The single `create()`/`retry()` entry point for all three capture
/// cubits (`TextEntryCubit`/`AudioEntryCubit`/`PhotoEntryCubit`) — Intent:
/// "the tracker, not `MeusRegistrosCubit`, owns reconciliation". Pure
/// Dart, no `package:flutter`/`data` import (RNF06) — a port+impl pair in
/// one file, same structural convention `SessionExpiryNotifier`/
/// `SessionExpiryNotifierImpl` already use.
abstract class PendingEntryWriteTracker {
  /// Identical contract to [EntriesRepository.create] (Boundaries) — every
  /// capture cubit swaps its `EntriesRepository` dependency for this one,
  /// with no other call-site change. Internally: records an optimistic
  /// [PendingEntryWrite] (status [PendingEntryWriteInFlight]) *before*
  /// calling through to the repository, so [pendingWrites] reflects it
  /// immediately; on success, drops the record and emits the confirmed
  /// [Entry] on [confirmedWrites]; on failure, flips the record to
  /// [PendingEntryWriteFailed] and leaves it for [retry].
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
  });

  /// Replays the exact same payload a failed write ([tempId]) was created
  /// with (Never: "a second retry endpoint — retry replays `create()`
  /// verbatim"). A no-op for an unknown [tempId] or one that isn't
  /// currently [PendingEntryWriteFailed] (e.g. already in flight, or
  /// already resolved).
  Future<void> retry(String tempId);

  /// Releases the underlying stream resources — wired into `get_it`'s own
  /// reset lifecycle (`entries_injection.dart`'s `dispose:`), same
  /// convention `SessionExpiryNotifier.dispose()`/`SessionRepository.
  /// dispose()` already use.
  Future<void> dispose();

  /// Every write this tracker currently holds (in flight or failed) —
  /// `MeusRegistrosCubit` overlays this on its own confirmed list (Intent).
  /// Replay-capable: a late subscriber sees the current snapshot
  /// immediately rather than only future changes (`Stream.multi` + cached
  /// last value, mirrors `SessionRepositoryImpl.statusStream`,
  /// `session_repository_impl.dart:69-89`) — necessary here because
  /// `MeusRegistrosCubit` is a long-lived singleton that may subscribe
  /// well after a write is already pending (e.g. the user opens "Meus
  /// Registros" after already starting a save from Home).
  Stream<List<PendingEntryWrite>> get pendingWrites;

  /// Broadcasts the real, server-confirmed [Entry] — paired with the
  /// [PendingEntryWrite.tempId] it resolved from — the instant a
  /// [create]/[retry] call resolves successfully. The one channel
  /// `MeusRegistrosCubit` (which never calls [create]/[retry] itself, and
  /// never talks to a capture cubit directly, AD-7) has to learn of a
  /// just-confirmed write and prepend it into its own state (Boundaries:
  /// "tracker drops the record; `MeusRegistrosCubit` prepends the
  /// confirmed `Entry` into its own state"). No replay semantics, same
  /// rationale `SessionExpiryNotifier.expiredEvents` already documents: a
  /// one-shot signal per confirmation, not a value a late subscriber needs
  /// to catch up on — a write that confirmed before `MeusRegistrosCubit`
  /// ever subscribed will simply arrive through its next `list()`
  /// instead.
  ///
  /// The paired `tempId` (Review finding) lets a listener drop its own
  /// locally-held pending placeholder for this exact write in the very
  /// same synchronous handler that prepends the confirmed [Entry] —
  /// `pendingWrites`' own removal of the same record is a separate
  /// `Stream.multi`-wrapped subscription that can otherwise deliver one
  /// microtask late, which previously left a one-frame window where both
  /// the stale placeholder and the real confirmed entry rendered at once.
  Stream<({String tempId, Entry entry})> get confirmedWrites;
}

/// Default implementation — an in-memory `Map` of outstanding writes
/// (Never: "persisting pending writes" — nothing here ever touches disk;
/// a killed app loses every pending record, by design, UX-DR30).
class PendingEntryWriteTrackerImpl implements PendingEntryWriteTracker {
  PendingEntryWriteTrackerImpl({required EntriesRepository repository})
    : _repository = repository;

  final EntriesRepository _repository;

  /// Insertion order matters for display (Boundaries: "Card appears
  /// top-of-today... before server responds") — a `Map` preserves it in
  /// Dart, and lookups by [PendingEntryWrite.tempId] (for [retry]) stay
  /// O(1).
  final Map<String, PendingEntryWrite> _pending = {};

  final StreamController<List<PendingEntryWrite>> _pendingController =
      StreamController<List<PendingEntryWrite>>.broadcast();

  final StreamController<({String tempId, Entry entry})> _confirmedController =
      StreamController<({String tempId, Entry entry})>.broadcast();

  /// Monotonic suffix so two `create()` calls landing in the very same
  /// microtask (e.g. two fast capture saves) never collide on
  /// [DateTime.now]'s own millisecond resolution.
  int _nextSuffix = 0;

  List<PendingEntryWrite> get _snapshot => List.unmodifiable(_pending.values);

  @override
  Stream<List<PendingEntryWrite>> get pendingWrites {
    // Mirrors `SessionRepositoryImpl.statusStream` exactly: a fresh
    // listener gets the current snapshot synchronously, then every
    // further change the shared broadcast controller delivers.
    return Stream<List<PendingEntryWrite>>.multi((controller) {
      controller.add(_snapshot);
      final subscription = _pendingController.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }

  @override
  Stream<({String tempId, Entry entry})> get confirmedWrites =>
      _confirmedController.stream;

  void _emitPending() {
    if (_pendingController.isClosed) {
      return;
    }
    _pendingController.add(_snapshot);
  }

  String _generateTempId() =>
      'pending-${DateTime.now().microsecondsSinceEpoch}-${_nextSuffix++}';

  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
  }) async {
    // Spec amendment (code-review round 1): drops any existing `failed`
    // record *before* registering the new `inFlight` one — exactly one
    // Insertion Modal exists app-wide, so a user retrying by tapping
    // "Salvar" again in the same still-open modal (not via the badge)
    // must not leave the superseded attempt's error card as a permanent
    // orphan on Meus Registros. Mutated in the same pass as the new
    // record's own insertion below, so only one combined snapshot is ever
    // emitted for this — never an intermediate "failed just removed, new
    // one not yet added" one.
    _pending.removeWhere((_, write) => write.status is PendingEntryWriteFailed);
    final tempId = _generateTempId();
    _pending[tempId] = PendingEntryWrite(
      tempId: tempId,
      content: content,
      source: source,
      mediaDurationSeconds: mediaDurationSeconds,
      startedAt: DateTime.now(),
      status: const PendingEntryWriteInFlight(),
    );
    _emitPending();

    final result = await _repository.create(
      content: content,
      source: source,
      mediaDurationSeconds: mediaDurationSeconds,
    );
    _resolve(tempId, result);
    return result;
  }

  @override
  Future<void> retry(String tempId) async {
    final current = _pending[tempId];
    if (current == null || current.status is! PendingEntryWriteFailed) {
      // Unknown, already in flight, or already resolved.
      return;
    }
    final failedStatus = current.status as PendingEntryWriteFailed;
    if (!failedStatus.failure.retryable) {
      // Review finding (round 2): the tracker, not just `SyncBadge`'s own
      // `onTap` guard, is the authoritative check — a non-retryable
      // failure must never be replayed regardless of which caller invokes
      // [retry].
      return;
    }
    _pending[tempId] = current.copyWith(
      status: const PendingEntryWriteInFlight(),
    );
    _emitPending();

    final result = await _repository.create(
      content: current.content,
      source: current.source,
      mediaDurationSeconds: current.mediaDurationSeconds,
    );
    _resolve(tempId, result);
  }

  /// Shared success/failure handling for both [create] and [retry] — on
  /// success, drops the pending record and broadcasts the confirmed
  /// [Entry]; on failure, flips the record to [PendingEntryWriteFailed]
  /// (re-reads [_pending] rather than trusting a closed-over reference, in
  /// case a concurrent call already replaced it).
  void _resolve(String tempId, Either<Failure, Entry> result) {
    result.match(
      (failure) {
        final latest = _pending[tempId];
        if (latest == null) {
          return;
        }
        _pending[tempId] = latest.copyWith(
          status: PendingEntryWriteFailed(failure: failure),
        );
        _emitPending();
      },
      (entry) {
        _pending.remove(tempId);
        _emitPending();
        if (!_confirmedController.isClosed) {
          _confirmedController.add((tempId: tempId, entry: entry));
        }
      },
    );
  }

  @override
  Future<void> dispose() async {
    await _pendingController.close();
    await _confirmedController.close();
  }
}
