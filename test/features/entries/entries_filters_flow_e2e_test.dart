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
import 'package:cerne/features/entries/presentation/cubit/meus_registros_cubit.dart';
import 'package:cerne/features/entries/presentation/cubit/meus_registros_state.dart';

import '../../support/fake_path_provider_platform.dart';

/// Same shape as `entries_list_flow_e2e_test.dart`'s/
/// `entries_search_flow_e2e_test.dart`'s own fake adapter — only the
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

/// End-to-end coverage for spec-5-2's metadata-filters path — the real
/// `MeusRegistrosCubit.applyFilters()`/`clearFilters()`/`loadMore()` ->
/// `EntriesRepositoryImpl.list()` -> `EntriesRemoteDataSource.list()` ->
/// `ApiClient` -> `Dio` (both real interceptors attached) -> a real
/// `entries` Hive box pipeline, same tier `entries_list_flow_e2e_test.dart`
/// already proves for the unfiltered path and `entries_search_flow_e2e_test
/// .dart` proves for `search()`.
///
/// `meus_registros_cubit_test.dart` already proves the filter state
/// machine (which params `list()` is called with) against a fake
/// repository, and `entries_remote_data_source_test.dart` already proves
/// the `source`/`dateFrom`/`dateTo` query-param serialization (including
/// the UTC `Z`-suffix conversion) against a mocked `ApiClient`. This file's
/// own job is only the real network + real disk pipeline underneath both —
/// including the one behavior that only shows up at this tier: the
/// offline-fallback cache dump staying filter-oblivious (AD-9,
/// `EntriesRepository.list()`'s own doc) when the real `RetryInterceptor`
/// exhausts its retries on a filtered query.
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

    // `entries-list` is a bearer-required operation — seed a user access
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

  test('source filter: applyFilters(source: audio) fires a genuine GET to '
      'entries-list with {limit, source} (no date bounds), lands the real '
      'cubit on MeusRegistrosLoaded, and persists the filtered page to the '
      'real entries Hive box', () async {
    adapter.queueJsonResponse(200, {
      'data': [
        _entryJson(
          id: 'entry-audio-1',
          content: 'Áudio transcrito do dia.',
          source: 'audio',
          occurredAt: '2026-01-02T10:00:00Z',
        ),
      ],
      'meta': {'nextCursor': null},
    });

    final cubit = sl<MeusRegistrosCubit>();
    await cubit.applyFilters(source: EntrySource.audio);

    final state = cubit.state;
    expect(state, isA<MeusRegistrosLoaded>());
    final loaded = state as MeusRegistrosLoaded;
    expect(loaded.entries.map((e) => e.id), ['entry-audio-1']);
    expect(cubit.activeSource, EntrySource.audio);

    expect(adapter.requests, hasLength(1));
    final sent = adapter.requests.single;
    expect(sent.path, sl<UrlBuilder>().build('entries-list'));
    expect(sent.queryParameters, {'limit': 20, 'source': 'audio'});
    expect(sent.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
    expect(sent.headers['Authorization'], 'Bearer e2e-test-access-token');

    final box = sl<Box<Map>>();
    expect(box.get('entry-audio-1')!['source'], 'audio');
  });

  test('date range filter: applyFilters(dateFrom/dateTo) sends both as their '
      'own .toUtc().toIso8601String() query params over the real pipeline, '
      'with no source param', () async {
    adapter.queueJsonResponse(200, {
      'data': [
        _entryJson(
          id: 'entry-january',
          content: 'Registro de janeiro.',
          source: 'manual',
          occurredAt: '2026-01-15T10:00:00Z',
        ),
      ],
      'meta': {'nextCursor': null},
    });

    final dateFrom = DateTime(2026, 1, 1);
    final dateTo = DateTime(2026, 1, 31);
    final cubit = sl<MeusRegistrosCubit>();
    await cubit.applyFilters(dateFrom: dateFrom, dateTo: dateTo);

    expect(cubit.state, isA<MeusRegistrosLoaded>());
    expect(adapter.requests, hasLength(1));
    final sent = adapter.requests.single.queryParameters;
    expect(sent['limit'], 20);
    expect(sent.containsKey('source'), isFalse);
    expect(sent['dateFrom'], dateFrom.toUtc().toIso8601String());
    expect(sent['dateTo'], dateTo.toUtc().toIso8601String());
    expect(sent['dateFrom'], endsWith('Z'));
    expect(sent['dateTo'], endsWith('Z'));
  });

  test('pagination with filters active: loadMore() after a filtered first '
      'page carries the same source/dateFrom/dateTo forward alongside the '
      'real cursor, and appends the new page to the real Hive box', () async {
    final dateFrom = DateTime(2026, 1, 1);
    final dateTo = DateTime(2026, 1, 31);

    adapter.queueJsonResponse(200, {
      'data': [
        _entryJson(
          id: 'entry-1',
          content: 'Primeira página filtrada.',
          source: 'photo',
          occurredAt: '2026-01-10T10:00:00Z',
        ),
      ],
      'meta': {'nextCursor': 'cursor-page-2'},
    });

    final cubit = sl<MeusRegistrosCubit>();
    await cubit.applyFilters(
      source: EntrySource.photo,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );

    adapter.queueJsonResponse(200, {
      'data': [
        _entryJson(
          id: 'entry-2',
          content: 'Segunda página filtrada.',
          source: 'photo',
          occurredAt: '2026-01-05T10:00:00Z',
        ),
      ],
      'meta': {'nextCursor': null},
    });

    await cubit.loadMore();

    final loaded = cubit.state as MeusRegistrosLoaded;
    expect(loaded.entries.map((e) => e.id), ['entry-1', 'entry-2']);
    expect(loaded.nextCursor, isNull);

    expect(adapter.requests, hasLength(2));
    final secondRequest = adapter.requests.last.queryParameters;
    expect(secondRequest['cursor'], 'cursor-page-2');
    expect(secondRequest['source'], 'photo');
    expect(secondRequest['dateFrom'], dateFrom.toUtc().toIso8601String());
    expect(secondRequest['dateTo'], dateTo.toUtc().toIso8601String());

    final box = sl<Box<Map>>();
    expect(box.keys, containsAll(['entry-1', 'entry-2']));
  });

  test('offline fallback stays filter-oblivious (AD-9): applyFilters() '
      'genuinely retries a NETWORK_OFFLINE entries-list call maxRetries '
      'times over the real RetryInterceptor, then falls back to the full '
      'cached entries Hive box dump — not a client-side-filtered subset — '
      'sorted occurredAt desc', () async {
    final box = sl<Box<Map>>();
    await box.putAll({
      'cached-manual': _entryJson(
        id: 'cached-manual',
        content: 'Registro manual antigo (não bate o filtro de áudio).',
        source: 'manual',
        occurredAt: '2026-01-01T00:00:00Z',
      ),
      'cached-audio': _entryJson(
        id: 'cached-audio',
        content: 'Registro de áudio mais recente.',
        source: 'audio',
        occurredAt: '2026-01-03T00:00:00Z',
      ),
    });

    for (var i = 0; i <= RetryInterceptor.maxRetries; i++) {
      adapter.queueErrorResponse('NETWORK_OFFLINE', 'Sem conexão');
    }

    final cubit = sl<MeusRegistrosCubit>();
    await cubit.applyFilters(source: EntrySource.audio);

    final loaded = cubit.state as MeusRegistrosLoaded;
    // The fallback returns both cached entries — including the one that
    // doesn't match the active `source: audio` filter — because the
    // cache dump is never locally filtered (AD-9).
    expect(loaded.entries.map((e) => e.id), ['cached-audio', 'cached-manual']);
    expect(loaded.nextCursor, isNull);
    expect(cubit.activeSource, EntrySource.audio);

    expect(adapter.requests, hasLength(1 + RetryInterceptor.maxRetries));
    expect(adapter.requests.first.queryParameters['source'], 'audio');
  });

  test('clearFilters() after a filtered load re-queries entries-list over the '
      'real pipeline with no source/dateFrom/dateTo — just limit', () async {
    adapter.queueJsonResponse(200, {
      'data': [
        _entryJson(
          id: 'entry-filtered',
          content: 'Resultado filtrado.',
          source: 'chat',
          occurredAt: '2026-01-10T10:00:00Z',
        ),
      ],
      'meta': {'nextCursor': null},
    });
    final cubit = sl<MeusRegistrosCubit>();
    await cubit.applyFilters(source: EntrySource.chat);

    adapter.queueJsonResponse(200, {
      'data': [
        _entryJson(
          id: 'entry-unfiltered',
          content: 'Resultado completo.',
          source: 'manual',
          occurredAt: '2026-01-11T10:00:00Z',
        ),
      ],
      'meta': {'nextCursor': null},
    });

    await cubit.clearFilters();

    expect(cubit.hasActiveFilters, isFalse);
    final loaded = cubit.state as MeusRegistrosLoaded;
    expect(loaded.entries.map((e) => e.id), ['entry-unfiltered']);

    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.last.queryParameters, {'limit': 20});
  });
}
