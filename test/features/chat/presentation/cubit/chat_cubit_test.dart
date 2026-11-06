import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:cerne/features/chat/domain/entities/chat_stream_event.dart';
import 'package:cerne/features/chat/domain/repositories/chat_repository.dart';
import 'package:cerne/features/chat/presentation/cubit/chat_cubit.dart';
import 'package:cerne/features/chat/presentation/cubit/chat_state.dart';

const _session = ChatSession(
  id: 's1',
  title: '',
  persona: ChatPersona.analitico,
  userMessageCount: 0,
  lastUserMessageAt: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

/// A controllable fake — this suite drives `sendMessage`'s own SSE-shaped
/// stream event by event (rather than mocktail-stubbing a fixed `Stream`),
/// so each test can assert the cubit's state *between* events (e.g. right
/// after one `token` but before `done`).
class _FakeChatRepository implements ChatRepository {
  Either<Failure, List<ChatSession>> listSessionsResult = right([_session]);
  Either<Failure, ChatSession> createSessionResult = right(_session);
  Either<Failure, List<ChatMessage>> listMessagesResult = right(const []);

  StreamController<Either<Failure, ChatStreamEvent>>? lastSendController;
  final List<({String sessionId, String content})> sendMessageCalls = [];

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
  ) {
    sendMessageCalls.add((sessionId: sessionId, content: content));
    final controller = StreamController<Either<Failure, ChatStreamEvent>>();
    lastSendController = controller;
    return controller.stream;
  }
}

void main() {
  late _FakeChatRepository fakeRepository;
  late ChatCubit cubit;

  setUp(() {
    fakeRepository = _FakeChatRepository();
    cubit = ChatCubit(fakeRepository);
  });

  tearDown(() => cubit.close());

  group('init() — bootstrap', () {
    test(
      'an existing session is reused (the most recent by updatedAt) and its '
      'history loads -> ChatReady',
      () async {
        final older = const ChatSession(
          id: 'older',
          title: '',
          persona: ChatPersona.analitico,
          userMessageCount: 0,
          lastUserMessageAt: null,
          createdAt: '2026-01-01T00:00:00Z',
          updatedAt: '2026-01-01T00:00:00Z',
        );
        final newer = const ChatSession(
          id: 'newer',
          title: '',
          persona: ChatPersona.analitico,
          userMessageCount: 0,
          lastUserMessageAt: null,
          createdAt: '2026-01-02T00:00:00Z',
          updatedAt: '2026-01-02T00:00:00Z',
        );
        fakeRepository.listSessionsResult = right([older, newer]);
        fakeRepository.listMessagesResult = right([
          const ChatMessage(
            id: 'm1',
            sessionId: 'newer',
            role: ChatMessageRole.user,
            content: 'oi',
            seq: 0,
            status: ChatMessageStatus.complete,
            retryCount: 0,
            createdAt: '2026-01-02T00:00:00Z',
          ),
        ]);

        await cubit.init();

        final state = cubit.state;
        expect(state, isA<ChatReady>());
        final ready = state as ChatReady;
        expect(ready.sessionId, 'newer');
        expect(ready.messages, hasLength(1));
        expect(ready.messages.single.content, 'oi');
      },
    );

    test(
      'no existing session -> silently creates exactly one, reused for the '
      'resulting ChatReady.sessionId',
      () async {
        fakeRepository.listSessionsResult = right(const []);
        fakeRepository.createSessionResult = right(_session);

        await cubit.init();

        expect(cubit.state, isA<ChatReady>());
        expect((cubit.state as ChatReady).sessionId, _session.id);
      },
    );

    test(
      'a bootstrap failure (chat-sessions-list) -> ChatBootstrapError, not '
      'an infinite spinner',
      () async {
        fakeRepository.listSessionsResult = left(
          const Failure.networkOffline(message: 'offline'),
        );

        await cubit.init();

        expect(cubit.state, isA<ChatBootstrapError>());
        expect(
          (cubit.state as ChatBootstrapError).failure,
          isA<NetworkOffline>(),
        );
      },
    );

    test(
      'a history-fetch failure after a successful session resolve -> '
      'ChatBootstrapError too',
      () async {
        fakeRepository.listMessagesResult = left(
          const Failure.networkTimeout(message: 'timeout'),
        );

        await cubit.init();

        expect(cubit.state, isA<ChatBootstrapError>());
      },
    );

    test('calling init() again once already ChatReady is a no-op', () async {
      await cubit.init();
      expect(cubit.state, isA<ChatReady>());

      // A second listSessions()/createSession() call would throw via the
      // fake if it were actually invoked again — asserting on call count
      // instead, so this test demonstrates the guard rather than crashing
      // past it.
      var listSessionsCallCount = 0;
      final countingRepository = _CountingChatRepository(
        fakeRepository,
        onListSessions: () => listSessionsCallCount++,
      );
      final secondCubit = ChatCubit(countingRepository);
      await secondCubit.init();
      await secondCubit.init();
      expect(listSessionsCallCount, 1);
      await secondCubit.close();
    });

    test(
      'review finding: two concurrent init() calls (before the first '
      'resolves) only bootstrap once and only create one session, never '
      'two — Boundaries: "silently ensure one Chat Session exists"',
      () async {
        fakeRepository.listSessionsResult = right(const []);
        var createSessionCallCount = 0;
        final countingRepository = _CountingChatRepository(
          fakeRepository,
          onCreateSession: () => createSessionCallCount++,
        );
        final secondCubit = ChatCubit(countingRepository);

        final first = secondCubit.init();
        final second = secondCubit.init();
        await Future.wait([first, second]);

        expect(createSessionCallCount, 1);
        expect(secondCubit.state, isA<ChatReady>());
        await secondCubit.close();
      },
    );
  });

  group('switchSession()/startNewSession() — spec-6-2', () {
    // Deliberately *older* than `_session` (updatedAt 2026-01-01) so
    // `_bootstrap`'s own "reuse the most recent" rule settles on
    // `_session` — every test below then genuinely switches *to*
    // `otherSession`, rather than a no-op (it would otherwise already be
    // the active one).
    const otherSession = ChatSession(
      id: 's2',
      title: 'Outra conversa',
      persona: ChatPersona.analitico,
      userMessageCount: 1,
      lastUserMessageAt: '2025-12-31T00:00:00Z',
      createdAt: '2025-12-31T00:00:00Z',
      updatedAt: '2025-12-31T00:00:00Z',
    );

    setUp(() async {
      fakeRepository.listSessionsResult = right([_session, otherSession]);
      await cubit.init();
    });

    test(
      'I/O matrix "Switch session": fetches the target session\'s own '
      'history via listMessages and makes it active',
      () async {
        fakeRepository.listMessagesResult = right([
          const ChatMessage(
            id: 'm-s2',
            sessionId: 's2',
            role: ChatMessageRole.user,
            content: 'oi de novo',
            seq: 0,
            status: ChatMessageStatus.complete,
            retryCount: 0,
            createdAt: '2026-01-02T00:00:00Z',
          ),
        ]);

        final result = await cubit.switchSession('s2');

        expect(result.isRight(), isTrue);
        final ready = cubit.state as ChatReady;
        expect(ready.sessionId, 's2');
        expect(ready.messages, hasLength(1));
        expect(ready.messages.single.content, 'oi de novo');
        // The bootstrapped session list is carried over untouched.
        expect(ready.sessions, [_session, otherSession]);
      },
    );

    test(
      'I/O matrix "Switch to already-active session": a no-op Right, no '
      're-fetch, state object unchanged',
      () async {
        final before = cubit.state as ChatReady;

        final result = await cubit.switchSession(before.sessionId);

        expect(result.isRight(), isTrue);
        expect(cubit.state, same(before));
      },
    );

    test(
      'a switchSession failure surfaces as Left, current session stays '
      'active',
      () async {
        fakeRepository.listMessagesResult = left(
          const Failure.networkTimeout(message: 'timeout'),
        );
        final before = cubit.state as ChatReady;

        final result = await cubit.switchSession('s2');

        expect(result.isLeft(), isTrue);
        expect((cubit.state as ChatReady).sessionId, before.sessionId);
      },
    );

    test(
      'Design Notes/Boundaries: switching to a session restores the '
      'scroll offset last recorded for it via recordScrollOffset, or '
      'null (ChatScreen\'s own cue to jump to the bottom) if none was '
      'ever recorded',
      () async {
        cubit.recordScrollOffset('s2', 123.0);

        final result = await cubit.switchSession('s2');

        expect(result.isRight(), isTrue);
        expect((cubit.state as ChatReady).restoreScrollOffset, 123.0);

        // Switching back to 's1' (never recorded) falls back to null.
        final backResult = await cubit.switchSession('s1');
        expect(backResult.isRight(), isTrue);
        expect((cubit.state as ChatReady).restoreScrollOffset, isNull);
      },
    );

    test(
      'I/O matrix "New session online": createSession() succeeds -> a '
      'new, empty session becomes active, prepended to sessions',
      () async {
        const created = ChatSession(
          id: 's3',
          title: '',
          persona: ChatPersona.analitico,
          userMessageCount: 0,
          lastUserMessageAt: null,
          createdAt: '2026-01-03T00:00:00Z',
          updatedAt: '2026-01-03T00:00:00Z',
        );
        fakeRepository.createSessionResult = right(created);
        final before = cubit.state as ChatReady;

        final result = await cubit.startNewSession();

        expect(result.isRight(), isTrue);
        final ready = cubit.state as ChatReady;
        expect(ready.sessionId, 's3');
        expect(ready.messages, isEmpty);
        expect(ready.sessions, [created, ...before.sessions]);
      },
    );

    test(
      'I/O matrix "New session offline": createSession() resolves '
      'Left(networkOffline) -> surfaced as Left, current session (and '
      'its sessions list) left completely untouched',
      () async {
        final before = cubit.state as ChatReady;
        fakeRepository.createSessionResult = left(
          const Failure.networkOffline(message: 'offline'),
        );

        final result = await cubit.startNewSession();

        expect(result.isLeft(), isTrue);
        result.match(
          (failure) => expect(failure, isA<NetworkOffline>()),
          (_) => fail('expected a Left'),
        );
        expect(cubit.state, same(before));
      },
    );

    test(
      'review finding "Cross-session stream leakage": switchSession '
      'cancels an in-flight send\'s subscription first, so the old '
      'sendMessage() call resolves promptly and a late event from the '
      'now-orphaned stream never reaches the cubit at all',
      () async {
        final sendFuture = cubit.sendMessage('oi');
        await Future<void>.delayed(Duration.zero);
        expect((cubit.state as ChatReady).isSending, isTrue);
        final oldController = fakeRepository.lastSendController!;

        fakeRepository.listMessagesResult = right(const []);
        await cubit.switchSession('s2');

        // Without the fix, nothing cancels `_sendSubscription`/completes
        // `_sendCompleter`, so this would hang until `oldController` is
        // closed (which this test deliberately never does) — the
        // `timeout` turns that hang into a clear failure instead of a
        // stuck test run.
        await sendFuture.timeout(const Duration(milliseconds: 500));

        final afterSwitch = cubit.state as ChatReady;
        expect(afterSwitch.sessionId, 's2');
        expect(afterSwitch.isSending, isFalse);

        // A genuinely cancelled subscription never delivers another
        // callback at all (Dart's own `StreamSubscription.cancel()`
        // contract) — `same()` (identity, not equality) catches even a
        // content-equivalent spurious re-emit, which `_applyStreamEvent`/
        // `_finishSending` would otherwise still produce via `copyWith`
        // despite the orphaned event's id never matching anything in the
        // newly active session.
        final beforeLateEvent = cubit.state;
        oldController.add(right(const ChatTokenEvent('late token')));
        oldController.add(right(const ChatDoneEvent()));
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state, same(beforeLateEvent));
      },
    );

    test(
      'review finding "Cross-session stream leakage": startNewSession '
      'cancels an in-flight send\'s subscription too, before creating '
      'the new session',
      () async {
        final sendFuture = cubit.sendMessage('oi');
        await Future<void>.delayed(Duration.zero);
        final oldController = fakeRepository.lastSendController!;

        const created = ChatSession(
          id: 's3',
          title: '',
          persona: ChatPersona.analitico,
          userMessageCount: 0,
          lastUserMessageAt: null,
          createdAt: '2026-01-03T00:00:00Z',
          updatedAt: '2026-01-03T00:00:00Z',
        );
        fakeRepository.createSessionResult = right(created);

        await cubit.startNewSession();
        await sendFuture.timeout(const Duration(milliseconds: 500));

        expect((cubit.state as ChatReady).sessionId, 's3');
        final beforeLateEvent = cubit.state;
        oldController.add(right(const ChatTokenEvent('late token')));
        oldController.add(right(const ChatDoneEvent()));
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state, same(beforeLateEvent));
        expect((cubit.state as ChatReady).sessionId, 's3');
      },
    );
  });

  group('sendMessage() — the 3 visible message states', () {
    setUp(() async {
      await cubit.init();
    });

    test(
      'optimistic send appends a complete user bubble and a streaming AI '
      'bubble immediately',
      () async {
        final future = cubit.sendMessage('Olá, tudo bem?');
        await Future<void>.delayed(Duration.zero);

        final ready = cubit.state as ChatReady;
        expect(ready.messages, hasLength(2));
        expect(ready.messages[0].role, ChatMessageRole.user);
        expect(ready.messages[0].content, 'Olá, tudo bem?');
        expect(ready.messages[0].status, ChatMessageStatus.complete);
        expect(ready.messages[1].role, ChatMessageRole.assistant);
        expect(ready.messages[1].content, '');
        expect(ready.messages[1].status, ChatMessageStatus.streaming);

        fakeRepository.lastSendController!.close();
        await future;
      },
    );

    test(
      'happy path: token deltas append progressively, done finalizes to '
      'complete',
      () async {
        final future = cubit.sendMessage('oi');
        await Future<void>.delayed(Duration.zero);
        final controller = fakeRepository.lastSendController!;

        controller.add(right(const ChatTokenEvent('Olá')));
        await Future<void>.delayed(Duration.zero);
        var aiMessage = (cubit.state as ChatReady).messages[1];
        expect(aiMessage.content, 'Olá');
        expect(aiMessage.status, ChatMessageStatus.streaming);

        controller.add(right(const ChatTokenEvent('!')));
        await Future<void>.delayed(Duration.zero);
        aiMessage = (cubit.state as ChatReady).messages[1];
        expect(aiMessage.content, 'Olá!');

        controller.add(right(const ChatDoneEvent()));
        await controller.close();
        await future;

        aiMessage = (cubit.state as ChatReady).messages[1];
        expect(aiMessage.content, 'Olá!');
        expect(aiMessage.status, ChatMessageStatus.complete);
      },
    );

    test(
      'mid-stream drop: partial text is never cleared, status becomes '
      'failed, no exception escapes the cubit',
      () async {
        final future = cubit.sendMessage('oi');
        await Future<void>.delayed(Duration.zero);
        final controller = fakeRepository.lastSendController!;

        controller.add(right(const ChatTokenEvent('resposta parcial')));
        await Future<void>.delayed(Duration.zero);
        // The connection drops — the repository stream closes with no
        // done/error event, mirroring `ChatRemoteDataSource`'s own
        // trailing-NetworkTimeout emission for this exact scenario.
        controller.add(left(const Failure.networkTimeout(message: 'drop')));
        await controller.close();
        await future;

        final aiMessage = (cubit.state as ChatReady).messages[1];
        expect(aiMessage.content, 'resposta parcial');
        expect(aiMessage.status, ChatMessageStatus.failed);
      },
    );

    test(
      'in-band error event: marks the bubble failed via the mapped '
      'Failure, text untouched',
      () async {
        final future = cubit.sendMessage('oi');
        await Future<void>.delayed(Duration.zero);
        final controller = fakeRepository.lastSendController!;

        controller.add(right(const ChatTokenEvent('algo')));
        controller.add(left(const Failure.rateLimited(message: 'slow down')));
        await controller.close();
        await future;

        final aiMessage = (cubit.state as ChatReady).messages[1];
        expect(aiMessage.content, 'algo');
        expect(aiMessage.status, ChatMessageStatus.failed);
      },
    );

    test(
      'send while offline: the AI bubble is marked failed immediately, no '
      'text ever streamed in (still never cleared — just empty)',
      () async {
        final future = cubit.sendMessage('oi');
        await Future<void>.delayed(Duration.zero);
        final controller = fakeRepository.lastSendController!;

        controller.add(
          left(const Failure.networkOffline(message: 'offline')),
        );
        await controller.close();
        await future;

        final aiMessage = (cubit.state as ChatReady).messages[1];
        expect(aiMessage.content, '');
        expect(aiMessage.status, ChatMessageStatus.failed);
      },
    );

    test('a blank (whitespace-only) message is never sent', () async {
      await cubit.sendMessage('   ');

      expect((cubit.state as ChatReady).messages, isEmpty);
      expect(fakeRepository.sendMessageCalls, isEmpty);
    });

    test(
      'a second sendMessage() call while one AI bubble is still streaming '
      'is a no-op (never races two concurrent sends)',
      () async {
        final firstFuture = cubit.sendMessage('primeira');
        await Future<void>.delayed(Duration.zero);
        expect(fakeRepository.sendMessageCalls, hasLength(1));

        await cubit.sendMessage('segunda');
        expect(fakeRepository.sendMessageCalls, hasLength(1));

        fakeRepository.lastSendController!.close();
        await firstFuture;
      },
    );
  });

  test(
    'review finding: a message restored from history with a persisted '
    '`streaming` status (left over from an earlier dropped response) '
    'never permanently disables the composer — the send-in-flight guard '
    'must not be derived from scanning loaded messages\' status',
    () async {
      final staleRepository = _FakeChatRepository();
      staleRepository.listMessagesResult = right([
        const ChatMessage(
          id: 'stale',
          sessionId: 's1',
          role: ChatMessageRole.assistant,
          content: 'metade de uma resposta',
          seq: 0,
          status: ChatMessageStatus.streaming,
          retryCount: 0,
          createdAt: '2026-01-01T00:00:00Z',
        ),
      ]);
      final staleCubit = ChatCubit(staleRepository);
      await staleCubit.init();
      expect(staleCubit.state, isA<ChatReady>());

      // Not awaited: `_FakeChatRepository.sendMessage`'s controller never
      // closes on its own, same reason every other sendMessage() test in
      // this file awaits a zero-duration delay instead of the call
      // itself before asserting.
      unawaited(staleCubit.sendMessage('nova mensagem'));
      await Future<void>.delayed(Duration.zero);

      expect(staleRepository.sendMessageCalls, hasLength(1));
      staleRepository.lastSendController!.close();
      await staleCubit.close();
    },
  );
}

/// A thin wrapper used only by the "calling init() again is a no-op" test
/// above, to count [listSessions] calls without mocktail.
class _CountingChatRepository implements ChatRepository {
  _CountingChatRepository(
    this._delegate, {
    this.onListSessions,
    this.onCreateSession,
  });

  final ChatRepository _delegate;
  final void Function()? onListSessions;
  final void Function()? onCreateSession;

  @override
  Future<Either<Failure, List<ChatSession>>> listSessions() async {
    onListSessions?.call();
    return _delegate.listSessions();
  }

  @override
  Future<Either<Failure, ChatSession>> createSession() async {
    onCreateSession?.call();
    return _delegate.createSession();
  }

  @override
  Future<Either<Failure, List<ChatMessage>>> listMessages(String sessionId) =>
      _delegate.listMessages(sessionId);

  @override
  Stream<Either<Failure, ChatStreamEvent>> sendMessage(
    String sessionId,
    String content,
  ) => _delegate.sendMessage(sessionId, content);
}
