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

/// Proves the epic's ONE `GoRouter`/`redirect` (Boundaries) resolves the
/// I/O & Edge-Case Matrix from spec-1-6 exactly — composing only
/// [SessionStatus] for now, with the AD-14 seam left as a comment, never a
/// hardcoded assumption baked into the matrix itself.
void main() {
  late _FakeSessionRepository fakeSessionRepository;

  setUp(() {
    fakeSessionRepository = _FakeSessionRepository();
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
  });

  Future<GoRouter> pumpRouter(WidgetTester tester) async {
    final router = buildAppRouter(
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
}
