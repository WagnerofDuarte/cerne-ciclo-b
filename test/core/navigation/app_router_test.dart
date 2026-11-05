import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/di/injection_container.dart';
import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/navigation/app_router.dart';
import 'package:cerne/core/navigation/placeholder_screens.dart';
import 'package:cerne/features/account/domain/repositories/account_settings_repository.dart';
import 'package:cerne/features/account/presentation/cubit/account_settings_cubit.dart';
import 'package:cerne/features/account/presentation/screens/account_settings_screen.dart';
import 'package:cerne/features/auth/domain/entities/session_status.dart';
import 'package:cerne/features/auth/domain/repositories/auth_repository.dart';
import 'package:cerne/features/auth/domain/repositories/session_repository.dart';
import 'package:cerne/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:cerne/features/auth/presentation/screens/auth_screen.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/pending_entry_write.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';
import 'package:cerne/features/entries/presentation/cubit/entries_search_cubit.dart';
import 'package:cerne/features/entries/presentation/cubit/entry_detail_cubit.dart';
import 'package:cerne/features/entries/presentation/cubit/meus_registros_cubit.dart';
import 'package:cerne/features/entries/presentation/screens/entry_detail_screen.dart';
import 'package:cerne/features/entries/presentation/screens/meus_registros_screen.dart';
import 'package:cerne/features/vault/domain/entities/vault_status.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:cerne/features/vault/presentation/screens/vault_lock_screen.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSessionRepository extends Mock implements SessionRepository {}

/// A trivial fake — this router-focused suite only needs
/// `MeusRegistrosScreen`'s/`EntryDetailScreen`'s own `GoRoute.builder`s to
/// resolve `sl<MeusRegistrosCubit>()`/`sl<EntryDetailCubit>()` without
/// throwing; `meus_registros_cubit_test.dart`/`entry_detail_cubit_test.dart`
/// already cover each cubit's own behavior against a more capable fake.
/// `list()` always resolves to an empty page so `MeusRegistrosScreen`
/// settles on its plain "no entries yet" state instead of hanging;
/// `getById()` always resolves to a trivial [Entry] with the requested
/// [id] so `EntryDetailScreen` settles on its own `EntryDetailData` state.
class _FakeEntriesRepository implements EntriesRepository {
  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, EntriesPage>> list({
    String? cursor,
    int limit = 20,
  }) async => right(const EntriesPage(items: [], nextCursor: null));

  @override
  Future<Either<Failure, Entry>> getById(String id) async => right(
    Entry(
      id: id,
      content: 'content-$id',
      source: EntrySource.manual,
      chatMessageId: null,
      occurredAt: '2026-01-01T10:00:00Z',
      serverRevision: 1,
      createdAt: '2026-01-01T10:00:00Z',
      updatedAt: '2026-01-01T10:00:00Z',
    ),
  );

  @override
  Future<Either<Failure, List<Entry>>> search(String query) async =>
      throw UnimplementedError('not expected to be called');
}

/// A trivial fake `PendingEntryWriteTracker` — this suite never exercises
/// spec-4-2's pending/retry overlay, only that `MeusRegistrosCubit`'s
/// `GoRoute.builder` resolution doesn't throw.
class _UnusedPendingEntryWriteTracker implements PendingEntryWriteTracker {
  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<void> retry(String tempId) async =>
      throw UnimplementedError('not expected to be called');

  @override
  Stream<List<PendingEntryWrite>> get pendingWrites => const Stream.empty();

  @override
  Stream<({String tempId, Entry entry})> get confirmedWrites =>
      const Stream.empty();

  @override
  Future<void> dispose() async {}
}

/// A plain (non-mocktail) fake — the redirect matrix needs [currentStatus]
/// read synchronously right after [setStatus], and `statusStream` to
/// actually emit so `GoRouterRefreshStream` re-triggers `redirect`; a
/// mocktail stub can't do both at once as naturally as this tiny fake.
class _FakeSessionRepository implements SessionRepository {
  SessionStatus? _status;
  final _controller = StreamController<SessionStatus>.broadcast();

  @override
  SessionStatus? get currentStatus => _status;

  @override
  Stream<SessionStatus> get statusStream => _controller.stream;

  @override
  Future<Either<Failure, Unit>> restoreSession() async => right(unit);

  @override
  void markAuthenticated() => setStatus(SessionStatus.authenticated);

  @override
  Future<void> dispose() => _controller.close();

  void setStatus(SessionStatus status) {
    _status = status;
    _controller.add(status);
  }
}

/// A plain (non-mocktail) fake for [VaultRepository], same rationale as
/// [_FakeSessionRepository] above — defaults to [VaultStatus.unlocked] so
/// every pre-existing (Story 1.6) test case is unaffected by AD-14's new
/// gate unless a test explicitly locks it.
class _FakeVaultRepository implements VaultRepository {
  VaultStatus _status = VaultStatus.unlocked;
  final _controller = StreamController<VaultStatus>.broadcast();

  /// Controls what [authenticate] resolves to. Defaults to `false` (a
  /// quiet failure) so that mounting `VaultLockScreen` in a test — which
  /// auto-calls [authenticate] once in `initState` — never silently
  /// unlocks the vault on its own; [setStatus] stays the single, explicit
  /// way a test flips vault state.
  bool authenticateSucceeds = false;

  @override
  VaultStatus get currentStatus => _status;

  @override
  Stream<VaultStatus> get statusStream => _controller.stream;

  @override
  Future<Either<Failure, Unit>> authenticate() async {
    if (authenticateSucceeds) {
      setStatus(VaultStatus.unlocked);
      return right(unit);
    }
    return left(
      const Failure.malformedResponse(message: 'fake: biometrics declined'),
    );
  }

  /// Not exercised by this router-focused suite (spec-2-2's PIN flow has
  /// its own dedicated coverage in `vault_lock_screen_test.dart`) — always
  /// fails, so a stray call here never silently unlocks the vault.
  @override
  Future<Either<Failure, Unit>> submitPin(String pin) async {
    return left(const Failure.malformedResponse(message: 'fake: unused'));
  }

  @override
  Future<void> dispose() => _controller.close();

  void setStatus(VaultStatus status) {
    _status = status;
    _controller.add(status);
  }
}

/// A plain (non-mocktail) fake for [AccountSettingsRepository] (Story 2.4,
/// AD-14-style seam) — same rationale as [_FakeSessionRepository]/
/// [_FakeVaultRepository]. Defaults to `true` (never `null`), matching
/// [AccountSettingsRepository.currentBiometricEnabled]'s own documented
/// default.
class _FakeAccountSettingsRepository implements AccountSettingsRepository {
  bool _value = true;
  final _controller = StreamController<bool>.broadcast();

  @override
  bool get currentBiometricEnabled => _value;

  @override
  Stream<bool> get biometricEnabledStream => _controller.stream;

  @override
  Future<Either<Failure, Unit>> fetchBiometricEnabled() async => right(unit);

  @override
  Future<Either<Failure, Unit>> setBiometricEnabled(bool enabled) async {
    setValue(enabled);
    return right(unit);
  }

  @override
  Future<void> dispose() => _controller.close();

  void setValue(bool value) {
    _value = value;
    _controller.add(value);
  }
}

/// Proves the epic's ONE `GoRouter`/`redirect` (Boundaries) resolves the
/// I/O & Edge-Case Matrix from spec-1-6/spec-2-1 exactly — composing
/// [VaultStatus] first, then [SessionStatus] (AD-14), never a hardcoded
/// assumption baked into either matrix.
void main() {
  late _FakeSessionRepository fakeSessionRepository;
  late _FakeVaultRepository fakeVaultRepository;
  late _FakeAccountSettingsRepository fakeAccountSettingsRepository;

  setUp(() {
    fakeSessionRepository = _FakeSessionRepository();
    fakeVaultRepository = _FakeVaultRepository();
    fakeAccountSettingsRepository = _FakeAccountSettingsRepository();
    // `/auth`'s `GoRoute.builder` resolves `sl<AuthCubit>()` — registered
    // directly (no full `setupCoreDependencies()`) since this suite only
    // exercises the router, not the auth call itself.
    final mockSessionRepositoryForCubit = MockSessionRepository();
    when(() => mockSessionRepositoryForCubit.markAuthenticated())
        .thenReturn(null);
    sl.registerLazySingleton<AuthCubit>(
      () => AuthCubit(MockAuthRepository(), mockSessionRepositoryForCubit),
    );
    // `/configuracoes`'s `GoRoute.builder` resolves `sl<AccountSettingsCubit>
    // ()` (Story 2.4) — same rationale as `AuthCubit` above, wired to the
    // same fake repository `pumpRouter` passes into `buildAppRouter` so a
    // test can also drive it through the cubit if ever needed.
    sl.registerLazySingleton<AccountSettingsCubit>(
      () => AccountSettingsCubit(fakeAccountSettingsRepository),
    );
    // `/meus-registros`'s `GoRoute.builder` resolves `sl<
    // MeusRegistrosCubit>()` (spec-4-1) — same rationale as `AuthCubit`/
    // `AccountSettingsCubit` above.
    sl.registerLazySingleton<MeusRegistrosCubit>(
      () => MeusRegistrosCubit(
        _FakeEntriesRepository(),
        _UnusedPendingEntryWriteTracker(),
      ),
    );
    // spec-5-1 — `/meus-registros`'s `GoRoute.builder` also resolves `sl<
    // EntriesSearchCubit>()` now; same trivial-fake rationale as
    // `MeusRegistrosCubit` above — this suite never exercises a real
    // search.
    sl.registerLazySingleton<EntriesSearchCubit>(
      () => EntriesSearchCubit(_FakeEntriesRepository()),
    );
    // `/meus-registros/:id`'s `GoRoute.builder` resolves `sl<
    // EntryDetailCubit>()` (spec-4-4) — same rationale as `MeusRegistros
    // Cubit` above; reuses the suite's own `fakeSessionRepository` so the
    // router's single `SessionRepository` and this cubit's own composed
    // one are the exact same instance, same convention every other
    // `GoRoute.builder` in this suite already follows.
    sl.registerFactory<EntryDetailCubit>(
      () => EntryDetailCubit(
        _FakeEntriesRepository(),
        _UnusedPendingEntryWriteTracker(),
        fakeSessionRepository,
      ),
    );
  });

  tearDown(() async {
    await sl.reset();
    await fakeSessionRepository.dispose();
    await fakeVaultRepository.dispose();
    await fakeAccountSettingsRepository.dispose();
  });

  Future<GoRouter> pumpRouter(WidgetTester tester) async {
    final router = buildAppRouter(
      vaultRepository: fakeVaultRepository,
      sessionRepository: fakeSessionRepository,
      accountSettingsRepository: fakeAccountSettingsRepository,
      navigatorKey: GlobalKey<NavigatorState>(),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    return router;
  }

  String location(GoRouter router) => router.state.uri.toString();

  testWidgets('status not yet known stays on /boot, splash shown', (
    tester,
  ) async {
    final router = await pumpRouter(tester);
    await tester.pump();

    expect(location(router), AppRoutePaths.boot);
    expect(find.byType(BootSplashScreen), findsOneWidget);
  });

  testWidgets('boot, unauthenticated -> redirected to /auth', (tester) async {
    final router = await pumpRouter(tester);
    fakeSessionRepository.setStatus(SessionStatus.unauthenticated);
    await tester.pumpAndSettle();

    expect(location(router), AppRoutePaths.auth);
    expect(find.byType(AuthScreen), findsOneWidget);
  });

  testWidgets('boot, authenticated -> redirected to /', (tester) async {
    final router = await pumpRouter(tester);
    fakeSessionRepository.setStatus(SessionStatus.authenticated);
    await tester.pumpAndSettle();

    expect(location(router), AppRoutePaths.home);
    expect(find.byType(HomeChatPlaceholderScreen), findsOneWidget);
  });

  testWidgets(
    'boot, expired -> redirected to / (treated the same as authenticated '
    'for routing purposes)',
    (tester) async {
      final router = await pumpRouter(tester);
      fakeSessionRepository.setStatus(SessionStatus.expired);
      await tester.pumpAndSettle();

      expect(location(router), AppRoutePaths.home);
      expect(find.byType(HomeChatPlaceholderScreen), findsOneWidget);
    },
  );

  testWidgets(
    'a mid-session expiry while already on a non-boot/non-auth route never '
    'navigates away (Story 1.5 behavior preserved)',
    (tester) async {
      final router = await pumpRouter(tester);
      fakeSessionRepository.setStatus(SessionStatus.authenticated);
      await tester.pumpAndSettle();

      router.go(AppRoutePaths.meusRegistros);
      await tester.pumpAndSettle();
      expect(location(router), AppRoutePaths.meusRegistros);

      fakeSessionRepository.setStatus(SessionStatus.expired);
      await tester.pumpAndSettle();

      expect(location(router), AppRoutePaths.meusRegistros);
    },
  );

  testWidgets(
    'explicit navigation to /reauth while expired is allowed, not bounced '
    'back to / by the redirect',
    (tester) async {
      final router = await pumpRouter(tester);
      fakeSessionRepository.setStatus(SessionStatus.expired);
      await tester.pumpAndSettle();

      router.go(AppRoutePaths.reauth);
      await tester.pumpAndSettle();

      expect(location(router), AppRoutePaths.reauth);
      expect(find.byType(BiometricReauthPlaceholderScreen), findsOneWidget);
    },
  );

  testWidgets('every destination (/, /meus-registros, /planos-de-acao, '
      '/configuracoes) is reachable with zero broken links while '
      'authenticated', (tester) async {
    final router = await pumpRouter(tester);
    fakeSessionRepository.setStatus(SessionStatus.authenticated);
    await tester.pumpAndSettle();

    for (final destination in [
      AppRoutePaths.meusRegistros,
      AppRoutePaths.planosDeAcao,
      AppRoutePaths.configuracoes,
      AppRoutePaths.home,
    ]) {
      router.go(destination);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(location(router), destination);
    }
  });

  group('AD-14 — VaultStatus composed first (spec-2-1)', () {
    testWidgets(
      'VaultStatus.locked overrides any SessionStatus — even an already '
      '`authenticated` session is bounced to /vault, never reaching Home',
      (tester) async {
        fakeVaultRepository.setStatus(VaultStatus.locked);
        final router = await pumpRouter(tester);
        fakeSessionRepository.setStatus(SessionStatus.authenticated);
        await tester.pumpAndSettle();

        expect(location(router), AppRoutePaths.vaultLock);
        expect(find.byType(VaultLockScreen), findsOneWidget);
        expect(find.byType(HomeChatPlaceholderScreen), findsNothing);
      },
    );

    testWidgets(
      'an explicit navigation attempt to any other route while locked is '
      'redirected straight back to /vault',
      (tester) async {
        fakeVaultRepository.setStatus(VaultStatus.locked);
        final router = await pumpRouter(tester);
        fakeSessionRepository.setStatus(SessionStatus.unauthenticated);
        await tester.pumpAndSettle();
        expect(location(router), AppRoutePaths.vaultLock);

        router.go(AppRoutePaths.meusRegistros);
        await tester.pumpAndSettle();

        expect(location(router), AppRoutePaths.vaultLock);
      },
    );

    testWidgets(
      'VaultStatus.unlocked + SessionStatus.authenticated while still at '
      '/vault (the cold-start happy path once authenticate() succeeds) '
      'routes through to Home via the existing session logic',
      (tester) async {
        fakeVaultRepository.setStatus(VaultStatus.locked);
        final router = await pumpRouter(tester);
        fakeSessionRepository.setStatus(SessionStatus.authenticated);
        await tester.pumpAndSettle();
        expect(location(router), AppRoutePaths.vaultLock);

        fakeVaultRepository.setStatus(VaultStatus.unlocked);
        await tester.pumpAndSettle();

        expect(location(router), AppRoutePaths.home);
        expect(find.byType(HomeChatPlaceholderScreen), findsOneWidget);
      },
    );
  });

  group(
    'Story 2.4 — AccountSettingsRepository feeds /vault and /configuracoes',
    () {
      testWidgets(
        '/configuracoes builds the real AccountSettingsScreen, not the old '
        'placeholder',
        (tester) async {
          final router = await pumpRouter(tester);
          fakeSessionRepository.setStatus(SessionStatus.authenticated);
          await tester.pumpAndSettle();

          router.go(AppRoutePaths.configuracoes);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byType(AccountSettingsScreen), findsOneWidget);
        },
      );

      testWidgets(
        'default currentBiometricEnabled (true) is passed straight through '
        'to VaultLockScreen.attemptBiometricFirst',
        (tester) async {
          fakeVaultRepository.setStatus(VaultStatus.locked);
          await pumpRouter(tester);
          await tester.pumpAndSettle();

          final screen = tester.widget<VaultLockScreen>(
            find.byType(VaultLockScreen),
          );
          expect(screen.attemptBiometricFirst, isTrue);
        },
      );

      testWidgets(
        'a false AccountSettingsRepository.currentBiometricEnabled, read at '
        'the moment /vault builds, is passed through as attemptBiometricFirst: '
        'false',
        (tester) async {
          fakeAccountSettingsRepository.setValue(false);
          fakeVaultRepository.setStatus(VaultStatus.locked);
          await pumpRouter(tester);
          await tester.pumpAndSettle();

          final screen = tester.widget<VaultLockScreen>(
            find.byType(VaultLockScreen),
          );
          expect(screen.attemptBiometricFirst, isFalse);
        },
      );
    },
  );

  group('spec-4-1 — /meus-registros builds the real MeusRegistrosScreen', () {
    testWidgets(
      '/meus-registros builds the real MeusRegistrosScreen, not the old '
      'placeholder',
      (tester) async {
        final router = await pumpRouter(tester);
        fakeSessionRepository.setStatus(SessionStatus.authenticated);
        await tester.pumpAndSettle();

        router.go(AppRoutePaths.meusRegistros);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(MeusRegistrosScreen), findsOneWidget);
      },
    );
  });

  group(
    'spec-4-4 — /meus-registros/:id resolves to the real EntryDetailScreen',
    () {
      testWidgets(
        'navigating to /meus-registros/e1 builds EntryDetailScreen, nested '
        'under the same meusRegistros GoRoute, reusing the epic\'s one '
        'redirect/ExpiryOverlayHost (Boundaries: "no second competing '
        'redirect")',
        (tester) async {
          final router = await pumpRouter(tester);
          fakeSessionRepository.setStatus(SessionStatus.authenticated);
          await tester.pumpAndSettle();

          router.go('${AppRoutePaths.meusRegistros}/e1');
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byType(EntryDetailScreen), findsOneWidget);
          expect(location(router), '${AppRoutePaths.meusRegistros}/e1');
        },
      );

      testWidgets(
        'the nested route is gated by the same shared redirect as every '
        'other destination — navigating to it while unauthenticated is '
        'bounced to /auth, never reaching EntryDetailScreen (review '
        'finding, round 2: previously only the authenticated happy path '
        'was covered)',
        (tester) async {
          final router = await pumpRouter(tester);
          fakeSessionRepository.setStatus(SessionStatus.unauthenticated);
          await tester.pumpAndSettle();

          router.go('${AppRoutePaths.meusRegistros}/e1');
          await tester.pumpAndSettle();

          expect(location(router), AppRoutePaths.auth);
          expect(find.byType(EntryDetailScreen), findsNothing);
        },
      );

      testWidgets(
        'a mid-session expiry while already on the nested route never '
        'navigates away, same as any other non-boot/non-auth destination '
        '(review finding, round 2)',
        (tester) async {
          final router = await pumpRouter(tester);
          fakeSessionRepository.setStatus(SessionStatus.authenticated);
          await tester.pumpAndSettle();

          router.go('${AppRoutePaths.meusRegistros}/e1');
          await tester.pumpAndSettle();
          expect(location(router), '${AppRoutePaths.meusRegistros}/e1');

          fakeSessionRepository.setStatus(SessionStatus.expired);
          await tester.pumpAndSettle();

          expect(location(router), '${AppRoutePaths.meusRegistros}/e1');
          expect(find.byType(EntryDetailScreen), findsOneWidget);
        },
      );
    },
  );
}
