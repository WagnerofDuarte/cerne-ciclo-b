import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:cerne/core/di/injection_container.dart';
import 'package:cerne/core/network/access_token_provider.dart';
import 'package:cerne/core/network/retry_interceptor.dart';
import 'package:cerne/core/network/url_builder.dart';
import 'package:cerne/features/entries/presentation/cubit/meus_registros_cubit.dart';
import 'package:cerne/features/entries/presentation/cubit/meus_registros_state.dart';

import '../../support/fake_path_provider_platform.dart';

/// Same shape as `capture_flow_e2e_test.dart`'s own fake — only the
/// transport boundary is faked, everything above it (URL building, both
/// real interceptors, `ApiClient`'s mapping) and below it (real `hive_ce`
/// write-through) is the genuine production wiring. [queueErrorResponse]
/// additionally lets a test simulate a retryable backend code (e.g.
/// `NETWORK_OFFLINE`) the same way `network_pipeline_integration_test.dart`
/// does — a JSON body carrying `code`, not a thrown `DioException` — since
/// `dioErrorCodeOf` reads `data['code']` before ever looking at the
/// response's own HTTP status.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<({int statusCode, Map<String, dynamic> body})> _queue = [];

  void queueJsonResponse(int statusCode, Map<String, dynamic> body) {
    _queue.add((statusCode: statusCode, body: body));
  }

  void queueErrorResponse(String code, String message) {
    queueJsonResponse(503, {
      'code': code,
      'message': message,
      'retryable': true,
    });
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
    final next = _queue.removeAt(0);
    return ResponseBody.fromString(
      jsonEncode(next.body),
      next.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _entryJson({
  required String id,
  required String content,
  required String source,
  required String occurredAt,
}) => {
  'id': id,
  'content': content,
  'source': source,
  'chatMessageId': null,
  'occurredAt': occurredAt,
  'serverRevision': 1,
  'createdAt': occurredAt,
  'updatedAt': occurredAt,
};

/// End-to-end coverage for spec-4-1's `list()` path — the counterpart
/// `capture_flow_e2e_test.dart` already proves for `create()`. Driven
/// directly against `MeusRegistrosCubit`'s own public API
/// (`loadFirstPage`/`loadMore`), the exact `lazySingleton` instance
/// `MeusRegistrosScreen` resolves through `sl`, wired to the real
/// `EntriesRepositoryImpl` -> `EntriesRemoteDataSource` -> `ApiClient` ->
/// `Dio` (both real interceptors attached) -> a real `entries` Hive box.
///
/// This complements rather than duplicates existing coverage:
/// `meus_registros_cubit_test.dart`/`meus_registros_screen_test.dart`
/// already prove the state machine/UI against a fake `EntriesRepository`,
/// and `entries_repository_impl_test.dart` already proves
/// `list()`/`_offlineFallback()` against a mocked datasource/`Box`. None
/// of them drives the real cubit through the real network + real disk
/// pipeline together, including a genuine retry-then-fallback sequence,
/// the way the app actually does on opening "Meus Registros" — a gap
/// `deferred-work.md` names explicitly for spec-4-1.
///
/// Like `capture_flow_e2e_test.dart`, this uses a plain `test()` driving
/// the cubit directly rather than `tester.tap`/`pumpAndSettle`: these
/// awaits are genuine async I/O (real Dio round trips, including the
/// retry interceptor's real 500ms delay in the offline-fallback case), and
/// `pumpAndSettle()` only waits for scheduled frames under the fake-async
/// test clock.
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

    // `entries-list` is a bearer-required operation — seed a user access
    // token through the real `AccessTokenProvider` (backed by the faked
    // secure storage channel above) so the real header interceptor has
    // one to send.
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
    'happy path: loadFirstPage() fires a genuine GET to entries-list with '
    'the right URL/headers/query, lands the real cubit on MeusRegistrosLoaded, '
    'and persists every item to the real entries Hive box',
    () async {
      adapter.queueJsonResponse(200, {
        'data': [
          _entryJson(
            id: 'entry-1',
            content: 'Primeiro registro do dia.',
            source: 'manual',
            occurredAt: '2026-01-02T10:00:00Z',
          ),
          _entryJson(
            id: 'entry-2',
            content: 'Áudio transcrito.',
            source: 'audio',
            occurredAt: '2026-01-01T09:00:00Z',
          ),
        ],
        'meta': {'nextCursor': 'cursor-page-2'},
      });

      final cubit = sl<MeusRegistrosCubit>();
      await cubit.loadFirstPage();

      final state = cubit.state;
      expect(state, isA<MeusRegistrosLoaded>());
      final loaded = state as MeusRegistrosLoaded;
      expect(loaded.entries.map((e) => e.id), ['entry-1', 'entry-2']);
      expect(loaded.nextCursor, 'cursor-page-2');

      // Exactly one real request left through the fake transport, built by
      // the real UrlBuilder/HeaderInterceptor, not a mock of ApiClient.
      expect(adapter.requests, hasLength(1));
      final sent = adapter.requests.single;
      expect(sent.path, sl<UrlBuilder>().build('entries-list'));
      expect(sent.queryParameters, {'limit': 20});
      expect(sent.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
      expect(
        sent.headers['Authorization'],
        'Bearer e2e-test-access-token',
      );

      // The real write-through happened against the real Hive box.
      final box = sl<Box<Map>>();
      expect(box.get('entry-1')!['content'], 'Primeiro registro do dia.');
      expect(box.get('entry-2')!['source'], 'audio');
    },
  );

  test(
    'pagination: loadMore() against the real pipeline sends the held '
    'nextCursor as a query param, appends the new page with no dup ids, '
    'and persists the new items to the real Hive box alongside the first '
    'page\'s',
    () async {
      adapter.queueJsonResponse(200, {
        'data': [
          _entryJson(
            id: 'entry-1',
            content: 'Primeiro registro do dia.',
            source: 'manual',
            occurredAt: '2026-01-02T10:00:00Z',
          ),
        ],
        'meta': {'nextCursor': 'cursor-page-2'},
      });

      final cubit = sl<MeusRegistrosCubit>();
      await cubit.loadFirstPage();

      adapter.queueJsonResponse(200, {
        'data': [
          _entryJson(
            id: 'entry-2',
            content: 'Foto do dia anterior.',
            source: 'photo',
            occurredAt: '2025-12-31T08:00:00Z',
          ),
        ],
        'meta': {'nextCursor': null},
      });

      await cubit.loadMore();

      final loaded = cubit.state as MeusRegistrosLoaded;
      expect(loaded.entries.map((e) => e.id), ['entry-1', 'entry-2']);
      expect(loaded.nextCursor, isNull);

      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.last.queryParameters, {
        'limit': 20,
        'cursor': 'cursor-page-2',
      });

      final box = sl<Box<Map>>();
      expect(box.keys, containsAll(['entry-1', 'entry-2']));
    },
  );

  test(
    'offline fallback: loadFirstPage() genuinely retries a NETWORK_OFFLINE '
    'entries-list call maxRetries times over the real RetryInterceptor '
    'before falling back to the real cached entries Hive box, sorted '
    'occurredAt desc',
    () async {
      final box = sl<Box<Map>>();
      await box.putAll({
        'cached-older': _entryJson(
          id: 'cached-older',
          content: 'Registro antigo.',
          source: 'manual',
          occurredAt: '2026-01-01T00:00:00Z',
        ),
        'cached-newer': _entryJson(
          id: 'cached-newer',
          content: 'Registro mais recente.',
          source: 'manual',
          occurredAt: '2026-01-03T00:00:00Z',
        ),
      });

      // Initial attempt + RetryInterceptor.maxRetries retries, all
      // genuinely retryable (error-taxonomy.md's NETWORK_OFFLINE).
      for (var i = 0; i <= RetryInterceptor.maxRetries; i++) {
        adapter.queueErrorResponse('NETWORK_OFFLINE', 'Sem conexão');
      }

      final cubit = sl<MeusRegistrosCubit>();
      await cubit.loadFirstPage();

      final loaded = cubit.state as MeusRegistrosLoaded;
      expect(loaded.entries.map((e) => e.id), [
        'cached-newer',
        'cached-older',
      ]);
      expect(loaded.nextCursor, isNull);

      // Every retry genuinely left through the real Dio pipeline before
      // the repository's own offline fallback ever engaged.
      expect(adapter.requests, hasLength(1 + RetryInterceptor.maxRetries));

      // The fallback only reads the cache — it never writes to it.
      expect(box.length, 2);
    },
  );
}
