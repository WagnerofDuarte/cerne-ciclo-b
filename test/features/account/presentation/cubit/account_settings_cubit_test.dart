import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/account/domain/repositories/account_settings_repository.dart';
import 'package:cerne/features/account/presentation/cubit/account_settings_cubit.dart';
import 'package:cerne/features/auth/domain/entities/session_status.dart';
import 'package:cerne/features/auth/domain/repositories/session_repository.dart';
import 'package:cerne/features/chat/domain/entities/chat_insight.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:cerne/features/chat/domain/entities/chat_stream_event.dart';
import 'package:cerne/features/chat/domain/repositories/chat_repository.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/vault/domain/entities/vault_status.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';

/// A plain (non-mocktail) fake — same rationale as `vault_lock_screen_test.
/// dart`'s own `_FakeVaultRepository`: this suite needs a scriptable
/// `setBiometricEnabled()` result plus a real stream the cubit actually
/// subscribes to, which a mocktail stub can't give as naturally.
class _FakeAccountSettingsRepository implements AccountSettingsRepository {
  bool _value = true;
  final _controller = StreamController<bool>.broadcast();

  /// The next `setBiometricEnabled()` call's own result — defaults to a
  /// failure so a test must opt in to the success path explicitly.
  Either<Failure, Unit> setBiometricEnabledResult = left(
    const Failure.malformedResponse(message: 'fake: not configured'),
  );

  int setBiometricEnabledCallCount = 0;

  // spec-8-3 — a scriptable profile-name slice, same rationale
  // [setBiometricEnabledResult] already gives for the toggle: a test must
  // opt in to a non-default [currentDisplayName]/[currentEmail] or a
  // [setDisplayNameResult] success explicitly.
  @override
  String currentDisplayName = '';
  @override
  String currentEmail = '';
  Either<Failure, Unit> setDisplayNameResult = left(
    const Failure.malformedResponse(message: 'fake: not configured'),
  );
  int setDisplayNameCallCount = 0;
  String? lastSetDisplayNameArg;

  /// Lets a test hold `setDisplayName()` unresolved, to observe
  /// `state.isSavingName` mid-flight — same rationale
  /// `account_settings_screen_test.dart`'s own `setBiometricEnabledGate`
  /// already gives for the toggle.
  Completer<void>? setDisplayNameGate;

  /// Review finding — mirrors `AccountSettingsRepositoryImpl.
  /// setDisplayName`'s own "echo wins" behavior: on success,
  /// `currentDisplayName` is set to this value (defaulting to whatever was
  /// actually sent) rather than always just echoing the argument back
  /// unchanged. Lets a test prove the cubit reads the repository's own
  /// post-save value rather than assuming the server stored exactly what
  /// was sent.
  String? setDisplayNameEchoedNameOverride;

  @override
  Future<Either<Failure, Unit>> setDisplayName(String name) async {
    setDisplayNameCallCount += 1;
    lastSetDisplayNameArg = name;
    final gate = setDisplayNameGate;
    if (gate != null) {
      await gate.future;
    }
    if (setDisplayNameResult.isRight()) {
      currentDisplayName = setDisplayNameEchoedNameOverride ?? name;
    }
    return setDisplayNameResult;
  }

  @override
  bool get currentBiometricEnabled => _value;

  @override
  Stream<bool> get biometricEnabledStream {
    return Stream<bool>.multi((controller) {
      controller.add(_value);
      final subscription = _controller.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }

  @override
  Future<Either<Failure, Unit>> fetchBiometricEnabled() async => right(unit);

  @override
  Future<Either<Failure, Unit>> setBiometricEnabled(bool enabled) async {
    setBiometricEnabledCallCount += 1;
    final previous = _value;
    _emit(enabled);
    final result = setBiometricEnabledResult;
    if (result.isLeft()) {
      _emit(previous);
    }
    return result;
  }

  // Story 8.5 — scriptable like [setBiometricEnabledResult]/
  // [setDisplayNameResult] above: defaults to a failure so a test must
  // opt in to the success path explicitly.
  Either<Failure, Unit> deleteAccountResult = left(
    const Failure.malformedResponse(message: 'fake: not configured'),
  );

  int deleteAccountCallCount = 0;

  /// Lets a test hold `deleteAccount()` unresolved, to observe
  /// `state.isDeletingAccount` mid-flight — same rationale
  /// [setDisplayNameGate] already gives for name saves.
  Completer<void>? deleteAccountGate;

  @override
  Future<Either<Failure, Unit>> deleteAccount() async {
    deleteAccountCallCount += 1;
    final gate = deleteAccountGate;
    if (gate != null) {
      await gate.future;
    }
    return deleteAccountResult;
  }

  @override
  Future<void> dispose() => _controller.close();

  void _emit(bool value) {
    _value = value;
    _controller.add(value);
  }
}

/// Story 8.4 — a plain (non-mocktail) fake [SessionRepository]: this
/// suite's own `AccountSettingsCubit.logout()` tests only ever call
/// [logout] on it (never `restoreSession`/`markAuthenticated` — those are
/// exercised by `session_repository_impl_test.dart`/`auth_cubit_test.dart`
/// instead), so every other member throws if ever reached.
class _FakeSessionRepository implements SessionRepository {
  int logoutCallCount = 0;

  /// Lets a test hold [logout] unresolved, to observe ordering against
  /// [_FakeVaultRepository.lock] (Boundaries: "`vaultRepository.lock()`...
  /// BEFORE awaiting `sessionRepository.logout()`").
  Completer<void>? logoutGate;

  Either<Failure, Unit> logoutResult = right(unit);

  @override
  SessionStatus? get currentStatus =>
      throw UnimplementedError('not expected to be called');

  @override
  Stream<SessionStatus> get statusStream =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, Unit>> restoreSession() async =>
      throw UnimplementedError('not expected to be called');

  @override
  void markAuthenticated() =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, Unit>> logout() async {
    logoutCallCount += 1;
    final gate = logoutGate;
    if (gate != null) {
      await gate.future;
    }
    return logoutResult;
  }

  @override
  Future<void> dispose() async {}
}

/// Story 8.4 — same rationale as [_FakeSessionRepository]: only [lock] is
/// ever expected to be called by this cubit.
class _FakeVaultRepository implements VaultRepository {
  int lockCallCount = 0;

  @override
  VaultStatus get currentStatus =>
      throw UnimplementedError('not expected to be called');

  @override
  Stream<VaultStatus> get statusStream =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, Unit>> authenticate() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, Unit>> submitPin(String pin) async =>
      throw UnimplementedError('not expected to be called');

  @override
  void lock() {
    lockCallCount += 1;
  }

  @override
  Future<void> dispose() async {}
}

/// Story 8.4 — same rationale as [_FakeSessionRepository]: only
/// [clearLocalCache] is ever expected to be called by this cubit.
class _FakeEntriesRepository implements EntriesRepository {
  int clearLocalCacheCallCount = 0;

  /// Lets a test hold [clearLocalCache] unresolved, to prove it's awaited
  /// alongside [_FakeChatRepository.clearLocalCache] via `Future.wait`
  /// (Boundaries), not sequentially.
  Completer<void>? clearLocalCacheGate;

  Either<Failure, Unit> clearLocalCacheResult = right(unit);

  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
    String? chatMessageId,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, EntriesPage>> list({
    String? cursor,
    int limit = 20,
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, Entry>> getById(String id) async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, List<Entry>>> search(
    String query, {
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, Unit>> clearLocalCache() async {
    clearLocalCacheCallCount += 1;
    final gate = clearLocalCacheGate;
    if (gate != null) {
      await gate.future;
    }
    return clearLocalCacheResult;
  }
}

/// Story 8.4 — same rationale as [_FakeEntriesRepository] above.
class _FakeChatRepository implements ChatRepository {
  int clearLocalCacheCallCount = 0;

  /// Same ordering rationale as
  /// [_FakeEntriesRepository.clearLocalCacheGate].
  Completer<void>? clearLocalCacheGate;

  Either<Failure, Unit> clearLocalCacheResult = right(unit);

  @override
  Future<Either<Failure, List<ChatSession>>> listSessions() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, ChatSession>> createSession() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, List<ChatMessage>>> listMessages(
    String sessionId,
  ) async => throw UnimplementedError('not expected to be called');

  @override
  Stream<Either<Failure, ChatStreamEvent>> sendMessage(
    String sessionId,
    String content,
  ) => throw UnimplementedError('not expected to be called');

  @override
  Stream<Either<Failure, ChatStreamEvent>> retryMessage(
    String sessionId,
    String userMessageId,
  ) => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, ChatInsight?>> generateInsight(
    String sessionId, {
    required InsightTriggerType triggerType,
    required String triggerKey,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, Unit>> clearLocalCache() async {
    clearLocalCacheCallCount += 1;
    final gate = clearLocalCacheGate;
    if (gate != null) {
      await gate.future;
    }
    return clearLocalCacheResult;
  }
}

Future<List<AccountSettingsState>> _emittedDuring(
  AccountSettingsCubit cubit,
  Future<void> Function() act,
) async {
  final emitted = <AccountSettingsState>[];
  final subscription = cubit.stream.listen(emitted.add);
  await act();
  // `pumpEventQueue()` (not a single `Future.delayed(Duration.zero)`): the
  // `biometricEnabled` mirror travels repository -> Stream.multi's own
  // forwarding subscription -> cubit's `emit()` -> `_stateController`,
  // several microtask hops deep — one `Duration.zero` delay only guarantees
  // draining one hop, leaving a later hop's delivery to land after this
  // helper already returned.
  await pumpEventQueue();
  await subscription.cancel();
  return emitted;
}

void main() {
  late _FakeAccountSettingsRepository fakeRepository;
  late _FakeSessionRepository fakeSessionRepository;
  late _FakeVaultRepository fakeVaultRepository;
  late _FakeEntriesRepository fakeEntriesRepository;
  late _FakeChatRepository fakeChatRepository;

  setUp(() {
    fakeRepository = _FakeAccountSettingsRepository();
    fakeSessionRepository = _FakeSessionRepository();
    fakeVaultRepository = _FakeVaultRepository();
    fakeEntriesRepository = _FakeEntriesRepository();
    fakeChatRepository = _FakeChatRepository();
  });

  /// Story 8.4 — every pre-existing test in this file only exercises the
  /// biometric toggle / profile-name slices, never [AccountSettingsCubit.
  /// logout], so the widened constructor's 4 new deps are passed through
  /// this one helper rather than repeating them at each of this file's
  /// pre-existing 16 call sites.
  AccountSettingsCubit buildCubit() => AccountSettingsCubit(
    fakeRepository,
    fakeSessionRepository,
    fakeVaultRepository,
    fakeEntriesRepository,
    fakeChatRepository,
  );

  group('initial state', () {
    test('mirrors currentBiometricEnabled (true) at construction', () async {
      final cubit = buildCubit();

      expect(cubit.state.biometricEnabled, isTrue);
      expect(cubit.state.errorMessage, isNull);
      await cubit.close();
    });

    test('mirrors a false currentBiometricEnabled (e.g. already fetched '
        'before the screen opened)', () async {
      fakeRepository._emit(false);
      final cubit = buildCubit();

      expect(cubit.state.biometricEnabled, isFalse);
      await cubit.close();
    });
  });

  group('toggleBiometric() — success', () {
    test('flips to the new value and clears any prior error, calling the '
        'repository with exactly the requested value', () async {
      fakeRepository.setBiometricEnabledResult = right(unit);
      final cubit = buildCubit();

      final emitted = await _emittedDuring(
        cubit,
        () => cubit.toggleBiometric(false),
      );

      expect(emitted.last.biometricEnabled, isFalse);
      expect(emitted.last.errorMessage, isNull);
      expect(fakeRepository.setBiometricEnabledCallCount, 1);
      await cubit.close();
    });
  });

  group('toggleBiometric() — failure', () {
    test('the switch reverts (mirrored from the repository\'s own revert) '
        'and the Failure\'s message is surfaced', () async {
      fakeRepository.setBiometricEnabledResult = left(
        const Failure.networkTimeout(message: 'Sem conexão'),
      );
      final cubit = buildCubit();
      // Drains the constructor's own subscription-replay of the current
      // value (Stream.multi's replay goes through its own forwarding
      // subscription, several microtask hops deep) before the capture
      // window below starts — otherwise that replay (allowed through by
      // Cubit's own "first emit always goes through" rule) can land
      // mid-capture as a spurious extra entry. `pumpEventQueue()` drains
      // repeatedly until the queue is empty, rather than a single
      // `Future.delayed(Duration.zero)` which only guarantees one hop.
      await pumpEventQueue();

      final emitted = await _emittedDuring(
        cubit,
        () => cubit.toggleBiometric(false),
      );

      // Two independent emission paths feed `emitted` here: the
      // `biometricEnabled` flip/revert mirrors the repository's own stream
      // (several `Stream.multi` forwarding hops deep), while the
      // `errorMessage` update is `toggleBiometric()`'s own direct `emit()`
      // (one hop). Their relative *order* isn't guaranteed by either path's
      // own contract, so asserting an exact sequence would pin an
      // implementation accident, not a behavior the spec requires — what
      // the I/O matrix actually requires (and what's asserted below) is
      // that the optimistic flip to `false` was visible at some point, and
      // that the settled end state reverted to `true` with the `Failure`'s
      // message surfaced.
      expect(emitted.map((s) => s.biometricEnabled), contains(false));
      expect(emitted.last.biometricEnabled, isTrue);
      expect(emitted.last.errorMessage, 'Sem conexão');
      expect(cubit.state.biometricEnabled, isTrue);
      expect(cubit.state.errorMessage, 'Sem conexão');
      await cubit.close();
    });

    test(
      'a later successful toggle clears the previous error message',
      () async {
        fakeRepository.setBiometricEnabledResult = left(
          const Failure.networkTimeout(message: 'Sem conexão'),
        );
        final cubit = buildCubit();
        await cubit.toggleBiometric(false);
        // `toggleBiometric()`'s own await only guarantees its direct
        // `setBiometricEnabled()` Future resolved — the `biometricEnabled`
        // mirror it emits travels back through the repository's
        // `Stream.multi` forwarding subscription, several microtask hops
        // behind that Future; drain those before asserting on `cubit.state`
        // (same rationale as `_emittedDuring`'s own `pumpEventQueue()`).
        await pumpEventQueue();
        expect(cubit.state.errorMessage, 'Sem conexão');

        fakeRepository.setBiometricEnabledResult = right(unit);
        await cubit.toggleBiometric(true);
        await pumpEventQueue();

        expect(cubit.state.errorMessage, isNull);
        expect(cubit.state.biometricEnabled, isTrue);
        await cubit.close();
      },
    );
  });

  // spec-8-3 — Boundaries: "Cubit reads displayName/email from the
  // repository at construction".
  group('initial state — displayName/email (spec-8-3)', () {
    test('mirrors currentDisplayName/currentEmail at construction', () async {
      fakeRepository.currentDisplayName = 'Ana Silva';
      fakeRepository.currentEmail = 'ana@example.com';
      final cubit = buildCubit();

      expect(cubit.state.displayName, 'Ana Silva');
      expect(cubit.state.email, 'ana@example.com');
      expect(cubit.state.isEditingName, isFalse);
      await cubit.close();
    });
  });

  // spec-8-3 — the full I/O & Edge-Case Matrix for the inline name edit.
  group('startEditingName()', () {
    test('switches to edit mode with draft = current name, clearing any '
        'leftover error (I/O matrix: "Tap pencil")', () async {
      fakeRepository.currentDisplayName = 'Ana Silva';
      final cubit = buildCubit();

      cubit.startEditingName();

      expect(cubit.state.isEditingName, isTrue);
      expect(cubit.state.nameDraft, 'Ana Silva');
      expect(cubit.state.nameErrorMessage, isNull);
      await cubit.close();
    });
  });

  group('updateNameDraft()', () {
    test(
      'updates nameDraft without touching isEditingName/displayName',
      () async {
        final cubit = buildCubit();
        cubit.startEditingName();

        cubit.updateNameDraft('Novo Nome');

        expect(cubit.state.nameDraft, 'Novo Nome');
        expect(cubit.state.isEditingName, isTrue);
        expect(cubit.state.displayName, fakeRepository.currentDisplayName);
        await cubit.close();
      },
    );
  });

  group('confirmEditingName() — empty/unchanged draft', () {
    test('an unchanged draft reverts immediately, no PATCH sent (I/O '
        'matrix)', () async {
      fakeRepository.currentDisplayName = 'Ana Silva';
      final cubit = buildCubit();
      cubit.startEditingName();

      await cubit.confirmEditingName();

      expect(cubit.state.isEditingName, isFalse);
      expect(cubit.state.displayName, 'Ana Silva');
      expect(fakeRepository.setDisplayNameCallCount, 0);
      await cubit.close();
    });

    test('an all-whitespace (trims to empty) draft reverts immediately, no '
        'PATCH sent', () async {
      fakeRepository.currentDisplayName = 'Ana Silva';
      final cubit = buildCubit();
      cubit.startEditingName();
      cubit.updateNameDraft('   ');

      await cubit.confirmEditingName();

      expect(cubit.state.isEditingName, isFalse);
      expect(cubit.state.displayName, 'Ana Silva');
      expect(fakeRepository.setDisplayNameCallCount, 0);
      await cubit.close();
    });
  });

  group('confirmEditingName() — changed non-empty draft, success', () {
    test('saves (trimmed), shows a saving indicator mid-flight, then '
        'reverts to display mode with the new name (I/O matrix)', () async {
      fakeRepository.currentDisplayName = 'Ana Silva';
      fakeRepository.setDisplayNameResult = right(unit);
      fakeRepository.setDisplayNameGate = Completer<void>();
      final cubit = buildCubit();
      cubit.startEditingName();
      cubit.updateNameDraft('  Nome Novo  ');

      final confirmFuture = cubit.confirmEditingName();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isSavingName, isTrue);
      expect(cubit.state.isEditingName, isTrue);

      fakeRepository.setDisplayNameGate!.complete();
      await confirmFuture;

      expect(cubit.state.isSavingName, isFalse);
      expect(cubit.state.isEditingName, isFalse);
      expect(cubit.state.displayName, 'Nome Novo');
      expect(cubit.state.nameErrorMessage, isNull);
      expect(fakeRepository.lastSetDisplayNameArg, 'Nome Novo');
      await cubit.close();
    });

    test(
      // Review finding: the success branch used to emit the locally-sent,
      // merely-trimmed draft instead of re-reading the repository's own
      // post-save value — defeating `AccountSettingsRepositoryImpl.
      // setDisplayName`'s own code-review patch, which sets
      // `currentDisplayName` from the response's echoed value so any
      // backend-side normalization (trimming, casing, etc.) is reflected
      // locally. This proves the cubit now shows that echoed value, not
      // the locally-sent one.
      'shows the repository\'s own echoed name on success, not the '
      'locally-sent one, when the server normalizes it differently',
      () async {
        fakeRepository.currentDisplayName = 'Ana Silva';
        fakeRepository.setDisplayNameResult = right(unit);
        fakeRepository.setDisplayNameEchoedNameOverride = 'Nome Novo (Servidor)';
        final cubit = buildCubit();
        cubit.startEditingName();
        cubit.updateNameDraft('Nome Novo');

        await cubit.confirmEditingName();

        expect(fakeRepository.lastSetDisplayNameArg, 'Nome Novo');
        expect(cubit.state.displayName, 'Nome Novo (Servidor)');
        await cubit.close();
      },
    );
  });

  group('confirmEditingName() — failure', () {
    test('stays editing with the draft kept and an inline error (I/O '
        'matrix)', () async {
      fakeRepository.currentDisplayName = 'Ana Silva';
      fakeRepository.setDisplayNameResult = left(
        const Failure.networkTimeout(message: 'Sem conexão'),
      );
      final cubit = buildCubit();
      cubit.startEditingName();
      cubit.updateNameDraft('Nome Novo');

      await cubit.confirmEditingName();

      expect(cubit.state.isEditingName, isTrue);
      expect(cubit.state.isSavingName, isFalse);
      expect(cubit.state.nameDraft, 'Nome Novo');
      expect(cubit.state.nameErrorMessage, 'Sem conexão');
      // The display name itself is untouched by a failed save.
      expect(cubit.state.displayName, 'Ana Silva');
      await cubit.close();
    });

    test('the superseded-call message is suppressed, same convention as '
        'toggleBiometric\'s own failure branch', () async {
      fakeRepository.currentDisplayName = 'Ana Silva';
      fakeRepository.setDisplayNameResult = left(
        const Failure.malformedResponse(
          message: AccountSettingsRepository.supersededMessage,
        ),
      );
      final cubit = buildCubit();
      cubit.startEditingName();
      cubit.updateNameDraft('Nome Novo');

      await cubit.confirmEditingName();

      expect(cubit.state.isSavingName, isFalse);
      expect(cubit.state.nameErrorMessage, isNull);
      await cubit.close();
    });
  });

  group('cancelEditingName()', () {
    test('not saving -> reverts immediately, no PATCH sent (I/O matrix: '
        '"Tap away, not saving")', () async {
      fakeRepository.currentDisplayName = 'Ana Silva';
      final cubit = buildCubit();
      cubit.startEditingName();
      cubit.updateNameDraft('Rascunho descartado');

      cubit.cancelEditingName();

      expect(cubit.state.isEditingName, isFalse);
      expect(cubit.state.displayName, 'Ana Silva');
      expect(fakeRepository.setDisplayNameCallCount, 0);
      await cubit.close();
    });

    test('a no-op while saving — the in-flight confirm owns the eventual '
        'transition (I/O matrix: "Tap away, saving")', () async {
      fakeRepository.currentDisplayName = 'Ana Silva';
      fakeRepository.setDisplayNameResult = right(unit);
      fakeRepository.setDisplayNameGate = Completer<void>();
      final cubit = buildCubit();
      cubit.startEditingName();
      cubit.updateNameDraft('Nome Novo');
      final confirmFuture = cubit.confirmEditingName();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isSavingName, isTrue);

      cubit.cancelEditingName();

      // Still editing/saving — the cancel call above was a no-op.
      expect(cubit.state.isEditingName, isTrue);
      expect(cubit.state.isSavingName, isTrue);

      fakeRepository.setDisplayNameGate!.complete();
      await confirmFuture;

      // The save completes normally, unaffected by the earlier no-op
      // cancel attempt.
      expect(cubit.state.isEditingName, isFalse);
      expect(cubit.state.displayName, 'Nome Novo');
      await cubit.close();
    });
  });

  // Story 8.4 — the full I/O & Edge-Case Matrix for the "Sair" flow.
  group('logout() — Story 8.4', () {
    test('locks the vault BEFORE awaiting sessionRepository.logout() — '
        'AD-14\'s vault-gate-first redirect lands on /vault with no '
        'transient /auth hop (Boundaries)', () async {
      fakeSessionRepository.logoutGate = Completer<void>();
      final cubit = buildCubit();

      final logoutFuture = cubit.logout();
      // The vault lock is synchronous, fired before the await on
      // sessionRepository.logout() below ever resolves.
      expect(fakeVaultRepository.lockCallCount, 1);
      expect(fakeSessionRepository.logoutCallCount, 1);

      fakeSessionRepository.logoutGate!.complete();
      await logoutFuture;
      await cubit.close();
    });

    test('awaits sessionRepository.logout() before clearing the entries/'
        'chat caches — each cache clear only starts once the session '
        'logout call has resolved', () async {
      fakeSessionRepository.logoutGate = Completer<void>();
      final cubit = buildCubit();

      final logoutFuture = cubit.logout();
      await Future<void>.delayed(Duration.zero);
      expect(fakeEntriesRepository.clearLocalCacheCallCount, 0);
      expect(fakeChatRepository.clearLocalCacheCallCount, 0);

      fakeSessionRepository.logoutGate!.complete();
      await logoutFuture;

      expect(fakeEntriesRepository.clearLocalCacheCallCount, 1);
      expect(fakeChatRepository.clearLocalCacheCallCount, 1);
      await cubit.close();
    });

    test('clears the entries and chat caches concurrently via Future.wait '
        '— neither awaits the other', () async {
      fakeEntriesRepository.clearLocalCacheGate = Completer<void>();
      fakeChatRepository.clearLocalCacheGate = Completer<void>();
      final cubit = buildCubit();

      final logoutFuture = cubit.logout();
      await Future<void>.delayed(Duration.zero);
      // Both calls have started even though neither has resolved yet —
      // proves they're concurrent, not sequential.
      expect(fakeEntriesRepository.clearLocalCacheCallCount, 1);
      expect(fakeChatRepository.clearLocalCacheCallCount, 1);

      fakeEntriesRepository.clearLocalCacheGate!.complete();
      fakeChatRepository.clearLocalCacheGate!.complete();
      await logoutFuture;
      await cubit.close();
    });

    test('isLoggingOut is true for the duration of the call, then false '
        'once everything settles', () async {
      fakeSessionRepository.logoutGate = Completer<void>();
      final cubit = buildCubit();
      expect(cubit.state.isLoggingOut, isFalse);

      final logoutFuture = cubit.logout();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isLoggingOut, isTrue);

      fakeSessionRepository.logoutGate!.complete();
      await logoutFuture;

      expect(cubit.state.isLoggingOut, isFalse);
      await cubit.close();
    });

    test('a double-tap (second call while the first is still in flight) '
        'no-ops — the switch\'s own disabled state is the first line of '
        'defense, this guard is the backstop (Boundaries)', () async {
      fakeSessionRepository.logoutGate = Completer<void>();
      final cubit = buildCubit();

      final firstLogout = cubit.logout();
      await Future<void>.delayed(Duration.zero);
      await cubit.logout();

      expect(fakeVaultRepository.lockCallCount, 1);
      expect(fakeSessionRepository.logoutCallCount, 1);

      fakeSessionRepository.logoutGate!.complete();
      await firstLogout;
      await cubit.close();
    });

    test('a backend logout failure (e.g. offline) still clears the local '
        'caches and settles isLoggingOut — never surfaced as an error '
        '(Never: "surfacing a backend-logout-failure error")', () async {
      fakeSessionRepository.logoutResult = left(
        const Failure.networkOffline(message: 'Offline'),
      );
      final cubit = buildCubit();

      await cubit.logout();

      expect(fakeEntriesRepository.clearLocalCacheCallCount, 1);
      expect(fakeChatRepository.clearLocalCacheCallCount, 1);
      expect(cubit.state.isLoggingOut, isFalse);
      expect(cubit.state.errorMessage, isNull);
      await cubit.close();
    });

    test('isClosed guard — a cubit closed mid-logout never throws trying '
        'to emit on it (same convention as toggleBiometric\'s own guard)',
        () async {
      fakeSessionRepository.logoutGate = Completer<void>();
      final cubit = buildCubit();

      final logoutFuture = cubit.logout();
      await Future<void>.delayed(Duration.zero);
      await cubit.close();
      fakeSessionRepository.logoutGate!.complete();

      await expectLater(logoutFuture, completes);
    });
  });

  // Story 8.5 — the full I/O & Edge-Case Matrix for the "Apagar conta"
  // flow (spec-8-5-account-deletion.md).
  group('deleteAccount() — Story 8.5', () {
    test('isDeletingAccount is true for the duration of the call, then '
        'false once everything settles', () async {
      fakeRepository.deleteAccountGate = Completer<void>();
      final cubit = buildCubit();
      expect(cubit.state.isDeletingAccount, isFalse);

      final deleteFuture = cubit.deleteAccount();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isDeletingAccount, isTrue);

      fakeRepository.deleteAccountGate!.complete();
      await deleteFuture;

      expect(cubit.state.isDeletingAccount, isFalse);
      await cubit.close();
    });

    test('success -> runs the same lock+session-logout+cache-clear '
        'sequence logout() uses (the shared _finishSession helper, '
        'Boundaries)', () async {
      fakeRepository.deleteAccountResult = right(unit);
      final cubit = buildCubit();

      await cubit.deleteAccount();

      expect(fakeRepository.deleteAccountCallCount, 1);
      expect(fakeVaultRepository.lockCallCount, 1);
      expect(fakeSessionRepository.logoutCallCount, 1);
      expect(fakeEntriesRepository.clearLocalCacheCallCount, 1);
      expect(fakeChatRepository.clearLocalCacheCallCount, 1);
      expect(cubit.state.isDeletingAccount, isFalse);
      expect(cubit.state.deleteAccountErrorMessage, isNull);
      await cubit.close();
    });

    test('failure -> isDeletingAccount resets, deleteAccountErrorMessage is '
        'set to the Failure\'s message, and the session is NEVER finished '
        '— the vault stays unlocked, nothing is cleared (I/O matrix: '
        '"vault stays unlocked, nothing cleared")', () async {
      fakeRepository.deleteAccountResult = left(
        const Failure.networkOffline(message: 'fake: offline'),
      );
      final cubit = buildCubit();

      await cubit.deleteAccount();

      expect(cubit.state.isDeletingAccount, isFalse);
      expect(cubit.state.deleteAccountErrorMessage, 'fake: offline');
      expect(fakeVaultRepository.lockCallCount, 0);
      expect(fakeSessionRepository.logoutCallCount, 0);
      expect(fakeEntriesRepository.clearLocalCacheCallCount, 0);
      expect(fakeChatRepository.clearLocalCacheCallCount, 0);
      await cubit.close();
    });

    test('a later call clears a previous attempt\'s leftover error message '
        'at the start, before the new call\'s own result is known', () async {
      fakeRepository.deleteAccountResult = left(
        const Failure.networkOffline(message: 'fake: offline'),
      );
      final cubit = buildCubit();
      await cubit.deleteAccount();
      expect(cubit.state.deleteAccountErrorMessage, isNotNull);

      fakeRepository.deleteAccountGate = Completer<void>();
      final secondFuture = cubit.deleteAccount();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.deleteAccountErrorMessage, isNull);

      fakeRepository.deleteAccountGate!.complete();
      await secondFuture;
      await cubit.close();
    });

    test('a double-tap (second call while the first is still in flight) '
        'no-ops — the button\'s own disabled state is the first line of '
        'defense, this guard is the backstop (I/O matrix: "Double-tap '
        'Apagar conta")', () async {
      fakeRepository.deleteAccountGate = Completer<void>();
      final cubit = buildCubit();

      final firstDelete = cubit.deleteAccount();
      await Future<void>.delayed(Duration.zero);
      await cubit.deleteAccount();

      expect(fakeRepository.deleteAccountCallCount, 1);

      fakeRepository.deleteAccountGate!.complete();
      await firstDelete;
      await cubit.close();
    });

    test('isClosed guard — a cubit closed mid-call (before the repository '
        'result resolves) never throws trying to emit on it', () async {
      fakeRepository.deleteAccountGate = Completer<void>();
      final cubit = buildCubit();

      final deleteFuture = cubit.deleteAccount();
      await Future<void>.delayed(Duration.zero);
      await cubit.close();
      fakeRepository.deleteAccountGate!.complete();

      await expectLater(deleteFuture, completes);
    });

    test('isClosed guard — a cubit closed mid-_finishSession (after a '
        'successful delete, before sessionRepository.logout() resolves) '
        'never throws trying to emit on it', () async {
      fakeRepository.deleteAccountResult = right(unit);
      fakeSessionRepository.logoutGate = Completer<void>();
      final cubit = buildCubit();

      final deleteFuture = cubit.deleteAccount();
      await Future<void>.delayed(Duration.zero);
      await cubit.close();
      fakeSessionRepository.logoutGate!.complete();

      await expectLater(deleteFuture, completes);
    });
  });
}
