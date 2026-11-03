import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:go_router/go_router.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/navigation/expiry_overlay_host.dart';
import 'package:cerne/core/widgets/confirmation_dialog.dart';
import 'package:cerne/features/auth/domain/entities/session_status.dart';
import 'package:cerne/features/auth/domain/repositories/session_repository.dart';

/// Same tiny fake used by `app_router_test.dart`/`main_test.dart` — gives
/// synchronous control over both [SessionStatus] values and the
/// [statusStream] emission `ExpiryOverlayHost` subscribes to.
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

void main() {
  setUp(() {
    ConfirmationDialog.isOpen = false;
  });

  testWidgets('an expired emission before the Navigator behind navigatorKey is '
      'mounted finds no overlay context, does not throw, and resets its '
      'one-shot guard so a later mount can still show the overlay', (
    tester,
  ) async {
    final fakeSessionRepository = _FakeSessionRepository();
    addTearDown(fakeSessionRepository.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SizedBox()),
      ],
    );
    addTearDown(router.dispose);
    final navigatorKey = GlobalKey<NavigatorState>();

    // First mount: `navigatorKey` matches nothing in this tree — no
    // `Navigator` anywhere uses it — simulating the Navigator not being
    // mounted yet when the expiry event arrives.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ExpiryOverlayHost(
          sessionRepository: fakeSessionRepository,
          router: router,
          navigatorKey: navigatorKey,
          child: const SizedBox(),
        ),
      ),
    );

    fakeSessionRepository.setStatus(SessionStatus.expired);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ConfirmationDialog), findsNothing);

    // Second pump of the *same* `ExpiryOverlayHost` (same type, no key,
    // same position — its State is preserved, not remounted): now the
    // child actually contains a `Navigator` using `navigatorKey`, so
    // `navigatorKey.currentState` resolves. Re-emitting `expired` here
    // only shows the overlay if the earlier failed attempt reset
    // `_expiryOverlayShown` back to `false` — if that guard had stayed
    // stuck `true`, this second, now-resolvable attempt would stay
    // silently dropped too.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ExpiryOverlayHost(
          sessionRepository: fakeSessionRepository,
          router: router,
          navigatorKey: navigatorKey,
          child: Navigator(
            key: navigatorKey,
            onGenerateRoute: (settings) =>
                MaterialPageRoute<void>(builder: (context) => const SizedBox()),
          ),
        ),
      ),
    );

    fakeSessionRepository.setStatus(SessionStatus.expired);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Sessão expirada'), findsOneWidget);
  });
}
