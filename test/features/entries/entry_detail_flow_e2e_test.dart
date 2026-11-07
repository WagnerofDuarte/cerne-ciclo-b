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
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';

import '../../support/fake_path_provider_platform.dart';

/// Same shape as `entries_list_flow_e2e_test.dart`'s own fake adapter —
/// only the transport boundary is faked.
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

/// End-to-end coverage for spec-4-4's `getById` path — the new
/// real-pipeline surface this story introduces (`EntriesRepositoryImpl.
/// getById` -> `EntriesRemoteDataSource.get` -> `ApiClient` -> `Dio` (both
/// real interceptors attached) -> a real `entries` Hive box), the same
/// tier `entries_list_flow_e2e_test.dart` already proves for `list()`.
///
/// Review finding (round 2): this story's own `getById`/`EntryDetailCubit`
/// I/O matrix was previously only proven against mocks/fakes
/// (`entries_repository_impl_test.dart`, `entry_detail_cubit_test.dart`) —
/// `tests/test-summary.md`'s own "Next Steps" from the prior run flagged
/// this exact gap.
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
        .setMockMethodCallHandler(
          secureStorageChannel,
          handleSecureStorageCall,
        );
    fakePathProvider = FakePathProviderPlatform();
    PathProviderPlatform.instance = fakePathProvider;

    await resetCoreDependencies();
    await setupCoreDependencies();

    adapter = _FakeHttpClientAdapter();
    sl<Dio>().httpClientAdapter = adapter;

    // `entries-get` is a bearer-required operation — seed a user access
    // token through the real `AccessTokenProvider` so the real header
    // interceptor has one to send.
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

  test('happy path: getById() fires a genuine GET to entries-get/{id} with '
      'the right URL/headers, resolves Right, and persists the entry to the '
      'real entries Hive box', () async {
    adapter.queueJsonResponse(200, {
      'data': _entryJson(
        id: 'entry-1',
        content: 'Primeiro registro do dia.',
        source: 'manual',
        occurredAt: '2026-01-02T10:00:00Z',
      ),
    });

    final result = await sl<EntriesRepository>().getById('entry-1');

    expect(result.isRight(), isTrue);
    result.match((_) => fail('expected Right'), (entry) {
      expect(entry.id, 'entry-1');
      expect(entry.content, 'Primeiro registro do dia.');
    });

    expect(adapter.requests, hasLength(1));
    final sent = adapter.requests.single;
    expect(sent.path, sl<UrlBuilder>().build('entries-get', ['entry-1']));
    expect(sent.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
    expect(sent.headers['Authorization'], 'Bearer e2e-test-access-token');

    final box = sl<Box<Map>>();
    expect(box.get('entry-1')!['content'], 'Primeiro registro do dia.');
  });

  test('offline fallback: getById() genuinely retries a NETWORK_OFFLINE '
      'entries-get call maxRetries times over the real RetryInterceptor '
      'before falling back to the real cached entry in the Hive box', () async {
    final box = sl<Box<Map>>();
    await box.put(
      'entry-1',
      _entryJson(
        id: 'entry-1',
        content: 'Versão em cache.',
        source: 'manual',
        occurredAt: '2026-01-01T00:00:00Z',
      ),
    );

    for (var i = 0; i <= RetryInterceptor.maxRetries; i++) {
      adapter.queueErrorResponse('NETWORK_OFFLINE', 'Sem conexão');
    }

    final result = await sl<EntriesRepository>().getById('entry-1');

    expect(result.isRight(), isTrue);
    result.match(
      (_) => fail('expected Right'),
      (entry) => expect(entry.content, 'Versão em cache.'),
    );
    expect(adapter.requests, hasLength(1 + RetryInterceptor.maxRetries));
  });

  test('not-found: a genuine NOT_FOUND response propagates as Left with no '
      'cache fallback, no synthesized state — the exact Failure the backend '
      'produced', () async {
    adapter.queueErrorResponse('NOT_FOUND', 'Registro não encontrado');

    final result = await sl<EntriesRepository>().getById('unknown-id');

    expect(result.isLeft(), isTrue);
    expect(adapter.requests, hasLength(1));
  });
}
