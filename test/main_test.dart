import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:fpdart/fpdart.dart' hide State;
import 'package:hive_ce/hive_ce.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:cerne/core/di/injection_container.dart';
import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/widgets/confirmation_dialog.dart';
import 'package:cerne/features/account/domain/repositories/account_settings_repository.dart';
import 'package:cerne/features/auth/domain/entities/authenticated_user.dart';
import 'package:cerne/features/auth/domain/entities/session_status.dart';
import 'package:cerne/features/auth/domain/repositories/auth_repository.dart';
import 'package:cerne/features/auth/domain/repositories/session_repository.dart';
import 'package:cerne/features/chat/domain/entities/chat_insight.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:cerne/features/chat/domain/entities/chat_stream_event.dart';
import 'package:cerne/features/chat/domain/repositories/chat_repository.dart';
import 'package:cerne/features/chat/presentation/cubit/chat_cubit.dart';
import 'package:cerne/features/chat/presentation/screens/chat_screen.dart';
import 'package:cerne/features/vault/domain/entities/vault_status.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:cerne/features/vault/presentation/screens/vault_lock_screen.dart';
import 'package:cerne/main.dart';

import 'support/fake_connectivity_watcher.dart';
import 'support/fake_path_provider_platform.dart';
import 'support/testwidgets_with_cleanup.dart';
import 'support/unused_save_chat_message_as_entry_use_case.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

/// A plain (non-mocktail) fake — the overlay/router tests below need
/// [currentStatus] to reflect whatever [setStatus] last set, read
/// synchronously by the router's `redirect`, while also actually emitting
/// on [statusStream] so both the router's `refreshListenable` and
/// `ExpiryOverlayHost`'s own subscription react — the same reason
/// `app_router_test.dart` uses one instead of a mocktail stub.
class _FakeSessionRepository implements SessionRepository {
  _FakeSessionRepository({Either<Failure, Unit>? restoreSessionResult})
    : _restoreSessionResult = restoreSessionResult ?? right(unit);

  final Either<Failure, Unit> _restoreSessionResult;
  SessionStatus? _status;
  final _controller = StreamController<SessionStatus>.broadcast();

  @override
  SessionStatus? get currentStatus => _status;

  @override
  Stream<SessionStatus> get statusStream => _controller.stream;

  @override
  Future<Either<Failure, Unit>> restoreSession() async => _restoreSessionResult;

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
/// [_FakeSessionRepository] above. [authenticateSucceeds] defaults to
/// `false` so mounting `VaultLockScreen` — which auto-calls [authenticate]
/// once in `initState` — never silently unlocks the vault on its own;
/// [setStatus] stays the single, explicit way a test flips vault state.
class _FakeVaultRepository implements VaultRepository {
  _FakeVaultRepository({VaultStatus initialStatus = VaultStatus.unlocked})
    : _status = initialStatus;

  VaultStatus _status;
  final _controller = StreamController<VaultStatus>.broadcast();
  bool authenticateSucceeds = false;

  /// The one PIN `submitPin()` treats as "stored" (spec-2-2) — `null`
  /// means no PIN has been stored yet, mirroring `VaultRepositoryImpl`'s
  /// own set-on-first-use behavior.
  String? storedPin;

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

  @override
  Future<Either<Failure, Unit>> submitPin(String pin) async {
    if (storedPin == null || storedPin == pin) {
      storedPin = pin;
      setStatus(VaultStatus.unlocked);
      return right(unit);
    }
    return left(const Failure.malformedResponse(message: 'fake: PIN mismatch'));
  }

  @override
  Future<void> dispose() => _controller.close();

  void setStatus(VaultStatus status) {
    _status = status;
    _controller.add(status);
  }
}

/// A plain (non-mocktail) fake for [AccountSettingsRepository] (Story 2.4)
/// — swapped in for the real `AccountSettingsRepositoryImpl` in every test
/// below (same rationale as [_FakeVaultRepository] replacing the real
/// `VaultRepositoryImpl`), so `CerneApp`'s boot-time
/// `fetchBiometricEnabled()` call (`main.dart`) never reaches the real
/// network pipeline. [fetchBiometricEnabledSucceeds] defaults to `true` so
/// the fetch is a harmless no-op (the fake's own `currentBiometricEnabled`
/// already starts `true`, matching production's own default) unless a
/// test explicitly wants to exercise the failure row.
class _FakeAccountSettingsRepository implements AccountSettingsRepository {
  bool _value = true;
  final _controller = StreamController<bool>.broadcast();

  bool fetchBiometricEnabledSucceeds = true;

  @override
  bool get currentBiometricEnabled => _value;

  @override
  Stream<bool> get biometricEnabledStream => _controller.stream;

  @override
  Future<Either<Failure, Unit>> fetchBiometricEnabled() async {
    if (!fetchBiometricEnabledSucceeds) {
      return left(
        const Failure.networkOffline(message: 'fake: boot fetch failed'),
      );
    }
    return right(unit);
  }

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

/// A trivial fake — swapped in for the real `ChatRepositoryImpl` (same
/// rationale as [_FakeVaultRepository]/[_FakeAccountSettingsRepository]
/// replacing their own real implementations): `ChatScreen`'s own
/// `initState()` now calls `ChatCubit.init()` unconditionally on every
/// mount, which would otherwise hit the real `ApiClient`/`Dio` pipeline
/// (no mock server exists in this suite) the moment any test reaches
/// Home/Chat. Always resolves one pre-existing session with an empty
/// history, so `ChatCubit.init()` settles on [ChatReady] without ever
/// calling [createSession]/[sendMessage] — no test below exercises the
/// chat feature's own behavior (that's `chat_cubit_test.dart`'s job),
/// only that the real composition root reaches a real [ChatScreen].
class _FakeChatRepository implements ChatRepository {
  @override
  Future<Either<Failure, List<ChatSession>>> listSessions() async => right([
    const ChatSession(
      id: 'fake-session',
      title: '',
      persona: ChatPersona.analitico,
      userMessageCount: 0,
      lastUserMessageAt: null,
      createdAt: '2024-01-01T00:00:00.000Z',
      updatedAt: '2024-01-01T00:00:00.000Z',
    ),
  ]);

  @override
  Future<Either<Failure, ChatSession>> createSession() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, List<ChatMessage>>> listMessages(
    String sessionId,
  ) async => right(const []);

  @override
  Stream<Either<Failure, ChatStreamEvent>> sendMessage(
    String sessionId,
    String content,
  ) => const Stream.empty();

  @override
  Stream<Either<Failure, ChatStreamEvent>> retryMessage(
    String sessionId,
    String userMessageId,
  ) => const Stream.empty();

  @override
  Future<Either<Failure, ChatInsight?>> generateInsight(
    String sessionId, {
    required InsightTriggerType triggerType,
    required String triggerKey,
  }) async => throw UnimplementedError('not expected to be called');
}

/// spec-6-5 — wraps the real `testWidgets` so every test in this file
/// automatically closes `sl<ChatCubit>()` right after its own body
/// completes. See the identical override in `app_router_test.dart` for
/// the full rationale: `testWidgets`' own `!timersPending` invariant
/// check runs *inside* the test's own callback, before any
/// `addTearDown`/`tearDown` callback (including this registration's own
/// `dispose`, run via `resetCoreDependencies()` below) ever fires.
void testWidgets(String description, WidgetTesterCallback callback) {
  testWidgetsWithCleanup(
    description,
    callback,
    cleanup: () async {
      if (sl.isRegistered<ChatCubit>()) {
        await sl<ChatCubit>().close();
      }
    },
  );
}

/// Proves the one real production composition root — `CerneApp` resolving
/// `sl<AuthCubit>()`/`sl<SessionRepository>()`/`sl<VaultRepository>()`,
/// building the one `go_router` (Story 1.6; AD-14's vault gate), and
/// wrapping it with `ExpiryOverlayHost` — actually works end to end. Every
/// other test either stops at DI registration
/// (`bootstrap_integration_test.dart`) or supplies its own
/// `AuthCubit`/`onAuthenticated` (`auth_screen_test.dart`), so neither
/// exercises `main.dart`'s own wiring.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final fakeNativeStorage = <String, String>{};
  late FakePathProviderPlatform fakePathProvider;

  Future<dynamic> handleSecureStorageCall(MethodCall call) async {
    final args = call.arguments as Map<dynamic, dynamic>;
    switch (call.method) {
      case 'write':
        fakeNativeStorage[args['key'] as String] = args['value'] as String;
        return null;
      case 'read':
        return fakeNativeStorage[args['key'] as String];
      case 'delete':
        fakeNativeStorage.remove(args['key'] as String);
        return null;
      case 'containsKey':
        return fakeNativeStorage.containsKey(args['key'] as String);
      default:
        return null;
    }
  }

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          secureStorageChannel,
          handleSecureStorageCall,
        );
    // Story 3.1 — `setupCoreDependencies()` now also calls
    // `Hive.initFlutter()` (transitively via `hive_ce_flutter`), which
    // asks `path_provider` for the documents directory; faked the same
    // way the secure-storage channel above is.
    fakePathProvider = FakePathProviderPlatform();
    PathProviderPlatform.instance = fakePathProvider;

    await resetCoreDependencies();
    await setupCoreDependencies();
    // `setupCoreDependencies()` registers the real `VaultRepositoryImpl`
    // (backed by the actual `local_auth` plugin, with no platform channel
    // mocked here) — swapped for a fake pre-`unlocked` one so every
    // existing auth/session test case (which predates AD-14's vault gate)
    // is unaffected; a test that wants to exercise the vault gate itself
    // swaps this for its own locked fake.
    sl.unregister<VaultRepository>();
    sl.registerLazySingleton<VaultRepository>(
      () => _FakeVaultRepository(),
      dispose: (repository) => repository.dispose(),
    );
    // Story 2.4 — same rationale as the `VaultRepository` swap above:
    // `setupCoreDependencies()` also registers the real
    // `AccountSettingsRepositoryImpl` (backed by the real `ApiClient`/`Dio`
    // pipeline, no mock server here), swapped for a fake so `CerneApp`'s
    // boot-time `fetchBiometricEnabled()` call never reaches the network.
    sl.unregister<AccountSettingsRepository>();
    sl.registerLazySingleton<AccountSettingsRepository>(
      () => _FakeAccountSettingsRepository(),
      dispose: (repository) => repository.dispose(),
    );
    // spec-6-1 — same rationale as the two swaps above: `setupCoreDependencies()`
    // also registers the real `ChatCubit` (backed by the real
    // `ChatRepositoryImpl`/`ApiClient`/`Dio` pipeline), swapped for one backed
    // by `_FakeChatRepository` so reaching Home/Chat never hits the network.
    sl.unregister<ChatCubit>();
    // spec-6-5 — this registration's own `dispose` only runs via
    // `resetCoreDependencies()` in `tearDown()` below, which fires too
    // late to satisfy `testWidgets`' own `!timersPending` invariant check
    // (a bootstrapped ChatCubit now always starts a real
    // `_insightInactivityTimer`) — closed instead by the local
    // `testWidgets` override at the bottom of this file, which runs
    // before that check (see its own doc for why `addTearDown`/
    // `tearDown` can't).
    sl.registerLazySingleton<ChatCubit>(
      () => ChatCubit(
        _FakeChatRepository(),
        FakeConnectivityWatcher(),
        UnusedSaveChatMessageAsEntryUseCase(),
      ),
      // spec-6-5 — this file's own `testWidgets` override below already
      // closes `sl<ChatCubit>()` right after each test's body, before
      // `resetCoreDependencies()` (`sl.reset()`) in `tearDown()` would
      // otherwise dispose it a second time via this callback. Guarded
      // here (not just left to run twice) because a second `close()` on
      // an already-closed `Cubit` never resolves inside `flutter_test`'s
      // fake-async zone — its `await` needs a microtask flush that only
      // happens on a later `pump()`, and none happens once a test's body
      // has already returned — which froze every test in this file.
      dispose: (cubit) => cubit.isClosed ? null : cubit.close(),
    );
    // `ConfirmationDialog.isOpen` is a static single-overlay guard (shared
    // across every instance by design, Story 1.5) — reset it so one test's
    // unclosed dialog never leaks into the next.
    ConfirmationDialog.isOpen = false;
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    fakeNativeStorage.clear();
    // Closes the `entries` Hive box opened above — `resetCoreDependencies()`
    // only resets `get_it`'s registrations, not Hive's own global box
    // registry, and `Hive.openBox` silently returns the already-open box
    // (ignoring a new path) if it isn't closed first.
    await Hive.close();
    await resetCoreDependencies();
    // Review finding: without this, every test run leaks one orphaned
    // temp folder onto the dev machine/CI runner (`FakePathProviderPlatform`
    // creates real disk directories, not an in-memory fake).
    await fakePathProvider.cleanUp();
  });

  testWidgets(
    'CerneApp resolves the real AuthCubit and navigates to / (the real '
    'Home/Chat placeholder) once onAuthenticated fires',
    (tester) async {
      final mockAuthRepository = MockAuthRepository();
      when(
        () => mockAuthRepository.logIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => right(const AuthenticatedUser(id: 'u1', email: 'a@b.com')),
      );

      // Swaps only the repository, before AuthCubit's first resolution, so
      // CerneApp's own `sl<AuthCubit>()` lookup and the real
      // `SessionRepository.markAuthenticated()` run unchanged.
      sl.unregister<AuthRepository>();
      sl.registerLazySingleton<AuthRepository>(() => mockAuthRepository);

      await tester.pumpWidget(const CerneApp());
      // Lets the real `SessionRepository.restoreSession()` boot call (no
      // stored refresh token in the fake secure-storage channel, so it
      // resolves to `unauthenticated` with no network call) settle before
      // interacting with `AuthScreen`.
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail'),
        'a@b.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        'segredo123',
      );
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Bem-vindo de volta'), findsNothing);
    },
  );

  testWidgets(
    'CerneApp resolves the real AuthCubit and navigates to / once signup '
    'succeeds, with the toggle-to-signup path exercised through the real '
    'composition root (only the login path was covered here before)',
    (tester) async {
      final mockAuthRepository = MockAuthRepository();
      when(
        () => mockAuthRepository.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async =>
            right(const AuthenticatedUser(id: 'u2', email: 'nova@b.com')),
      );

      sl.unregister<AuthRepository>();
      sl.registerLazySingleton<AuthRepository>(() => mockAuthRepository);

      await tester.pumpWidget(const CerneApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Não tem conta? Criar conta'));
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail'),
        'nova@b.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        'segredo123',
      );
      await tester.tap(find.text('Criar conta'));
      await tester.pumpAndSettle();

      verify(
        () => mockAuthRepository.signUp(
          email: 'nova@b.com',
          password: 'segredo123',
        ),
      ).called(1);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Crie sua conta'), findsNothing);
    },
  );

  testWidgets('CerneApp lands on the Home/Chat placeholder when the session '
      'repository already reports authenticated, with no AuthScreen ever '
      'shown', (tester) async {
    final fakeSessionRepository = _FakeSessionRepository()
      ..setStatus(SessionStatus.authenticated);
    addTearDown(fakeSessionRepository.dispose);

    sl.unregister<SessionRepository>();
    sl.registerLazySingleton<SessionRepository>(() => fakeSessionRepository);

    await tester.pumpWidget(const CerneApp());
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('Entrar'), findsNothing);
  });

  testWidgets(
    'CerneApp lands on AuthScreen when the session repository reports '
    'unauthenticated',
    (tester) async {
      final fakeSessionRepository = _FakeSessionRepository()
        ..setStatus(SessionStatus.unauthenticated);
      addTearDown(fakeSessionRepository.dispose);

      sl.unregister<SessionRepository>();
      sl.registerLazySingleton<SessionRepository>(() => fakeSessionRepository);

      await tester.pumpWidget(const CerneApp());
      await tester.pumpAndSettle();

      expect(find.text('Entrar'), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);
    },
  );

  testWidgets(
    'BootSplashScreen stays blank below the 300ms threshold and shows a '
    'spinner once past it, while the session status is not yet known',
    (tester) async {
      final fakeSessionRepository = _FakeSessionRepository();
      addTearDown(fakeSessionRepository.dispose);

      sl.unregister<SessionRepository>();
      sl.registerLazySingleton<SessionRepository>(() => fakeSessionRepository);

      await tester.pumpWidget(const CerneApp());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump(const Duration(milliseconds: 299));
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump(const Duration(milliseconds: 2));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  group(
    'Story 1.5 — expired-session recovery overlay (now go_router-based)',
    () {
      testWidgets('an expired emission shows the overlay over the same screen '
          '(Home/Chat placeholder never replaced, stays visible under it)', (
        tester,
      ) async {
        final fakeSessionRepository = _FakeSessionRepository();
        addTearDown(fakeSessionRepository.dispose);
        sl.unregister<SessionRepository>();
        sl.registerLazySingleton<SessionRepository>(
          () => fakeSessionRepository,
        );

        await tester.pumpWidget(const CerneApp());
        fakeSessionRepository.setStatus(SessionStatus.authenticated);
        await tester.pumpAndSettle();

        expect(find.byType(ChatScreen), findsOneWidget);
        expect(find.text('Sessão expirada'), findsNothing);

        fakeSessionRepository.setStatus(SessionStatus.expired);
        await tester.pumpAndSettle();

        expect(find.text('Sessão expirada'), findsOneWidget);
        // The underlying screen is still mounted and visible underneath the
        // overlay — it was never navigated away from or rebuilt as a
        // different widget (Boundaries: Story 1.5 behavior unchanged).
        expect(find.byType(ChatScreen), findsOneWidget);
      });

      testWidgets(
        'a second expired emission while the overlay is already open never '
        'stacks a second dialog',
        (tester) async {
          final fakeSessionRepository = _FakeSessionRepository();
          addTearDown(fakeSessionRepository.dispose);
          sl.unregister<SessionRepository>();
          sl.registerLazySingleton<SessionRepository>(
            () => fakeSessionRepository,
          );

          await tester.pumpWidget(const CerneApp());
          fakeSessionRepository.setStatus(SessionStatus.authenticated);
          await tester.pumpAndSettle();

          fakeSessionRepository.setStatus(SessionStatus.expired);
          await tester.pumpAndSettle();
          expect(find.text('Sessão expirada'), findsOneWidget);

          fakeSessionRepository.setStatus(SessionStatus.expired);
          await tester.pumpAndSettle();

          expect(find.text('Sessão expirada'), findsOneWidget);
        },
      );

      testWidgets(
        '"Entrar novamente" dismisses the overlay and routes to /reauth '
        '(the biometric/PIN placeholder)',
        (tester) async {
          final fakeSessionRepository = _FakeSessionRepository();
          addTearDown(fakeSessionRepository.dispose);
          sl.unregister<SessionRepository>();
          sl.registerLazySingleton<SessionRepository>(
            () => fakeSessionRepository,
          );

          await tester.pumpWidget(const CerneApp());
          fakeSessionRepository.setStatus(SessionStatus.authenticated);
          await tester.pumpAndSettle();

          fakeSessionRepository.setStatus(SessionStatus.expired);
          await tester.pumpAndSettle();
          expect(find.text('Sessão expirada'), findsOneWidget);

          await tester.tap(find.text('Entrar novamente'));
          await tester.pumpAndSettle();

          expect(find.text('Sessão expirada'), findsNothing);
          expect(find.text('Biometria'), findsOneWidget);
        },
      );

      testWidgets(
        'after "Entrar novamente" is confirmed, a later rebuild while the '
        'session status is still expired does not reopen the overlay on top '
        'of the placeholder it already routed to',
        (tester) async {
          final fakeSessionRepository = _FakeSessionRepository();
          addTearDown(fakeSessionRepository.dispose);
          sl.unregister<SessionRepository>();
          sl.registerLazySingleton<SessionRepository>(
            () => fakeSessionRepository,
          );

          await tester.pumpWidget(const CerneApp());
          fakeSessionRepository.setStatus(SessionStatus.authenticated);
          await tester.pumpAndSettle();

          fakeSessionRepository.setStatus(SessionStatus.expired);
          await tester.pumpAndSettle();

          await tester.tap(find.text('Entrar novamente'));
          await tester.pumpAndSettle();
          expect(find.text('Biometria'), findsOneWidget);

          // Simulates a rebuild that isn't driven by a new stream event
          // while the session status is still `expired` — pumping the same
          // root widget again updates the existing `_CerneAppState` in
          // place (same type, no key) rather than remounting it, forcing
          // `build()` to re-run exactly as a parent rebuild would. Without
          // the overlay's own one-shot-per-episode guard, that re-run would
          // reopen it on top of the placeholder the user already navigated
          // to.
          await tester.pumpWidget(const CerneApp());
          await tester.pumpAndSettle();

          expect(find.text('Sessão expirada'), findsNothing);
          expect(find.text('Biometria'), findsOneWidget);
        },
      );

      testWidgets(
        'tapping "Entrar novamente" twice in quick succession before its '
        'exit fade settles does not throw and routes to /reauth only once',
        (tester) async {
          final fakeSessionRepository = _FakeSessionRepository();
          addTearDown(fakeSessionRepository.dispose);
          sl.unregister<SessionRepository>();
          sl.registerLazySingleton<SessionRepository>(
            () => fakeSessionRepository,
          );

          await tester.pumpWidget(const CerneApp());
          fakeSessionRepository.setStatus(SessionStatus.authenticated);
          await tester.pumpAndSettle();

          fakeSessionRepository.setStatus(SessionStatus.expired);
          await tester.pumpAndSettle();
          expect(find.text('Sessão expirada'), findsOneWidget);

          // `tapAt` the same screen offset twice, with only `pump()` (not
          // `pumpAndSettle()`) between taps, so the second one lands while
          // the dialog's own exit fade/teardown is still in flight — the
          // exact window `_reauthRouteRequested` guards against (code
          // review, Story 1.6). `tapAt` (rather than re-resolving
          // `find.text(...)`) tolerates the button no longer being present
          // by the second tap without failing the test on that alone.
          final confirmButtonCenter = tester.getCenter(
            find.text('Entrar novamente'),
          );
          await tester.tapAt(confirmButtonCenter);
          await tester.pump();
          await tester.tapAt(confirmButtonCenter);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('Biometria'), findsOneWidget);
        },
      );
    },
  );

  group(
    'AD-14 — VaultStatus gate composed ahead of SessionStatus (spec-2-1)',
    () {
      testWidgets('cold start stays on /vault (VaultLockScreen) until a fake '
          'authenticate() success flips VaultStatus to unlocked, at which '
          'point the existing SessionStatus logic takes over and routes to '
          'Home', (tester) async {
        final fakeVaultRepository = _FakeVaultRepository(
          initialStatus: VaultStatus.locked,
        );
        addTearDown(fakeVaultRepository.dispose);
        sl.unregister<VaultRepository>();
        sl.registerLazySingleton<VaultRepository>(() => fakeVaultRepository);

        final fakeSessionRepository = _FakeSessionRepository()
          ..setStatus(SessionStatus.authenticated);
        addTearDown(fakeSessionRepository.dispose);
        sl.unregister<SessionRepository>();
        sl.registerLazySingleton<SessionRepository>(
          () => fakeSessionRepository,
        );

        await tester.pumpWidget(const CerneApp());
        await tester.pumpAndSettle();

        // Still locked: the vault gate wins over the already-authenticated
        // session, and VaultLockScreen's own auto-triggered authenticate()
        // call (the fake defaults `authenticateSucceeds: false`) left it
        // that way.
        expect(find.byType(VaultLockScreen), findsOneWidget);
        expect(find.byType(ChatScreen), findsNothing);

        // Simulates the OS biometric prompt succeeding: flips VaultStatus
        // straight to unlocked (same effect `VaultRepositoryImpl.
        // authenticate()` would have), which the router's
        // `refreshListenable` picks up and re-runs `_redirect` with no
        // further vault gate in the way.
        fakeVaultRepository.setStatus(VaultStatus.unlocked);
        await tester.pumpAndSettle();

        expect(find.byType(ChatScreen), findsOneWidget);
        expect(find.byType(VaultLockScreen), findsNothing);
      });

      testWidgets(
        'biometric failure falls through to the real PinKeypad wiring '
        '(spec-2-2): the initial auto-attempt fails (authenticateSucceeds '
        'starts false) and shows the keypad, then entering 4 digits stores '
        'them as the new PIN, unlocks the vault and routes through to Home',
        (tester) async {
          final fakeVaultRepository = _FakeVaultRepository(
            initialStatus: VaultStatus.locked,
          );
          addTearDown(fakeVaultRepository.dispose);
          sl.unregister<VaultRepository>();
          sl.registerLazySingleton<VaultRepository>(() => fakeVaultRepository);

          final fakeSessionRepository = _FakeSessionRepository()
            ..setStatus(SessionStatus.authenticated);
          addTearDown(fakeSessionRepository.dispose);
          sl.unregister<SessionRepository>();
          sl.registerLazySingleton<SessionRepository>(
            () => fakeSessionRepository,
          );

          await tester.pumpWidget(const CerneApp());
          await tester.pumpAndSettle();

          // The initial auto-triggered authenticate() call used the fake's
          // default authenticateSucceeds == false, so the PIN keypad is now
          // visible (never a "Tentar novamente" biometric-retry affordance —
          // AC2) and the vault is still locked.
          expect(find.byType(VaultLockScreen), findsOneWidget);
          expect(find.text('Digite seu PIN'), findsOneWidget);
          expect(find.text('Tentar novamente'), findsNothing);

          // Drive the real PinKeypad wiring (_submitPin) rather than
          // setStatus directly — no PIN stored yet, so this first entry
          // becomes the stored PIN (Design Notes).
          for (final digit in '1234'.split('')) {
            await tester.tap(find.text(digit));
            await tester.pump();
          }
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pumpAndSettle();

          expect(find.byType(ChatScreen), findsOneWidget);
          expect(find.byType(VaultLockScreen), findsNothing);
        },
      );
    },
  );

  group('Story 2.4 — AccountSettingsRepository feeds VaultLockScreen through '
      'the real composition root', () {
    testWidgets(
      'currentBiometricEnabled: false (preference already fetched/changed '
      'before /vault builds) -> VaultLockScreen never auto-triggers '
      'authenticate(), shows the PIN keypad directly',
      (tester) async {
        final fakeVaultRepository = _FakeVaultRepository(
          initialStatus: VaultStatus.locked,
        );
        addTearDown(fakeVaultRepository.dispose);
        sl.unregister<VaultRepository>();
        sl.registerLazySingleton<VaultRepository>(() => fakeVaultRepository);

        final fakeAccountSettingsRepository = _FakeAccountSettingsRepository()
          ..setValue(false);
        addTearDown(fakeAccountSettingsRepository.dispose);
        sl.unregister<AccountSettingsRepository>();
        sl.registerLazySingleton<AccountSettingsRepository>(
          () => fakeAccountSettingsRepository,
        );

        await tester.pumpWidget(const CerneApp());
        await tester.pumpAndSettle();

        expect(find.byType(VaultLockScreen), findsOneWidget);
        expect(find.text('Digite seu PIN'), findsOneWidget);
        expect(
          find.text('Não foi possível reconhecer — digite seu PIN'),
          findsNothing,
        );

        // Entering the PIN still unlocks the vault normally — PIN remains
        // the access method regardless (Boundaries).
        for (final digit in '1234'.split('')) {
          await tester.tap(find.text(digit));
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(fakeVaultRepository.currentStatus, VaultStatus.unlocked);
      },
    );

    testWidgets('a boot fetch failure leaves currentBiometricEnabled unchanged '
        '(default true) -> VaultLockScreen still attempts biometric first, '
        'same as pre-2.4 behavior', (tester) async {
      final fakeVaultRepository = _FakeVaultRepository(
        initialStatus: VaultStatus.locked,
      );
      addTearDown(fakeVaultRepository.dispose);
      sl.unregister<VaultRepository>();
      sl.registerLazySingleton<VaultRepository>(() => fakeVaultRepository);

      final fakeAccountSettingsRepository = _FakeAccountSettingsRepository()
        ..fetchBiometricEnabledSucceeds = false;
      addTearDown(fakeAccountSettingsRepository.dispose);
      sl.unregister<AccountSettingsRepository>();
      sl.registerLazySingleton<AccountSettingsRepository>(
        () => fakeAccountSettingsRepository,
      );

      await tester.pumpWidget(const CerneApp());
      await tester.pumpAndSettle();

      // The fake's own `authenticateSucceeds` default is `false`, so a
      // biometric attempt was made and declined -> PIN keypad with the
      // biometric-failure band. Had `attemptBiometricFirst` wrongly been
      // `false` here, no such attempt would ever happen and this band
      // would never appear.
      expect(find.byType(VaultLockScreen), findsOneWidget);
      expect(
        find.text('Não foi possível reconhecer — digite seu PIN'),
        findsOneWidget,
      );
      expect(fakeAccountSettingsRepository.currentBiometricEnabled, isTrue);
    });
  });
}
