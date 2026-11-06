import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:cerne/core/di/injection_container.dart';
import 'package:cerne/core/network/access_token_provider.dart';
import 'package:cerne/core/network/url_builder.dart';
import 'package:cerne/features/chat/domain/entities/bookmark_state.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/presentation/cubit/chat_cubit.dart';
import 'package:cerne/features/chat/presentation/cubit/chat_state.dart';

import '../../support/fake_path_provider_platform.dart';

/// Same shape as `capture_flow_e2e_test.dart`'s/`entry_detail_flow_e2e_
/// test.dart`'s own fake adapter, extended with [queueSseResponse] for
/// `ApiClient.postStream`'s `ResponseType.stream` requests — only the
/// transport boundary is faked.
///
/// A queued SSE response is delivered as the exact [chunks] given, each
/// its own separate stream emission (never pre-joined into one string) —
/// this is what proves `ChatRemoteDataSource.sendMessage`'s own
/// `\n\n`-boundary buffering really works across genuine network chunk
/// boundaries, not just against a single already-complete event.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<ResponseBody Function()> _queue = [];

  void queueJsonResponse(int statusCode, Map<String, dynamic> body) {
    _queue.add(
      () => ResponseBody.fromString(
        jsonEncode(body),
        statusCode,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
  }

  void queueErrorResponse(String code, String message, {int statusCode = 503}) {
    queueJsonResponse(statusCode, {
      'code': code,
      'message': message,
      'retryable': true,
    });
  }

  void queueSseResponse(List<String> chunks, {int statusCode = 200}) {
    _queue.add(
      () => ResponseBody(
        Stream.fromIterable(
          chunks.map((chunk) => Uint8List.fromList(utf8.encode(chunk))),
        ),
        statusCode,
        headers: {
          Headers.contentTypeHeader: ['text/event-stream'],
        },
      ),
    );
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (_queue.isEmpty) {
      throw StateError(
        'No queued response for ${options.method} ${options.path}',
      );
    }
    return _queue.removeAt(0)();
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _sessionJson({required String id, required String updatedAt}) => {
  'id': id,
  'title': 'Nova conversa',
  'personaSnapshot': 'empatico',
  'userMessageCount': 0,
  'lastUserMessageAt': null,
  'createdAt': updatedAt,
  'updatedAt': updatedAt,
};

/// `entries-create`'s own response `data` shape (`EntryDto.fromJson`) —
/// mirrors `entries_remote_data_source_test.dart`'s own fixture, extended
/// with a non-null [chatMessageId] (spec-6-4's own `source: chat` entries).
Map<String, dynamic> _entryJson({
  required String id,
  required String chatMessageId,
}) => {
  'id': id,
  'content': 'Como você está?',
  'source': 'chat',
  'chatMessageId': chatMessageId,
  'occurredAt': '2026-01-01T00:00:00Z',
  'serverRevision': 1,
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-01T00:00:00Z',
};

/// End-to-end coverage for spec-6-1's chat flow, driven through the real
/// production object graph `sl` resolves for Home/Chat (the exact
/// `ChatCubit` instance `app_router.dart` gives `ChatScreen`), wired to
/// the real `ChatRepositoryImpl` -> `ChatRemoteDataSource` -> `ApiClient`
/// -> `Dio` (both real interceptors attached) -> the real `chat_sessions`/
/// `chat_messages` Hive boxes. Only the transport boundary and the native
/// plugins (secure storage, path_provider) are faked — no device/
/// simulator/CI exists yet (AGENTS.md).
///
/// Complements rather than duplicates this story's existing mocked tests
/// (`chat_cubit_test.dart` against a fake `ChatRepository`,
/// `chat_repository_impl_test.dart`/`chat_remote_data_source_test.dart`
/// against a mocked `ApiClient`): none of them drives a real SSE byte
/// stream through the real `ApiClient.postStream` -> `ChatRemoteDataSource`
/// `\n\n`-buffering -> `ChatCubit` token-append pipeline in one send, the
/// way the app actually does on every message.
///
/// Driven directly against `ChatCubit`'s own public API (`init`/
/// `sendMessage`), not through `tester.tap`/`pumpAndSettle` — same
/// rationale `capture_flow_e2e_test.dart` documents: these awaits span
/// genuine async I/O (a real Dio round trip over a faked transport), and
/// `pumpAndSettle` isn't guaranteed to wait for that.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final fakeNativeStorage = <String, String>{};

  // spec-6-3 — `sl<ChatCubit>()` below resolves the *real* `ChatCubit`,
  // whose constructor subscribes to the real `connectivity_plus`-backed
  // `ConnectivityWatcher` immediately; faked the same way
  // `bootstrap_integration_test.dart` fakes it, since no device/simulator
  // exists yet (AGENTS.md) to answer these channels for real.
  const connectivityMethodChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );
  const connectivityEventChannel = EventChannel(
    'dev.fluttercommunity.plus/connectivity_status',
  );

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

  late FakePathProviderPlatform fakePathProvider;
  late _FakeHttpClientAdapter adapter;

  // spec-6-3 — the real `connectivity_plus` plugin reaches this channel's
  // own event stream via `EventChannel.receiveBroadcastStream()`, not a
  // plain method call, so it must be mocked with `setMockStreamHandler`
  // rather than `setMockMethodCallHandler` to let a test push a live
  // reading. Captured on `onListen` (fired as soon as `sl<ChatCubit>()`'s
  // own constructor subscribes) so a test can call
  // `connectivityEventSink!.success([...])` to simulate a connectivity
  // change arriving from the OS.
  MockStreamHandlerEventSink? connectivityEventSink;

  /// Pushes a live `connectivity_plus` reading and flushes the microtask
  /// hops between the fake event channel and `ChatCubit`'s own listener
  /// (the channel's `receiveBroadcastStream` -> `connectivity_plus`'s
  /// `distinct()` wrapper -> `ConnectivityPlusWatcher`'s own controller ->
  /// `ChatCubit._handleConnectivityChange`) — same `Future.delayed(Duration.
  /// zero)`-per-hop convention `connectivity_plus_watcher_test.dart` uses.
  Future<void> emitConnectivity(List<String> results) async {
    connectivityEventSink!.success(results);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, handleSecureStorageCall);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          connectivityMethodChannel,
          (call) async => call.method == 'check' ? <String>['wifi'] : null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          connectivityEventChannel,
          MockStreamHandler.inline(
            onListen: (_, events) => connectivityEventSink = events,
            onCancel: (_) => connectivityEventSink = null,
          ),
        );
    fakePathProvider = FakePathProviderPlatform();
    PathProviderPlatform.instance = fakePathProvider;

    await resetCoreDependencies();
    await setupCoreDependencies();

    adapter = _FakeHttpClientAdapter();
    sl<Dio>().httpClientAdapter = adapter;

    // `chat-messages-send` et al. are bearer-required operations — seed a
    // user access token through the real `AccessTokenProvider` so the
    // real header interceptor has one to send.
    await sl<AccessTokenProvider>().saveAccessToken('e2e-test-access-token');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityMethodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(connectivityEventChannel, null);
    fakeNativeStorage.clear();
    await Hive.close();
    await resetCoreDependencies();
    await fakePathProvider.cleanUp();
  });

  test(
    'happy path: no existing session -> bootstrap creates one, then '
    'sendMessage() drives a genuine multi-chunk SSE POST to '
    'chat-messages-send/{sessionId} through the real pipeline, joining '
    'tokens split across chunk boundaries into one complete AI bubble',
    () async {
      adapter.queueJsonResponse(200, {'data': <dynamic>[]});
      adapter.queueJsonResponse(200, {
        'data': _sessionJson(id: 'session-1', updatedAt: '2026-01-01T00:00:00Z'),
      });
      adapter.queueJsonResponse(200, {'data': <dynamic>[]});
      adapter.queueSseResponse([
        'event: message_created\ndata: {"id":"srv-msg-1"}\n\n',
        // Split mid-event: this chunk ends inside an incomplete token
        // event's `data:` line, the next one finishes it and immediately
        // opens a second event in the same chunk.
        'event: token\ndata: {"delta":"Ol',
        'á, tudo bem?"}\n\nevent: token\ndata: {"delta":" Vamos conversar."}\n\n',
        'event: done\ndata: {}\n\n',
      ]);

      final cubit = sl<ChatCubit>();
      await cubit.init();
      expect(cubit.state, isA<ChatReady>());

      await cubit.sendMessage('Oi, bom dia!');

      final state = cubit.state as ChatReady;
      expect(state.sessionId, 'session-1');
      expect(state.isSending, isFalse);
      expect(state.messages, hasLength(2));
      expect(state.messages[0].role, ChatMessageRole.user);
      expect(state.messages[0].content, 'Oi, bom dia!');
      expect(state.messages[0].status, ChatMessageStatus.complete);
      expect(state.messages[1].role, ChatMessageRole.assistant);
      expect(state.messages[1].content, 'Olá, tudo bem? Vamos conversar.');
      expect(state.messages[1].status, ChatMessageStatus.complete);

      expect(adapter.requests, hasLength(4));
      final sendRequest = adapter.requests.last;
      expect(
        sendRequest.path,
        sl<UrlBuilder>().build('chat-messages-send', ['session-1']),
      );
      expect(sendRequest.data, {'content': 'Oi, bom dia!'});
      expect(sendRequest.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
      expect(
        sendRequest.headers['Authorization'],
        'Bearer e2e-test-access-token',
      );

      // The real write-through happened against the real `chat_sessions`
      // Hive box (`createSession()`'s own persist-then-return step).
      final sessionsBox = sl<Box<Map>>(instanceName: 'chat_sessions');
      expect(sessionsBox.get('session-1'), isNotNull);
    },
  );

  test(
    'review finding: a second sendMessage() on the same cubit, issued '
    'after the first one fully completed, resolves promptly through the '
    'real Dio/ApiClient.postStream subscription lifecycle — proves the '
    'stale-_sendSubscription-nulling fix (chat_cubit.dart\'s '
    '_consumeStream) actually works against a real subscription, not '
    'only the fake-StreamController-backed one unit tests use',
    () async {
      adapter.queueJsonResponse(200, {'data': <dynamic>[]});
      adapter.queueJsonResponse(200, {
        'data': _sessionJson(id: 'session-1', updatedAt: '2026-01-01T00:00:00Z'),
      });
      adapter.queueJsonResponse(200, {'data': <dynamic>[]});
      adapter.queueSseResponse([
        'event: token\ndata: {"delta":"Primeira resposta."}\n\n'
            'event: done\ndata: {}\n\n',
      ]);
      adapter.queueSseResponse([
        'event: token\ndata: {"delta":"Segunda resposta."}\n\n'
            'event: done\ndata: {}\n\n',
      ]);

      final cubit = sl<ChatCubit>();
      await cubit.init();

      await cubit.sendMessage('Primeira pergunta.');
      expect(
        (cubit.state as ChatReady).messages[1].content,
        'Primeira resposta.',
      );

      // Without the fix, the first call's own now-finished subscription
      // is never cleared, so this second call's `await
      // _sendSubscription?.cancel()` would hang on the real subscription
      // — the timeout turns that hang into a clear failure instead of a
      // stuck test run.
      await cubit
          .sendMessage('Segunda pergunta.')
          .timeout(const Duration(seconds: 5));

      final state = cubit.state as ChatReady;
      expect(state.messages, hasLength(4));
      expect(state.messages[3].content, 'Segunda resposta.');
      expect(state.messages[3].status, ChatMessageStatus.complete);
    },
  );

  test(
    'mid-stream drop: a connection that closes with no done/error event '
    'keeps the AI bubble\'s partial text (never cleared) and marks it '
    'failed, with no exception escaping the cubit',
    () async {
      adapter.queueJsonResponse(200, {
        'data': [_sessionJson(id: 'session-1', updatedAt: '2026-01-01T00:00:00Z')],
      });
      adapter.queueJsonResponse(200, {'data': <dynamic>[]});
      adapter.queueSseResponse([
        'event: message_created\ndata: {"id":"srv-msg-1"}\n\n'
            'event: token\ndata: {"delta":"Entendo."}\n\n',
        // Stream ends here with no `done`/`error` event — a mid-stream
        // drop (I/O matrix).
      ]);

      final cubit = sl<ChatCubit>();
      await cubit.init();

      await cubit.sendMessage('Como você está?');

      final state = cubit.state as ChatReady;
      expect(state.isSending, isFalse);
      expect(state.messages, hasLength(2));
      expect(state.messages[1].content, 'Entendo.');
      expect(state.messages[1].status, ChatMessageStatus.failed);
    },
  );

  test(
    'in-band error event: an SSE `error` event with a taxonomy code marks '
    'the AI bubble failed and fires exactly one POST (chat-messages-send '
    'is excluded from transparent retry)',
    () async {
      adapter.queueJsonResponse(200, {
        'data': [_sessionJson(id: 'session-1', updatedAt: '2026-01-01T00:00:00Z')],
      });
      adapter.queueJsonResponse(200, {'data': <dynamic>[]});
      adapter.queueSseResponse([
        'event: message_created\ndata: {"id":"srv-msg-1"}\n\n'
            'event: error\ndata: {"code":"RATE_LIMITED","message":"Limite atingido."}\n\n',
      ]);

      final cubit = sl<ChatCubit>();
      await cubit.init();

      await cubit.sendMessage('Mais uma pergunta.');

      final state = cubit.state as ChatReady;
      expect(state.isSending, isFalse);
      expect(state.messages[1].content, '');
      expect(state.messages[1].status, ChatMessageStatus.failed);

      // Exactly 3 requests total (sessions-list, messages-list, the one
      // send) — no retry attempt behind the scenes.
      expect(adapter.requests, hasLength(3));
    },
  );

  test(
    'spec-6-3: tap-to-retry on a failed AI bubble (its preceding user '
    'message already carrying a serverId) regenerates that exact bubble '
    'in place through the real chat-messages-retry endpoint — no new '
    'bubble pair, no re-send of the question',
    () async {
      adapter.queueJsonResponse(200, {
        'data': [_sessionJson(id: 'session-1', updatedAt: '2026-01-01T00:00:00Z')],
      });
      adapter.queueJsonResponse(200, {'data': <dynamic>[]});
      // `message_created` arrives (capturing the serverId), then the
      // stream drops mid-token with no `done`/`error` — I/O matrix's
      // "Tap retry, normal" precondition.
      adapter.queueSseResponse([
        'event: message_created\ndata: {"id":"srv-msg-1"}\n\n'
            'event: token\ndata: {"delta":"Entendo."}\n\n',
      ]);
      adapter.queueSseResponse([
        'event: token\ndata: {"delta":"Resposta regenerada."}\n\n'
            'event: done\ndata: {}\n\n',
      ]);

      final cubit = sl<ChatCubit>();
      await cubit.init();
      await cubit.sendMessage('Como você está?');

      var state = cubit.state as ChatReady;
      expect(state.messages, hasLength(2));
      final userMessageId = state.messages[0].id;
      final aiMessageId = state.messages[1].id;
      expect(state.messages[1].status, ChatMessageStatus.failed);

      await cubit.retryMessage(aiMessageId);

      state = cubit.state as ChatReady;
      expect(state.messages, hasLength(2));
      expect(state.messages[0].id, userMessageId);
      expect(state.messages[0].content, 'Como você está?');
      expect(state.messages[1].id, aiMessageId);
      expect(state.messages[1].content, 'Resposta regenerada.');
      expect(state.messages[1].status, ChatMessageStatus.complete);

      final retryRequest = adapter.requests.last;
      expect(
        retryRequest.path,
        sl<UrlBuilder>().build('chat-messages-retry', [
          'session-1',
          'srv-msg-1',
        ]),
      );
    },
  );

  test(
    'spec-6-3: tap-to-retry on a failed bubble whose stream dropped '
    'before message_created ever arrived falls back to a full '
    'chat-messages-send resend of the same question into the same '
    'bubble slot — never calls chat-messages-retry with no serverId',
    () async {
      adapter.queueJsonResponse(200, {
        'data': [_sessionJson(id: 'session-1', updatedAt: '2026-01-01T00:00:00Z')],
      });
      adapter.queueJsonResponse(200, {'data': <dynamic>[]});
      // Drops before `message_created` ever arrives — the user message
      // never gains a serverId (I/O matrix: "Tap retry, no serverId").
      adapter.queueSseResponse(['event: token\ndata: {"delta":"Oi."}\n\n']);
      adapter.queueSseResponse([
        'event: token\ndata: {"delta":"Resposta via resend."}\n\n'
            'event: done\ndata: {}\n\n',
      ]);

      final cubit = sl<ChatCubit>();
      await cubit.init();
      await cubit.sendMessage('Pergunta original.');

      var state = cubit.state as ChatReady;
      expect(state.messages, hasLength(2));
      final userMessageId = state.messages[0].id;
      final aiMessageId = state.messages[1].id;
      expect(state.messages[1].status, ChatMessageStatus.failed);

      await cubit.retryMessage(aiMessageId);

      state = cubit.state as ChatReady;
      expect(state.messages, hasLength(2));
      expect(state.messages[0].id, userMessageId);
      expect(state.messages[1].id, aiMessageId);
      expect(state.messages[1].content, 'Resposta via resend.');
      expect(state.messages[1].status, ChatMessageStatus.complete);

      expect(
        adapter.requests.every((r) => !r.path.contains('chat-messages-retry')),
        isTrue,
      );
      final sendUrl = sl<UrlBuilder>().build('chat-messages-send', ['session-1']);
      expect(adapter.requests.where((r) => r.path == sendUrl).length, 2);
    },
  );

  test(
    'spec-6-3: a live "offline" reading from the real connectivity_plus '
    'event-channel pipeline flips ChatReady.isOffline to true',
    () async {
      adapter.queueJsonResponse(200, {'data': <dynamic>[]});
      adapter.queueJsonResponse(200, {
        'data': _sessionJson(id: 'session-1', updatedAt: '2026-01-01T00:00:00Z'),
      });
      adapter.queueJsonResponse(200, {'data': <dynamic>[]});

      final cubit = sl<ChatCubit>();
      await cubit.init();
      expect((cubit.state as ChatReady).isOffline, isFalse);

      await emitConnectivity(['none']);

      expect((cubit.state as ChatReady).isOffline, isTrue);
    },
  );

  test(
    'spec-6-3: connectivity returning flips ChatReady.isOffline back to '
    'false through the same real event-channel pipeline',
    () async {
      adapter.queueJsonResponse(200, {'data': <dynamic>[]});
      adapter.queueJsonResponse(200, {
        'data': _sessionJson(id: 'session-1', updatedAt: '2026-01-01T00:00:00Z'),
      });
      adapter.queueJsonResponse(200, {'data': <dynamic>[]});

      final cubit = sl<ChatCubit>();
      await cubit.init();

      await emitConnectivity(['none']);
      expect((cubit.state as ChatReady).isOffline, isTrue);

      await emitConnectivity(['wifi']);
      expect((cubit.state as ChatReady).isOffline, isFalse);
    },
  );

  test(
    'spec-6-4: bookmarkMessage() on a user bubble drives a genuine POST '
    'to entries-create through the real SaveChatMessageAsEntryUseCase -> '
    'EntriesRepositoryImpl -> ApiClient pipeline, flips that bubble to '
    'BookmarkSaved, and persists the new Entry to the real `entries` Hive '
    'box -- none of the mocked chat_cubit_test.dart/chat_screen_test.dart '
    'coverage drives this cross-feature call through real production '
    'wiring',
    () async {
      adapter.queueJsonResponse(200, {'data': <dynamic>[]});
      adapter.queueJsonResponse(200, {
        'data': _sessionJson(id: 'session-1', updatedAt: '2026-01-01T00:00:00Z'),
      });
      adapter.queueJsonResponse(200, {'data': <dynamic>[]});
      adapter.queueSseResponse([
        'event: message_created\ndata: {"id":"srv-msg-1"}\n\n'
            'event: token\ndata: {"delta":"Entendo."}\n\n'
            'event: done\ndata: {}\n\n',
      ]);

      final cubit = sl<ChatCubit>();
      await cubit.init();
      await cubit.sendMessage('Como você está?');

      var state = cubit.state as ChatReady;
      final userMessage = state.messages[0];
      expect(userMessage.role, ChatMessageRole.user);
      expect(userMessage.serverId, 'srv-msg-1');
      expect(userMessage.bookmarkState, const BookmarkState.idle());

      adapter.queueJsonResponse(
        200,
        {'data': _entryJson(id: 'entry-1', chatMessageId: 'srv-msg-1')},
      );

      await cubit.bookmarkMessage(userMessage.id);

      state = cubit.state as ChatReady;
      expect(state.messages[0].bookmarkState, const BookmarkState.saved());
      // Rest of the session stays untouched by the bookmark save.
      expect(state.isSending, isFalse);
      expect(state.messages[1].content, 'Entendo.');

      final createRequest = adapter.requests.last;
      expect(
        createRequest.path,
        sl<UrlBuilder>().build('entries-create'),
      );
      expect(createRequest.data, {
        'content': 'Como você está?',
        'source': 'chat',
        'chatMessageId': 'srv-msg-1',
      });
      expect(
        createRequest.headers['Authorization'],
        'Bearer e2e-test-access-token',
      );

      // The real write-through happened against the real `entries` Hive
      // box (`EntriesRepositoryImpl.create()`'s own persist-then-return
      // step) -- proves the use case really reached the entries feature's
      // own repository, not a fake standing in for it.
      final entriesBox = sl<Box<Map>>();
      expect(entriesBox.get('entry-1'), isNotNull);

      // I/O matrix: "Already saved" -- tapping a BookmarkSaved bubble
      // again is a client-side no-op, no second entries-create call.
      await cubit.bookmarkMessage(userMessage.id);
      expect(adapter.requests, hasLength(5));
    },
  );

  test(
    'spec-6-4: a failing entries-create flips only the tapped bubble to '
    'BookmarkError, leaving the rest of the Chat Session (composer, other '
    'bubbles) fully usable -- the save never propagates past '
    'bookmarkMessage()',
    () async {
      adapter.queueJsonResponse(200, {'data': <dynamic>[]});
      adapter.queueJsonResponse(200, {
        'data': _sessionJson(id: 'session-1', updatedAt: '2026-01-01T00:00:00Z'),
      });
      adapter.queueJsonResponse(200, {'data': <dynamic>[]});
      adapter.queueSseResponse([
        'event: message_created\ndata: {"id":"srv-msg-1"}\n\n'
            'event: token\ndata: {"delta":"Entendo."}\n\n'
            'event: done\ndata: {}\n\n',
      ]);

      final cubit = sl<ChatCubit>();
      await cubit.init();
      await cubit.sendMessage('Como você está?');

      final userMessage = (cubit.state as ChatReady).messages[0];

      adapter.queueErrorResponse('INTERNAL_ERROR', 'Falha ao salvar.');

      await cubit.bookmarkMessage(userMessage.id);

      final state = cubit.state as ChatReady;
      expect(state.messages[0].bookmarkState, isA<BookmarkError>());
      // The session itself is untouched: still ChatReady, composer
      // re-enabled, the unrelated AI bubble unaffected.
      expect(state.isSending, isFalse);
      expect(state.isOffline, isFalse);
      expect(state.messages[1].content, 'Entendo.');
      expect(state.messages[1].status, ChatMessageStatus.complete);
    },
  );
}
