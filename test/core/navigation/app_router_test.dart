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
import 'package:cerne/features/auth/domain/entities/session_status.dart';
import 'package:cerne/features/auth/domain/repositories/auth_repository.dart';
import 'package:cerne/features/auth/domain/repositories/session_repository.dart';
import 'package:cerne/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:cerne/features/auth/presentation/screens/auth_screen.dart';
import 'package:cerne/features/vault/domain/entities/vault_status.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:cerne/features/vault/presentation/screens/vault_lock_screen.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSessionRepository extends Mock implements SessionRepository {}

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

/// Proves the epic's ONE `GoRouter`/`redirect` (Boundaries) resolves the
/// I/O & Edge-Case Matrix from spec-1-6/spec-2-1 exactly — composing
/// [VaultStatus] first, then [SessionStatus] (AD-14), never a hardcoded
/// assumption baked into either matrix.
void main() {
  late _FakeSessionRepository fakeSessionRepository;
  late _FakeVaultRepository fakeVaultRepository;

  setUp(() {
    fakeSessionRepository = _FakeSessionRepository();
    fakeVaultRepository = _FakeVaultRepository();
    // `/auth`'s `GoRoute.builder` resolves `sl<AuthCubit>()` — registered
    // directly (no full `setupCoreDependencies()`) since this suite only
    // exercises the router, not the auth call itself.
    final mockSessionRepositoryForCubit = MockSessionRepository();
    when(() => mockSessionRepositoryForCubit.markAuthenticated())
        .thenReturn(null);
    sl.registerLazySingleton<AuthCubit>(
      () => AuthCubit(MockAuthRepository(), mockSessionRepositoryForCubit),
    );
  });

  tearDown(() async {
    await sl.reset();
    await fakeSessionRepository.dispose();
    await fakeVaultRepository.dispose();
  });

  Future<GoRouter> pumpRouter(WidgetTester tester) async {
    final router = buildAppRouter(
      vaultRepository: fakeVaultRepository,
      sessionRepository: fakeSessionRepository,
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
}
