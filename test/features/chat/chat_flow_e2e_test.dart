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

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, handleSecureStorageCall);
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
}
