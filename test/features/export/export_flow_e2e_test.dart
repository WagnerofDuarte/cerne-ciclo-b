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
import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/url_builder.dart';
import 'package:cerne/features/export/domain/entities/export_job_state.dart';
import 'package:cerne/features/export/presentation/cubit/export_job_cubit.dart';

import '../../support/fake_path_provider_platform.dart';

/// Same shape as `capture_flow_e2e_test.dart`'s/`chat_flow_e2e_test.dart`'s
/// own fake adapter — only the transport boundary is faked.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<
    ({int statusCode, Map<String, dynamic>? body, Map<String, String>? headers})
  >
  _queue = [];

  void queueJsonResponse(int statusCode, Map<String, dynamic> body) {
    _queue.add((statusCode: statusCode, body: body, headers: null));
  }

  /// spec-7-2 review patch (item 8) — queues a `302` with no JSON body,
  /// just a `Location` header, mirroring `export-download-get`'s own real
  /// shape (`openapi.yaml`: "302: Redirect to a signed Storage URL").
  void queueRedirectResponse(String location) {
    _queue.add((statusCode: 302, body: null, headers: {'location': location}));
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
    final body = next.body;
    return ResponseBody.fromString(
      body != null ? jsonEncode(body) : '',
      next.statusCode,
      headers: {
        if (body != null) Headers.contentTypeHeader: [Headers.jsonContentType],
        ...next.headers?.map((key, value) => MapEntry(key, [value])) ?? {},
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// `export-status-get`'s own response `data` shape (`ExportJobStatusDto.
/// fromJson`) — mirrors `export_remote_data_source_test.dart`'s own
/// fixture.
Map<String, dynamic> _statusJson({
  required String jobId,
  required String status,
  String narrativeStatus = 'pending',
  int? entryCount,
  String? errorCode,
  bool downloadAvailable = false,
}) => {
  'jobId': jobId,
  'status': status,
  'narrativeStatus': narrativeStatus,
  'entryCount': entryCount,
  'errorCode': errorCode,
  'narrativeErrorCode': null,
  'downloadAvailable': downloadAvailable,
};

/// Waits for [cubit]'s state to satisfy [match], via the cubit's own
/// `stream` rather than a fixed real-time sleep keyed to the exact 2s poll
/// cadence (`ExportJobCubit._pollInterval`) — resolves immediately if
/// already true. The timeout only ever fires if the poll loop is
/// genuinely broken, turning a hang into a fast, clear test failure.
Future<void> _waitForState(
  ExportJobCubit cubit,
  bool Function(ExportJobState) match,
) {
  if (match(cubit.state)) {
    return Future.value();
  }
  return cubit.stream.firstWhere(match).timeout(const Duration(seconds: 10));
}

/// End-to-end coverage for spec-7-1's export flow, driven through the real
/// production object graph `sl` resolves for the download icon
/// (`MeusRegistrosScreen._onExportTap`'s exact `sl<ExportJobCubit>()`
/// call) — wired to the real `ExportRepositoryImpl` ->
/// `ExportRemoteDataSource` -> `ApiClient` -> `Dio` (both real
/// interceptors attached) -> this faked transport boundary only. No
/// device/simulator/CI exists yet (AGENTS.md).
///
/// Complements rather than duplicates this story's existing coverage:
/// `export_job_cubit_test.dart` already proves every I/O-matrix transition
/// against a hand-written fake `ExportRepository` (no real `Failure.
/// fromCode`/DTO decoding involved), `export_remote_data_source_test.dart`
/// proves the DTO mapping against a *mocked* `ApiClient`, and
/// `meus_registros_screen_test.dart`'s "export entry point" group proves
/// the tap -> picker -> `start()` -> sheet wiring against a fake
/// repository too. None of them drives a real `export-summary-create`/
/// `export-status-get` round trip — real URL building, real headers, the
/// real `RetryInterceptor.neverRetriedFunctions` exclusion, the real
/// `ExportJobStatusDto.toState()` + `Failure.fromCode` mapping off a real
/// decoded JSON payload — through the real `Timer.periodic` poll loop in
/// one job lifecycle.
///
/// Driven directly against `ExportJobCubit`'s own public API (`start()`),
/// not through `tester.tap`/`pumpAndSettle`: `start()` awaits genuine
/// async I/O (a real Dio round trip) and then a real 2s `Timer.periodic`
/// poll loop, and `pumpAndSettle` isn't guaranteed to wait for either —
/// same rationale `capture_flow_e2e_test.dart`/`chat_flow_e2e_test.dart`
/// already document for their own cubits. `_waitForState` lets each real
/// poll tick elapse in real wall-clock time rather than mixing in
/// `fake_async` (the project's own `network_pipeline_integration_test.dart`
/// already accepts real wall-clock delays the same way for
/// `RetryInterceptor`'s 500ms backoff).
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

    // Swap only the transport boundary on the real, DI-resolved Dio
    // instance — both real interceptors (header + retry) stay attached.
    adapter = _FakeHttpClientAdapter();
    sl<Dio>().httpClientAdapter = adapter;

    // Both export functions are bearer-required operations — seed a user
    // access token through the real AccessTokenProvider so the real
    // header interceptor has one to send.
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

  test('happy path: start() fires a genuine POST to export-summary-create '
      '(right URL/headers/body, periodEnd bumped to local end-of-day before '
      'UTC conversion), then the real Timer.periodic poll loop drives a '
      'genuine GET to export-status-get/{jobId} through Pendente -> '
      'Processando -> Concluído (narrativeReady)', () async {
    adapter.queueJsonResponse(202, {
      'data': {'jobId': 'job-1'},
    });
    adapter.queueJsonResponse(200, {
      'data': _statusJson(jobId: 'job-1', status: 'processing'),
    });
    adapter.queueJsonResponse(200, {
      'data': _statusJson(
        jobId: 'job-1',
        status: 'done',
        narrativeStatus: 'done',
        entryCount: 12,
        downloadAvailable: true,
      ),
    });

    final cubit = sl<ExportJobCubit>();
    addTearDown(cubit.close);

    final periodStart = DateTime(2026, 1, 1);
    final periodEnd = DateTime(2026, 1, 31);
    final started = await cubit.start(
      periodStart: periodStart,
      periodEnd: periodEnd,
    );

    expect(started, isTrue);
    expect(cubit.state, isA<ExportJobPreparing>());

    final createRequest = adapter.requests.single;
    expect(createRequest.path, sl<UrlBuilder>().build('export-summary-create'));
    expect(createRequest.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
    expect(
      createRequest.headers['Authorization'],
      'Bearer e2e-test-access-token',
    );
    final sentData = createRequest.data as Map<String, dynamic>;
    expect(
      DateTime.parse(sentData['periodStart'] as String).toLocal(),
      periodStart,
    );
    expect(
      DateTime.parse(sentData['periodEnd'] as String).toLocal(),
      DateTime(2026, 1, 31, 23, 59, 59, 999),
    );

    await _waitForState(cubit, (s) => s is ExportJobGenerating);
    final pollRequest = adapter.requests.last;
    expect(
      pollRequest.path,
      sl<UrlBuilder>().build('export-status-get', ['job-1']),
    );
    expect(pollRequest.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));

    await _waitForState(cubit, (s) => s is ExportJobDone);
    final state = cubit.state as ExportJobDone;
    expect(state.outcome, ExportOutcome.narrativeReady);

    // Terminal — the poll Timer really stopped, not just the state:
    // no further export-status-get call ever lands past this point.
    final requestCountAtTerminal = adapter.requests.length;
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(adapter.requests.length, requestCountAtTerminal);
  });

  test('Narrativa falhou: status done with narrativeStatus failed maps '
      'through the real ExportJobStatusDto.toState() to '
      'ExportOutcome.narrativeUnavailable', () async {
    adapter.queueJsonResponse(202, {
      'data': {'jobId': 'job-2'},
    });
    adapter.queueJsonResponse(200, {
      'data': _statusJson(
        jobId: 'job-2',
        status: 'done',
        narrativeStatus: 'failed',
      ),
    });

    final cubit = sl<ExportJobCubit>();
    addTearDown(cubit.close);

    await cubit.start(
      periodStart: DateTime(2026, 1, 1),
      periodEnd: DateTime(2026, 1, 31),
    );

    await _waitForState(cubit, (s) => s is ExportJobDone);
    expect(
      (cubit.state as ExportJobDone).outcome,
      ExportOutcome.narrativeUnavailable,
    );
  });

  test(
    'Período vazio: status error with errorCode EXPORT_EMPTY_PERIOD maps '
    'through the real Failure.fromCode -> ExportJobStatusDto.toState() '
    'pipeline to ExportJobState.emptyPeriod(), not a generic error',
    () async {
      adapter.queueJsonResponse(202, {
        'data': {'jobId': 'job-3'},
      });
      adapter.queueJsonResponse(200, {
        'data': _statusJson(
          jobId: 'job-3',
          status: 'error',
          errorCode: 'EXPORT_EMPTY_PERIOD',
        ),
      });

      final cubit = sl<ExportJobCubit>();
      addTearDown(cubit.close);

      await cubit.start(
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 31),
      );

      await _waitForState(cubit, (s) => s is ExportJobEmptyPeriod);
    },
  );

  test('Erro: a job-level status error with a non-empty-period errorCode '
      '(AI_GENERATION_TIMEOUT) maps through the real Failure.fromCode to '
      'ExportJobState.error — generic, terminal, no download', () async {
    adapter.queueJsonResponse(202, {
      'data': {'jobId': 'job-4'},
    });
    adapter.queueJsonResponse(200, {
      'data': _statusJson(
        jobId: 'job-4',
        status: 'error',
        errorCode: 'AI_GENERATION_TIMEOUT',
      ),
    });

    final cubit = sl<ExportJobCubit>();
    addTearDown(cubit.close);

    await cubit.start(
      periodStart: DateTime(2026, 1, 1),
      periodEnd: DateTime(2026, 1, 31),
    );

    await _waitForState(cubit, (s) => s is ExportJobError);
    expect((cubit.state as ExportJobError).failure, isA<AiGenerationTimeout>());
  });

  test('review-patch coverage: export-summary-create failing with a '
      'retryable server code (RATE_LIMITED) is never retried — proves '
      "RetryInterceptor.neverRetriedFunctions' real wiring for this "
      'function, unlike retry_interceptor_test.dart (tests shouldRetry() in '
      'isolation) or export_job_cubit_test.dart (fake repository, no real '
      'Dio pipeline)', () async {
    adapter.queueJsonResponse(429, {
      'code': 'RATE_LIMITED',
      'message': 'Limite atingido.',
      'retryable': true,
    });

    final cubit = sl<ExportJobCubit>();
    addTearDown(cubit.close);

    final started = await cubit.start(
      periodStart: DateTime(2026, 1, 1),
      periodEnd: DateTime(2026, 1, 31),
    );

    expect(started, isFalse);
    expect(cubit.state, isA<ExportJobError>());
    expect((cubit.state as ExportJobError).failure, isA<RateLimited>());
    // Exactly one request ever left — RATE_LIMITED is one of the 6
    // retryable codes (RetryInterceptor.retryableCodes), so without the
    // neverRetriedFunctions exclusion this would be 1 + maxRetries.
    expect(adapter.requests, hasLength(1));

    // No poll ever starts for a job that was never created.
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(
      adapter.requests.every((r) => !r.path.contains('export-status-get')),
      isTrue,
    );
  });

  group('getRedirectLocation (spec-7-2 review patch, item 8)', () {
    test(
      'a real 302 with a Location header, through the real header + '
      'retry interceptor chain (not just the mocked-Dio unit coverage in '
      'api_client_test.dart), reaches ApiClient.getRedirectLocation as a '
      'Right with that URL — proving the custom followRedirects/'
      'validateStatus combination plays correctly with both interceptors',
      () async {
        adapter.queueRedirectResponse('https://storage.example.com/signed-url');

        final result = await sl<ApiClient>().getRedirectLocation(
          'export-download-get',
          pathParams: ['job-5'],
          queryParameters: {'format': 'pdf'},
        );

        expect(result.isRight(), isTrue);
        result.match(
          (_) => fail('expected Right'),
          (url) => expect(url, 'https://storage.example.com/signed-url'),
        );

        final request = adapter.requests.single;
        expect(
          request.path,
          sl<UrlBuilder>().build('export-download-get', ['job-5']),
        );
        expect(request.queryParameters, {'format': 'pdf'});
        expect(request.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
        expect(
          request.headers['Authorization'],
          'Bearer e2e-test-access-token',
        );
      },
    );

    test('a real error response (e.g. NOT_FOUND) is never swallowed by the '
        'permissive validateStatus — it still maps through the real '
        'Failure.fromCode path, exactly like every other call on this '
        'interceptor chain', () async {
      adapter.queueJsonResponse(404, {
        'code': 'NOT_FOUND',
        'message': 'Job not found',
        'retryable': false,
      });

      final result = await sl<ApiClient>().getRedirectLocation(
        'export-download-get',
        pathParams: ['job-6'],
        queryParameters: {'format': 'raw'},
      );

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<NotFound>()),
        (_) => fail('expected Left'),
      );
      // NOT_FOUND isn't one of the 6 retryable codes either way, but
      // this also confirms the call wasn't retried into a second
      // request.
      expect(adapter.requests, hasLength(1));
    });
  });
}
