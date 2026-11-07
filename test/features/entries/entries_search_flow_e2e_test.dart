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
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';

import '../../support/fake_path_provider_platform.dart';

/// Same shape as `entries_list_flow_e2e_test.dart`'s/
/// `entry_detail_flow_e2e_test.dart`'s own fake adapter — only the
/// transport boundary is faked.
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

/// End-to-end coverage for spec-5-1's `search()` path — the new
/// real-pipeline surface this story introduces
/// (`EntriesRepositoryImpl.search` -> `EntriesRemoteDataSource.search` ->
/// `ApiClient` -> `Dio` (both real interceptors attached) -> a real
/// `entries` Hive box), the same tier `entry_detail_flow_e2e_test.dart`
/// already proves for `getById()` (Tasks & Acceptance: "same rationale
/// spec-4-4 used for `getById`").
///
/// Driven directly against `EntriesRepository.search()` rather than
/// `EntriesSearchCubit` — `entries_search_cubit_test.dart` already proves
/// the debounce/generation-guard state machine against a fake repository;
/// this file's own job is only the real network + real disk pipeline
/// underneath it, matching `entries_list_flow_e2e_test.dart`'s/
/// `entry_detail_flow_e2e_test.dart`'s own split between cubit-level and
/// repository-level e2e coverage.
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

    // `entries-search` is a bearer-required operation — seed a user access
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

  test('happy path: search() fires a genuine GET to entries-search with the '
      'right URL/headers/query ({q: query}, never limit/cursor), resolves '
      'Right with a semantic match, and persists it to the real entries '
      'Hive box', () async {
    adapter.queueJsonResponse(200, {
      'data': [
        _entryJson(
          id: 'entry-1',
          content: 'Hoje me senti muito nervoso no trabalho.',
          source: 'manual',
          occurredAt: '2026-01-02T10:00:00Z',
        ),
      ],
    });

    final result = await sl<EntriesRepository>().search('ansiedade');

    expect(result.isRight(), isTrue);
    result.match((_) => fail('expected Right'), (entries) {
      expect(entries, hasLength(1));
      expect(entries.single.id, 'entry-1');
      expect(
        entries.single.content,
        'Hoje me senti muito nervoso no trabalho.',
      );
    });

    expect(adapter.requests, hasLength(1));
    final sent = adapter.requests.single;
    expect(sent.path, sl<UrlBuilder>().build('entries-search'));
    expect(sent.queryParameters, {'q': 'ansiedade'});
    expect(sent.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
    expect(sent.headers['Authorization'], 'Bearer e2e-test-access-token');

    final box = sl<Box<Map>>();
    expect(
      box.get('entry-1')!['content'],
      'Hoje me senti muito nervoso no trabalho.',
    );
  });

  test('offline: search() genuinely retries a NETWORK_OFFLINE entries-search '
      'call maxRetries times over the real RetryInterceptor, then '
      'propagates Left(networkOffline) unmapped — no cache fallback (AD-9), '
      'even with a matching entry already cached from a prior list()/'
      'getById()', () async {
    final box = sl<Box<Map>>();
    await box.put(
      'cached-1',
      _entryJson(
        id: 'cached-1',
        content: 'Um registro antigo qualquer, já em cache.',
        source: 'manual',
        occurredAt: '2026-01-01T00:00:00Z',
      ),
    );

    for (var i = 0; i <= RetryInterceptor.maxRetries; i++) {
      adapter.queueErrorResponse('NETWORK_OFFLINE', 'Sem conexão');
    }

    final result = await sl<EntriesRepository>().search('ansiedade');

    expect(result.isLeft(), isTrue);
    result.match(
      (failure) => expect(failure.message, 'Sem conexão'),
      (_) => fail(
        'expected Left — AD-9: no client-side vector index/'
        'cache fallback for search',
      ),
    );
    expect(adapter.requests, hasLength(1 + RetryInterceptor.maxRetries));

    // The pre-existing cache entry is untouched — search() never reads
    // or writes it on a failure path.
    expect(box.length, 1);
    expect(box.get('cached-1'), isNotNull);
  });

  // spec-5-3 (deferred-work.md, 2026-11-05): closes the self-disclosed gap
  // that no e2e test drove `entries-search` with `source`/`dateFrom`/
  // `dateTo` over the real network/Hive pipeline — only the mocked-
  // `ApiClient` tier (`entries_remote_data_source_test.dart`) and the
  // fake-repository tier (cubit/widget tests) covered them until now.
  // Same source/date serialization convention
  // `entries_filters_flow_e2e_test.dart` already proves for `list()`:
  // `source` as `.name`, `dateFrom`/`dateTo` as `.toUtc().toIso8601String()`.
  test(
    'source filter: search(source: audio) sends {q, source} to '
    'entries-search over the real pipeline and persists the real result',
    () async {
      adapter.queueJsonResponse(200, {
        'data': [
          _entryJson(
            id: 'entry-audio-1',
            content: 'Um áudio sobre ansiedade.',
            source: 'audio',
            occurredAt: '2026-01-02T10:00:00Z',
          ),
        ],
      });

      final result = await sl<EntriesRepository>().search(
        'ansiedade',
        source: EntrySource.audio,
      );

      expect(result.isRight(), isTrue);
      final sent = adapter.requests.single.queryParameters;
      expect(sent, {'q': 'ansiedade', 'source': 'audio'});

      final box = sl<Box<Map>>();
      expect(box.get('entry-audio-1')!['source'], 'audio');
    },
  );

  test('date range filter: search(dateFrom/dateTo) sends both as their own '
      'UTC ISO8601 strings to entries-search over the real pipeline, with '
      'no source param', () async {
    adapter.queueJsonResponse(200, {
      'data': [
        _entryJson(
          id: 'entry-dated-1',
          content: 'Um registro de janeiro sobre ansiedade.',
          source: 'manual',
          occurredAt: '2026-01-15T10:00:00Z',
        ),
      ],
    });

    final dateFrom = DateTime(2026, 1, 1);
    final dateTo = DateTime(2026, 1, 31);

    final result = await sl<EntriesRepository>().search(
      'ansiedade',
      dateFrom: dateFrom,
      dateTo: dateTo,
    );

    expect(result.isRight(), isTrue);
    final sent = adapter.requests.single.queryParameters;
    expect(sent['q'], 'ansiedade');
    expect(sent.containsKey('source'), isFalse);
    expect(sent['dateFrom'], dateFrom.toUtc().toIso8601String());
    expect(sent['dateTo'], dateTo.toUtc().toIso8601String());
    expect(sent['dateFrom'], endsWith('Z'));
    expect(sent['dateTo'], endsWith('Z'));

    final box = sl<Box<Map>>();
    expect(box.get('entry-dated-1')!['content'], isNotNull);
  });
}
