import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:cerne/core/di/injection_container.dart';
import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/network/access_token_provider.dart';
import 'package:cerne/core/network/retry_interceptor.dart';
import 'package:cerne/core/network/url_builder.dart';
import 'package:cerne/core/resource.dart';
import 'package:cerne/features/dashboard/domain/entities/dashboard_aggregate.dart';
import 'package:cerne/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:cerne/features/dashboard/presentation/cubit/dashboard_narrative_cubit.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';

import '../../support/fake_path_provider_platform.dart';

/// Same shape as `pending_write_sync_e2e_test.dart`'s/`export_flow_e2e_test.
/// dart`'s own fake — only the transport boundary is faked, everything
/// above it (URL building, both real interceptors, `ApiClient`'s mapping,
/// `DashboardAggregateDto`'s decode) is the genuine production wiring.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<({int statusCode, Map<String, dynamic> body})> _queue = [];

  void queueJsonResponse(int statusCode, Map<String, dynamic> body) {
    _queue.add((statusCode: statusCode, body: body));
  }

  void queueErrorResponse(String code, String message) {
    final status = switch (code) {
      'VALIDATION_ERROR' => 400,
      'NETWORK_TIMEOUT' => 504,
      _ => 500,
    };
    queueJsonResponse(status, {
      'code': code,
      'message': message,
      'retryable': RetryInterceptor.retryableCodes.contains(code),
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

/// `dashboard.aggregate.get`'s own `sources` shape — zero-filled, same as
/// `dashboard_remote_data_source_test.dart`'s own fixture; the domain layer
/// never reads these, but the DTO's `@JsonSerializable` requires all four.
Map<String, dynamic> _sourcesJson() => {
  'manual': 0,
  'audio': 0,
  'photo': 0,
  'chat': 0,
};

/// `dashboard-narrative-get`'s own `data` shape (`openapi.yaml:1689-1736`) —
/// same fixture precedent [_aggregateJson] already sets for its own
/// endpoint.
Map<String, dynamic> _narrativeJson({
  required String text,
  String generatedAt = '2026-01-01T00:00:00Z',
}) => {
  'data': {'text': text, 'generatedAt': generatedAt},
};

Map<String, dynamic> _bucketJson(String date, int count) => {
  'date': date,
  'count': count,
  'sources': _sourcesJson(),
};

Map<String, dynamic> _aggregateJson({
  required int totalCount,
  required List<Map<String, dynamic>> buckets,
}) => {
  'data': {
    'buckets': buckets,
    'totals': {'count': totalCount, 'sources': _sourcesJson()},
  },
};

/// `entries.create`'s own confirmed-entry response shape, same fixture
/// `pending_write_sync_e2e_test.dart` already uses.
Map<String, dynamic> _entryJson({
  required String id,
  required String content,
  required String source,
  required String occurredAt,
}) => {
  'data': {
    'id': id,
    'content': content,
    'source': source,
    'chatMessageId': null,
    'occurredAt': occurredAt,
    'serverRevision': 1,
    'createdAt': occurredAt,
    'updatedAt': occurredAt,
  },
};

/// Waits for [cubit]'s state to satisfy [match] via its own `stream`,
/// rather than a fixed real-time sleep — same rationale/shape
/// `export_flow_e2e_test.dart`'s own `_waitForState` gives: `load()`'s real
/// `dio` round trip (and, in the confirmedWrites test below, a second one
/// triggered with no test code calling `load()` itself) isn't guaranteed to
/// have landed by any particular `pump()`/microtask count.
Future<void> _waitForState(
  DashboardCubit cubit,
  bool Function(Resource<DashboardAggregate>) match,
) {
  if (match(cubit.state)) {
    return Future.value();
  }
  return cubit.stream.firstWhere(match).timeout(const Duration(seconds: 10));
}

/// Same rationale as [_waitForState], for [DashboardNarrativeCubit]'s own
/// `Resource<String>` — review finding: the sibling [DashboardCubit] had a
/// dedicated real-`confirmedWrites` e2e proof, this cubit (Boundaries:
/// "mirroring DashboardCubit's exact shape") did not.
Future<void> _waitForNarrativeState(
  DashboardNarrativeCubit cubit,
  bool Function(Resource<String>) match,
) {
  if (match(cubit.state)) {
    return Future.value();
  }
  return cubit.stream.firstWhere(match).timeout(const Duration(seconds: 10));
}

/// End-to-end coverage for spec-8-1's dashboard aggregation (plus spec-8-2's
/// independent narrative fetch, added in its own `DashboardNarrativeCubit`
/// group below), driven through the real production object graph `sl`
/// resolves for `AccountSettingsScreen` (its `dashboardCubit` and
/// `narrativeCubit` constructor params, `app_router.dart`) — the real
/// `DashboardCubit`/`DashboardNarrativeCubit` through `DashboardRepositoryImpl`,
/// `DashboardRemoteDataSource`, `ApiClient` and `Dio` (both real
/// interceptors attached) down to this faked transport boundary only. No
/// device/simulator/CI exists yet (AGENTS.md).
///
/// Complements rather than duplicates existing coverage: `dashboard_cubit_
/// test.dart` already proves every I/O-matrix transition against a
/// hand-written fake `DashboardRepository`/`PendingEntryWriteTracker` (no
/// real `Failure.fromCode`/DTO decoding, no real shared-tracker DI wiring
/// involved), `dashboard_remote_data_source_test.dart` proves the DTO
/// mapping against a *mocked* `ApiClient`, and `account_settings_screen_
/// test.dart`/`dashboard_chart_section_test.dart` prove the chart's own
/// rendering against a fake repository too. None of them drives a real
/// `dashboard-aggregate-get` round trip — real URL building, real headers,
/// the real `RetryInterceptor` policy, the real `DashboardAggregateDto.
/// toDomain()` mapping off a real decoded JSON payload — nor proves that
/// `DashboardCubit`'s own constructor subscription actually reaches the
/// exact shared `sl<PendingEntryWriteTracker>()` singleton a real
/// `entries-create` confirms a write through.
///
/// Driven directly against `DashboardCubit`'s own public API (`load()`),
/// not through `tester.tap`/`pumpAndSettle`: `load()` awaits a genuine
/// async `dio` round trip, and `pumpAndSettle` isn't guaranteed to wait for
/// it — same rationale `export_flow_e2e_test.dart`/`pending_write_sync_
/// e2e_test.dart` already document for their own cubits.
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

    // dashboard-aggregate-get (and entries-create, for the confirmedWrites
    // test below) are both bearer-required operations — seed a user access
    // token through the real AccessTokenProvider so the real header
    // interceptor has one to send.
    await sl<AccessTokenProvider>().saveAccessToken('e2e-test-access-token');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    fakeNativeStorage.clear();
    await Hive.close();
    // DashboardCubit is a lazySingleton with `dispose: cubit.close()` wired
    // into get_it's own reset lifecycle (dashboard_injection.dart) — no
    // manual close() needed here, same convention `pending_write_sync_
    // e2e_test.dart` already relies on for MeusRegistrosCubit.
    await resetCoreDependencies();
    await fakePathProvider.cleanUp();
  });

  test(
    'happy path: load() fires a genuine GET to dashboard-aggregate-get '
    "with period: 'all' and real headers, decoding a real multi-bucket "
    'JSON payload into ResourceData with bucketCounts in the exact '
    'backend order (DashboardAggregateDto.toDomain(), no reordering)',
    () async {
      adapter.queueJsonResponse(
        200,
        _aggregateJson(
          totalCount: 7,
          buckets: [
            _bucketJson('2026-01-01', 2),
            _bucketJson('2026-01-02', 0),
            _bucketJson('2026-01-03', 5),
          ],
        ),
      );

      final cubit = sl<DashboardCubit>();
      await cubit.load();

      final state = cubit.state as ResourceData<DashboardAggregate>;
      expect(state.data.totalCount, 7);
      expect(state.data.bucketCounts, [2, 0, 5]);

      final request = adapter.requests.single;
      expect(request.path, sl<UrlBuilder>().build('dashboard-aggregate-get'));
      expect(request.queryParameters, {'period': 'all'});
      expect(request.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
      expect(request.headers['Authorization'], 'Bearer e2e-test-access-token');
    },
  );

  test('a response missing the required "totals" field maps through the '
      "real DashboardRemoteDataSource try/catch and DashboardAggregateDto's "
      'generated fromJson to ResourceError(MalformedResponse), never a '
      'crash — the local decode-failure path, not Failure.fromCode', () async {
    adapter.queueJsonResponse(200, {
      'data': {
        'buckets': [_bucketJson('2026-01-01', 2)],
        // 'totals' deliberately omitted.
      },
    });

    final cubit = sl<DashboardCubit>();
    await cubit.load();

    final state = cubit.state as ResourceError<DashboardAggregate>;
    expect(state.failure, isA<MalformedResponse>());
  });

  test('a non-retryable VALIDATION_ERROR maps through the real Failure.'
      'fromCode pipeline to ResourceError — exactly one request left, no '
      'RetryInterceptor retry', () async {
    adapter.queueErrorResponse('VALIDATION_ERROR', 'period inválido');

    final cubit = sl<DashboardCubit>();
    await cubit.load();

    final state = cubit.state as ResourceError<DashboardAggregate>;
    expect(state.failure, isA<Validation>());
    expect(adapter.requests, hasLength(1));
  });

  test('a retryable NETWORK_TIMEOUT exhausts the real RetryInterceptor\'s '
      'retries (1 + maxRetries requests, same policy export/entries e2e '
      'suites already prove for their own functions) before surfacing as '
      'ResourceError', () async {
    for (var i = 0; i <= RetryInterceptor.maxRetries; i++) {
      adapter.queueErrorResponse('NETWORK_TIMEOUT', 'Tempo esgotado');
    }

    final cubit = sl<DashboardCubit>();
    await cubit.load();

    final state = cubit.state as ResourceError<DashboardAggregate>;
    expect(state.failure, isA<NetworkTimeout>());
    expect(adapter.requests, hasLength(1 + RetryInterceptor.maxRetries));
  });

  test('Acceptance Criteria: "entry created elsewhere while mounted ... chart '
      'recomputes" driven for real — a genuine entries-create round trip '
      'through the exact shared sl<PendingEntryWriteTracker>() singleton '
      "confirms a write, and DashboardCubit's own constructor subscription "
      '(wired by registerDashboardFeature()) reacts with a brand-new real '
      'dashboard-aggregate-get fetch, with no test/screen code ever calling '
      'load() a second time', () async {
    // Resolves (and starts) the real DashboardCubit — same as
    // AccountSettingsScreen.initState mounting Configurações — before the
    // write is confirmed, so its constructor subscription is already
    // live when confirmedWrites fires.
    final cubit = sl<DashboardCubit>();
    adapter.queueJsonResponse(200, _aggregateJson(totalCount: 0, buckets: []));
    await cubit.load();
    expect(
      (cubit.state as ResourceData<DashboardAggregate>).data.totalCount,
      0,
    );

    adapter.queueJsonResponse(
      200,
      _entryJson(
        id: 'entry-1',
        content: 'Primeiro registro do dia.',
        source: 'manual',
        occurredAt: '2026-01-02T10:00:00Z',
      ),
    );
    adapter.queueJsonResponse(
      200,
      _aggregateJson(totalCount: 1, buckets: [_bucketJson('2026-01-02', 1)]),
    );

    final tracker = sl<PendingEntryWriteTracker>();
    final result = await tracker.create(
      content: 'Primeiro registro do dia.',
      source: EntrySource.manual,
    );
    expect(result.isRight(), isTrue);

    await _waitForState(
      cubit,
      (s) => s is ResourceData<DashboardAggregate> && s.data.totalCount == 1,
    );
    final state = cubit.state as ResourceData<DashboardAggregate>;
    expect(state.data.bucketCounts, [1]);

    // Exactly two dashboard-aggregate-get calls left through the real
    // transport — the initial load() plus the one confirmedWrites-
    // triggered reload, never a third.
    final dashboardRequests = adapter.requests
        .where((r) => r.path.contains('dashboard-aggregate-get'))
        .toList();
    expect(dashboardRequests, hasLength(2));
  });

  group('DashboardNarrativeCubit — spec-8-2 independent narrative fetch', () {
    test('happy path: load() fires a genuine GET to dashboard-narrative-get '
        "with period: 'all' and real headers, decoding a real JSON payload "
        'into ResourceData with the narrative text '
        '(DashboardNarrativeDto.toDomain(), one field)', () async {
      adapter.queueJsonResponse(
        200,
        _narrativeJson(text: 'Seu balanço do período mostra evolução.'),
      );

      final cubit = sl<DashboardNarrativeCubit>();
      await cubit.load();

      final state = cubit.state as ResourceData<String>;
      expect(state.data, 'Seu balanço do período mostra evolução.');

      final request = adapter.requests.single;
      expect(request.path, sl<UrlBuilder>().build('dashboard-narrative-get'));
      expect(request.queryParameters, {'period': 'all'});
      expect(request.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
      expect(request.headers['Authorization'], 'Bearer e2e-test-access-token');
    });

    test('a response missing the required "generatedAt" field maps through '
        "the real DashboardRemoteDataSource try/catch and "
        "DashboardNarrativeDto's generated fromJson to ResourceError"
        '(MalformedResponse), never a crash — the local decode-failure '
        'path, not Failure.fromCode', () async {
      adapter.queueJsonResponse(200, {
        'data': {
          'text': 'Texto incompleto',
          // 'generatedAt' deliberately omitted.
        },
      });

      final cubit = sl<DashboardNarrativeCubit>();
      await cubit.load();

      final state = cubit.state as ResourceError<String>;
      expect(state.failure, isA<MalformedResponse>());
    });

    test('a non-retryable VALIDATION_ERROR maps through the real Failure.'
        'fromCode pipeline to ResourceError — exactly one request left, no '
        'RetryInterceptor retry', () async {
      adapter.queueErrorResponse('VALIDATION_ERROR', 'period inválido');

      final cubit = sl<DashboardNarrativeCubit>();
      await cubit.load();

      final state = cubit.state as ResourceError<String>;
      expect(state.failure, isA<Validation>());
      expect(adapter.requests, hasLength(1));
    });

    test(
      'a retryable NETWORK_TIMEOUT exhausts the real RetryInterceptor\'s '
      'retries (1 + maxRetries requests, same policy the sibling '
      'DashboardCubit group above already proves for the identical '
      'transport/retry pipeline) before surfacing as ResourceError',
      () async {
        for (var i = 0; i <= RetryInterceptor.maxRetries; i++) {
          adapter.queueErrorResponse('NETWORK_TIMEOUT', 'Tempo esgotado');
        }

        final cubit = sl<DashboardNarrativeCubit>();
        await cubit.load();

        final state = cubit.state as ResourceError<String>;
        expect(state.failure, isA<NetworkTimeout>());
        expect(adapter.requests, hasLength(1 + RetryInterceptor.maxRetries));
      },
    );

    test(
      'Boundaries: "constructor-subscribes to confirmedWrites, recompute on '
      'every entry write, same as the aggregate" driven for real — a '
      'genuine entries-create round trip through the exact shared '
      'sl<PendingEntryWriteTracker>() singleton confirms a write, and '
      "DashboardNarrativeCubit's own constructor subscription (wired by "
      'registerDashboardFeature()) reacts with a brand-new real '
      'dashboard-narrative-get fetch, with no test/screen code ever calling '
      'load() a second time',
      () async {
        // Resolves (and starts) the real DashboardNarrativeCubit — same as
        // AccountSettingsScreen.initState mounting Configurações — before
        // the write is confirmed, so its constructor subscription is
        // already live when confirmedWrites fires.
        final cubit = sl<DashboardNarrativeCubit>();
        adapter.queueJsonResponse(
          200,
          _narrativeJson(text: 'Balanço inicial.'),
        );
        await cubit.load();
        expect((cubit.state as ResourceData<String>).data, 'Balanço inicial.');

        adapter.queueJsonResponse(
          200,
          _entryJson(
            id: 'entry-1',
            content: 'Primeiro registro do dia.',
            source: 'manual',
            occurredAt: '2026-01-02T10:00:00Z',
          ),
        );
        adapter.queueJsonResponse(
          200,
          _narrativeJson(text: 'Balanço atualizado.'),
        );

        final tracker = sl<PendingEntryWriteTracker>();
        final result = await tracker.create(
          content: 'Primeiro registro do dia.',
          source: EntrySource.manual,
        );
        expect(result.isRight(), isTrue);

        await _waitForNarrativeState(
          cubit,
          (s) => s is ResourceData<String> && s.data == 'Balanço atualizado.',
        );

        // Exactly two dashboard-narrative-get calls left through the real
        // transport — the initial load() plus the one confirmedWrites-
        // triggered reload, never a third.
        final narrativeRequests = adapter.requests
            .where((r) => r.path.contains('dashboard-narrative-get'))
            .toList();
        expect(narrativeRequests, hasLength(2));
      },
    );
  });
}
