import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/chat/domain/entities/bookmark_state.dart';
import 'package:cerne/features/chat/domain/entities/chat_insight.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:cerne/features/chat/domain/entities/chat_stream_event.dart';
import 'package:cerne/features/chat/domain/repositories/chat_repository.dart';
import 'package:cerne/features/chat/presentation/cubit/chat_cubit.dart';
import 'package:cerne/features/chat/presentation/cubit/chat_state.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/usecases/save_chat_message_as_entry_use_case.dart';

import '../../../../support/fake_connectivity_watcher.dart';

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

  StreamController<Either<Failure, ChatStreamEvent>>? lastRetryController;
  final List<({String sessionId, String userMessageId})> retryMessageCalls = [];

  /// spec-6-5 — a `Completer`-per-call fake, same shape
  /// `_FakeSaveChatMessageAsEntryUseCase` already uses below: lets a test
  /// resolve a specific call whenever it chooses, so it can assert on the
  /// cubit's state *before* the fire-and-forget call resolves (the window
  /// having already reset/reopened by then) as well as after.
  final List<
    ({String sessionId, InsightTriggerType triggerType, String triggerKey})
  >
  generateInsightCalls = [];
  final List<Completer<Either<Failure, ChatInsight?>>> _insightCompleters = [];

  @override
  Future<Either<Failure, ChatInsight?>> generateInsight(
    String sessionId, {
    required InsightTriggerType triggerType,
    required String triggerKey,
  }) {
    generateInsightCalls.add((
      sessionId: sessionId,
      triggerType: triggerType,
      triggerKey: triggerKey,
    ));
    final completer = Completer<Either<Failure, ChatInsight?>>();
    _insightCompleters.add(completer);
    return completer.future;
  }

  void resolveInsight(int callIndex, Either<Failure, ChatInsight?> result) {
    _insightCompleters[callIndex].complete(result);
  }

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

  @override
  Stream<Either<Failure, ChatStreamEvent>> retryMessage(
    String sessionId,
    String userMessageId,
  ) {
    retryMessageCalls.add((sessionId: sessionId, userMessageId: userMessageId));
    final controller = StreamController<Either<Failure, ChatStreamEvent>>();
    lastRetryController = controller;
    return controller.stream;
  }

  // Story 8.4 — not exercised by this suite, same trivial rationale this
  // fake's other untouched members already follow.
  @override
  Future<Either<Failure, Unit>> clearLocalCache() async => right(unit);
}

/// spec-6-4 — a controllable fake, same `Completer`-per-call shape
/// `pending_entry_write_tracker_test.dart`'s own `_FakeEntriesRepository`
/// already uses: lets a test resolve a call whenever it chooses (to
/// observe the `saving` state in between), or throw synchronously (I/O
/// matrix: "Side-effect throws").
class _FakeSaveChatMessageAsEntryUseCase
    implements SaveChatMessageAsEntryUseCase {
  final List<({String content, String chatMessageId})> calls = [];
  final List<Completer<Either<Failure, Entry>>> _completers = [];

  /// When set, the *next* [call] throws synchronously instead of
  /// recording a completer — exercises `isolatedSideEffect`'s own
  /// catch-to-`malformedResponse` path from `bookmarkMessage`'s call site.
  bool throwOnNextCall = false;

  @override
  Future<Either<Failure, Entry>> call({
    required String content,
    required String chatMessageId,
  }) {
    calls.add((content: content, chatMessageId: chatMessageId));
    if (throwOnNextCall) {
      throwOnNextCall = false;
      throw Exception('boom');
    }
    final completer = Completer<Either<Failure, Entry>>();
    _completers.add(completer);
    return completer.future;
  }

  void resolve(int callIndex, Either<Failure, Entry> result) {
    _completers[callIndex].complete(result);
  }
}

const _savedEntry = Entry(
  id: 'entry-1',
  content: 'oi',
  source: EntrySource.chat,
  chatMessageId: 'srv-1',
  occurredAt: '2026-01-01T00:00:00Z',
  serverRevision: 1,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

void main() {
  late _FakeChatRepository fakeRepository;
  late FakeConnectivityWatcher fakeConnectivityWatcher;
  late _FakeSaveChatMessageAsEntryUseCase fakeSaveChatMessageAsEntryUseCase;
  late ChatCubit cubit;

  setUp(() {
    fakeRepository = _FakeChatRepository();
    fakeConnectivityWatcher = FakeConnectivityWatcher();
    fakeSaveChatMessageAsEntryUseCase = _FakeSaveChatMessageAsEntryUseCase();
    cubit = ChatCubit(
      fakeRepository,
      fakeConnectivityWatcher,
      fakeSaveChatMessageAsEntryUseCase,
    );
  });

  tearDown(() async {
    await cubit.close();
    await fakeConnectivityWatcher.close();
  });

  group('init() — bootstrap', () {
    test('an existing session is reused (the most recent by updatedAt) and its '
        'history loads -> ChatReady', () async {
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
    });

    test('no existing session -> silently creates exactly one, reused for the '
        'resulting ChatReady.sessionId', () async {
      fakeRepository.listSessionsResult = right(const []);
      fakeRepository.createSessionResult = right(_session);

      await cubit.init();

      expect(cubit.state, isA<ChatReady>());
      expect((cubit.state as ChatReady).sessionId, _session.id);
    });

    test('a bootstrap failure (chat-sessions-list) -> ChatBootstrapError, not '
        'an infinite spinner', () async {
      fakeRepository.listSessionsResult = left(
        const Failure.networkOffline(message: 'offline'),
      );

      await cubit.init();

      expect(cubit.state, isA<ChatBootstrapError>());
      expect(
        (cubit.state as ChatBootstrapError).failure,
        isA<NetworkOffline>(),
      );
    });

    test('a history-fetch failure after a successful session resolve -> '
        'ChatBootstrapError too', () async {
      fakeRepository.listMessagesResult = left(
        const Failure.networkTimeout(message: 'timeout'),
      );

      await cubit.init();

      expect(cubit.state, isA<ChatBootstrapError>());
    });

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
      final secondCubit = ChatCubit(
        countingRepository,
        FakeConnectivityWatcher(),
        _FakeSaveChatMessageAsEntryUseCase(),
      );
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
        final secondCubit = ChatCubit(
          countingRepository,
          FakeConnectivityWatcher(),
          _FakeSaveChatMessageAsEntryUseCase(),
        );

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

    test('I/O matrix "Switch session": fetches the target session\'s own '
        'history via listMessages and makes it active', () async {
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
    });

    test('I/O matrix "Switch to already-active session": a no-op Right, no '
        're-fetch, state object unchanged', () async {
      final before = cubit.state as ChatReady;

      final result = await cubit.switchSession(before.sessionId);

      expect(result.isRight(), isTrue);
      expect(cubit.state, same(before));
    });

    test('a switchSession failure surfaces as Left, current session stays '
        'active', () async {
      fakeRepository.listMessagesResult = left(
        const Failure.networkTimeout(message: 'timeout'),
      );
      final before = cubit.state as ChatReady;

      final result = await cubit.switchSession('s2');

      expect(result.isLeft(), isTrue);
      expect((cubit.state as ChatReady).sessionId, before.sessionId);
    });

    test('Design Notes/Boundaries: switching to a session restores the '
        'scroll offset last recorded for it via recordScrollOffset, or '
        'null (ChatScreen\'s own cue to jump to the bottom) if none was '
        'ever recorded', () async {
      cubit.recordScrollOffset('s2', 123.0);

      final result = await cubit.switchSession('s2');

      expect(result.isRight(), isTrue);
      expect((cubit.state as ChatReady).restoreScrollOffset, 123.0);

      // Switching back to 's1' (never recorded) falls back to null.
      final backResult = await cubit.switchSession('s1');
      expect(backResult.isRight(), isTrue);
      expect((cubit.state as ChatReady).restoreScrollOffset, isNull);
    });

    test('I/O matrix "New session online": createSession() succeeds -> a '
        'new, empty session becomes active, prepended to sessions', () async {
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
    });

    test('I/O matrix "New session offline": createSession() resolves '
        'Left(networkOffline) -> surfaced as Left, current session (and '
        'its sessions list) left completely untouched', () async {
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
    });

    test('review finding "Cross-session stream leakage": switchSession '
        'cancels an in-flight send\'s subscription first, so the old '
        'sendMessage() call resolves promptly and a late event from the '
        'now-orphaned stream never reaches the cubit at all', () async {
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
    });

    test('review finding "Cross-session stream leakage": startNewSession '
        'cancels an in-flight send\'s subscription too, before creating '
        'the new session', () async {
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
    });

    test('review fix: a switchSession failure while a send was in flight '
        'flips the stale isSending flag back to false, so the composer '
        "isn't left disabled for the rest of the app run (isSending gates "
        'canSend, which _cancelInFlightSend() alone never resets)', () async {
      final sendFuture = cubit.sendMessage('oi');
      await Future<void>.delayed(Duration.zero);
      expect((cubit.state as ChatReady).isSending, isTrue);

      fakeRepository.listMessagesResult = left(
        const Failure.networkTimeout(message: 'timeout'),
      );

      final result = await cubit.switchSession('s2');
      await sendFuture.timeout(const Duration(milliseconds: 500));

      expect(result.isLeft(), isTrue);
      final after = cubit.state as ChatReady;
      expect(after.sessionId, _session.id);
      expect(after.isSending, isFalse);
    });

    test('review fix: a startNewSession failure while a send was in flight '
        'flips the stale isSending flag back to false too', () async {
      final sendFuture = cubit.sendMessage('oi');
      await Future<void>.delayed(Duration.zero);
      expect((cubit.state as ChatReady).isSending, isTrue);

      fakeRepository.createSessionResult = left(
        const Failure.networkOffline(message: 'offline'),
      );

      final result = await cubit.startNewSession();
      await sendFuture.timeout(const Duration(milliseconds: 500));

      expect(result.isLeft(), isTrue);
      final after = cubit.state as ChatReady;
      expect(after.sessionId, _session.id);
      expect(after.isSending, isFalse);
    });
  });

  group('sendMessage() — the 3 visible message states', () {
    setUp(() async {
      await cubit.init();
    });

    test('optimistic send appends a complete user bubble and a streaming AI '
        'bubble immediately', () async {
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
    });

    test('happy path: token deltas append progressively, done finalizes to '
        'complete', () async {
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
    });

    test('mid-stream drop: partial text is never cleared, status becomes '
        'failed, no exception escapes the cubit', () async {
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
    });

    test('in-band error event: marks the bubble failed via the mapped '
        'Failure, text untouched', () async {
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
    });

    test('send while offline: the AI bubble is marked failed immediately, no '
        'text ever streamed in (still never cleared — just empty)', () async {
      final future = cubit.sendMessage('oi');
      await Future<void>.delayed(Duration.zero);
      final controller = fakeRepository.lastSendController!;

      controller.add(left(const Failure.networkOffline(message: 'offline')));
      await controller.close();
      await future;

      final aiMessage = (cubit.state as ChatReady).messages[1];
      expect(aiMessage.content, '');
      expect(aiMessage.status, ChatMessageStatus.failed);
    });

    test('a blank (whitespace-only) message is never sent', () async {
      await cubit.sendMessage('   ');

      expect((cubit.state as ChatReady).messages, isEmpty);
      expect(fakeRepository.sendMessageCalls, isEmpty);
    });

    test('a second sendMessage() call while one AI bubble is still streaming '
        'is a no-op (never races two concurrent sends)', () async {
      final firstFuture = cubit.sendMessage('primeira');
      await Future<void>.delayed(Duration.zero);
      expect(fakeRepository.sendMessageCalls, hasLength(1));

      await cubit.sendMessage('segunda');
      expect(fakeRepository.sendMessageCalls, hasLength(1));

      fakeRepository.lastSendController!.close();
      await firstFuture;
    });
  });

  group('message_created -> ChatUiMessage.serverId — spec-6-3', () {
    setUp(() async {
      await cubit.init();
    });

    test('message_created sets serverId on the matching user bubble only, '
        'leaving the AI bubble untouched', () async {
      final future = cubit.sendMessage('oi');
      await Future<void>.delayed(Duration.zero);
      final controller = fakeRepository.lastSendController!;

      controller.add(right(const ChatMessageCreatedEvent('srv-1')));
      await Future<void>.delayed(Duration.zero);

      final ready = cubit.state as ChatReady;
      expect(ready.messages[0].serverId, 'srv-1');
      expect(ready.messages[1].serverId, isNull);
      expect(ready.messages[1].status, ChatMessageStatus.streaming);

      controller.add(right(const ChatDoneEvent()));
      await controller.close();
      await future;
    });

    test('a message reloaded from history/cache already carries its own id '
        'as serverId (ChatCubit._fromDomain)', () async {
      fakeRepository.listMessagesResult = right([
        const ChatMessage(
          id: 'm1',
          sessionId: 's1',
          role: ChatMessageRole.user,
          content: 'oi',
          seq: 0,
          status: ChatMessageStatus.complete,
          retryCount: 0,
          createdAt: '2026-01-01T00:00:00Z',
        ),
      ]);
      final freshCubit = ChatCubit(
        fakeRepository,
        FakeConnectivityWatcher(),
        _FakeSaveChatMessageAsEntryUseCase(),
      );
      await freshCubit.init();

      expect((freshCubit.state as ChatReady).messages.single.serverId, 'm1');
      await freshCubit.close();
    });
  });

  group('retryMessage() — spec-6-3', () {
    setUp(() async {
      await cubit.init();
    });

    /// Drives a full send that ends up `failed`, with `message_created`
    /// (carrying [serverId]) having arrived first — the "Tap retry,
    /// normal" scenario's own precondition.
    Future<void> sendAndFailWithServerId(String serverId) async {
      final future = cubit.sendMessage('oi');
      await Future<void>.delayed(Duration.zero);
      final controller = fakeRepository.lastSendController!;
      controller.add(right(ChatMessageCreatedEvent(serverId)));
      controller.add(right(const ChatTokenEvent('resposta parcial')));
      controller.add(left(const Failure.networkTimeout(message: 'drop')));
      await controller.close();
      await future;
    }

    test('I/O matrix "Tap retry, normal": calls chat-messages-retry keyed by '
        'the preceding user message\'s serverId, resets the same AI bubble '
        'in place (same id, same position — never a second bubble), and '
        'completes it via done', () async {
      await sendAndFailWithServerId('srv-user-1');
      final before = cubit.state as ChatReady;
      expect(before.messages, hasLength(2));
      final aiId = before.messages[1].id;
      expect(before.messages[1].status, ChatMessageStatus.failed);
      expect(before.messages[1].content, 'resposta parcial');

      final retryFuture = cubit.retryMessage(aiId);
      await Future<void>.delayed(Duration.zero);

      expect(fakeRepository.retryMessageCalls, [
        (sessionId: before.sessionId, userMessageId: 'srv-user-1'),
      ]);
      // Never a full resend — chat-messages-retry alone was called.
      expect(fakeRepository.sendMessageCalls, hasLength(1));

      var ready = cubit.state as ChatReady;
      expect(ready.messages, hasLength(2));
      expect(ready.messages[1].id, aiId);
      expect(ready.messages[1].content, '');
      expect(ready.messages[1].status, ChatMessageStatus.streaming);

      final retryController = fakeRepository.lastRetryController!;
      retryController.add(right(const ChatTokenEvent('nova resposta')));
      await Future<void>.delayed(Duration.zero);
      ready = cubit.state as ChatReady;
      expect(ready.messages[1].content, 'nova resposta');

      retryController.add(right(const ChatDoneEvent()));
      await retryController.close();
      await retryFuture;

      ready = cubit.state as ChatReady;
      expect(ready.messages, hasLength(2));
      expect(ready.messages[1].id, aiId);
      expect(ready.messages[1].content, 'nova resposta');
      expect(ready.messages[1].status, ChatMessageStatus.complete);
    });

    test('I/O matrix "Tap retry, no serverId": the stream dropped before '
        'message_created ever arrived -> falls back to a full sendMessage '
        'resend of the same content, into the same AI bubble slot', () async {
      final future = cubit.sendMessage('pergunta original');
      await Future<void>.delayed(Duration.zero);
      final controller = fakeRepository.lastSendController!;
      controller.add(left(const Failure.networkTimeout(message: 'drop')));
      await controller.close();
      await future;

      final before = cubit.state as ChatReady;
      final aiId = before.messages[1].id;
      expect(before.messages[0].serverId, isNull);
      expect(before.messages[1].status, ChatMessageStatus.failed);

      final retryFuture = cubit.retryMessage(aiId);
      await Future<void>.delayed(Duration.zero);

      expect(fakeRepository.retryMessageCalls, isEmpty);
      expect(fakeRepository.sendMessageCalls, hasLength(2));
      expect(fakeRepository.sendMessageCalls.last.content, 'pergunta original');

      final ready = cubit.state as ChatReady;
      expect(ready.messages, hasLength(2));
      expect(ready.messages[1].id, aiId);
      expect(ready.messages[1].status, ChatMessageStatus.streaming);

      final newController = fakeRepository.lastSendController!;
      newController.add(right(const ChatDoneEvent()));
      await newController.close();
      await retryFuture;
    });

    test('a second failure after retry re-marks the same bubble failed, '
        'stays tappable', () async {
      await sendAndFailWithServerId('srv-1');
      final aiId = (cubit.state as ChatReady).messages[1].id;

      final retryFuture = cubit.retryMessage(aiId);
      await Future<void>.delayed(Duration.zero);
      final retryController = fakeRepository.lastRetryController!;
      retryController.add(
        left(const Failure.rateLimited(message: 'slow down')),
      );
      await retryController.close();
      await retryFuture;

      final after = cubit.state as ChatReady;
      expect(after.messages[1].id, aiId);
      expect(after.messages[1].status, ChatMessageStatus.failed);
    });

    test('retrying a non-existent message id is a silent no-op', () async {
      await cubit.retryMessage('does-not-exist');

      expect(fakeRepository.retryMessageCalls, isEmpty);
      expect(fakeRepository.sendMessageCalls, isEmpty);
    });

    test('retrying a bubble that is no longer failed (already complete) is '
        'a no-op', () async {
      await sendAndFailWithServerId('srv-1');
      final aiId = (cubit.state as ChatReady).messages[1].id;

      final retryFuture = cubit.retryMessage(aiId);
      await Future<void>.delayed(Duration.zero);
      fakeRepository.lastRetryController!.add(right(const ChatDoneEvent()));
      await fakeRepository.lastRetryController!.close();
      await retryFuture;
      expect(
        (cubit.state as ChatReady).messages[1].status,
        ChatMessageStatus.complete,
      );

      await cubit.retryMessage(aiId);

      expect(fakeRepository.retryMessageCalls, hasLength(1));
    });

    test('Boundaries: "a second retry while one is in flight" is a no-op — '
        'reuses _isSending verbatim', () async {
      await sendAndFailWithServerId('srv-1');
      final aiId = (cubit.state as ChatReady).messages[1].id;

      final firstRetry = cubit.retryMessage(aiId);
      await Future<void>.delayed(Duration.zero);
      expect(fakeRepository.retryMessageCalls, hasLength(1));

      await cubit.retryMessage(aiId);
      expect(fakeRepository.retryMessageCalls, hasLength(1));

      fakeRepository.lastRetryController!.close();
      await firstRetry;
    });

    test('review finding: close()-ing the cubit while retryMessage() is '
        'in-flight resolves its stranded Future instead of leaving it '
        'permanently unresolved (same fix _consumeStream already proves '
        'for sendMessage, extended to the retry call path)', () async {
      await sendAndFailWithServerId('srv-1');
      final aiId = (cubit.state as ChatReady).messages[1].id;

      final retryFuture = cubit.retryMessage(aiId);
      await Future<void>.delayed(Duration.zero);
      expect(fakeRepository.retryMessageCalls, hasLength(1));

      // The retry's own stream controller is never closed here —
      // close() alone must still resolve retryFuture promptly.
      await cubit.close();

      await retryFuture.timeout(const Duration(milliseconds: 500));
    });
  });

  group(
    'connectivity — spec-6-3 (ConnectivityWatcher -> ChatReady.isOffline)',
    () {
      setUp(() async {
        await cubit.init();
      });

      test('I/O matrix "Goes offline mid-session": an offline reading flips '
          'ChatReady.isOffline to true', () async {
        expect((cubit.state as ChatReady).isOffline, isFalse);

        fakeConnectivityWatcher.emit(false);
        await Future<void>.delayed(Duration.zero);

        expect((cubit.state as ChatReady).isOffline, isTrue);
      });

      test('I/O matrix "Comes back online": a subsequent online reading '
          'flips it back to false', () async {
        fakeConnectivityWatcher.emit(false);
        await Future<void>.delayed(Duration.zero);
        expect((cubit.state as ChatReady).isOffline, isTrue);

        fakeConnectivityWatcher.emit(true);
        await Future<void>.delayed(Duration.zero);

        expect((cubit.state as ChatReady).isOffline, isFalse);
      });

      test('a connectivity reading that arrives before bootstrap resolves is '
          'still reflected on the very first ChatReady emitted', () async {
        final freshRepository = _FakeChatRepository();
        final freshWatcher = FakeConnectivityWatcher();
        final freshCubit = ChatCubit(
          freshRepository,
          freshWatcher,
          _FakeSaveChatMessageAsEntryUseCase(),
        );

        freshWatcher.emit(false);
        await Future<void>.delayed(Duration.zero);

        await freshCubit.init();

        expect((freshCubit.state as ChatReady).isOffline, isTrue);
        await freshCubit.close();
        await freshWatcher.close();
      });

      test('startNewSession() carries the current offline status forward '
          'onto the newly emitted ChatReady', () async {
        fakeConnectivityWatcher.emit(false);
        await Future<void>.delayed(Duration.zero);
        expect((cubit.state as ChatReady).isOffline, isTrue);

        const created = ChatSession(
          id: 's-new',
          title: '',
          persona: ChatPersona.analitico,
          userMessageCount: 0,
          lastUserMessageAt: null,
          createdAt: '2026-01-05T00:00:00Z',
          updatedAt: '2026-01-05T00:00:00Z',
        );
        fakeRepository.createSessionResult = right(created);

        final result = await cubit.startNewSession();

        expect(result.isRight(), isTrue);
        expect((cubit.state as ChatReady).isOffline, isTrue);
      });

      test('RNF09: a connectivity-watch stream error never crashes the '
          'cubit — isOffline simply keeps its last known value', () async {
        fakeConnectivityWatcher.emitError(
          Exception('platform channel unavailable'),
        );
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state, isA<ChatReady>());
        expect((cubit.state as ChatReady).isOffline, isFalse);
      });
    },
  );

  test('review finding: a message restored from history with a persisted '
      '`streaming` status (left over from an earlier dropped response) '
      'never permanently disables the composer — the send-in-flight guard '
      'must not be derived from scanning loaded messages\' status', () async {
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
    final staleCubit = ChatCubit(
      staleRepository,
      FakeConnectivityWatcher(),
      _FakeSaveChatMessageAsEntryUseCase(),
    );
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
  });

  group('bookmarkMessage() — spec-6-4', () {
    /// Drives a send that resolves into a `complete` user bubble with a
    /// known [serverId] (via `message_created`) — the "happy path"/most
    /// scenarios' own precondition: a user bubble eligible for
    /// bookmarking.
    Future<String> sendAndCompleteWithServerId(
      String content,
      String serverId,
    ) async {
      final future = cubit.sendMessage(content);
      await Future<void>.delayed(Duration.zero);
      final controller = fakeRepository.lastSendController!;
      controller.add(right(ChatMessageCreatedEvent(serverId)));
      controller.add(right(const ChatDoneEvent()));
      await controller.close();
      await future;
      // Review finding: filters by role rather than assuming index 0,
      // so this helper keeps working if message ordering ever changes
      // (e.g. a prepended system message) instead of silently asserting
      // on the wrong bubble.
      return (cubit.state as ChatReady).messages
          .firstWhere((message) => message.role == ChatMessageRole.user)
          .id;
    }

    setUp(() async {
      await cubit.init();
    });

    test('happy path: idle -> saving -> saved, the use case called once with '
        'the message content and its serverId as chatMessageId', () async {
      final userId = await sendAndCompleteWithServerId('oi', 'srv-1');
      expect(
        (cubit.state as ChatReady).messages[0].bookmarkState,
        const BookmarkState.idle(),
      );

      final bookmarkFuture = cubit.bookmarkMessage(userId);
      await Future<void>.delayed(Duration.zero);

      expect(
        (cubit.state as ChatReady).messages[0].bookmarkState,
        const BookmarkState.saving(),
      );
      expect(fakeSaveChatMessageAsEntryUseCase.calls, [
        (content: 'oi', chatMessageId: 'srv-1'),
      ]);

      fakeSaveChatMessageAsEntryUseCase.resolve(0, right(_savedEntry));
      await bookmarkFuture;

      expect(
        (cubit.state as ChatReady).messages[0].bookmarkState,
        const BookmarkState.saved(),
      );
    });

    test('I/O matrix "Already saved": tapping a saved bubble again is a '
        'no-op — no new call, no state change', () async {
      final userId = await sendAndCompleteWithServerId('oi', 'srv-1');
      final bookmarkFuture = cubit.bookmarkMessage(userId);
      fakeSaveChatMessageAsEntryUseCase.resolve(0, right(_savedEntry));
      await bookmarkFuture;
      expect(
        (cubit.state as ChatReady).messages[0].bookmarkState,
        const BookmarkState.saved(),
      );
      final before = cubit.state;

      await cubit.bookmarkMessage(userId);

      expect(fakeSaveChatMessageAsEntryUseCase.calls, hasLength(1));
      expect(cubit.state, same(before));
    });

    test('I/O matrix "No serverId yet": tapping bookmark before '
        'message_created ever set serverId is a no-op, same guard shape as '
        'retryMessage', () async {
      final future = cubit.sendMessage('oi');
      await Future<void>.delayed(Duration.zero);
      final userId = (cubit.state as ChatReady).messages[0].id;
      expect((cubit.state as ChatReady).messages[0].serverId, isNull);

      await cubit.bookmarkMessage(userId);

      expect(fakeSaveChatMessageAsEntryUseCase.calls, isEmpty);
      expect(
        (cubit.state as ChatReady).messages[0].bookmarkState,
        const BookmarkState.idle(),
      );

      fakeRepository.lastSendController!.add(right(const ChatDoneEvent()));
      await fakeRepository.lastSendController!.close();
      await future;
    });

    test('a bookmark attempt on an AI (assistant) bubble is a no-op — the '
        'affordance only ever exists on the user\'s own messages', () async {
      final future = cubit.sendMessage('oi');
      await Future<void>.delayed(Duration.zero);
      final controller = fakeRepository.lastSendController!;
      controller.add(right(const ChatMessageCreatedEvent('srv-1')));
      controller.add(right(const ChatDoneEvent()));
      await controller.close();
      await future;
      final aiId = (cubit.state as ChatReady).messages[1].id;
      expect(
        (cubit.state as ChatReady).messages[1].role,
        ChatMessageRole.assistant,
      );

      await cubit.bookmarkMessage(aiId);

      expect(fakeSaveChatMessageAsEntryUseCase.calls, isEmpty);
    });

    test('I/O matrix "Save fails": create() resolves Left(Failure) -> the '
        'bubble flips to error (retryable); the rest of the session '
        '(isSending, other messages) is unaffected', () async {
      final userId = await sendAndCompleteWithServerId('oi', 'srv-1');

      final bookmarkFuture = cubit.bookmarkMessage(userId);
      fakeSaveChatMessageAsEntryUseCase.resolve(
        0,
        left(const Failure.networkTimeout(message: 'timeout')),
      );
      await bookmarkFuture;

      final ready = cubit.state as ChatReady;
      expect(ready.messages[0].bookmarkState, isA<BookmarkError>());
      expect(ready.isSending, isFalse);
      expect(ready.messages, hasLength(2));
    });

    test(
      'I/O matrix "Save fails" Error Handling: tapping an error bubble '
      'again re-attempts the same save, returning to saving and then '
      'resolving per the new result — never stuck on the first failure',
      () async {
        final userId = await sendAndCompleteWithServerId('oi', 'srv-1');

        final firstAttempt = cubit.bookmarkMessage(userId);
        fakeSaveChatMessageAsEntryUseCase.resolve(
          0,
          left(const Failure.networkTimeout(message: 'timeout')),
        );
        await firstAttempt;
        expect(
          (cubit.state as ChatReady).messages[0].bookmarkState,
          isA<BookmarkError>(),
        );

        final retryAttempt = cubit.bookmarkMessage(userId);
        await Future<void>.delayed(Duration.zero);
        expect(fakeSaveChatMessageAsEntryUseCase.calls, hasLength(2));
        expect(
          (cubit.state as ChatReady).messages[0].bookmarkState,
          const BookmarkState.saving(),
        );

        fakeSaveChatMessageAsEntryUseCase.resolve(1, right(_savedEntry));
        await retryAttempt;
        expect(
          (cubit.state as ChatReady).messages[0].bookmarkState,
          const BookmarkState.saved(),
        );
      },
    );

    test('I/O matrix "Side-effect throws": a synchronous throw from the use '
        'case is caught by isolatedSideEffect, mapped to '
        'malformedResponse, and never propagates to the caller — the '
        'bubble still flips to error', () async {
      final userId = await sendAndCompleteWithServerId('oi', 'srv-1');
      fakeSaveChatMessageAsEntryUseCase.throwOnNextCall = true;

      await cubit.bookmarkMessage(userId);

      final ready = cubit.state as ChatReady;
      expect(ready.messages[0].bookmarkState, isA<BookmarkError>());
      expect(
        (ready.messages[0].bookmarkState as BookmarkError).failure,
        isA<MalformedResponse>(),
      );
    });

    test('I/O matrix "Second tap while saving": a no-op re-entrancy guard, '
        'scoped to that one message — never a second call while the first '
        'is still in flight', () async {
      final userId = await sendAndCompleteWithServerId('oi', 'srv-1');

      final firstBookmark = cubit.bookmarkMessage(userId);
      await Future<void>.delayed(Duration.zero);
      expect(fakeSaveChatMessageAsEntryUseCase.calls, hasLength(1));

      await cubit.bookmarkMessage(userId);
      expect(fakeSaveChatMessageAsEntryUseCase.calls, hasLength(1));

      fakeSaveChatMessageAsEntryUseCase.resolve(0, right(_savedEntry));
      await firstBookmark;
    });

    test('a save failure never disables the composer or affects other '
        'bubbles — the session stays fully usable', () async {
      final userId = await sendAndCompleteWithServerId('oi', 'srv-1');

      final bookmarkFuture = cubit.bookmarkMessage(userId);
      fakeSaveChatMessageAsEntryUseCase.resolve(
        0,
        left(const Failure.networkTimeout(message: 'timeout')),
      );
      await bookmarkFuture;

      final ready = cubit.state as ChatReady;
      expect(ready.isOffline, isFalse);
      expect(ready.messages[1].bookmarkState, const BookmarkState.idle());
    });

    test(
      'review: close()-ing the cubit while a bookmark save is in flight '
      'never crashes — the stray emit after close is simply swallowed, '
      'guarded by isClosed on both of bookmarkMessage\'s own emit() calls',
      () async {
        final userId = await sendAndCompleteWithServerId('oi', 'srv-1');

        final bookmarkFuture = cubit.bookmarkMessage(userId);
        await Future<void>.delayed(Duration.zero);
        await cubit.close();
        fakeSaveChatMessageAsEntryUseCase.resolve(0, right(_savedEntry));

        await expectLater(bookmarkFuture, completes);
      },
    );

    test(
      'review fix (round 2): a save that resolves after the user has '
      'switched sessions is never silently dropped — re-entering a '
      'session carrying the bookmarked message picks the outcome back up',
      () async {
        final userId = await sendAndCompleteWithServerId('oi', 'srv-1');

        final bookmarkFuture = cubit.bookmarkMessage(userId);
        await Future<void>.delayed(Duration.zero);
        expect(
          (cubit.state as ChatReady).messages[0].bookmarkState,
          const BookmarkState.saving(),
        );

        // Switches away before the save resolves — switchSession replaces
        // ChatReady.messages wholesale, so `userId` (this session's own
        // local id) no longer identifies anything in the new state.
        fakeRepository.listMessagesResult = right(const []);
        await cubit.switchSession('s2');
        expect((cubit.state as ChatReady).sessionId, 's2');

        fakeSaveChatMessageAsEntryUseCase.resolve(0, right(_savedEntry));
        await bookmarkFuture;

        // The now-active, unrelated session is untouched by the stray
        // result — no crash, no spurious message materializing in it.
        expect((cubit.state as ChatReady).messages, isEmpty);

        // Re-entering the original session reloads the message fresh
        // from the server — its own `id` is now the backend id
        // ('srv-1'), the same identifier the save resolved under.
        fakeRepository.listMessagesResult = right(const [
          ChatMessage(
            id: 'srv-1',
            sessionId: 's1',
            role: ChatMessageRole.user,
            content: 'oi',
            seq: 0,
            status: ChatMessageStatus.complete,
            retryCount: 0,
            createdAt: '2026-01-01T00:00:00Z',
          ),
        ]);
        await cubit.switchSession('s1');

        expect(
          (cubit.state as ChatReady).messages.single.bookmarkState,
          const BookmarkState.saved(),
        );
      },
    );

    test('bookmarkMessage() is a no-op while state is not yet ChatReady '
        '(bootstrap still loading or failed)', () async {
      final freshCubit = ChatCubit(
        _FakeChatRepository(),
        FakeConnectivityWatcher(),
        fakeSaveChatMessageAsEntryUseCase,
      );
      expect(freshCubit.state, isA<ChatBootstrapLoading>());

      await freshCubit.bookmarkMessage('whatever');

      expect(freshCubit.state, isA<ChatBootstrapLoading>());
      expect(fakeSaveChatMessageAsEntryUseCase.calls, isEmpty);
      await freshCubit.close();
    });

    test('review: calling bookmarkMessage() on an already-closed cubit never '
        'crashes and never reaches the use case — the isClosed guard before '
        'the first (saving) emit, not just the one after the await', () async {
      final userId = await sendAndCompleteWithServerId('oi', 'srv-1');
      await cubit.close();

      await expectLater(cubit.bookmarkMessage(userId), completes);

      expect(fakeSaveChatMessageAsEntryUseCase.calls, isEmpty);
    });

    test('bookmarking two different messages concurrently resolves each '
        'independently, with no cross-talk', () async {
      final firstId = await sendAndCompleteWithServerId('oi', 'srv-1');
      // sendAndCompleteWithServerId's own role-only filter always returns
      // the *first* user message, so a second round trip needs its own
      // content-keyed lookup to get the message it actually just sent.
      await sendAndCompleteWithServerId('tudo bem', 'srv-2');
      final secondId = (cubit.state as ChatReady).messages
          .firstWhere((message) => message.content == 'tudo bem')
          .id;

      final firstBookmark = cubit.bookmarkMessage(firstId);
      await Future<void>.delayed(Duration.zero);
      final secondBookmark = cubit.bookmarkMessage(secondId);
      await Future<void>.delayed(Duration.zero);

      expect(fakeSaveChatMessageAsEntryUseCase.calls, [
        (content: 'oi', chatMessageId: 'srv-1'),
        (content: 'tudo bem', chatMessageId: 'srv-2'),
      ]);

      // Resolves the *second* call first — proves the result lands on
      // its own message only, never the other one still in flight.
      fakeSaveChatMessageAsEntryUseCase.resolve(1, right(_savedEntry));
      await secondBookmark;

      var ready = cubit.state as ChatReady;
      expect(
        ready.messages.firstWhere((m) => m.id == secondId).bookmarkState,
        const BookmarkState.saved(),
      );
      expect(
        ready.messages.firstWhere((m) => m.id == firstId).bookmarkState,
        const BookmarkState.saving(),
      );

      fakeSaveChatMessageAsEntryUseCase.resolve(
        0,
        left(const Failure.networkTimeout(message: 'timeout')),
      );
      await firstBookmark;

      ready = cubit.state as ChatReady;
      expect(
        ready.messages.firstWhere((m) => m.id == firstId).bookmarkState,
        isA<BookmarkError>(),
      );
      expect(
        ready.messages.firstWhere((m) => m.id == secondId).bookmarkState,
        const BookmarkState.saved(),
      );
    });
  });

  group('proactive insight — spec-6-5', () {
    late ChatCubit insightCubit;
    // Review fix: a plain `late` var's own `tearDown` close() throws
    // `LateInitializationError` (masking the real failure) if a test
    // fails before `initInsightCubit` ever assigns it — this flag lets
    // `tearDown` tell "never assigned" apart from "assigned".
    var insightCubitInitialized = false;

    /// Builds a dedicated cubit for this group — a short/long
    /// [timeout] override lets each test control whether the inactivity
    /// side of the race can realistically fire during the test's own
    /// real-time execution, without a `fake_async` dependency (Design
    /// Notes). Assigns [insightCubit] itself (rather than returning it)
    /// so [insightCubitInitialized] is always set at the same time.
    Future<void> initInsightCubit({required Duration timeout}) async {
      insightCubit = ChatCubit(
        fakeRepository,
        fakeConnectivityWatcher,
        fakeSaveChatMessageAsEntryUseCase,
        insightInactivityTimeout: timeout,
      );
      insightCubitInitialized = true;
      await insightCubit.init();
    }

    /// Drives one full send-to-completion on [target] — same shape the
    /// top-level `sendMessage()` test group's own inline helper already
    /// uses, lifted here so every test below can send several messages
    /// back to back without repeating it.
    Future<void> sendAndComplete(ChatCubit target, String content) async {
      final future = target.sendMessage(content);
      await Future<void>.delayed(Duration.zero);
      final controller = fakeRepository.lastSendController!;
      controller.add(right(const ChatDoneEvent()));
      await controller.close();
      await future;
    }

    tearDown(() async {
      if (insightCubitInitialized) {
        await insightCubit.close();
        insightCubitInitialized = false;
      }
    });

    test('I/O matrix "5th user message": the message_count trigger fires '
        'exactly once, never before, with a non-empty triggerKey', () async {
      await initInsightCubit(timeout: const Duration(seconds: 5));

      for (var i = 0; i < 4; i++) {
        await sendAndComplete(insightCubit, 'msg $i');
      }
      expect(fakeRepository.generateInsightCalls, isEmpty);

      await sendAndComplete(insightCubit, 'msg 5');

      expect(fakeRepository.generateInsightCalls, hasLength(1));
      final call = fakeRepository.generateInsightCalls.single;
      expect(call.sessionId, (insightCubit.state as ChatReady).sessionId);
      expect(call.triggerType, InsightTriggerType.messageCount);
      expect(call.triggerKey, isNotEmpty);
    });

    test('after firing, the window reopens immediately: a new count starts '
        'from zero, never refiring on the very next send', () async {
      await initInsightCubit(timeout: const Duration(seconds: 5));
      for (var i = 0; i < 5; i++) {
        await sendAndComplete(insightCubit, 'msg $i');
      }
      expect(fakeRepository.generateInsightCalls, hasLength(1));
      final firstKey = fakeRepository.generateInsightCalls.single.triggerKey;

      // 4 more sends in the new window — still below its own threshold.
      for (var i = 0; i < 4; i++) {
        await sendAndComplete(insightCubit, 'later $i');
      }
      expect(fakeRepository.generateInsightCalls, hasLength(1));

      // The 5th send in the new window fires again, with a fresh key.
      await sendAndComplete(insightCubit, 'final');
      expect(fakeRepository.generateInsightCalls, hasLength(2));
      expect(
        fakeRepository.generateInsightCalls.last.triggerKey,
        isNot(firstKey),
      );
    });

    test('I/O matrix "2 minutes idle": the inactivity trigger fires once '
        'after the configured (here, injected-short) duration with no '
        'sendMessage() call at all', () async {
      await initInsightCubit(timeout: const Duration(milliseconds: 20));

      // Real-wall-clock timer (Design Notes: no `fake_async` dependency
      // in this project) — `_resetInsightWindow` restarts an equally
      // short timer the instant this one fires (Boundaries: "fires
      // once ... fresh timer starts"), so a *second* idle window is
      // just as real and just as fast; a fixed sleep many multiples of
      // `timeout` (the previous shape here) reliably outlasted it and
      // caught several fires instead of the one this test is about.
      // Polling stops the moment the first call lands instead, so the
      // second window's own timer never gets the chance to also fire
      // before the assertions below run.
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (fakeRepository.generateInsightCalls.isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }

      expect(fakeRepository.generateInsightCalls, hasLength(1));
      expect(
        fakeRepository.generateInsightCalls.single.triggerType,
        InsightTriggerType.inactivity,
      );
    });

    test('I/O matrix "Near-simultaneous": sending the threshold message '
        'cancels the still-pending inactivity timer synchronously, so only '
        'message_count ever fires for that window', () async {
      // Long enough that the inactivity side could never win this race
      // for real within the test's own (near-instant) execution time —
      // sendAndComplete only ever yields via zero-duration delays.
      await initInsightCubit(timeout: const Duration(milliseconds: 500));
      for (var i = 0; i < 5; i++) {
        await sendAndComplete(insightCubit, 'msg $i');
      }

      expect(fakeRepository.generateInsightCalls, hasLength(1));
      expect(
        fakeRepository.generateInsightCalls.single.triggerType,
        InsightTriggerType.messageCount,
      );
      // The new window's own fresh timer (also 500ms) hasn't had a
      // chance to fire yet either — confirms there's no stray second
      // call lingering from the cancelled original timer.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fakeRepository.generateInsightCalls, hasLength(1));
    });

    test('fire-and-forget: a pending (never-resolved) generateInsight call '
        'never blocks sending another message', () async {
      await initInsightCubit(timeout: const Duration(seconds: 5));
      for (var i = 0; i < 5; i++) {
        await sendAndComplete(insightCubit, 'msg $i');
      }
      expect(fakeRepository.generateInsightCalls, hasLength(1));
      // Never resolved — the insight call is left permanently pending.
      expect((insightCubit.state as ChatReady).isSending, isFalse);

      await sendAndComplete(insightCubit, 'still works');

      expect(fakeRepository.sendMessageCalls, hasLength(6));
    });

    test('I/O matrix "Generation fails" (transport Left): activeInsight '
        'stays null, no crash, ordinary chat keeps working', () async {
      await initInsightCubit(timeout: const Duration(seconds: 5));
      for (var i = 0; i < 5; i++) {
        await sendAndComplete(insightCubit, 'msg $i');
      }

      fakeRepository.resolveInsight(
        0,
        left(const Failure.networkTimeout(message: 'timeout')),
      );
      await Future<void>.delayed(Duration.zero);

      expect((insightCubit.state as ChatReady).activeInsight, isNull);
      await sendAndComplete(insightCubit, 'works fine');
      expect(fakeRepository.sendMessageCalls, hasLength(6));
    });

    test('I/O matrix "Generation fails" (in-payload, status != ready — '
        'ChatRepository.generateInsight already maps this to Right(null)): '
        'activeInsight stays null', () async {
      await initInsightCubit(timeout: const Duration(seconds: 5));
      for (var i = 0; i < 5; i++) {
        await sendAndComplete(insightCubit, 'msg $i');
      }

      fakeRepository.resolveInsight(0, right<Failure, ChatInsight?>(null));
      await Future<void>.delayed(Duration.zero);

      expect((insightCubit.state as ChatReady).activeInsight, isNull);
    });

    test('a successful, ready insight is appended onto ChatReady.'
        'activeInsight', () async {
      await initInsightCubit(timeout: const Duration(seconds: 5));
      for (var i = 0; i < 5; i++) {
        await sendAndComplete(insightCubit, 'msg $i');
      }

      fakeRepository.resolveInsight(
        0,
        right(const ChatInsight(id: 'ins-1', content: 'um padrão notado')),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        (insightCubit.state as ChatReady).activeInsight,
        const ChatInsight(id: 'ins-1', content: 'um padrão notado'),
      );
    });

    test('review fix: a stale (earlier-fired) result that resolves after a '
        'later-fired request already applied its own insight is dropped — '
        'it never overwrites the newer activeInsight', () async {
      await initInsightCubit(timeout: const Duration(seconds: 5));
      // First window: 5 sends fire the first generateInsight call
      // (index 0), left pending (never resolved yet).
      for (var i = 0; i < 5; i++) {
        await sendAndComplete(insightCubit, 'msg $i');
      }
      // Second window: 5 more sends fire a second, overlapping
      // generateInsight call (index 1) before the first has resolved —
      // two requests for the same session now in flight at once.
      for (var i = 0; i < 5; i++) {
        await sendAndComplete(insightCubit, 'later $i');
      }
      expect(fakeRepository.generateInsightCalls, hasLength(2));

      // The later (index 1) request resolves first and applies.
      fakeRepository.resolveInsight(
        1,
        right(const ChatInsight(id: 'ins-newer', content: 'mais recente')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        (insightCubit.state as ChatReady).activeInsight,
        const ChatInsight(id: 'ins-newer', content: 'mais recente'),
      );

      // The earlier (index 0) request finally resolves after — it must
      // not overwrite the newer insight already applied above.
      fakeRepository.resolveInsight(
        0,
        right(const ChatInsight(id: 'ins-stale', content: 'desatualizado')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        (insightCubit.state as ChatReady).activeInsight,
        const ChatInsight(id: 'ins-newer', content: 'mais recente'),
      );
    });

    test('review fix: a stale result also can\'t resurrect an insight the '
        'user already dismissed', () async {
      await initInsightCubit(timeout: const Duration(seconds: 5));
      for (var i = 0; i < 5; i++) {
        await sendAndComplete(insightCubit, 'msg $i');
      }
      for (var i = 0; i < 5; i++) {
        await sendAndComplete(insightCubit, 'later $i');
      }

      fakeRepository.resolveInsight(
        1,
        right(const ChatInsight(id: 'ins-newer', content: 'mais recente')),
      );
      await Future<void>.delayed(Duration.zero);
      insightCubit.dismissInsight();
      expect((insightCubit.state as ChatReady).activeInsight, isNull);

      fakeRepository.resolveInsight(
        0,
        right(const ChatInsight(id: 'ins-stale', content: 'desatualizado')),
      );
      await Future<void>.delayed(Duration.zero);
      expect((insightCubit.state as ChatReady).activeInsight, isNull);
    });

    test('I/O matrix "Session switched mid-flight": a result that resolves '
        'after switchSession moved away is dropped — sessionId no longer '
        'matches', () async {
      fakeRepository.listSessionsResult = right([_session, _otherSession]);
      await initInsightCubit(timeout: const Duration(seconds: 5));
      for (var i = 0; i < 5; i++) {
        await sendAndComplete(insightCubit, 'msg $i');
      }

      fakeRepository.listMessagesResult = right(const []);
      final switchResult = await insightCubit.switchSession(_otherSession.id);
      expect(switchResult.isRight(), isTrue);
      expect((insightCubit.state as ChatReady).sessionId, _otherSession.id);

      fakeRepository.resolveInsight(
        0,
        right(const ChatInsight(id: 'ins-1', content: 'tarde demais')),
      );
      await Future<void>.delayed(Duration.zero);

      expect((insightCubit.state as ChatReady).activeInsight, isNull);
    });

    test('dismissInsight() clears activeInsight via a direct ChatReady(...) '
        'construction, every other field — messages, sessions, isSending, '
        'restoreScrollOffset, isOffline — left exactly as-is', () async {
      await initInsightCubit(timeout: const Duration(seconds: 5));
      for (var i = 0; i < 5; i++) {
        await sendAndComplete(insightCubit, 'msg $i');
      }
      fakeRepository.resolveInsight(
        0,
        right(const ChatInsight(id: 'ins-1', content: 'conteúdo')),
      );
      await Future<void>.delayed(Duration.zero);
      final before = insightCubit.state as ChatReady;
      expect(before.activeInsight, isNotNull);

      insightCubit.dismissInsight();

      final after = insightCubit.state as ChatReady;
      expect(after.activeInsight, isNull);
      expect(after.messages, before.messages);
      expect(after.sessions, before.sessions);
      expect(after.isSending, before.isSending);
      expect(after.restoreScrollOffset, before.restoreScrollOffset);
      expect(after.isOffline, before.isOffline);
    });

    test('I/O matrix "Dismiss with none active": a no-op — the state object '
        'itself is left untouched', () async {
      await initInsightCubit(timeout: const Duration(seconds: 5));
      final before = insightCubit.state;

      insightCubit.dismissInsight();

      expect(insightCubit.state, same(before));
    });

    test('never calls the backend on dismiss — only the one generateInsight '
        'call this test itself drove is ever recorded', () async {
      await initInsightCubit(timeout: const Duration(seconds: 5));
      for (var i = 0; i < 5; i++) {
        await sendAndComplete(insightCubit, 'msg $i');
      }
      fakeRepository.resolveInsight(
        0,
        right(const ChatInsight(id: 'ins-1', content: 'conteúdo')),
      );
      await Future<void>.delayed(Duration.zero);

      insightCubit.dismissInsight();

      expect(fakeRepository.generateInsightCalls, hasLength(1));
    });

    test('the window resets on switchSession — a session switch never '
        'carries over the previous session\'s own message count', () async {
      fakeRepository.listSessionsResult = right([_session, _otherSession]);
      await initInsightCubit(timeout: const Duration(seconds: 5));
      for (var i = 0; i < 4; i++) {
        await sendAndComplete(insightCubit, 'msg $i');
      }
      expect(fakeRepository.generateInsightCalls, isEmpty);

      fakeRepository.listMessagesResult = right(const []);
      await insightCubit.switchSession(_otherSession.id);

      // If the counter had carried over at 4, this single send would
      // already hit 5 and fire — it must not.
      await sendAndComplete(insightCubit, 'first in new session');
      expect(fakeRepository.generateInsightCalls, isEmpty);

      for (var i = 0; i < 4; i++) {
        await sendAndComplete(insightCubit, 'more $i');
      }
      expect(fakeRepository.generateInsightCalls, hasLength(1));
      expect(
        fakeRepository.generateInsightCalls.single.sessionId,
        _otherSession.id,
      );
    });

    test('the window resets on startNewSession the same way', () async {
      await initInsightCubit(timeout: const Duration(seconds: 5));
      for (var i = 0; i < 4; i++) {
        await sendAndComplete(insightCubit, 'msg $i');
      }
      expect(fakeRepository.generateInsightCalls, isEmpty);

      const created = ChatSession(
        id: 's-new',
        title: '',
        persona: ChatPersona.analitico,
        userMessageCount: 0,
        lastUserMessageAt: null,
        createdAt: '2026-01-05T00:00:00Z',
        updatedAt: '2026-01-05T00:00:00Z',
      );
      fakeRepository.createSessionResult = right(created);
      await insightCubit.startNewSession();

      await sendAndComplete(insightCubit, 'first in new session');
      expect(fakeRepository.generateInsightCalls, isEmpty);

      for (var i = 0; i < 4; i++) {
        await sendAndComplete(insightCubit, 'more $i');
      }
      expect(fakeRepository.generateInsightCalls, hasLength(1));
      expect(fakeRepository.generateInsightCalls.single.sessionId, created.id);
    });

    test('close() cancels the pending inactivity timer — it never fires '
        'into a closed cubit', () async {
      await initInsightCubit(timeout: const Duration(milliseconds: 20));
      await insightCubit.close();

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(fakeRepository.generateInsightCalls, isEmpty);
    });

    test('review: close()-ing the cubit while a generateInsight call is in '
        'flight never crashes — the stray emit after close is simply '
        'swallowed, guarded by isClosed in _applyInsightResult, same shape '
        "bookmarkMessage's own in-flight-close test already proves", () async {
      await initInsightCubit(timeout: const Duration(seconds: 5));
      for (var i = 0; i < 5; i++) {
        await sendAndComplete(insightCubit, 'msg $i');
      }
      expect(fakeRepository.generateInsightCalls, hasLength(1));

      await insightCubit.close();
      fakeRepository.resolveInsight(
        0,
        right(const ChatInsight(id: 'ins-1', content: 'conteúdo')),
      );

      // No crash reaching here is the assertion itself.
      await Future<void>.delayed(Duration.zero);
      expect(insightCubit.isClosed, isTrue);
    });

    test('review: retryMessage() never counts toward the insight trigger '
        'window — the no-serverId branch calls _repository.sendMessage '
        'directly, never through ChatCubit.sendMessage() where the '
        'counting logic lives, even retried enough times to exceed the '
        'message-count threshold', () async {
      await initInsightCubit(timeout: const Duration(seconds: 5));

      final sendFuture = insightCubit.sendMessage('oi');
      await Future<void>.delayed(Duration.zero);
      fakeRepository.lastSendController!.add(
        left(const Failure.networkTimeout(message: 'drop')),
      );
      await fakeRepository.lastSendController!.close();
      await sendFuture;
      final aiId = (insightCubit.state as ChatReady).messages[1].id;

      for (var i = 0; i < 6; i++) {
        final retryFuture = insightCubit.retryMessage(aiId);
        await Future<void>.delayed(Duration.zero);
        fakeRepository.lastSendController!.add(
          left(const Failure.networkTimeout(message: 'drop again')),
        );
        await fakeRepository.lastSendController!.close();
        await retryFuture;
      }

      expect(fakeRepository.generateInsightCalls, isEmpty);
    });

    test('a real insight resolving while ChatReady.isSending is true (an AI '
        'response still streaming) is applied without disturbing the send '
        '— isSending and the streaming bubble are both left exactly as '
        'they were', () async {
      await initInsightCubit(timeout: const Duration(seconds: 5));
      for (var i = 0; i < 4; i++) {
        await sendAndComplete(insightCubit, 'msg $i');
      }
      expect(fakeRepository.generateInsightCalls, isEmpty);

      final sendFuture = insightCubit.sendMessage('msg 4');
      await Future<void>.delayed(Duration.zero);
      expect(fakeRepository.generateInsightCalls, hasLength(1));
      expect((insightCubit.state as ChatReady).isSending, isTrue);

      fakeRepository.resolveInsight(
        0,
        right(const ChatInsight(id: 'ins-1', content: 'conteúdo')),
      );
      await Future<void>.delayed(Duration.zero);

      final midStream = insightCubit.state as ChatReady;
      expect(midStream.isSending, isTrue);
      expect(
        midStream.activeInsight,
        const ChatInsight(id: 'ins-1', content: 'conteúdo'),
      );
      expect(midStream.messages.last.status, ChatMessageStatus.streaming);

      fakeRepository.lastSendController!.add(right(const ChatDoneEvent()));
      await fakeRepository.lastSendController!.close();
      await sendFuture;
    });

    test('a second successful insight resolving while a prior one is still '
        'visible (never dismissed) silently replaces it — the newer '
        'result always wins', () async {
      await initInsightCubit(timeout: const Duration(seconds: 5));
      for (var i = 0; i < 5; i++) {
        await sendAndComplete(insightCubit, 'msg $i');
      }
      fakeRepository.resolveInsight(
        0,
        right(const ChatInsight(id: 'ins-1', content: 'primeiro')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        (insightCubit.state as ChatReady).activeInsight,
        const ChatInsight(id: 'ins-1', content: 'primeiro'),
      );

      for (var i = 0; i < 5; i++) {
        await sendAndComplete(insightCubit, 'more $i');
      }
      expect(fakeRepository.generateInsightCalls, hasLength(2));

      fakeRepository.resolveInsight(
        1,
        right(const ChatInsight(id: 'ins-2', content: 'segundo')),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        (insightCubit.state as ChatReady).activeInsight,
        const ChatInsight(id: 'ins-2', content: 'segundo'),
      );
    });
  });
}

const _otherSession = ChatSession(
  id: 'other-insight-session',
  title: '',
  persona: ChatPersona.analitico,
  userMessageCount: 0,
  lastUserMessageAt: null,
  createdAt: '2025-12-30T00:00:00Z',
  updatedAt: '2025-12-30T00:00:00Z',
);

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

  @override
  Stream<Either<Failure, ChatStreamEvent>> retryMessage(
    String sessionId,
    String userMessageId,
  ) => _delegate.retryMessage(sessionId, userMessageId);

  @override
  Future<Either<Failure, ChatInsight?>> generateInsight(
    String sessionId, {
    required InsightTriggerType triggerType,
    required String triggerKey,
  }) => _delegate.generateInsight(
    sessionId,
    triggerType: triggerType,
    triggerKey: triggerKey,
  );

  // Story 8.4 — not exercised by this counting wrapper's own test, same
  // pure-delegation rationale every other method above already follows.
  @override
  Future<Either<Failure, Unit>> clearLocalCache() => _delegate.clearLocalCache();
}
