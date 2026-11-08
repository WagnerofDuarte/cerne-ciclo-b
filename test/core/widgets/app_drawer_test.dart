import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:fpdart/fpdart.dart' hide State;
import 'package:go_router/go_router.dart';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/widgets/app_drawer.dart';
import 'package:cerne/features/chat/domain/entities/chat_insight.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:cerne/features/chat/domain/entities/chat_stream_event.dart';
import 'package:cerne/features/chat/domain/repositories/chat_repository.dart';
import 'package:cerne/features/chat/presentation/cubit/chat_cubit.dart';
import 'package:cerne/features/chat/presentation/cubit/chat_state.dart';

import '../../support/fake_connectivity_watcher.dart';
import '../../support/testwidgets_with_cleanup.dart';
import '../../support/unused_save_chat_message_as_entry_use_case.dart';

const _sessionA = ChatSession(
  id: 'session-a',
  title: 'Primeira conversa',
  persona: ChatPersona.analitico,
  userMessageCount: 3,
  lastUserMessageAt: '2026-01-01T10:00:00Z',
  createdAt: '2026-01-01T09:00:00Z',
  updatedAt: '2026-01-01T10:00:00Z',
);

/// Deliberately the most recently `updatedAt` of the two, and an empty
/// `title` — `ChatCubit._bootstrap` reuses this one (Boundaries: "reuse
/// the most recent"), and its fallback label ("Nova conversa", Boundaries)
/// doubles as this suite's way of tapping the already-active row by text.
const _sessionB = ChatSession(
  id: 'session-b',
  title: '',
  persona: ChatPersona.analitico,
  userMessageCount: 0,
  lastUserMessageAt: null,
  createdAt: '2026-01-02T09:00:00Z',
  updatedAt: '2026-01-02T09:00:00Z',
);

/// A controllable fake — mirrors `chat_cubit_test.dart`'s own
/// `_FakeChatRepository`, scoped to what this drawer-focused suite needs:
/// `AppDrawer` only ever drives `ChatCubit.switchSession`/
/// `startNewSession` (and, indirectly, `ChatCubit.init()`'s own
/// bootstrap) — never `sendMessage`.
class _FakeChatRepository implements ChatRepository {
  Either<Failure, List<ChatSession>> listSessionsResult = right([
    _sessionA,
    _sessionB,
  ]);
  Either<Failure, ChatSession> createSessionResult = right(_sessionA);
  Either<Failure, List<ChatMessage>> listMessagesResult = right(const []);

  @override
  Future<Either<Failure, List<ChatSession>>> listSessions() async =>
      listSessionsResult;

  @override
  Future<Either<Failure, ChatSession>> createSession() async =>
      createSessionResult;

  @override
  Future<Either<Failure, List<ChatMessage>>> listMessages(
    String sessionId,
  ) async => listMessagesResult;

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

  // Story 8.4 — not exercised by this drawer-focused suite, same trivial
  // rationale this fake's other untouched members already follow.
  @override
  Future<Either<Failure, Unit>> clearLocalCache() async => right(unit);
}

/// Tiny standalone `GoRouter` — [AppDrawer] needs *some* router ancestor
/// to resolve `context.go(...)`, and — since spec-6-2 — a `ChatCubit`
/// ancestor too, provided here exactly the way `ChatScreen` provides it
/// in the real app (`BlocProvider<ChatCubit>.value`, Boundaries: "never a
/// second `sl<ChatCubit>()` inside `AppDrawer`"). This suite isn't
/// exercising the real app shell's redirect (that's `app_router_test.
/// dart`'s job).
GoRouter _buildTestRouter(ChatCubit cubit) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => BlocProvider<ChatCubit>.value(
          value: cubit,
          child: const Scaffold(drawer: AppDrawer(), body: SizedBox.shrink()),
        ),
      ),
      GoRoute(
        path: '/meus-registros',
        builder: (context, state) => const Text('Meus Registros Screen'),
      ),
      GoRoute(
        path: '/planos-de-acao',
        builder: (context, state) => const Text('Planos Screen'),
      ),
      GoRoute(
        path: '/configuracoes',
        builder: (context, state) => const Text('Config Screen'),
      ),
    ],
  );
}

Future<void> _openDrawer(WidgetTester tester) async {
  tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
  await tester.pumpAndSettle();
}

/// spec-6-5 — every [ChatCubit] this suite constructs (the shared one
/// from `setUp()`, plus any test-local one) is tracked here and closed
/// from the local `testWidgets` override below, right after each test's
/// own body completes. A bootstrapped `ChatCubit` now always starts a
/// real `_insightInactivityTimer`; the ordinary `addTearDown`/group-level
/// `tearDown()` pattern this suite already uses for other cleanup runs
/// too late to satisfy `testWidgets`' own `!timersPending` invariant
/// check — that check runs *inside* the test's own callback execution,
/// before any `addTearDown`/`tearDown` callback ever fires, regardless of
/// whether the cubit (and its Timer) was created in `setUp()` or mid-test
/// (`close()` cancels either way, so tracking covers both).
final List<ChatCubit> _cubitsPendingClose = [];

/// Wraps the real `testWidgets` so every test in this file automatically
/// closes every cubit [_cubitsPendingClose] collected during it.
void testWidgets(String description, WidgetTesterCallback callback) {
  testWidgetsWithCleanup(
    description,
    callback,
    cleanup: () async {
      for (final cubit in _cubitsPendingClose) {
        await cubit.close();
      }
      _cubitsPendingClose.clear();
    },
  );
}

/// Tela 3 — Menu lateral. Covers the static chrome (header, nav items,
/// width token — unchanged since Story 1.6) plus spec-6-2's "CONVERSAS"
/// section and its two entry points (`switchSession`/`startNewSession`),
/// driven through the exact `BlocProvider<ChatCubit>` instance the real
/// `ChatScreen` would provide.
void main() {
  late _FakeChatRepository fakeRepository;
  late FakeConnectivityWatcher fakeConnectivityWatcher;
  late ChatCubit cubit;

  setUp(() async {
    fakeRepository = _FakeChatRepository();
    fakeConnectivityWatcher = FakeConnectivityWatcher();
    cubit = ChatCubit(
      fakeRepository,
      fakeConnectivityWatcher,
      UnusedSaveChatMessageAsEntryUseCase(),
    );
    await cubit.init();
    _cubitsPendingClose.add(cubit);
  });

  tearDown(() async {
    // spec-6-5 — `cubit` is already closed by this file's own `testWidgets`
    // override above, which has to run before this `tearDown` (see that
    // override's doc). Calling `Cubit.close()` a second time on an
    // already-closed instance never resolves inside `flutter_test`'s
    // fake-async zone — its `await` depends on a microtask that's only
    // flushed by a later `pump()`, and none happens once the test body has
    // already returned — which froze this entire suite until guarded here.
    if (!cubit.isClosed) {
      await cubit.close();
    }
    await fakeConnectivityWatcher.close();
  });

  testWidgets(
    'header shows a generic avatar + static label, no real identity',
    (tester) async {
      final router = _buildTestRouter(cubit);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _openDrawer(tester);

      expect(find.text('Usuário'), findsOneWidget);
      expect(find.text('U'), findsOneWidget);
    },
  );

  testWidgets('CONVERSAS section lists every bootstrapped session (title + '
      'timestamp), with an empty title falling back to "Nova conversa"', (
    tester,
  ) async {
    final router = _buildTestRouter(cubit);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _openDrawer(tester);

    expect(find.text('CONVERSAS'), findsOneWidget);
    expect(find.text('Primeira conversa'), findsOneWidget);
    expect(find.text('Nova conversa'), findsOneWidget);
  });

  testWidgets(
    'review finding: a session with a malformed updatedAt never crashes '
    'the CONVERSAS sort — it still renders, sorted defensively instead '
    'of throwing a FormatException',
    (tester) async {
      final crashFakeRepository = _FakeChatRepository();
      crashFakeRepository.listSessionsResult = right([
        _sessionA,
        const ChatSession(
          id: 'session-bad',
          title: 'Conversa corrompida',
          persona: ChatPersona.analitico,
          userMessageCount: 0,
          lastUserMessageAt: null,
          createdAt: 'not-a-date',
          updatedAt: 'not-a-date',
        ),
      ]);
      final crashCubit = ChatCubit(
        crashFakeRepository,
        FakeConnectivityWatcher(),
        UnusedSaveChatMessageAsEntryUseCase(),
      );
      _cubitsPendingClose.add(crashCubit);
      await crashCubit.init();

      final router = _buildTestRouter(crashCubit);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _openDrawer(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('CONVERSAS'), findsOneWidget);
      expect(find.text('Primeira conversa'), findsOneWidget);
      expect(find.text('Conversa corrompida'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping a past session switches ChatCubit to it and closes the drawer',
    (tester) async {
      final router = _buildTestRouter(cubit);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _openDrawer(tester);

      // Bootstrap reused session-b (most recent by updatedAt) — tap the
      // other one to switch away from it.
      expect((cubit.state as ChatReady).sessionId, 'session-b');
      await tester.tap(find.text('Primeira conversa'));
      await tester.pumpAndSettle();

      expect(find.byType(AppDrawer), findsNothing);
      expect(router.state.uri.toString(), '/');
      expect((cubit.state as ChatReady).sessionId, 'session-a');
    },
  );

  testWidgets(
    'tapping the already-active session is a no-op reload — drawer just '
    'closes, nothing else changes',
    (tester) async {
      final router = _buildTestRouter(cubit);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _openDrawer(tester);

      expect((cubit.state as ChatReady).sessionId, 'session-b');
      await tester.tap(find.text('Nova conversa'));
      await tester.pumpAndSettle();

      expect(find.byType(AppDrawer), findsNothing);
      expect((cubit.state as ChatReady).sessionId, 'session-b');
    },
  );

  testWidgets('tapping "Novo Chat" while online creates and switches to a new, '
      'empty session, then closes the drawer', (tester) async {
    const created = ChatSession(
      id: 'session-new',
      title: '',
      persona: ChatPersona.analitico,
      userMessageCount: 0,
      lastUserMessageAt: null,
      createdAt: '2026-01-03T00:00:00Z',
      updatedAt: '2026-01-03T00:00:00Z',
    );
    fakeRepository.createSessionResult = right(created);

    final router = _buildTestRouter(cubit);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _openDrawer(tester);

    await tester.tap(find.text('Novo Chat'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDrawer), findsNothing);
    expect(router.state.uri.toString(), '/');
    final state = cubit.state as ChatReady;
    expect(state.sessionId, 'session-new');
    expect(state.messages, isEmpty);
  });

  testWidgets('tapping "Novo Chat" while offline leaves the current session '
      'untouched, closes the drawer, and shows an error SnackBar (I/O '
      'matrix: "New session offline")', (tester) async {
    fakeRepository.createSessionResult = left(
      const Failure.networkOffline(message: 'Sem conexão'),
    );

    final router = _buildTestRouter(cubit);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _openDrawer(tester);

    final sessionIdBefore = (cubit.state as ChatReady).sessionId;

    await tester.tap(find.text('Novo Chat'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDrawer), findsNothing);
    expect((cubit.state as ChatReady).sessionId, sessionIdBefore);
    expect(find.text('Sem conexão'), findsOneWidget);
  });

  group('spec-6-3 — "Novo Chat" disables while ChatReady.isOffline', () {
    // Deliberately builds its own `ChatCubit`/`FakeConnectivityWatcher`
    // pair inside each test body below, rather than reusing the shared
    // `cubit`/`fakeConnectivityWatcher` the outer `setUp()` constructs —
    // `ChatCubit`'s constructor subscribes to the watcher's stream
    // immediately, and a subscription created inside an *async* `setUp()`
    // callback is registered in a different zone than the one
    // `tester.pumpAndSettle()` drains for a `testWidgets` body (a known
    // `flutter_test` gotcha: `setUp()`'s own async work runs outside
    // `TestWidgetsFlutterBinding`'s per-test zone), so a later
    // `watcher.emit(...)` call's effect on the widget tree would never be
    // observed by `pumpAndSettle()` within the test body. Constructing
    // both inside the test body itself keeps everything in the one zone
    // `pumpAndSettle()` actually watches.
    Future<({ChatCubit cubit, FakeConnectivityWatcher watcher})> boot(
      WidgetTester tester,
    ) async {
      final repository = _FakeChatRepository();
      final watcher = FakeConnectivityWatcher();
      final localCubit = ChatCubit(
        repository,
        watcher,
        UnusedSaveChatMessageAsEntryUseCase(),
      );
      await localCubit.init();
      _cubitsPendingClose.add(localCubit);
      addTearDown(watcher.close);

      final router = _buildTestRouter(localCubit);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _openDrawer(tester);
      return (cubit: localCubit, watcher: watcher);
    }

    InkWell novoChatInkWell(WidgetTester tester) => tester.widget<InkWell>(
      find.ancestor(of: find.text('Novo Chat'), matching: find.byType(InkWell)),
    );

    Opacity novoChatOpacity(WidgetTester tester) => tester.widget<Opacity>(
      find.ancestor(of: find.text('Novo Chat'), matching: find.byType(Opacity)),
    );

    testWidgets('"Novo Chat" disables (dimmed, no tap handler) once the '
        'ConnectivityWatcher reports offline', (tester) async {
      final booted = await boot(tester);
      expect(novoChatOpacity(tester).opacity, 1);

      booted.watcher.emit(false);
      await tester.pumpAndSettle();

      expect(novoChatOpacity(tester).opacity, lessThan(1));
      expect(novoChatInkWell(tester).onTap, isNull);

      // Tapping it while disabled does nothing — never reaches
      // ChatCubit.startNewSession() at all.
      final sessionIdBefore = (booted.cubit.state as ChatReady).sessionId;
      await tester.tap(find.text('Novo Chat'));
      await tester.pumpAndSettle();

      expect(find.byType(AppDrawer), findsOneWidget);
      expect((booted.cubit.state as ChatReady).sessionId, sessionIdBefore);
    });

    testWidgets(
      '"Novo Chat" re-enables automatically once connectivity returns',
      (tester) async {
        final booted = await boot(tester);

        booted.watcher.emit(false);
        await tester.pumpAndSettle();
        expect(novoChatInkWell(tester).onTap, isNull);

        booted.watcher.emit(true);
        await tester.pumpAndSettle();

        expect(novoChatInkWell(tester).onTap, isNotNull);
      },
    );
  });

  testWidgets(
    'tapping "Meus Registros" closes the drawer and navigates there',
    (tester) async {
      final router = _buildTestRouter(cubit);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _openDrawer(tester);

      await tester.tap(find.text('Meus Registros'));
      await tester.pumpAndSettle();

      expect(find.byType(AppDrawer), findsNothing);
      expect(router.state.uri.toString(), '/meus-registros');
      expect(find.text('Meus Registros Screen'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping "Planos de Ação" closes the drawer and navigates there',
    (tester) async {
      final router = _buildTestRouter(cubit);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _openDrawer(tester);

      await tester.tap(find.text('Planos de Ação'));
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/planos-de-acao');
    },
  );

  testWidgets('tapping "Configurações" closes the drawer and navigates there', (
    tester,
  ) async {
    final router = _buildTestRouter(cubit);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _openDrawer(tester);

    await tester.tap(find.text('Configurações'));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/configuracoes');
  });

  testWidgets('drawer width matches the design token', (tester) async {
    final router = _buildTestRouter(cubit);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _openDrawer(tester);

    final drawer = tester.widget<Drawer>(find.byType(Drawer));
    expect(drawer.width, DesignTokens.drawerWidth);
  });
}
